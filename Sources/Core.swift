import Foundation
import Security
import CryptoKit

struct Target: Codable, Equatable {
    let url: String
    let host: String
    let port: Int
    init(_ input: String) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count < 2048, !text.contains(where: { $0.isWhitespace || $0.isNewline }),
              var c = URLComponents(string: text.contains("://") ? text : "https://" + text),
              let scheme = c.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = c.host, !host.isEmpty, !host.hasPrefix("-"),
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.url != nil, (1...65535).contains(c.port ?? (scheme == "https" ? 443 : 80)) else {
            throw WorkError.message("Enter an HTTP or HTTPS URL or hostname. Remove credentials, query strings, fragments, and spaces. Ports must be 1–65535.")
        }
        c.scheme = scheme
        self.url = c.url!.absoluteString
        self.host = host.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        self.port = c.port ?? (scheme == "https" ? 443 : 80)
    }
}
enum WorkError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
struct Evidence: Codable, Identifiable {
    var id: String
    var command: String
    var output: String
    var exitCode: Int32
    var timedOut: Bool
    var started: Date = Date()
    var duration: Double = 0
}
struct WebProbe: Codable {
    var status: Int?
    var error: String?
    var duration: Double
    var certificates: [String]
}
struct Capture: Codable, Identifiable {
    var schemaVersion = 1
    var appVersion = "1.0.0"
    var id = UUID()
    var started = Date()
    var finished = Date()
    var label: String
    var target: Target
    var osVersion: String
    var evidence: [Evidence]
    var systemProbe: WebProbe
    func item(_ id: String) -> Evidence? { evidence.first { $0.id == id } }
}
struct Finding: Identifiable {
    var id: String
    var title: String
    var detail: String
    var next: String
}

enum Runner {
    static func run(_ id: String, _ path: String, _ args: [String], timeout: Double = 8) -> Evidence {
        let start = Date()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: dir) }
            let out = dir.appendingPathComponent("out")
            FileManager.default.createFile(atPath: out.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let handle = try FileHandle(forWritingTo: out)
            defer { try? handle.close() }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            p.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "HOME": dir.path]
            p.standardOutput = handle
            p.standardError = handle
            p.standardInput = FileHandle.nullDevice
            try p.run()
            let end = Date().addingTimeInterval(timeout)
            while p.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.05) }
            let expired = p.isRunning
            if expired {
                p.terminate()
                Thread.sleep(forTimeInterval: 0.15)
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            }
            p.waitUntilExit()
            let reader = try FileHandle(forReadingFrom: out)
            defer { try? reader.close() }
            let data = try reader.read(upToCount: 262144) ?? Data()
            return Evidence(id: id, command: ([path] + args).joined(separator: " "), output: String(decoding: data, as: UTF8.self), exitCode: p.terminationStatus, timedOut: expired, started: start, duration: Date().timeIntervalSince(start))
        } catch {
            return Evidence(id: id, command: path, output: error.localizedDescription, exitCode: -1, timedOut: false, started: start, duration: Date().timeIntervalSince(start))
        }
    }
}

final class SystemProbe: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var fingerprints: [String] = []
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = challenge.protectionSpace.serverTrust,
           let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] {
            let prints = chain.map { cert in SHA256.hash(data: SecCertificateCopyData(cert) as Data).map { String(format: "%02x", $0) }.joined() }
            lock.lock(); fingerprints = prints; lock.unlock()
            completionHandler(.performDefaultHandling, nil)
        } else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }
    func perform(_ target: Target) -> WebProbe {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let done = DispatchSemaphore(value: 0)
        let box = ProbeBox()
        let start = Date()
        var request = URLRequest(url: URL(string: target.url)!)
        request.httpMethod = "HEAD"
        request.setValue("ConnectionWorkbench/1.0", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: request) { _, response, error in
            box.lock.lock()
            box.status = (response as? HTTPURLResponse)?.statusCode
            box.error = error.map { "\(($0 as NSError).domain) \(($0 as NSError).code): \($0.localizedDescription)" }
            box.lock.unlock()
            done.signal()
        }
        task.resume()
        let timedOut = done.wait(timeout: .now() + 17) == .timedOut
        session.invalidateAndCancel()
        box.lock.lock(); defer { box.lock.unlock() }
        lock.lock(); defer { lock.unlock() }
        return WebProbe(status: box.status, error: timedOut ? "Application probe timed out" : box.error, duration: Date().timeIntervalSince(start), certificates: fingerprints)
    }
}
final class ProbeBox: @unchecked Sendable {
    let lock = NSLock()
    var status: Int?
    var error: String?
}

