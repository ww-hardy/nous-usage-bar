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
    private var payload: UsagePayload?

    private var pythonPath: String {
        // The Hermes venv python (resolved from the `hermes` shim on PATH).
        let candidates = [
            "/Users/hartmuth/.hermes/hermes-agent/venv/bin/python",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        return "/usr/bin/python3"
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
