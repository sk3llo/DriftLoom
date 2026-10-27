// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Network

/// Whether the current connection is mobile data (or another connection iOS marks as expensive),
/// which picks the default resolution cap.
@MainActor
final class NetworkStatus: ObservableObject {
    @Published private(set) var isMobileData = false
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let mobile = path.usesInterfaceType(.cellular) || path.isExpensive
            Task { @MainActor [weak self] in
                if self?.isMobileData != mobile { self?.isMobileData = mobile }
            }
        }
        monitor.start(queue: DispatchQueue(label: "DriftLoom.playbackNetwork"))
    }
    deinit { monitor.cancel() }
}