enum Collector {
    static func collect(target: Target, label: String, progress: @escaping (String) -> Void) -> Capture {
        var capture = Capture(label: label, target: target, osVersion: ProcessInfo.processInfo.operatingSystemVersionString, evidence: [], systemProbe: WebProbe(duration: 0, certificates: []))
        let steps: [(String, String, [String])] = [
            ("dns", "/usr/sbin/scutil", ["--dns"]),
            ("proxy", "/usr/sbin/scutil", ["--proxy"]),
            ("network", "/usr/sbin/scutil", ["--nwi"]),
            ("vpn", "/usr/sbin/scutil", ["--nc", "list"]),
            ("resolution", "/usr/bin/dscacheutil", ["-q", "host", "-a", "name", target.host]),
            ("curlVersion", "/usr/bin/curl", ["--disable", "--version"])
        ]
        for (id, path, args) in steps {
            progress("Collecting \(id)…")
            capture.evidence.append(Runner.run(id, path, args))
        }
        // Route lookup uses numeric resolver results; never asks route to resolve a name through a different resolver.
        let addresses = capture.item("resolution")?.output.components(separatedBy: .newlines).compactMap { line -> String? in
            let parts = line.split(separator: " ")
            guard parts.count == 2, ["ip_address:", "ipv6_address:"].contains(String(parts[0])) else { return nil }
            return String(parts[1])
        } ?? []
        for (i, address) in Array(Set(addresses)).sorted().prefix(8).enumerated() {
            progress("Checking route \(i + 1)…")
            capture.evidence.append(Runner.run("route-\(address)", "/sbin/route", ["-n", "get"] + (address.contains(":") ? ["-inet6"] : ["-inet"]) + [address]))
        }
        progress("Testing macOS application connection…")
        capture.systemProbe = SystemProbe().perform(target)
        progress("Testing direct connection…")
        let format = "http_code=%{http_code}\nremote_ip=%{remote_ip}\nremote_port=%{remote_port}\nlocal_ip=%{local_ip}\ndns_seconds=%{time_namelookup}\ntcp_seconds=%{time_connect}\ntls_seconds=%{time_appconnect}\ntotal_seconds=%{time_total}\nssl_verify_result=%{ssl_verify_result}\n"
        capture.evidence.append(Runner.run("direct", "/usr/bin/curl", ["--disable", "--silent", "--show-error", "--head", "--output", "/dev/null", "--noproxy", "*", "--proxy", "", "--connect-timeout", "6", "--max-time", "12", "--proto", "=http,https", "--write-out", format, "--url", target.url], timeout: 14))
        capture.evidence.append(Runner.run("networkAfter", "/usr/sbin/scutil", ["--nwi"]))
        capture.finished = Date()
        return capture
    }
}

