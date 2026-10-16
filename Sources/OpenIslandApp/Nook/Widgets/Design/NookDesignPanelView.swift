import SwiftUI

/// What one floating reference panel shows, and how.
@MainActor
@Observable
final class NookDesignPanelState {
    let reference: NookDesignReference
    let image: CGImage
    /// The size of the whole panel: the picture area and the strip of
    /// controls under it. It follows the window as the user drags it.
    private(set) var panelSize: CGSize
    /// True for a picture that can have see-through parts. It is drawn
    /// over a checkerboard, which shows where they are.
    let hasAlpha: Bool

    var zoom = NookDesignZoom.fit
    var opacity: Double = 1
    /// Always on top. A new panel starts that way: a reference is there
    /// to be looked at while working in another window.
    var isPinned = true
    /// True while the panel has the keyboard.
    var isFocused = false

    /// A panel with no size given is in the shape of its picture, the way
    /// a new one opens.
    init(reference: NookDesignReference, image: CGImage, panelSize: CGSize? = nil) {
        self.reference = reference
        self.image = image
        self.panelSize = panelSize ?? NookDesignPanelRules.panelSize(
            width: NookDesignPanelRules.initialLongSide, pictureAspect: reference.aspectRatio
        )
        hasAlpha = NookDesignPictures.carriesAlpha(image.alphaInfo)
    }

    /// The part of the picture area the fitted picture covers on each
    /// axis, for the area the panel has now.
    var fitted: CGSize {
        NookDesignPanelRules.fittedFraction(pictureAspect: reference.aspectRatio, panelSize: panelSize)
    }

    /// The panel was resized. The picture keeps its zoom, and is pulled back
    /// where the new area leaves it room to be.
    func resize(to size: CGSize) {
        guard size != panelSize else { return }
        panelSize = size
        zoom = zoom.clamped(fitted: fitted)
    }

    func zoomIn() { zoom = zoom.zoomed(by: NookDesignZoom.step, fitted: fitted) }
    func zoomOut() { zoom = zoom.zoomed(by: 1 / NookDesignZoom.step, fitted: fitted) }
    func fit() { zoom = .fit }
}

/// What the panel's controls ask of its window.
@MainActor
struct NookDesignPanelActions {
    var setPinned: (Bool) -> Void = { _ in }
    var setOpacity: (Double) -> Void = { _ in }
    var close: () -> Void = {}
    /// A plain click on the picture. The panel takes the keyboard.
    var focus: () -> Void = {}
    /// A drag on the picture at the fit moves the whole panel.
    var beginMove: () -> Void = {}
    var move: () -> Void = {}
    /// Sends the panel back to the picture's shape at its width.
    var matchShape: () -> Void = {}
}

/// A reference picture in its floating panel: the picture, whole and in
/// its own shape, over a strip of controls. Drawn from plain SwiftUI,
/// which lets a still picture of it be made for review.
struct NookDesignPanelView: View {
    var state: NookDesignPanelState
    var actions: NookDesignPanelActions
    var isStill = false

