import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor final class Workbench: ObservableObject {
    @Published var target = ""
    @Published var labelA = "VPN connected"
    @Published var labelB = "VPN disconnected"
    @Published var a: Capture?
    @Published var b: Capture?
    @Published var busy = false
    @Published var progress = ""
    @Published var message: String?
    @Published var tab = 0
    @Published var evidenceID = "resolution"
    func capture(_ slot: Int) {
        do {
            let endpoint = try Target(target)
            if let other = slot == 0 ? b : a, other.target != endpoint { throw WorkError.message("Use the same URL for both captures, or start a new comparison.") }
            let label = (slot == 0 ? labelA : labelB).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, label.count <= 120 else { throw WorkError.message("Add a condition label of 1–120 characters.") }
            busy = true
            progress = "Starting capture…"
            Task { [self] in
                let result = await Task.detached { [weak self] in
                    Collector.collect(target: endpoint, label: label) { text in
                        Task { @MainActor in self?.progress = text }
                    }
                }.value
                if slot == 0 { a = result } else { b = result }
                busy = false
                progress = "Capture \(slot == 0 ? "A" : "B") complete."
            }
        } catch { message = error.localizedDescription }
    }
    func load(_ slot: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.message = "Choose a Connection Workbench capture JSON. Importing never runs a probe."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let c = try Files.read(url)
            if let other = slot == 0 ? b : a, other.target != c.target { throw WorkError.message("Imported capture has a different target. Start a new comparison to use it.") }
            target = c.target.url
            if slot == 0 { a = c; labelA = c.label } else { b = c; labelB = c.label }
        } catch { message = error.localizedDescription }
    }
    func save(_ c: Capture) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "capture-\(c.started.formatted(.iso8601.year().month().day()))-\(c.id.uuidString.prefix(8)).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Files.save(c, to: url) } catch { message = error.localizedDescription }
    }
    func export() {
        guard let a else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.zip]; panel.nameFieldStringValue = "Connection-Workbench-Support.zip"
        panel.message = "Contains internal DNS, IPs, proxy configuration, target paths, and labels. This bundle is not redacted or encrypted. Review before sharing."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Files.bundle(a,b,to:url); progress = "Support bundle saved." } catch { message = error.localizedDescription }
    }
}

