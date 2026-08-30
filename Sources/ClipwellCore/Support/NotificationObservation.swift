import Foundation

/// Owns a notification observer and removes it when this object goes away.
///
/// A `@MainActor` class can't reliably tear down its own observer in `deinit`:
/// `deinit` is nonisolated, so reaching a main-actor-isolated stored property
/// from it crosses an isolation boundary. Parking the token on a plain
/// non-isolated object sidesteps that -- the owner just holds one of these and
/// needs no `deinit` of its own.
final class NotificationObservation {
    private let token: NSObjectProtocol
    private let center: NotificationCenter

    init(name: Notification.Name,
         object: Any? = nil,
         center: NotificationCenter = .default,
         queue: OperationQueue? = .main,
         handler: @escaping () -> Void) {
        self.center = center
        self.token = center.addObserver(forName: name, object: object, queue: queue) { _ in
            handler()
        }
    }

    deinit {
        center.removeObserver(token)
    }
}
