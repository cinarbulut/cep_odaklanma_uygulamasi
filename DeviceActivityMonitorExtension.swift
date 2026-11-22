// Device Activity Monitor Extension hedefinin içindeki dosya.
// Uygulama kapalıyken bile sınırı uygular.
import DeviceActivity
import ManagedSettings
import FamilyControls

// ScreenTimeBridge.swift'teki ile AYNI App Group.
private let kAppGroup = "group.com.senin.kamodaklanma"

private func defaults() -> UserDefaults { UserDefaults(suiteName: kAppGroup) ?? .standard }

private func todayString() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f.string(from: Date())
}

private func shield(_ id: String) {
    guard
        let data = defaults().data(forKey: "sel_\(id)"),
        let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    else { return }
    let store = ManagedSettingsStore(named: .init(id))
    store.shield.applications = sel.applicationTokens.isEmpty ? nil : sel.applicationTokens
    store.shield.applicationCategories = sel.categoryTokens.isEmpty ? nil : .specific(sel.categoryTokens)
    store.shield.webDomains = sel.webDomainTokens.isEmpty ? nil : sel.webDomainTokens
    defaults().set(true, forKey: "locked_\(id)")
    defaults().set(0, forKey: "graceUntil_\(id)")
}

class KamMonitor: DeviceActivityMonitor {

    /// Gün başlayınca (00:00) kilit sıfırlanır. Aynı gün içinde yeniden başlatma kilidi açmaz.
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        let raw = activity.rawValue
        guard raw.hasPrefix("daily_") else { return }
        let id = String(raw.dropFirst("daily_".count))
        let d = defaults()
        let today = todayString()
        if d.string(forKey: "day_\(id)") != today {
            ManagedSettingsStore(named: .init(id)).clearAllSettings()
            d.set(false, forKey: "locked_\(id)")
            d.set(0, forKey: "graceUntil_\(id)")
            d.set(today, forKey: "day_\(id)")
        }
    }

    /// Günlük sınıra ulaşıldı: kilitle.
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        let raw = activity.rawValue
        guard raw.hasPrefix("daily_") else { return }
        shield(String(raw.dropFirst("daily_".count)))
    }

    /// 15 dk mola bitti: tekrar kilitle (aynı gün içindeyse).
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        let raw = activity.rawValue
        guard raw.hasPrefix("grace_") else { return }
        let id = String(raw.dropFirst("grace_".count))
        if defaults().string(forKey: "graceDay_\(id)") == todayString() {
            shield(id)
        }
    }
}
