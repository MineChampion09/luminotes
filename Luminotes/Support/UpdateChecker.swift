import AppKit
import Combine
import Foundation

@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case downloading
        case installing
        case failed
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var latestVersion: String?
    @Published private(set) var releaseNotes: String?
    @Published private(set) var releasePageURL: URL?
    @Published private(set) var downloadURL: URL?
    @Published private(set) var errorMessage: String?
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            UserDefaults.standard.set(
                automaticallyChecksForUpdates,
                forKey: Self.autoCheckKey
            )
        }
    }

    private static let autoCheckKey = "Luminotes.automaticallyCheckForUpdates"
    private static let lastCheckKey = "Luminotes.lastUpdateCheck"
    private static let releaseAPI = URL(
        string: "https://api.github.com/repos/MineChampion09/luminotes/releases/latest"
    )!

    init() {
        automaticallyChecksForUpdates =
            UserDefaults.standard.object(forKey: Self.autoCheckKey) as? Bool ?? true
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
    }

    var canInstall: Bool {
        state == .available && downloadURL != nil
    }

    var isBusy: Bool {
        state == .checking || state == .downloading || state == .installing
    }

    var statusMessage: String {
        switch state {
        case .idle:
            return "Check GitHub Releases for a newer version."
        case .checking:
            return "Checking for updates…"
        case .upToDate:
            return "You're up to date (v\(currentVersion))."
        case .available:
            return "Version \(latestVersion ?? "new") is available."
        case .downloading:
            return "Downloading update…"
        case .installing:
            return "Installing update and relaunching…"
        case .failed:
            return errorMessage ?? "The update could not be installed."
        }
    }

    func checkForUpdatesIfNeeded() {
        guard automaticallyChecksForUpdates else { return }
        if let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }
        checkForUpdates()
    }

    func checkForUpdates() {
        guard !isBusy else { return }

        state = .checking
        errorMessage = nil
        latestVersion = nil
        releaseNotes = nil
        releasePageURL = nil
        downloadURL = nil

        var request = URLRequest(url: Self.releaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Luminotes", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.fail("Could not check for updates: \(error.localizedDescription)")
                    return
                }
                guard let data,
                      let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
                    self.fail("Could not read the update information.")
                    return
                }
                self.apply(release)
            }
        }
        .resume()
    }

    func downloadAndInstall() {
        guard canInstall, let downloadURL else { return }

        guard !Bundle.main.bundleURL.path.hasPrefix("/Volumes/") else {
            fail("Move Luminotes to Applications before updating.")
            return
        }

        state = .downloading
        errorMessage = nil

        URLSession.shared.downloadTask(with: downloadURL) { [weak self] tempURL, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.fail("Download failed: \(error.localizedDescription)")
                    return
                }
                guard let tempURL else {
                    self.fail("The update download was empty.")
                    return
                }
                do {
                    try self.install(from: tempURL)
                } catch {
                    self.fail(error.localizedDescription)
                }
            }
        }
        .resume()
    }

    private func apply(_ release: GitHubRelease) {
        let latest = release.tagName.trimmingCharacters(
            in: CharacterSet(charactersIn: "vV")
        )
        latestVersion = latest
        releaseNotes = release.body
        releasePageURL = release.htmlURL.flatMap(URL.init(string:))
        downloadURL = release.assets
            .first(where: { $0.name.lowercased().hasSuffix(".zip") })
            .flatMap { URL(string: $0.browserDownloadURL) }

        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

        if isVersion(latest, newerThan: currentVersion) {
            state = .available
        } else {
            state = .upToDate
        }
    }

    private func install(from tempURL: URL) throws {
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory
            .appendingPathComponent("LuminotesUpdate-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)

        let zipURL = work.appendingPathComponent("update.zip")
        try fileManager.copyItem(at: tempURL, to: zipURL)

        let extractURL = work.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: extractURL, withIntermediateDirectories: true)

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipURL.path, extractURL.path]
        try ditto.run()
        ditto.waitUntilExit()

        guard ditto.terminationStatus == 0 else {
            throw UpdateError("Could not unzip the update.")
        }

        guard let newApp = try fileManager
            .contentsOfDirectory(at: extractURL, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError("The update did not contain a Luminotes app.")
        }

        let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let destination: URL
        if bundleURL.path.contains("/AppTranslocation/") {
            // Gatekeeper may run a quarantined app from a temporary location.
            // Update the real installed app instead of the read-only copy.
            let applicationsURL = URL(fileURLWithPath: "/Applications/Luminotes.app")
            guard fileManager.fileExists(atPath: applicationsURL.path) else {
                throw UpdateError(
                    "Luminotes is running from a temporary location. Move it to Applications and relaunch before updating."
                )
            }
            destination = applicationsURL
        } else {
            destination = bundleURL
        }

        let helperURL = work.appendingPathComponent("update-helper.sh")
        let replaceURL = work.appendingPathComponent("replace-app.sh")
        try Self.helperScript.write(to: helperURL, atomically: true, encoding: .utf8)
        try Self.replaceScript.write(to: replaceURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            helperURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            newApp.path,
            destination.path,
            replaceURL.path,
            work.path
        ]
        try process.run()

        state = .installing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }

    private func fail(_ message: String) {
        state = .failed
        errorMessage = message
    }

    private func isVersion(_ latest: String, newerThan current: String) -> Bool {
        let latestParts = latest.split(separator: ".").map { Int($0) ?? 0 }
        let currentParts = current.split(separator: ".").map { Int($0) ?? 0 }

        for index in 0..<max(latestParts.count, currentParts.count) {
            let latestValue = index < latestParts.count ? latestParts[index] : 0
            let currentValue = index < currentParts.count ? currentParts[index] : 0
            if latestValue != currentValue {
                return latestValue > currentValue
            }
        }
        return false
    }

    private static let helperScript = """
    #!/bin/sh
    PID="$1"
    NEW="$2"
    DEST="$3"
    REPLACE="$4"
    TEMP="$5"
    LOG="/tmp/luminotes-update.log"

    exec >> "$LOG" 2>&1
    echo "Luminotes update helper started"

    while kill -0 "$PID" 2>/dev/null; do
        sleep 0.2
    done

    if [ -w "$(dirname "$DEST")" ]; then
        /bin/sh "$REPLACE" "$DEST" "$NEW"
    else
        APPLESCRIPT="$TEMP/admin-update.applescript"
        cat > "$APPLESCRIPT" <<'APPLESCRIPT'
    on run argv
        set scriptPath to item 1 of argv
        set dest to item 2 of argv
        set newApp to item 3 of argv
        do shell script "/bin/sh " & quoted form of scriptPath & " " & quoted form of dest & " " & quoted form of newApp with administrator privileges
    end run
    APPLESCRIPT
        osascript "$APPLESCRIPT" "$REPLACE" "$DEST" "$NEW"
    fi

    open "$DEST"
    rm -rf "$TEMP"
    """

    private static let replaceScript = """
    #!/bin/sh
    DEST="$1"
    NEW="$2"
    BACKUP="${DEST}.old"

    rm -rf "$BACKUP"
    mv "$DEST" "$BACKUP" || exit 1

    if ditto "$NEW" "$DEST"; then
        rm -rf "$BACKUP"
    else
        rm -rf "$DEST"
        mv "$BACKUP" "$DEST"
        exit 1
    fi

    xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
    exit 0
    """
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String?
    let body: String?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case assets
    }

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}

private struct UpdateError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
