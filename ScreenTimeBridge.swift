// ios/Runner/ScreenTimeBridge.swift  (Runner hedefi, iOS 16+)
import Flutter
import UIKit
import SwiftUI
import FamilyControls
import ManagedSettings
import DeviceActivity

// Xcode'da oluşturduğun App Group ile AYNI olmalı (Runner + extension).
let kAppGroup = "group.com.senin.kamodaklanma"
let kGraceMinutes = 15

private func defaults() -> UserDefaults { UserDefaults(suiteName: kAppGroup) ?? .standard }

private func todayString() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f.string(from: Date())
}

private func loadSelection(_ id: String) -> FamilyActivitySelection? {
    guard let data = defaults().data(forKey: "sel_\(id)") else { return nil }
    return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
}

private func applyShield(_ id: String) {
    guard let sel = loadSelection(id) else { return }
    let store = ManagedSettingsStore(named: .init(id))
    store.shield.applications = sel.applicationTokens.isEmpty ? nil : sel.applicationTokens
    store.shield.applicationCategories = sel.categoryTokens.isEmpty ? nil : .specific(sel.categoryTokens)
    store.shield.webDomains = sel.webDomainTokens.isEmpty ? nil : sel.webDomainTokens
}

final class ScreenTimeBridge {
    static func register(with messenger: FlutterBinaryMessenger) {
        let ch = FlutterMethodChannel(name: "kam/screentime", binaryMessenger: messenger)
        ch.setMethodCallHandler { call, result in
            let a = call.arguments as? [String: Any] ?? [:]
            let id = a["ruleId"] as? String ?? ""
            switch call.method {
            case "requestAuthorization":
                Task {
                    do {
                        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                        result(true)
                    } catch { result(false) }
                }
            case "pickApps":
                presentPicker(ruleId: id) { result($0) }
            case "startLimit":
                startLimit(ruleId: id, minutes: a["minutes"] as? Int ?? 60); result(nil)
            case "unshield":
                unshield(ruleId: id); result(nil)
            case "status":
                let d = defaults()
                result(["locked": d.bool(forKey: "locked_\(id)"),
                        "graceUntil": d.integer(forKey: "graceUntil_\(id)")])
            case "removeRule":
                removeRule(ruleId: id); result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    /// Günlük sınırı kurar: gün boyu izler, sınıra ulaşınca extension kilitler.
    static func startLimit(ruleId: String, minutes: Int) {
        guard let sel = loadSelection(ruleId) else { return }
        let d = defaults()
        d.set(todayString(), forKey: "day_\(ruleId)") // yeniden başlatma kilidi açmasın
        let center = DeviceActivityCenter()
        let name = DeviceActivityName("daily_\(ruleId)")
        center.stopMonitoring([name])

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        let event = DeviceActivityEvent(
            applications: sel.applicationTokens,
            categories: sel.categoryTokens,
            webDomains: sel.webDomainTokens,
            threshold: DateComponents(hour: minutes / 60, minute: minutes % 60)
        )
        try? center.startMonitoring(name, during: schedule,
                                    events: [DeviceActivityEvent.Name("limit"): event])
    }

    /// Görevler bitince: kalkanı kaldırır, sabit 15 dk mola verir. Uzatma yok.
    static func unshield(ruleId: String) {
        let d = defaults()
        ManagedSettingsStore(named: .init(ruleId)).clearAllSettings()
        d.set(false, forKey: "locked_\(ruleId)")
        d.set(todayString(), forKey: "graceDay_\(ruleId)")

        let cal = Calendar.current
        let now = Date()
        let end = now.addingTimeInterval(TimeInterval(kGraceMinutes * 60))
        d.set(Int(end.timeIntervalSince1970 * 1000), forKey: "graceUntil_\(ruleId)")

        let center = DeviceActivityCenter()
        let name = DeviceActivityName("grace_\(ruleId)")
        center.stopMonitoring([name])
        let comps: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents(comps, from: now),
            intervalEnd: cal.dateComponents(comps, from: end),
            repeats: false
        )
        try? center.startMonitoring(name, during: schedule)
    }

    static func removeRule(ruleId: String) {
        DeviceActivityCenter().stopMonitoring([
            DeviceActivityName("daily_\(ruleId)"),
            DeviceActivityName("grace_\(ruleId)")
        ])
        ManagedSettingsStore(named: .init(ruleId)).clearAllSettings()
        let d = defaults()
        for k in ["sel_", "locked_", "graceUntil_", "graceDay_", "day_"] { d.removeObject(forKey: "\(k)\(ruleId)") }
    }

    // MARK: Uygulama seçici

    static func presentPicker(ruleId: String, completion: @escaping (Bool) -> Void) {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first?.windows.first?.rootViewController else {
            completion(false); return
        }
        var top = root
        while let p = top.presentedViewController { top = p }

        let host = UIHostingController(rootView: PickerView(
            initial: loadSelection(ruleId) ?? FamilyActivitySelection(),
            onDone: { sel in
                let any = !sel.applicationTokens.isEmpty || !sel.categoryTokens.isEmpty || !sel.webDomainTokens.isEmpty
                if any, let data = try? JSONEncoder().encode(sel) {
                    defaults().set(data, forKey: "sel_\(ruleId)")
                }
                top.dismiss(animated: true) { completion(any) }
            },
            onCancel: { top.dismiss(animated: true) { completion(false) } }
        ))
        top.present(host, animated: true)
    }
}

struct PickerView: View {
    @State var selection: FamilyActivitySelection
    let onDone: (FamilyActivitySelection) -> Void
    let onCancel: () -> Void

    init(initial: FamilyActivitySelection,
         onDone: @escaping (FamilyActivitySelection) -> Void,
         onCancel: @escaping () -> Void) {
        _selection = State(initialValue: initial)
        self.onDone = onDone
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationView {
            FamilyActivityPicker(selection: $selection)
                .navigationTitle("Sınırlanacak uygulamalar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("İptal", action: onCancel) }
                    ToolbarItem(placement: .confirmationAction) { Button("Bitti") { onDone(selection) } }
                }
        }
    }
}