enum Analysis {
    static func metrics(_ c: Capture) -> [String: String] {
        var result: [String: String] = [:]
        for line in (c.item("direct")?.output ?? "").split(separator: "\n") {
            let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if pair.count == 2 { result[String(pair[0])] = String(pair[1]) }
        }
        return result
    }
    static func findings(_ a: Capture, _ b: Capture?) -> [Finding] {
        var result: [Finding] = []
        if let b, a.target != b.target { return [Finding(id: "target", title: "Different targets cannot establish a connection comparison", detail: "A: \(a.target.url)\nB: \(b.target.url)", next: "Capture the same URL, including scheme, port, and path, in both conditions.")] }
        for (index, c) in [a, b].compactMap({ $0 }).enumerated() {
            let prefix = index == 0 ? "A" : "B"
            let direct = c.item("direct")
            let m = metrics(c)
            let directResponse = direct?.exitCode == 0 && m["http_code"] != nil && m["http_code"] != "000"
            if let before = c.item("network"), let after = c.item("networkAfter"), before.exitCode == 0, after.exitCode == 0, before.output != after.output {
                result.append(Finding(id: "\(prefix)-unstable", title: "\(prefix): Network context changed during collection", detail: "The network state before and after the probes differs. Results may span more than one condition.", next: "Wait until the network and VPN are stable, then retake this capture."))
            }
            if let resolution = c.item("resolution"), resolution.exitCode == 0, resolution.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(Finding(id: "\(prefix)-resolution", title: "\(prefix): Resolver query returned no address evidence", detail: "The dscacheutil query produced no output. No destination-specific routes were collected from this query.", next: "Compare the actual connection probes and scoped resolver configuration; an empty lookup alone is not proof of a DNS fault."))
            }
            if c.systemProbe.status != nil && directResponse {
                result.append(Finding(id: "\(prefix)-response", title: "\(prefix): Both probes received HTTP responses", detail: "Application: HTTP \(c.systemProbe.status!). Direct: HTTP \(m["http_code"] ?? "unknown"). Responses establish an HTTP exchange, not application health or successful login.", next: "If the user still sees a failure, compare the affected browser, authentication flow, and exact resource."))
            } else if (c.systemProbe.status != nil) != directResponse {
                result.append(Finding(id: "\(prefix)-paths", title: "\(prefix): Application and direct results differ", detail: "The URLSession probe uses macOS networking behavior; curl is explicitly configured without an HTTP proxy. Different results can involve proxies, PAC, trust, or application behavior. This alone does not identify the cause.", next: "Inspect proxy evidence and compare with the affected application's settings. Do not disable a required security proxy."))
            }
            if let status = c.systemProbe.status, status >= 400 {
                result.append(Finding(id: "\(prefix)-http", title: "\(prefix): Server returned HTTP \(status)", detail: "An HTTP response was received. Authentication, access rules, or the requested path may explain the response. HEAD may be treated differently from GET.", next: "Check the service's expected response and application logs; 401, 403, and 405 can be expected for an unauthenticated HEAD request."))
            }
            if let e = c.systemProbe.error {
                result.append(Finding(id: "\(prefix)-app", title: "\(prefix): Application probe did not receive an HTTP response", detail: e, next: "Review DNS, proxy, route, and direct-probe evidence. A probe failure does not prove the server is down."))
            }
            if let d = direct, d.exitCode != 0 || d.timedOut {
                let meaning: String
                switch d.exitCode { case 6: meaning = "Direct probe could not resolve the hostname."; case 7: meaning = "Direct TCP connection failed."; case 28: meaning = "Direct probe exceeded its time limit."; case 60: meaning = "Direct probe rejected the certificate."; case 35: meaning = "Direct TLS negotiation failed."; default: meaning = "Direct probe failed (exit \(d.exitCode))." }
                result.append(Finding(id: "\(prefix)-direct", title: "\(prefix): \(meaning)", detail: d.output, next: "Compare this stage with the other capture. Direct access may intentionally be blocked when a proxy is required."))
            }
            let missing = c.evidence.filter { $0.id != "direct" && ($0.exitCode != 0 || $0.timedOut) }.map(\.id)
            if !missing.isEmpty { result.append(Finding(id: "\(prefix)-missing", title: "\(prefix): Some evidence was unavailable", detail: missing.joined(separator: ", "), next: "Inspect command results. Unavailable evidence is not a passing test.")) }
            if targetIsHTTP(c) { result.append(Finding(id: "\(prefix)-plain", title: "\(prefix): HTTP target has no TLS assessment", detail: "This capture uses unencrypted HTTP.", next: "Use the HTTPS service URL if certificate or trust behavior is the issue.")) }
        }
        if let b {
            let comparisonStart = result.count
            for (id, title, next) in [
                ("resolution", "Resolver answers differ", "Check whether split DNS, address rotation, or a network change explains the difference. Different addresses alone do not establish a fault."),
                ("dns", "DNS configuration differs", "Review nameserver and scoped resolver changes against the expected VPN configuration."),
                ("proxy", "System proxy configuration differs", "Check PAC and proxy policy with the network team. The app does not execute or inspect PAC logic itself."),
                ("network", "Network reachability context differs", "Compare active interfaces and routes; a tunnel interface alone does not prove VPN connectivity."),
                ("vpn", "Listed VPN service state differs", "Confirm the VPN condition manually. Third-party VPNs may not appear in this list.")
            ] {
                if let x = a.item(id), let y = b.item(id), x.exitCode == 0, y.exitCode == 0, !x.timedOut, !y.timedOut, x.output != y.output {
                    result.append(Finding(id: id, title: title, detail: "Captured \(id) evidence changed between A and B. Open the evidence tab to inspect both observations.", next: next))
                }
            }
            let x = metrics(a), y = metrics(b)
            if x["http_code"] != y["http_code"] || a.item("direct")?.exitCode != b.item("direct")?.exitCode || a.item("direct")?.timedOut != b.item("direct")?.timedOut {
                result.append(Finding(id: "directOutcome", title: "Direct probe outcomes differ", detail: "A: HTTP \(x["http_code"] ?? "not observed"), exit \(a.item("direct").map { String($0.exitCode) } ?? "not observed")\nB: HTTP \(y["http_code"] ?? "not observed"), exit \(b.item("direct").map { String($0.exitCode) } ?? "not observed")", next: "Compare DNS, route, and TLS evidence to locate the first observed difference."))
            }
            if let first = Double(x["total_seconds"] ?? ""), let second = Double(y["total_seconds"] ?? ""), abs(first-second) >= 2, max(first,second) >= 3 * max(min(first,second),0.001) {
                result.append(Finding(id: "timing", title: "Direct probe duration differs substantially", detail: String(format: "A: %.2fs; B: %.2fs. These are single samples, not performance statistics.", first, second), next: "Repeat captures under stable conditions before attributing a performance problem."))
            }
            let routeA = a.evidence.filter { $0.id.hasPrefix("route-") }.map { $0.id + "\n" + $0.output }.sorted()
            let routeB = b.evidence.filter { $0.id.hasPrefix("route-") }.map { $0.id + "\n" + $0.output }.sorted()
            if routeA != routeB { result.append(Finding(id: "routes", title: "Collected route evidence differs", detail: "Routes or the set of resolved destinations changed. Review route entries for gateways, interfaces, and collection failures.", next: "Check the expected VPN and destination-specific route. Different destination addresses can produce different route entries without a routing fault.")) }
            if x["remote_ip"] != y["remote_ip"] { result.append(Finding(id: "peer", title: "Direct connection peer differs", detail: "A: \(x["remote_ip"] ?? "not observed")\nB: \(y["remote_ip"] ?? "not observed")", next: "Check DNS answers, load balancing, and routes. This is an observed difference, not proof of redirection.")) }
            if !a.systemProbe.certificates.isEmpty, !b.systemProbe.certificates.isEmpty, a.systemProbe.certificates != b.systemProbe.certificates {
                result.append(Finding(id: "certs", title: "Presented certificate chains differ", detail: "SHA-256 fingerprints from the application probe differ. Renewal, alternate servers, and TLS inspection can all change the chain.", next: "Validate the change with the service or security team before attributing it to interception."))
            }
            if a.systemProbe.status != b.systemProbe.status { result.append(Finding(id: "status", title: "Application HTTP outcomes differ", detail: "A: \(a.systemProbe.status.map(String.init) ?? "no response")\nB: \(b.systemProbe.status.map(String.init) ?? "no response")", next: "Use the first differing evidence stage to choose the next test. The comparison shows correlation, not causation.")) }
            if result.count == comparisonStart { result.append(Finding(id: "same", title: "No tracked comparison differences found", detail: "These bounded probes may miss browser-specific DNS, authentication, intermittent faults, or configuration changes during collection.", next: "Reproduce the user's symptom and capture again while it is happening.")) }
        }
        return result
    }
    static func targetIsHTTP(_ c: Capture) -> Bool { c.target.url.hasPrefix("http:") }
}

