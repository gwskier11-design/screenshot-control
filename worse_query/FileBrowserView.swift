import SwiftUI
import Darwin

private struct AppContainer: Identifiable {
    let path: String
    let bundleID: String
    var id: String { path }
}

private struct SelectedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

struct FileBrowserView: View {
    @State private var containers: [AppContainer] = []
    @State private var currentFolder: URL?
    @State private var rootFolder: URL?
    @State private var extensionHandle: Int64 = -1
    @State private var files: [URL] = []
    @State private var selectedFile: SelectedFile?
    @State private var status = "Tap Scan to find app containers."
    @State private var scanning = false
    @State private var openSnapchatAfterScan = false
    @State private var currentBundleID: String?
    @State private var search = ""
    @State private var showingSearch = false
    @FocusState private var searchFocused: Bool
    private let group = "group.com.georgewatts.screenshotcontrol"

    private var matchingContainers: [AppContainer] {
        search.isEmpty ? containers : containers.filter { $0.bundleID.localizedCaseInsensitiveContains(search) }
    }

    private var matchingFiles: [URL] {
        search.isEmpty ? files : files.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if showingSearch {
                    TextField(currentFolder == nil ? "Search apps" : "Search files", text: $search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                }
                if let folder = currentFolder {
                    Section {
                        Button("Back") { goBack(from: folder) }
                        Text(status).font(.caption)
                        Text(folder.path.replacingOccurrences(of: rootFolder?.path ?? "", with: currentBundleID == "com.toyopagroup.picaboo" ? "Snapchat" : "App Data"))
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    if let rootFolder {
                        Section("Jump to") {
                            Button("App data root") { jump(to: rootFolder) }
                            ForEach(["Documents", "Library", "Library/Caches", "tmp"], id: \.self) { folderName in
                                let destination = rootFolder.appendingPathComponent(folderName)
                                if isDirectory(destination) {
                                    Button(folderName) { jump(to: destination) }
                                }
                            }
                        }
                    }
                    Section("Files") {
                        ForEach(matchingFiles, id: \.self) { file in
                            Button {
                                if isDirectory(file) {
                                    currentFolder = file
                                    search = ""
                                    loadFiles()
                                } else {
                                    selectedFile = SelectedFile(url: file)
                                }
                            } label: {
                                Label(file.lastPathComponent, systemImage: isDirectory(file) ? "folder" : "doc")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                } else {
                    Section {
                        Button("Open Snapchat Files") { openSnapchat() }
                            .disabled(scanning)
                        Button(scanning ? "Scanning..." : "Scan App Containers") { scan() }
                            .disabled(scanning)
                        Text(status).font(.caption).textSelection(.enabled)
                    }
                    Section("Applications") {
                        ForEach(matchingContainers) { container in
                            Button(container.bundleID == "com.toyopagroup.picaboo" ? "Snapchat" : container.bundleID) { open(container) }
                        }
                    }
                }
            }
            .navigationTitle("File Browser")
            .toolbar {
                Button {
                    showingSearch.toggle()
                    if showingSearch { searchFocused = true } else { search = "" }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel(showingSearch ? "Close search" : "Search")
            }
            .sheet(item: $selectedFile) { file in
                FilePreview(url: file.url)
            }
            .onDisappear {
                if extensionHandle >= 0 {
                    worse_query_release(extensionHandle)
                    extensionHandle = -1
                }
                currentFolder = nil
                rootFolder = nil
                currentBundleID = nil
                files = []
            }
        }
    }

    private func openSnapchat() {
        if let snapchat = containers.first(where: { $0.bundleID == "com.toyopagroup.picaboo" }) {
            open(snapchat)
        } else {
            openSnapchatAfterScan = true
            scan()
        }
    }

    private func scan() {
        scanning = true
        status = "Scanning app container paths..."
        DispatchQueue.global(qos: .userInitiated).async {
            let root = "/private/var/mobile/Containers/Data/Application"
            let rootHandle = worse_query(root, group, false, false)
            let paths: [String]
            if rootHandle >= 0 {
                paths = (try? FileManager.default.contentsOfDirectory(atPath: root))?.map { root + "/" + $0 } ?? []
                worse_query_release(rootHandle)
            } else {
                let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                guard (try? Data([0]).write(to: marker)) != nil else {
                    finishScan([], message: "Could not create scan marker")
                    return
                }
                var info = stat()
                let valid = stat(marker.path, &info) == 0
                try? FileManager.default.removeItem(at: marker)
                guard valid else {
                    finishScan([], message: "Could not scan app containers")
                    return
                }
                paths = pathleak(root, info.st_ino) ?? []
            }
            var found: [AppContainer] = []
            for path in paths {
                let handle = worse_query(path, group, false, false)
                guard handle >= 0 else { continue }
                var buffer = [CChar](repeating: 0, count: 512)
                let length = getxattr(path, "com.apple.containermanager.identifier", &buffer, buffer.count, 0, 0)
                if length > 0 {
                    found.append(AppContainer(path: path, bundleID: String(cString: buffer)))
                }
                worse_query_release(handle)
            }
            found.sort { $0.bundleID.localizedStandardCompare($1.bundleID) == .orderedAscending }
            finishScan(found, message: "Found \(found.count) accessible app containers")
        }
    }

    private func finishScan(_ result: [AppContainer], message: String) {
        DispatchQueue.main.async {
            containers = result
            status = message
            scanning = false
            if openSnapchatAfterScan {
                openSnapchatAfterScan = false
                if let snapchat = result.first(where: { $0.bundleID == "com.toyopagroup.picaboo" }) {
                    open(snapchat)
                } else {
                    status = "Snapchat container was not found"
                }
            }
        }
    }

    private func open(_ container: AppContainer) {
        let handle = worse_query(container.path, group, false, false)
        guard handle >= 0 else {
            status = "Could not access \(container.bundleID). Code \(handle)"
            return
        }
        extensionHandle = handle
        let folder = URL(fileURLWithPath: container.path)
        rootFolder = folder
        currentFolder = folder
        currentBundleID = container.bundleID
        search = ""
        loadFiles()
    }

    private func goBack(from folder: URL) {
        search = ""
        guard let rootFolder, folder != rootFolder else {
            currentFolder = nil
            rootFolder = nil
            currentBundleID = nil
            files = []
            if extensionHandle >= 0 { worse_query_release(extensionHandle) }
            extensionHandle = -1
            return
        }
        currentFolder = folder.deletingLastPathComponent()
        loadFiles()
    }

    private func jump(to folder: URL) {
        currentFolder = folder
        search = ""
        loadFiles()
    }

    private func loadFiles() {
        guard let currentFolder else { return }
        do {
            files = try FileManager.default.contentsOfDirectory(at: currentFolder, includingPropertiesForKeys: [.isDirectoryKey], options: [])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            status = "\(files.count) items"
        } catch {
            files = []
            status = "Could not read folder: \(error.localizedDescription)"
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}

private struct FilePreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(preview)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .navigationTitle(url.lastPathComponent)
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private var preview: String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "Could not read file" }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 100_000) else { return "Could not read file" }
        if let text = String(data: data, encoding: .utf8) { return String(text.prefix(100_000)) }
        if url.pathExtension.lowercased() == "plist",
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) {
            return String(describing: plist)
        }
        return "Binary file (\(data.count) bytes)"
    }
}