    /// The zoom a drag started from, while the picture is being panned.
    @State private var panStart: NookDesignZoom?
    @State private var isMoving = false

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                picture(in: proxy.size)
            }
            bar
                .frame(height: NookDesignPanelRules.barHeight)
        }
        .background(Color.black)
        .overlay {
            if state.isFocused {
                Rectangle()
                    .strokeBorder(HangoverAccentSource.tint().highlight(.orange).opacity(0.9), lineWidth: 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    // MARK: Picture

    private func picture(in size: CGSize) -> some View {
        let lang = LanguageManager.shared
        let name = state.reference.name.isEmpty ? lang.t("nook.design.reference.untitled") : state.reference.name
        // The checkerboard is the picture's own size and moves with it.
        // Around a picture that does not fill the area there is plain black.
        return Image(decorative: state.image, scale: 1)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .background {
                if state.hasAlpha {
                    // Pulled in a point: a scaled picture's edge is soft,
                    // and the squares would show along it.
                    // Clipped to the picture: the last squares of the board
                    // are drawn whole and would show outside it, on the
                    // black, wherever the area is not in the picture's shape.
                    NookDesignCheckerboard(square: 8)
                        .padding(1)
                        .clipped()
                }
            }
            .scaleEffect(state.zoom.scale)
            .offset(
                x: state.zoom.offset.width * size.width,
                y: state.zoom.offset.height * size.height
            )
            .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(drag(in: size))
        .onTapGesture(count: 2) { state.fit() }
        .onTapGesture { actions.focus() }
        .accessibilityElement()
        .accessibilityLabel(name)
        .accessibilityHint(lang.t("nook.design.panel.hint"))
        .accessibilityAction(named: Text(lang.t("nook.design.panel.matchShape"))) { actions.matchShape() }
    }

    /// Zoomed in, a drag moves the picture inside the panel. At the fit
    /// there is nowhere to move it to, and the drag moves the panel.
    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if isMoving {
                    actions.move()
                } else if let start = panStart {
                    guard size.width > 0, size.height > 0 else { return }
                    state.zoom = start.panned(
                        by: CGSize(
                            width: value.translation.width / size.width,
                            height: value.translation.height / size.height
                        ),
                        fitted: state.fitted
                    )
                } else if state.zoom.scale > 1 {
                    panStart = state.zoom
                } else {
                    isMoving = true
                    actions.beginMove()
                }
            }
            .onEnded { _ in
                panStart = nil
                isMoving = false
            }
    }

    // MARK: Controls

    private var bar: some View {
        let lang = LanguageManager.shared
        return HStack(spacing: 3) {
            barButton("minus.magnifyingglass", lang.t("nook.design.panel.zoomOut")) { state.zoomOut() }
                .disabled(state.zoom.scale <= NookDesignZoom.range.lowerBound)
            Text(state.zoom.percentText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 34)
                .accessibilityLabel(lang.t("nook.design.panel.zoom"))
                .accessibilityValue(state.zoom.percentText)
            barButton("plus.magnifyingglass", lang.t("nook.design.panel.zoomIn")) { state.zoomIn() }
                .disabled(state.zoom.scale >= NookDesignZoom.range.upperBound)
            barButton("arrow.up.left.and.arrow.down.right", lang.t("nook.design.panel.fit")) { state.fit() }
                .disabled(state.zoom.isFit)
            // The empty part of the strip: a double click sends the panel back
            // to the picture's shape. A button for it would not fit beside
            // the others at the narrowest panel.
            Color.clear
                .frame(minWidth: 2, maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { actions.matchShape() }
                .help(lang.t("nook.design.panel.matchShape.help"))
            opacitySlider
                .frame(width: 48)
            barButton(
                state.isPinned ? "pin.fill" : "pin",
                lang.t(state.isPinned ? "nook.design.panel.unpin" : "nook.design.panel.pin"),
                isOn: state.isPinned
            ) {
                actions.setPinned(!state.isPinned)
            }
            barButton("xmark", lang.t("nook.design.panel.close")) { actions.close() }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.11))
    }

    @ViewBuilder
    private var opacitySlider: some View {
        let label = LanguageManager.shared.t("nook.design.panel.opacity")
        if isStill {
            // A slider is an AppKit control, which a still picture cannot
            // hold. This draws the same thing.
            GeometryReader { proxy in
                let range = NookDesignPanelRules.opacityRange
                let fraction = (state.opacity - range.lowerBound) / (range.upperBound - range.lowerBound)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18)).frame(height: 3)
                    Capsule().fill(Color.white.opacity(0.7)).frame(width: proxy.size.width * fraction, height: 3)
                }
                .frame(maxHeight: .infinity)
            }
        } else {
            Slider(
                value: Binding(get: { state.opacity }, set: { actions.setOpacity($0) }),
                in: NookDesignPanelRules.opacityRange
            )
            .controlSize(.mini)
            .help(label)
            .accessibilityLabel(label)
        }
    }

    private func barButton(_ symbol: String, _ label: String, isOn: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? HangoverAccentSource.tint().highlight(.orange) : Color.white.opacity(0.75))
                .frame(width: 20, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