enum Files {
    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e }()
    static func save(_ capture: Capture, to url: URL, overwrite: Bool = true) throws {
        // Foundation explicitly disallows combining atomic and withoutOverwriting.
        try encoder.encode(capture).write(to: url, options: overwrite ? .atomic : .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func read(_ url: URL) throws -> Capture {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 5_000_000 else { throw WorkError.message("Capture exceeds the 5 MB import limit.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let c = try decoder.decode(Capture.self, from: Data(contentsOf: url))
        guard c.schemaVersion == 1, try Target(c.target.url) == c.target, c.evidence.count < 100 else { throw WorkError.message("Unsupported or inconsistent capture file.") }
        return c
    }
    static func report(_ a: Capture, _ b: Capture?) -> String {
        var text = "# Connection Workbench report\n\nGenerated: \(Date().ISO8601Format())\n\n"
        for (index, c) in [a,b].compactMap({ $0 }).enumerated() {
            text += "## \(index == 0 ? "A" : "B"): \(c.label)\n\nTarget: \(c.target.url)\n\nStarted: \(c.started.ISO8601Format())\nFinished: \(c.finished.ISO8601Format())\nOS: \(c.osVersion)\n\nApplication HTTP: \(c.systemProbe.status.map(String.init) ?? "not observed")\nError: \(c.systemProbe.error ?? "none")\nCertificate SHA-256: \(c.systemProbe.certificates.joined(separator: ", "))\n\n"
        }
        text += "## Findings\n\n"
        for f in Analysis.findings(a,b) { text += "### \(f.title)\n\n\(f.detail)\n\nNext: \(f.next)\n\n" }
        text += "## Scope and handling\n\nHEAD requests only. No redirects followed, response bodies saved, cookies sent, or stored login credentials supplied. macOS URLSession and direct curl are separate observations and do not reproduce every browser. Direct means no configured HTTP proxy; VPNs and transparent filters may still apply. Configuration is sampled sequentially and can change during capture. DNS answers can vary normally. Certificate fingerprints may be unavailable when a trust challenge was not observed. scutil VPN output does not cover every third-party tunnel. Reports and JSON contain internal hostnames, IPs, proxy URLs, target paths, and operator labels; review before sharing. Bundles are not redacted or encrypted. Hashes detect later file changes; they do not establish authenticity or chain of custody.\n"
        return text
    }
    static func bundle(_ a: Capture, _ b: Capture?, to destination: URL) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ConnectionWorkbench-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }
        var entries: [(String, Data)] = [("capture-A.json", try encoder.encode(a)), ("report.md", Data(report(a,b).utf8))]
        if let b { entries.append(("capture-B.json", try encoder.encode(b))) }
        var hashes = ""
        for (name, data) in entries {
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
            hashes += SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + "  " + name + "\n"
        }
        try Data(hashes.utf8).write(to: dir.appendingPathComponent("SHA256SUMS.txt"))
        let result = Runner.run("export", "/usr/bin/ditto", ["-c", "-k", "--keepParent", dir.path, destination.path], timeout: 20)
        guard result.exitCode == 0, !result.timedOut else { throw WorkError.message("Export failed: " + result.output) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}
