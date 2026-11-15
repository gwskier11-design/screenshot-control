import SwiftUI
import UIKit
import Darwin

struct ContentView: View {
    @State private var status = "Ready"
    @State private var busy = false
    @State private var log = ""
    private let group = "group.com.georgewatts.screenshotcontrol"
    private let targetBundle = "com.georgewatts.screenshottest"

    var body: some View {
        NavigationStack {
            Form {
                Section("Control") {
                    Button("Disable Screenshot Test alert") { changeAlert(to: false) }
                        .disabled(busy)
                    Button("Enable Screenshot Test alert") { changeAlert(to: true) }
                        .disabled(busy)
                    Text(status)
                }
                Section("Log") {
                    ScrollView {
                        Text(log.isEmpty ? "No attempt yet" : log)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 220)
                    HStack {
                        Button("Copy Log") { UIPasteboard.general.string = log }
                            .disabled(log.isEmpty)
                        Spacer()
                        Button("Clear") { log = "" }
                            .disabled(busy || log.isEmpty)
                    }
                }
            }
            .navigationTitle("Screenshot Control")
        }
    }

    private func changeAlert(to enabled: Bool) {
        busy = true
        status = "Working..."
        appendLog("Requested alert setting: \(enabled)")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = updateTarget(enabled: enabled) { message in
                DispatchQueue.main.async { appendLog(message) }
            }
            DispatchQueue.main.async {
                appendLog(result)
                status = result
                busy = false
            }
        }
    }

    private func appendLog(_ message: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        log += "[\(time)] \(message)\n"
    }

    private func updateTarget(enabled: Bool, progress: (String) -> Void) -> String {
        let root = "/private/var/mobile/Containers/Data/Application"
        progress("Requesting access to app container directory")
        let rootHandle = worse_query(root, group, false, false)
        let paths: [String]
        if rootHandle >= 0 {
            progress("Directory access granted")
            paths = (try? FileManager.default.contentsOfDirectory(atPath: root))?.map { root + "/" + $0 } ?? []
            worse_query_release(rootHandle)
        } else {
            progress("Directory access returned \(rootHandle). Scanning container paths")
            let baseline = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            guard (try? Data([0]).write(to: baseline)) != nil else { return "Could not create scan marker" }
            var info = stat()
            let found = stat(baseline.path, &info) == 0
            try? FileManager.default.removeItem(at: baseline)
            guard found else { return "Could not scan app containers" }
            paths = pathleak(root, info.st_ino) ?? []
        }
        progress("Found \(paths.count) candidate containers")
        var accessible = 0
        for path in paths {
            let handle = worse_query(path, group, false, false)
            guard handle >= 0 else { continue }
            accessible += 1
            var buffer = [CChar](repeating: 0, count: 512)
            let length = getxattr(path, "com.apple.containermanager.identifier", &buffer, buffer.count, 0, 0)
            guard length > 0, String(cString: buffer) == targetBundle else {
                worse_query_release(handle)
                continue
            }
            progress("Screenshot Test container found after \(accessible) accessible containers")
            let file = URL(fileURLWithPath: path).appendingPathComponent("Documents/ScreenshotSettings.plist")
            guard FileManager.default.fileExists(atPath: file.path) else {
                worse_query_release(handle)
                return "Open Screenshot Test once to create its settings file"
            }
            progress("Writing Documents/ScreenshotSettings.plist")
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: ["alertsEnabled": enabled], format: .xml, options: 0)
                try data.write(to: file, options: .atomic)
                let stored = try Data(contentsOf: file)
                let value = try PropertyListSerialization.propertyList(from: stored, format: nil) as? [String: Bool]
                worse_query_release(handle)
                return value?["alertsEnabled"] == enabled ? "Readback verified. Reopen Screenshot Test and take a screenshot." : "Write verification failed"
            } catch {
                worse_query_release(handle)
                return "Could not edit settings: \(error.localizedDescription)"
            }
        }
        return "Screenshot Test container unavailable. Accessed \(accessible) of \(paths.count) candidates."
    }
}