@main struct ConnectionWorkbenchApp: App {
    @StateObject private var model = Workbench()
    var body: some Scene {
        WindowGroup("Connection Workbench") { ContentView().environmentObject(model) }
            .defaultSize(width: 1160, height: 820)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}

struct ContentView: View {
    @EnvironmentObject var m: Workbench
    private let accent = Color(red: 0.04, green: 0.48, blue: 0.48)
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 34)).foregroundStyle(accent)
                Text("CONNECTION\nWORKBENCH").font(.system(size: 15, weight: .bold, design: .rounded)).tracking(2)
                Text("A clear path from symptom to evidence.").font(.callout).foregroundStyle(.secondary)
                Divider()
                step("1", "Choose a target", "Use the exact service URL.")
                step("2", "Capture condition A", "Reproduce the first condition.")
                step("3", "Change one thing", "For example, connect the VPN.")
                step("4", "Capture condition B", "Keep the target unchanged.")
                step("5", "Compare & hand off", "Review findings and export.")
                Spacer()
                Label("Local collection", systemImage: "internaldrive").font(.caption)
                Text("No admin access or agent required. Captures stay in memory until you save or export them.").font(.caption).foregroundStyle(.secondary)
                Text("macOS 13+ · v1.0").font(.caption2).foregroundStyle(.secondary)
            }.padding(24).frame(width: 220).frame(maxHeight: .infinity).background(accent.opacity(0.055))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Find the difference.").font(.system(size: 30, weight: .semibold, design: .rounded))
                            Text("Compare two connection attempts with the evidence attached.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("New comparison") { m.a = nil; m.b = nil; m.progress = "" }.disabled(m.busy || (m.a == nil && m.b == nil))
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SERVICE TO TEST").font(.caption.weight(.semibold)).tracking(1)
                        TextField("https://service.example.com", text: $m.target).textFieldStyle(.roundedBorder).font(.system(size: 16)).disabled(m.busy || m.a != nil || m.b != nil)
                        Text("Hostname or HTTP(S) URL. No passwords, query strings, or fragments. Requests use HEAD and do not follow redirects.").font(.caption).foregroundStyle(.secondary)
                        Label("Uses built-in macOS tools. No administrator access required.", systemImage: "desktopcomputer").font(.callout).foregroundStyle(.secondary)
                    }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 14))
                    HStack(alignment: .top, spacing: 14) { captureCard(0); captureCard(1) }
                    if m.busy { HStack { ProgressView().controlSize(.small); Text(m.progress).font(.callout); Spacer(); Text("Usually under a minute").font(.caption).foregroundStyle(.secondary) } }
                    else if !m.progress.isEmpty { Label(m.progress, systemImage: "checkmark.circle").font(.callout).foregroundStyle(accent) }
                    if let a = m.a {
                        HStack {
                            Picker("View", selection: $m.tab) { Text("Findings").tag(0); Text("Evidence").tag(1); Text("Scope").tag(2) }.pickerStyle(.segmented).frame(width: 320)
                            Spacer()
                            Button { m.export() } label: { Label("Export support bundle", systemImage: "square.and.arrow.up") }.disabled(m.busy)
                        }
                        if m.tab == 0 {
                            if m.b == nil { Label("Capture B to compare conditions. Findings below describe A only.", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
                            ForEach(Analysis.findings(a,m.b)) { finding in
                                VStack(alignment: .leading, spacing: 9) {
                                    Text(finding.title).font(.headline)
                                    Text(finding.detail).font(.callout).textSelection(.enabled)
                                    Text("Next test · " + finding.next).font(.callout).foregroundStyle(accent)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.background, in: RoundedRectangle(cornerRadius: 12))
                            }
                        } else if m.tab == 1 { evidence(a) }
                        else { scope }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "arrow.left.arrow.right.square").font(.system(size: 32)).foregroundStyle(accent)
                            Text("Two conditions. One useful comparison.").font(.headline)
                            Text("Capture on this Mac, or import a saved JSON capture from another workstation. Use the same service URL on both.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(30)
                    }
                }.padding(28)
            }.background(Color(nsColor: .windowBackgroundColor))
        }.frame(minWidth: 980, minHeight: 720).tint(accent)
            .alert("Connection Workbench", isPresented: Binding(get: { m.message != nil }, set: { if !$0 { m.message = nil } })) { Button("OK") { m.message = nil } } message: { Text(m.message ?? "") }
    }
    func step(_ n: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.caption.bold()).frame(width: 23, height: 23).background(accent.opacity(0.12), in: Circle()).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.callout.weight(.semibold)); Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
    func captureCard(_ slot: Int) -> some View {
        let c = slot == 0 ? m.a : m.b
        return VStack(alignment: .leading, spacing: 12) {
            HStack { Text(slot == 0 ? "A · FIRST CONDITION" : "B · SECOND CONDITION").font(.caption.weight(.semibold)).tracking(0.8); Spacer(); if c != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) } }
            TextField("Describe the network condition", text: slot == 0 ? $m.labelA : $m.labelB).textFieldStyle(.roundedBorder).disabled(m.busy || c != nil)
            if let c {
                Text(c.started.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.secondary)
                Text("Application: " + (c.systemProbe.status.map { "HTTP \($0)" } ?? "No HTTP response")).font(.callout.weight(.medium))
                Text("Direct: " + (Analysis.metrics(c)["http_code"].flatMap { $0 == "000" ? nil : "HTTP \($0)" } ?? "No HTTP response")).font(.callout)
                HStack { Button("Save capture…") { m.save(c) }; Button("Retake") { if slot == 0 { m.a = nil } else { m.b = nil } } }.disabled(m.busy)
            } else {
                Text(slot == 0 ? "Set up the first condition, then capture." : "Change one condition, then capture again.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Capture \(slot == 0 ? "A" : "B")") { m.capture(slot) }.buttonStyle(.borderedProminent).disabled(m.target.isEmpty || m.busy)
                    Button("Import…") { m.load(slot) }.disabled(m.busy)
                }
            }
        }.frame(maxWidth: .infinity, minHeight: 145, alignment: .topLeading).padding(18).background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
    func evidence(_ a: Capture) -> some View {
        let ids = Array(Set(a.evidence.map(\.id) + (m.b?.evidence.map(\.id) ?? []) + ["application"])).sorted()
        return VStack(alignment: .leading, spacing: 14) {
            Picker("Evidence source", selection: $m.evidenceID) { ForEach(ids, id: \.self) { Text($0).tag($0) } }.frame(maxWidth: 400)
            HStack(alignment: .top, spacing: 12) { evidenceColumn(a,"A"); if let b = m.b { evidenceColumn(b,"B") } }
        }
    }
    func evidenceColumn(_ c: Capture, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title + " · " + c.label).font(.headline)
            if m.evidenceID == "application" {
                Text("URLSession HEAD · redirects disabled\nHTTP: \(c.systemProbe.status.map(String.init) ?? "not observed")\nDuration: \(String(format: "%.2f", c.systemProbe.duration))s\nError: \(c.systemProbe.error ?? "none")\nCertificate chain SHA-256:\n" + (c.systemProbe.certificates.isEmpty ? "Not observed" : c.systemProbe.certificates.joined(separator: "\n"))).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            } else if let e = c.item(m.evidenceID) {
                Text("Exit \(e.exitCode) · \(e.timedOut ? "Timed out" : String(format: "%.2fs", e.duration))\n\(e.started.ISO8601Format())").font(.caption).foregroundStyle(.secondary)
                Text(e.command).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                Divider()
                Text(e.output.isEmpty ? "No output observed." : e.output).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            } else { Text("Not collected in this capture.").foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
    var scope: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What this procedure establishes").font(.headline)
            Text("Each capture samples DNS, proxy settings, network context, listed VPN services, resolver answers, and routes for up to eight resolved addresses. It then sends two unauthenticated HEAD requests to your target.")
            Text("The application probe uses ephemeral URLSession with default certificate validation. The direct curl probe disables configured HTTP proxies and curl configuration files. VPNs and transparent network filters still apply. Neither probe follows redirects or saves response bodies or headers.")
            Text("A response—even 401, 403, or 405—shows an HTTP exchange, not a working login or healthy application. Browser DNS, certificate stores, extensions, authentication, and PAC behavior may differ. Capture observations are sequential, not an atomic network snapshot.")
            Text("No hostname, username, serial number, cookies, or stored credentials are deliberately collected. DNS and proxy configuration can still disclose internal names, addresses, PAC URLs, and identifiers. Labels and target paths can contain sensitive information. Exports are not redacted or encrypted.")
            Text("A differing setting is a lead for the next test, not proof of the cause. Unavailable evidence and absent certificate fingerprints must not be interpreted as a pass.")
        }.font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(20).background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
}
