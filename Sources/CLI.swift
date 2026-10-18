import Foundation

@main struct CLI {
    static func main() {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard args.first == "capture", args.count == 6, args[2] == "--label", args[4] == "--output" else {
                print("Usage: connection-workbench capture https://service.example.com --label 'VPN connected' --output capture.json\nRuns unauthenticated HEAD probes; captures contain internal network details. No administrator access required.")
                exit(args.isEmpty || args == ["--help"] ? 0 : 2)
            }
            let target = try Target(args[1])
            guard !args[3].isEmpty, args[3].count <= 120 else { throw WorkError.message("Label must contain 1–120 characters.") }
            let destination = URL(fileURLWithPath: args[5])
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw WorkError.message("Output already exists. Choose another filename.") }
            let c = Collector.collect(target: target, label: args[3]) { print($0) }
            try Files.save(c, to: destination, overwrite: false)
            print("Saved \(destination.path)")
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
}
