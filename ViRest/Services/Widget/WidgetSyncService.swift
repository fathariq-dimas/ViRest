import Foundation
import WidgetKit

@MainActor
final class WidgetSyncService {
    private let widgetKind = "ViRestDashboardWidget"
    private let defaults: UserDefaults?
    private let encoder = JSONEncoder()

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: ViRestWidgetShared.appGroupId)
    }

    func publish(snapshot: ViRestWidgetSnapshot) {
        guard let defaults else { return }
        guard let payload = try? encoder.encode(snapshot) else { return }
        defaults.set(payload, forKey: ViRestWidgetShared.snapshotStorageKey)
        defaults.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func clear() {
        guard let defaults else { return }
        defaults.removeObject(forKey: ViRestWidgetShared.snapshotStorageKey)
        defaults.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
