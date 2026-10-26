// DJ.app: paste a link, get an MP3 in ~/Music/DJ.
// The heavy lifting is done by ~/.dj/bin/dj (yt-dlp + ffmpeg + deno), which the bundled
// install-dj.command sets up on first launch.
import AppKit
import SwiftUI

// Must match INSTALL_VERSION in install-dj.command
let installVersion = "2"

let home = FileManager.default.homeDirectoryForCurrentUser
let djHome = home.appendingPathComponent(".dj")
let djCommand = djHome.appendingPathComponent("bin/dj")
let ytdlp = djHome.appendingPathComponent("bin/yt-dlp")
let updateStamp = djHome.appendingPathComponent("bin/.last-update")
let outDir = home.appendingPathComponent("Music/DJ")

@main
struct DJApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var model = Model()

    var body: some Scene {
        Window("DJ", id: "main") {
            ContentView().environmentObject(model)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
final class Model: ObservableObject {
    enum State { case working, ready, done, failed }

    @Published var state = State.working
    @Published var status = ""
    @Published var progress: Double?  // nil shows a moving "busy" bar
    @Published var link = ""
    @Published var lastFile: URL?

    private var process: Process?
    private var errors: [String] = []
    private var itemLabel = ""

    var busy: Bool { state == .working }

    init() {
        let installed = (try? String(contentsOf: djHome.appendingPathComponent(".version"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if installed == installVersion && FileManager.default.isExecutableFile(atPath: djCommand.path) {
            updateIfStale()
        } else {
            setup()
        }
    }

    // MARK: First-launch setup

    private func setup() {
        guard let installer = Bundle.main.url(forResource: "install-dj", withExtension: "command") else {
            fail("The app is damaged (installer missing). Try downloading it again.")
            return
        }
        state = .working
        status = "Setting up (one time only)…"
        progress = nil
        run("/bin/bash", [installer.path], onLine: { [weak self] line in
            guard let self else { return }
            if line.hasPrefix("==> ") {
                self.status = "Setting up: " + line.dropFirst(4).replacingOccurrences(of: "Downloading", with: "downloading")
                self.progress = nil
            } else if let pct = Self.percent(in: line) {
                self.progress = pct
            }
        }, onExit: { [weak self] ok in
            guard let self else { return }
            ok ? self.becomeReady() : self.fail("Setup failed. Check your internet connection and reopen DJ.")
        })
    }

    // YouTube changes often and old yt-dlp versions stop working, so check weekly
    private func updateIfStale() {
        let modified = (try? updateStamp.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard modified == nil || Date().timeIntervalSince(modified!) > 7 * 24 * 3600 else {
            becomeReady()
            return
        }
        state = .working
        status = "Checking for updates…"
        progress = nil
        run(ytdlp.path, ["-U"], onLine: { _ in }, onExit: { [weak self] ok in
            if ok { FileManager.default.createFile(atPath: updateStamp.path, contents: nil) }
            self?.becomeReady()  // an outdated yt-dlp is still worth trying
        })
    }

    private func becomeReady() {
        state = .ready
        status = ""
        progress = nil
        pasteIfLink()
    }

    // MARK: Downloading

    func pasteIfLink() {
        guard link.isEmpty, let clip = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), clip.hasPrefix("http") else { return }
        link = clip
    }

    func download() {
        let links = link.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !busy, !links.isEmpty else { return }
        state = .working
        status = "Starting…"
        progress = nil
        lastFile = nil
        errors = []
        itemLabel = ""
        run(djCommand.path, links + ["--newline"], onLine: { [weak self] in self?.handle($0) },
            onExit: { [weak self] ok in
                guard let self else { return }
                if ok {
                    self.state = .done
                    self.status = self.lastFile.map { "Saved “\($0.deletingPathExtension().lastPathComponent)”" } ?? "Done!"
                    self.progress = 1
                    self.link = ""
                } else if self.process == nil {
                    self.fail("Cancelled.")
                } else {
                    self.fail(self.errors.last ?? "Something went wrong. Check the link and try again.")
                }
                self.process = nil
            })
    }

    func cancel() {
        let p = process
        process = nil
        p?.terminate()
    }

    // Turns yt-dlp's log lines into something friendlier
    private func handle(_ line: String) {
        if line.hasPrefix("ERROR:") {
            errors.append(String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces))
        } else if let range = line.range(of: #"Downloading item (\d+) of (\d+)"#, options: .regularExpression) {
            itemLabel = String(line[range]).replacingOccurrences(of: "Downloading item", with: "Song") + ": "
        } else if line.hasPrefix("[download]"), let pct = Self.percent(in: line) {
            status = itemLabel + "Downloading…"
            progress = pct
        } else if line.hasPrefix("[download]") && line.contains("has already been downloaded") {
            status = itemLabel + "Already downloaded"
            if let path = line.firstMatch(of: /\[download\] (.+) has already been downloaded/)?.1 {
                lastFile = URL(fileURLWithPath: String(path))
            }
        } else if line.hasPrefix("[ExtractAudio]") {
            status = itemLabel + "Converting to MP3…"
            progress = nil
            if let path = line.firstMatch(of: /Destination: (.+)/)?.1 { lastFile = URL(fileURLWithPath: String(path)) }
        } else if line.hasPrefix("[EmbedThumbnail]") || line.hasPrefix("[ThumbnailsConvertor]") {
            status = itemLabel + "Adding artwork…"
        } else if line.hasPrefix("[youtube]") || line.hasPrefix("[info]") || line.hasPrefix("[soundcloud]") {
            if progress == nil { status = itemLabel + "Finding the song…" }
        }
    }

    private func fail(_ message: String) {
        state = .failed
        status = message
        progress = nil
    }

    private static func percent(in line: String) -> Double? {
        guard let m = line.firstMatch(of: /(\d{1,3}(?:\.\d+)?)%/), let v = Double(m.1) else { return nil }
        return min(v / 100, 1)
    }

    // MARK: Process plumbing

    private func run(_ exe: String, _ args: [String], onLine: @escaping (String) -> Void,
                     onExit: @escaping (Bool) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        // curl's progress bar uses \r rather than \n, so split on both
        let buffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            let lines = buffer.append(chunk)
            if !lines.isEmpty {
                DispatchQueue.main.async { lines.filter { !$0.isEmpty }.forEach(onLine) }
            }
        }
        p.terminationHandler = { p in
            pipe.fileHandleForReading.readabilityHandler = nil
            let ok = p.terminationStatus == 0
            DispatchQueue.main.async { onExit(ok) }
        }

        do {
            try p.run()
            process = p
        } catch {
            fail("Couldn't start: \(error.localizedDescription)")
        }
    }
}

// Only touched from a pipe's readabilityHandler, which runs serially
final class LineBuffer: @unchecked Sendable {
    private var data = Data()

    func append(_ chunk: Data) -> [String] {
        data.append(chunk)
        var lines: [String] = []
        while let i = data.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            lines.append(String(decoding: data[data.startIndex..<i], as: UTF8.self))
            data.removeSubrange(data.startIndex...i)
        }
        return lines
    }
}

struct ContentView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paste a YouTube or SoundCloud link")
                .font(.headline)

            HStack {
                TextField("https://…", text: $model.link)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.download() }
                    .disabled(model.busy)
                if model.busy && model.status.hasPrefix("Setting up") == false && model.status != "Checking for updates…" {
                    Button("Cancel") { model.cancel() }
                } else {
                    Button("Download") { model.download() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.busy || model.link.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Group {
                if model.busy || model.state == .done {
                    if let p = model.progress {
                        ProgressView(value: p)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }
            }

            HStack(alignment: .top) {
                Text(model.status)
                    .foregroundStyle(model.state == .failed ? Color.red : Color.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer()
                Button(model.lastFile != nil ? "Show in Finder" : "Open DJ folder") {
                    if let file = model.lastFile, FileManager.default.fileExists(atPath: file.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([file])
                    } else {
                        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(outDir)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if model.state != .working { model.pasteIfLink() }
        }
    }
}
