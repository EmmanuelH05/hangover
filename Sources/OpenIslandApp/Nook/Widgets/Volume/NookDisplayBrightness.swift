import CoreGraphics
import Foundation
import OSLog

private let brightnessLog = Logger(subsystem: "app.openisland", category: "nook.brightness")

/// The built-in display's brightness, from 0 to 1. The app uses the system
/// call below; tests pass a fake, which keeps them from ever changing the
/// real screen.
@MainActor
protocol NookBrightnessControl: AnyObject {
    /// Nil when there is no built-in display, or it cannot be read.
    func brightness() -> Float?
    @discardableResult func setBrightness(_ value: Float) -> Bool
}

/// PRIVATE API. macOS has no public call that reads or sets the built-in
/// display's brightness on Apple silicon. This soft-links three symbols
/// from `/System/Library/PrivateFrameworks/DisplayServices.framework`:
///
///   - `DisplayServicesCanChangeBrightness`
///   - `DisplayServicesGetBrightness`
///   - `DisplayServicesSetBrightness`
///
/// Everything fails closed: with the framework or a symbol missing, or on a
/// display that refuses, the brightness reads as nil and the brightness
/// keys stay with macOS. It is used only while the app has taken over the
/// media keys, which is off until the user turns it on.
@MainActor
final class NookDisplayBrightness: NookBrightnessControl {
    static let shared = NookDisplayBrightness()

    private typealias CanChange = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private struct Symbols {
        let canChange: CanChange
        let get: Get
        let set: Set
    }

    private static let frameworkPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    private lazy var symbols: Symbols? = Self.load()

    private init() {}

    private static func load() -> Symbols? {
        guard let handle = dlopen(frameworkPath, RTLD_LAZY),
              let canChange = dlsym(handle, "DisplayServicesCanChangeBrightness"),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness")
        else {
            brightnessLog.warning("DisplayServices brightness calls are not available")
            return nil
        }
        return Symbols(
            canChange: unsafeBitCast(canChange, to: CanChange.self),
            get: unsafeBitCast(get, to: Get.self),
            set: unsafeBitCast(set, to: Set.self)
        )
    }

    private static func builtInDisplay() -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    func brightness() -> Float? {
        guard let symbols, let display = Self.builtInDisplay(), symbols.canChange(display) else { return nil }
        var value: Float = 0
        guard symbols.get(display, &value) == 0 else { return nil }
        return min(max(value, 0), 1)
    }

    func setBrightness(_ value: Float) -> Bool {
        guard let symbols, let display = Self.builtInDisplay(), symbols.canChange(display) else { return false }
        return symbols.set(display, min(max(value, 0), 1)) == 0
    }
}
