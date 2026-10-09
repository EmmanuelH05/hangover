import Foundation

/// The names and links a user reads. Internal identifiers (module and type
/// names, the hooks program, the Application Support folder, the bridge
/// socket, settings keys) keep the upstream "OpenIsland" spelling and are
/// not here.
enum AppBrand {
    /// The product's name. The string tables carry it as `app.name` too.
    static let name = "Hangover"

    /// The Settings window's title. `AppModel.showSettings` finds the window
    /// by this title, which is why the scene and the lookup share one value.
    static let settingsWindowTitle = "\(name) Settings"

    // MARK: Credit and license

    /// Where Hangover's source code is published. The GNU GPL requires that
    /// everyone given the app can get its source, and the About pane links
    /// here.
    static let sourceCodeURL = URL(string: "https://github.com/EmmanuelH05/hangover")!

    /// Hangover's own releases. Nothing in the app may send a user to the
    /// upstream project's releases, which hold a different app.
    static let releasesURL = sourceCodeURL.appendingPathComponent("releases")

    /// The project Hangover is based on, credited in the About pane.
    static let upstreamName = "Open Island"
    static let upstreamURL = URL(string: "https://github.com/Octane0411/open-vibe-island")!

    /// The license text on the web, for a build that carries no copy.
    static let licenseWebURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!

    /// The license copy that `scripts/package-app.sh` puts in the bundle's
    /// Resources. It carries an extension, which lets macOS open it as text.
    static let bundledLicenseFileName = "LICENSE.txt"

    /// Where the About pane's license row leads: the copy inside the app
    /// when there is one, which also works offline, and the web page
    /// otherwise (a `swift run` build has no bundled copy).
    static func licenseURL(bundledCopy: URL?) -> URL {
        bundledCopy ?? licenseWebURL
    }

    /// The license copy inside the running app, if it has one.
    static var bundledLicenseURL: URL? {
        guard let copy = Bundle.main.resourceURL?.appendingPathComponent(bundledLicenseFileName),
              FileManager.default.fileExists(atPath: copy.path) else {
            return nil
        }
        return copy
    }
}
