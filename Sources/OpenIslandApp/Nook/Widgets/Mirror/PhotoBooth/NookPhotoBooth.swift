import AVFoundation
import SwiftUI

/// The mirror's corner button that starts a photo booth session, and
/// stops one that is running. It shows only while the mirror has a camera
/// picture to take.
struct NookPhotoBoothButton: View {
    var nook: NookModel

    private static let hitArea: CGFloat = 22

    private var lang: LanguageManager { .shared }

    var body: some View {
        let booth = nook.photoBooth
        let controller = NookMirrorController.shared
        if controller.authorization == .authorized, controller.hasCamera, booth.result == nil, booth.failure == nil {
            let isRunning = booth.isRunning
            Button {
                if isRunning {
                    withMotion(Motion.contentSwap) { booth.cancel() }
                } else {
                    withMotion(Motion.contentSwap) { booth.start() }
                }
            } label: {
                Image(systemName: isRunning ? "stop.fill" : "camera.aperture")
                    .font(.system(size: isRunning ? 8 : 11, weight: .semibold))
                    .foregroundStyle(isRunning ? Color.red : Color.white.opacity(0.9))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Self.hitArea, height: Self.hitArea)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(lang.t(isRunning ? "nook.photoBooth.button.stop" : "nook.photoBooth.button.start"))
            .accessibilityLabel(lang.t(isRunning ? "nook.photoBooth.button.stop" : "nook.photoBooth.button.start"))
        }
    }
}

/// What the photo booth draws over the mirror's picture: the countdown and
/// the flash while a session runs, then the finished strip.
struct NookPhotoBoothOverlay: View {
    var nook: NookModel

