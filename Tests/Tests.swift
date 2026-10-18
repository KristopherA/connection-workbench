import Foundation
import CryptoKit

@main struct Tests {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        count += 1
        if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func fixture(_ target: Target) -> Capture {
        Capture(label: "Test", target: target, osVersion: "Test OS", evidence: [Evidence(id: "resolution", command: "fixture", output: "ip_address: 127.0.0.1\n", exitCode: 0, timedOut: false), Evidence(id: "direct", command: "fixture", output: "http_code=200\nremote_ip=127.0.0.1\n", exitCode: 0, timedOut: false)], systemProbe: WebProbe(status: 200, duration: 0.1, certificates: ["aaa"]))
    }
    static func main() throws {
        for invalid in ["", "file:///etc/passwd", "ftp://example.com", "https://u:p@example.com", "https://example.com?token=x", "https://example.com#secret", "https://example.com:0", "https://example.com:65536", "--help", "example.com\n--insecure"] {
            do { _ = try Target(invalid); check(false, "rejected \(invalid)") } catch { check(true, "invalid target") }
        }
        let target = try Target("example.com")
        check(target.url == "https://example.com", "default HTTPS")
        let ipv6 = try Target("http://[::1]:8080")
        check(ipv6.host == "::1", "IPv6 target")
        let a = fixture(target)
        check(Analysis.findings(a,a).contains { $0.id == "same" }, "same capture has no differences")
        var b = a
        b.evidence[0].output = "ip_address: 10.1.2.3\n"
        check(Analysis.findings(a,b).contains { $0.id == "resolution" }, "DNS diff detected")
        b.systemProbe.certificates = ["bbb"]
        check(Analysis.findings(a,b).contains { $0.id == "certs" }, "certificate diff detected")
        b.systemProbe.certificates = []
        check(!Analysis.findings(a,b).contains { $0.id == "certs" }, "missing certificate not asserted as change")
        b.systemProbe.status = nil
        b.systemProbe.error = "test failure"
        check(Analysis.findings(a,b).contains { $0.id == "B-paths" }, "path discrepancy detected")
        b.target = try Target("https://different.example")
        check(Analysis.findings(a,b).first?.id == "target", "different targets rejected")
        let timeout = Runner.run("timeout", "/bin/sleep", ["3"], timeout: 0.1)
        check(timeout.timedOut && timeout.duration < 2, "bounded process timeout")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("capture.json")
        try Files.save(a, to: file, overwrite: false)
        do { try Files.save(a, to: file, overwrite: false); check(false, "existing capture not overwritten") } catch { check(true, "existing capture protected") }
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        check(mode == 0o600, "saved capture owner-only permissions")
        let loaded = try Files.read(file)
        check(loaded.target == a.target && loaded.id == a.id, "capture roundtrip")
        var broken = a; broken.schemaVersion = 99
        try Files.encoder.encode(broken).write(to: file)
        do { _ = try Files.read(file); check(false, "unsupported schema rejected") } catch { check(true, "schema validation") }
        let zip = dir.appendingPathComponent("bundle.zip")
        try Files.bundle(a,a,to:zip)
        let listing = Runner.run("unzip", "/usr/bin/unzip", ["-Z1", zip.path])
        check(listing.exitCode == 0 && listing.output.contains("SHA256SUMS.txt") && listing.output.contains("capture-B.json"), "bundle contains report captures manifest")
        let extraction = dir.appendingPathComponent("unpacked")
        let extract = Runner.run("unzip", "/usr/bin/unzip", ["-q", zip.path, "-d", extraction.path])
        check(extract.exitCode == 0, "bundle extracts")
        let folders = try FileManager.default.contentsOfDirectory(at: extraction, includingPropertiesForKeys: nil)
        let manifest = try String(contentsOf: folders[0].appendingPathComponent("SHA256SUMS.txt"), encoding: .utf8)
        check(manifest.split(separator: "\n").count == 3, "manifest includes all three payloads")
        for line in manifest.split(separator: "\n") {
            let fields = line.split(separator: " ")
            let payload = try Data(contentsOf: folders[0].appendingPathComponent(String(fields[1])))
            let hash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
            check(hash == fields[0], "export checksum matches payload")
        }
        if CommandLine.arguments.count > 1 {
            let local = try Target(CommandLine.arguments[1])
            let capture = Collector.collect(target: local, label: "Loopback integration") { print($0) }
            check(capture.systemProbe.status == 204, "system HTTP HEAD probe")
            check(Analysis.metrics(capture)["http_code"] == "204", "direct HTTP HEAD probe")
            check(capture.item("direct")?.exitCode == 0, "direct successful exit")
            check(capture.systemProbe.certificates.isEmpty, "HTTP not classified as TLS")
            var components = URLComponents(string: local.url)!
            components.path = "/redirect"
            let redirect = SystemProbe().perform(try Target(components.url!.absoluteString))
            check(redirect.status == 302, "application redirect not followed")
            components.path = "/head-not-supported"
            let method = SystemProbe().perform(try Target(components.url!.absoluteString))
            check(method.status == 405, "HEAD unsupported reported as HTTP response")
            components.path = "/disconnect"
            let unreachable = SystemProbe().perform(try Target(components.url!.absoluteString))
            check(unreachable.status == nil && unreachable.error != nil, "failed connection has no passing response")
            if CommandLine.arguments.count > 2 {
                let untrusted = SystemProbe().perform(try Target(CommandLine.arguments[2]))
                check(untrusted.status == nil && untrusted.error != nil, "untrusted TLS certificate rejected")
            }
        }
        print("PASS: \(count) checks")
    }
}
