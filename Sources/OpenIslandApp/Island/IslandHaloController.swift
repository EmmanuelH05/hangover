import Foundation
import Observation

/// Holds the short-lived completion flash. `noteCompletion()` hands out a
/// new token that the halo resolver turns into a flash; the token clears
/// itself after `Motion.Halo.flashHold`.
@MainActor
@Observable
final class IslandHaloController {
    private(set) var flashToken: UInt64?

    @ObservationIgnored private var counter: UInt64 = 0
    @ObservationIgnored private var clearTask: Task<Void, Never>?

    func noteCompletion() {
        counter &+= 1
        let token = counter
        flashToken = token
        clearTask?.cancel()
        clearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Motion.Halo.flashHold))
            guard let self, !Task.isCancelled, self.flashToken == token else { return }
            self.flashToken = nil
        }
    }
}