    var body: some View {
        let booth = nook.photoBooth
        ZStack {
            if let failure = booth.failure {
                NookPhotoBoothFailureView(booth: booth, failure: failure)
                    .transition(.opacity)
            } else if let result = booth.result {
                NookPhotoBoothResultView(booth: booth, result: result)
                    .transition(.opacity)
            } else if let session = booth.session {
                NookPhotoBoothSessionView(booth: booth, session: session)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            NookPhotoBoothFlash(count: booth.flashes)
                .allowsHitTesting(false)
        }
        // The sticker editor sits under this. Only the finished strip and
        // an error take clicks. Idle, and while a session counts down,
        // every click goes through.
        .allowsHitTesting(booth.result != nil || booth.failure != nil)
        .motionAnimation(Motion.contentSwap, value: booth.isShowing)
    }
}

// MARK: - While a session runs

/// The countdown, the look at each picture, and the steps between.
private struct NookPhotoBoothSessionView: View {
    var booth: NookPhotoBoothModel
    var session: NookPhotoBoothSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lang: LanguageManager { .shared }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                cropBands(in: proxy.size)
                center(in: proxy.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .topLeading) { progress.padding(10) }
        }
    }

    /// Darkens the sides a narrower slot will cut away, which shows what
    /// the picture keeps before it is taken.
    @ViewBuilder
    private func cropBands(in size: CGSize) -> some View {
        if let layout = booth.sessionLayout, let shot = session.currentShot, size.height > 0 {
            let kept = NookPhotoBoothLiveCrop.keptSize(
                pictureSize: size,
                slotAspect: layout.aspect(ofSlot: min(shot, layout.shots) - 1)
            )
            let side = (size.width - kept.width) / 2
            let band = (size.height - kept.height) / 2
            ZStack {
                if side > 0.5 {
                    HStack(spacing: 0) {
                        Color.black.opacity(0.5).frame(width: side)
                        Spacer(minLength: 0)
                        Color.black.opacity(0.5).frame(width: side)
                    }
                }
                if band > 0.5 {
                    VStack(spacing: 0) {
                        Color.black.opacity(0.5).frame(height: band)
                        Spacer(minLength: 0)
                        Color.black.opacity(0.5).frame(height: band)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func center(in size: CGSize) -> some View {
        switch session.phase {
        case .getReady:
            card(lang.t("nook.photoBooth.getReady"), detail: booth.sessionLayout.map { lang.t($0.kind.nameKey) })
        case let .countdown(_, number):
            Text("\(number)")
                .font(.system(size: min(120, size.height * 0.5), weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 10, y: 2)
                .id(number)
                .transition(Motion.transition(
                    .asymmetric(insertion: .scale(scale: 1.2).combined(with: .opacity), removal: .opacity),
                    reduceMotion: reduceMotion
                ))
                .motionAnimation(Motion.contentSwap, value: number)
                .accessibilityLabel("\(number)")
        case .capturing:
            EmptyView()
        case let .preview(shot):
            if let picture = booth.pictures.last {
                NookPhotoBoothPrint(picture: picture)
                    .padding(.vertical, 18)
                    .padding(.horizontal, 28)
                    .overlay(alignment: .bottom) {
                        pill(lang.t("nook.photoBooth.shotOf", shot, session.plan.shots)).padding(.bottom, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.55))
            }
        case .nextPose:
            card(lang.t("nook.photoBooth.nextPose"), detail: nil)
        case .composing:
            VStack(spacing: 10) {
                ProgressView().controlSize(.small).tint(.white)
                Text(lang.t("nook.photoBooth.printing"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.6))
        case .done:
            EmptyView()
        }
    }

    /// One dot per picture, filled as they come in.
    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(0..<session.plan.shots, id: \.self) { index in
                Circle()
                    .fill(index < session.shotsTaken ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 18)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .accessibilityHidden(true)
    }

    private func card(_ title: String, detail: String?) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if let detail {
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.6)))
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 20)
            .background(Capsule().fill(Color.black.opacity(0.65)))
    }
}

/// The part of the live picture a slot keeps. A plain enum, which keeps it
/// callable from tests off the main actor.
enum NookPhotoBoothLiveCrop {
    /// The largest size of the slot's shape that fits inside the picture.
    static func keptSize(pictureSize: CGSize, slotAspect: CGFloat) -> CGSize {
        guard pictureSize.width > 0, pictureSize.height > 0, slotAspect > 0 else { return pictureSize }
        let pictureAspect = pictureSize.width / pictureSize.height
        if pictureAspect > slotAspect {
            return CGSize(width: pictureSize.height * slotAspect, height: pictureSize.height)
        }
        return CGSize(width: pictureSize.width, height: pictureSize.width / slotAspect)
    }
}

/// One picture shown like a small print: the camera's picture, its
/// decorations, and a white edge.
private struct NookPhotoBoothPrint: View {
    var picture: NookPhotoBoothPicture

    var body: some View {
        Image(decorative: picture.camera, scale: 1)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                if let decorations = picture.decorations {
                    Image(decorative: decorations, scale: 1).resizable()
                }
            }
            .padding(4)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
    }
}

/// The white flash as a picture is taken. With Reduce Motion on it is a
/// short white edge, never a full white screen.
private struct NookPhotoBoothFlash: View {
    var count: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var strength: Double = 0

    var body: some View {
        Group {
            if reduceMotion {
                Rectangle().strokeBorder(Color.white, lineWidth: 8)
            } else {
                Color.white
            }
        }
        .opacity(strength)
        .onChange(of: count) { _, _ in
            strength = 1
            withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.45)) { strength = 0 }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The finished strip

/// The strip, sliding out like a print, beside what can be done with it.
private struct NookPhotoBoothResultView: View {
    var booth: NookPhotoBoothModel
    var result: NookPhotoBoothResult

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOut = false
    @State private var shareAnchor = NookTrayAnchorBox()
    @State private var shareFailed = false

    private var lang: LanguageManager { .shared }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 16) {
                Image(decorative: result.preview, scale: 1)
                    .resizable()
                    .aspectRatio(result.pageSize.width / max(result.pageSize.height, 1), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .shadow(color: .black.opacity(0.6), radius: 10, y: 4)
                    .offset(y: isOut || reduceMotion ? 0 : -proxy.size.height)
                    .opacity(isOut ? 1 : (reduceMotion ? 0 : 1))
                    .accessibilityLabel(lang.t("nook.photoBooth.done.strip"))
                actions
                    .frame(width: 132)
                    .opacity(isOut ? 1 : 0)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.opacity(0.78))
        .onAppear {
            // A print takes a moment to come out. That wait is the fun of it.
            withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.9, dampingFraction: 0.78)) {
                isOut = true
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lang.t(shareFailed ? "nook.photoBooth.error.share" : "nook.photoBooth.done.saved"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(shareFailed ? Color.orange : Color.white.opacity(0.85))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)
            action("folder", "nook.photoBooth.action.reveal") { booth.revealInFinder() }
            action("square.and.arrow.up", "nook.photoBooth.action.share") {
                shareFailed = !booth.share(from: shareAnchor.view)
            }
            .background(NookTrayShareAnchor(box: shareAnchor))
            action(
                result.isInTray ? "checkmark" : "tray.and.arrow.down",
                result.isInTray ? "nook.photoBooth.action.inTray" : "nook.photoBooth.action.tray"
            ) { booth.addToTray() }
                .disabled(result.isInTray)
            action("arrow.counterclockwise", "nook.photoBooth.action.retake") {
                withMotion(Motion.contentSwap) { booth.retake() }
            }
            .help(lang.t("nook.photoBooth.action.retake.help"))
            action("checkmark.circle.fill", "nook.photoBooth.action.done", isPrimary: true) {
                withMotion(Motion.contentSwap) { booth.finish() }
            }
        }
    }

    private func action(
        _ symbol: String,
        _ key: String,
        isPrimary: Bool = false,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 14)
                Text(lang.t(key))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isPrimary ? Color.black : Color.white.opacity(0.92))
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isPrimary ? Color.white : Color.white.opacity(0.14))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Shown when a session ended without a strip.
private struct NookPhotoBoothFailureView: View {
    var booth: NookPhotoBoothModel
    var failure: NookPhotoBoothFailure

    private var lang: LanguageManager { .shared }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.orange)
            Text(lang.t(failure.messageKey))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                if failure == .save, booth.unsavedStrip != nil {
                    Button(lang.t("nook.photoBooth.error.saveAgain")) {
                        Task { await booth.saveAgain() }
                    }
                }
                Button(lang.t("nook.photoBooth.error.tryAgain")) {
                    booth.cancel()
                    booth.start()
                }
                Button(lang.t("nook.photoBooth.action.done")) { booth.cancel() }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.78))
    }
}
