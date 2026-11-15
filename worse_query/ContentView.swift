import SwiftUI
import Darwin

struct ContentView: View {
    @State private var status = "Ready"
    @State private var busy = false
    private let group = "group.com.georgewatts.screenshotcontrol"
    private let targetBundle = "com.georgewatts.screenshottest"

    var body: some View {
        NavigationStack {
            Form {
                Button("Disable Screenshot Test alert") { changeAlert(to: false) }
                    .disabled(busy)
                Button("Enable Screenshot Test alert") { changeAlert(to: true) }
                    .disabled(busy)
                Text(status).textSelection(.enabled)
            }
            .navigationTitle("Screenshot Control")
        }
    }

    private func changeAlert(to enabled: Bool) {
        busy = true
        status = "Finding Screenshot Test data..."
        DispatchQueue.global(qos: .userInitiated).async {
            let result = updateTarget(enabled: enabled)
            DispatchQueue.main.async {
                status = result
                busy = false
            }
        }
    }

    private func updateTarget(enabled: Bool) -> String {
        let root = "/private/var/mobile/Containers/Data/Application"
        let rootHandle = worse_query(root, group, false, false)
        let paths: [String]
        if rootHandle >= 0 {
            paths = (try? FileManager.default.contentsOfDirectory(atPath: root))?.map { root + "/" + $0 } ?? []
            worse_query_release(rootHandle)
        } else {
            let baseline = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            guard (try? Data([0]).write(to: baseline)) != nil else { return "Could not create scan marker" }
            var info = stat()
            let found = stat(baseline.path, &info) == 0
            try? FileManager.default.removeItem(at: baseline)
            guard found else { return "Could not scan app containers" }
            paths = pathleak(root, info.st_ino) ?? []
        }
        for path in paths {
            let handle = worse_query(path, group, false, false)
            guard handle >= 0 else { continue }
            var buffer = [CChar](repeating: 0, count: 512)
            let length = getxattr(path, "com.apple.containermanager.identifier", &buffer, buffer.count, 0, 0)
            guard length > 0, String(cString: buffer) == targetBundle else {
                worse_query_release(handle)
                continue
            }
            let file = URL(fileURLWithPath: path).appendingPathComponent("Documents/ScreenshotSettings.plist")
            guard FileManager.default.fileExists(atPath: file.path) else {
                worse_query_release(handle)
                return "Open Screenshot Test once to create its settings file"
            }
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: ["alertsEnabled": enabled], format: .xml, options: 0)
                try data.write(to: file, options: .atomic)
                let stored = try Data(contentsOf: file)
                let value = try PropertyListSerialization.propertyList(from: stored, format: nil) as? [String: Bool]
                worse_query_release(handle)
                return value?["alertsEnabled"] == enabled ? "Saved. Reopen Screenshot Test and take a screenshot." : "Write verification failed"
            } catch {
                worse_query_release(handle)
                return "Could not edit settings: \(error.localizedDescription)"
            }
        }
        return "Screenshot Test container was not found or could not be accessed"
    }
}
