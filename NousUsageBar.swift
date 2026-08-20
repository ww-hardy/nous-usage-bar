//
//  NousUsageBar.swift — macOS menu-bar widget for Nous Portal credit usage.
//
//  Runs a small Python backend (fetch_nous_usage.py, bundled in Resources) that
//  reuses Hermes' own Nous Portal account machinery (OAuth refresh + parsing),
//  so this app never touches credentials directly.
//
//  Build:  xcrun swiftc -O -o NousUsageBar NousUsageBar.swift -framework AppKit
//

import AppKit
import Foundation

// MARK: - JSON payload (mirrors fetch_nous_usage.py output)

struct UsagePayload: Decodable {
    let ok: Bool
    let source: String?
    let plan: String?
    let monthly_credits: Double?
    let subscription_remaining: Double?
    let purchased_remaining: Double?
    let total_usable: Double?
    let period_end: String?
    let org_name: String?
    let email: String?
    let error: String?
}

// MARK: - Main app

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var updateTimer: Timer?
    private var payload: UsagePayload?

    // Update checking state.
    private var latestVersion: String?
    private var updateAvailable = false
    private var updateCheckState = "idle" // idle | checking | done | error

    /// The version baked into this bundle's Info.plist (e.g. "1.1.0").
    private var localVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    private var pythonPath: String {
        // Resolve the Hermes venv python robustly so the widget works on any
        // machine with Hermes installed, not just this one.
        //
        // 1) If `hermes` is on PATH, the shim lives in the venv's bin/ dir
        //    (…/venv/bin/hermes) — so the interpreter is its sibling `python`.
        // 2) Fall back to the standard install location.
        // 3) Last resort: whatever python3 is on PATH (fetch will report a
        //    clear "hermes import failed" error rather than crash).
        if let hermesShim = findOnPath("hermes") {
            let venvPython = hermesShim
                .deletingLastPathComponent()
                .appendingPathComponent("python")
            if FileManager.default.isExecutableFile(atPath: venvPython.path) {
                return venvPython.path
            }
        }
        let candidates = [
            NSHomeDirectory() + "/.hermes/hermes-agent/venv/bin/python",
            "/usr/local/opt/hermes/bin/python",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        return "/usr/bin/python3"
    }

    /// Locate an executable by scanning $PATH (like `which`), or nil.
    private func findOnPath(_ name: String) -> URL? {
        guard let pathVar = ProcessInfo.processInfo.environment["PATH"] else {
            return nil
        }
        for dir in pathVar.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir))
                .appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private var fetchScriptPath: String {
        Bundle.main.resourceURL?
            .appendingPathComponent("fetch_nous_usage.py").path
            ?? "/Users/hartmuth/Documents/Hermes/nous-statusbar/fetch_nous_usage.py"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

        refreshNow()

        // Refresh every 5 minutes.
        refreshTimer = Timer.scheduledTimer(timeInterval: 300, target: self,
                                            selector: #selector(refreshNow),
                                            userInfo: nil, repeats: true)
        // Also refresh when the menu opens (NSMenuDelegate below).

        // Update check: once at launch (silent), then weekly.
        checkForUpdates()
        updateTimer = Timer.scheduledTimer(timeInterval: 7 * 24 * 3600, target: self,
                                           selector: #selector(checkForUpdates),
                                           userInfo: nil, repeats: true)
    }

    // MARK: - Fetch

    @objc func refreshNow() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = [fetchScriptPath]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
        } catch {
            setPayload(nil, error: "could not launch fetch: \(error.localizedDescription)")
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard let text = String(data: data, encoding: .utf8),
              let jsonData = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(UsagePayload.self, from: jsonData) else {
            setPayload(nil, error: "unparsable fetch output")
            return
        }
        setPayload(decoded, error: nil)
    }

    private func setPayload(_ p: UsagePayload?, error: String?) {
        var final = p
        if error != nil {
            final = UsagePayload(ok: false, source: nil, plan: nil, monthly_credits: nil,
                                 subscription_remaining: nil, purchased_remaining: nil,
                                 total_usable: nil, period_end: nil, org_name: nil,
                                 email: nil, error: error)
        }
        payload = final
        updateStatusLabel()
        rebuildMenu()
    }

    // MARK: - Label

    private func updateStatusLabel() {
        guard let button = statusItem.button else { return }

        guard let p = payload, p.ok, let usable = p.total_usable else {
            let attr = NSMutableAttributedString(string: "● N/A",
                                                 attributes: [.foregroundColor: NSColor.systemRed])
            button.attributedTitle = attr
            button.toolTip = payload?.error ?? "Nous usage unavailable"
            return
        }

        let color: NSColor
        if usable < 10 { color = .systemRed }
        else if usable < 30 { color = .systemOrange }
        else { color = .systemGreen }

        let title = String(format: "●  $%.2f", usable)
        let attr = NSMutableAttributedString(string: title)
        attr.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: 1))
        attr.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 1, length: attr.length - 1))
        button.attributedTitle = attr
        button.toolTip = buildTooltip(p)
    }

    private func buildTooltip(_ p: UsagePayload) -> String {
        var lines = ["Nous Portal — \(p.plan ?? "plan")"]
        if let s = p.subscription_remaining { lines.append(String(format: "Subscription: $%.2f", s)) }
        if let s = p.purchased_remaining { lines.append(String(format: "Top-up: $%.2f", s)) }
        if let s = p.monthly_credits { lines.append(String(format: "Monthly credits: $%.2f", s)) }
        if let e = p.period_end { lines.append("Renews: \(e.prefix(10))") }
        return lines.joined(separator: "\n")
    }

    // MARK: - Update checking

    /// Query the GitHub latest-release API and compare against the installed version.
    @objc func checkForUpdates() {
        updateCheckState = "checking"
        rebuildMenu()

        guard let url = URL(string: "https://api.github.com/repos/ww-hardy/nous-usage-bar/releases/latest") else {
            updateCheckState = "error"
            rebuildMenu()
            return
        }
        var request = URLRequest(url: url)
        request.setValue("NousUsageBar/\(localVersion)", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            var latest: String?
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String {
                latest = tag
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let latest = latest {
                    self.latestVersion = latest
                    self.updateAvailable = Self.compareVersions(latest, self.localVersion) > 0
                    self.updateCheckState = "done"
                } else {
                    self.updateCheckState = "error"
                }
                self.rebuildMenu()
            }
        }
        task.resume()
    }

    /// Run the pull-from-git updater (update.sh) if a checkout is found on disk,
    /// otherwise point the user at the GitHub Releases page.
    @objc private func performUpdate() {
        if let repo = findRepoCheckout() {
            runUpdateScript(in: repo)
        } else {
            openURL("https://github.com/ww-hardy/nous-usage-bar/releases")
        }
    }

    /// Locate a local clone of the repo (where update.sh lives).
    private func findRepoCheckout() -> String? {
        let candidates = [
            NSHomeDirectory() + "/Documents/Hermes/nous-statusbar",
            NSHomeDirectory() + "/nous-usage-bar",
            NSHomeDirectory() + "/Documents/nous-usage-bar",
            NSHomeDirectory() + "/Developer/nous-usage-bar",
            NSHomeDirectory() + "/src/nous-usage-bar",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c + "/update.sh") {
            return c
        }
        return nil
    }

    /// Kick off update.sh in the repo checkout, then exit — update.sh rebuilds,
    /// kills the old instance, and relaunches the new build itself.
    private func runUpdateScript(in dir: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["update.sh"]
        proc.currentDirectoryURL = URL(fileURLWithPath: dir)
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            openURL("https://github.com/ww-hardy/nous-usage-bar/releases")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSApp.terminate(nil)
        }
    }

    /// Compare dotted version strings ("v1.2.0" vs "1.1.0"): > 0 if a is newer.
    private static func compareVersions(_ a: String, _ b: String) -> Int {
        let ta = Self.components(a), tb = Self.components(b)
        for i in 0..<max(ta.count, tb.count) {
            let x = i < ta.count ? ta[i] : 0
            let y = i < tb.count ? tb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    private static func components(_ v: String) -> [Int] {
        v.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .compactMap { Int($0) }
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        guard let p = payload, p.ok else {
            let err = NSMenuItem(title: payload?.error ?? "Unavailable", action: nil, keyEquivalent: "")
            err.isEnabled = false
            menu.addItem(err)
            addRefreshFooter(menu)
            statusItem.menu = menu
            return
        }

        let header = NSMenuItem(title: "Nous Portal — \(p.plan ?? "account")", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        func addRow(_ label: String, _ value: String) {
            let item = NSMenuItem(title: "\(label)\t\(value)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        if let usable = p.total_usable { addRow("Total usable", dollar(usable)) }
        if let sub = p.subscription_remaining { addRow("Subscription credits", dollar(sub)) }
        if let pur = p.purchased_remaining { addRow("Top-up credits", dollar(pur)) }
        if let mc = p.monthly_credits { addRow("Monthly credits", dollar(mc)) }
        if let pe = p.period_end, pe.count >= 10 { addRow("Renews", String(pe.prefix(10))) }

        menu.addItem(.separator())

        let openBilling = NSMenuItem(title: "Open billing page…", action: #selector(openBilling), keyEquivalent: "b")
        openBilling.target = self
        menu.addItem(openBilling)

        let topup = NSMenuItem(title: "Top up…", action: #selector(openTopup), keyEquivalent: "t")
        topup.target = self
        menu.addItem(topup)

        menu.addItem(.separator())

        // Update section: button + status + manual check.
        let updateTitle = updateAvailable
            ? "⬆ Update NousUsageBar — \(latestVersion ?? "new version") available"
            : "Update NousUsageBar"
        let updateItem = NSMenuItem(title: updateTitle, action: #selector(performUpdate), keyEquivalent: "u")
        updateItem.target = self
        updateItem.isEnabled = updateAvailable
        menu.addItem(updateItem)

        let statusTitle: String
        switch updateCheckState {
        case "checking": statusTitle = "Checking for updates…"
        case "error": statusTitle = "Update check failed"
        case "done":
            statusTitle = updateAvailable
                ? "Installed: v\(localVersion) · Latest: \(latestVersion ?? "?")"
                : "Up to date — v\(localVersion)"
        default: statusTitle = "Latest: \(latestVersion ?? "unknown")"
        }
        let statusRow = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusRow.isEnabled = false
        menu.addItem(statusRow)

        let checkItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        checkItem.target = self
        menu.addItem(checkItem)

        addRefreshFooter(menu)

        statusItem.menu = menu
    }

    private func addRefreshFooter(_ menu: NSMenu) {
        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "Refresh now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        let quit = NSMenuItem(title: "Quit NousUsageBar", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func dollar(_ v: Double) -> String { String(format: "$%.2f", v) }

    @objc private func openBilling() {
        openURL("https://portal.nousresearch.com/billing")
    }

    @objc private func openTopup() {
        openURL("https://portal.nousresearch.com/billing?topup=open")
    }

    private func openURL(_ s: String) {
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}

// Refresh on menu open so the numbers are always fresh when the user looks.
extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) { refreshNow() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
