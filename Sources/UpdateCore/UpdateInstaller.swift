import Foundation

public struct UpdateInstallation: Sendable {
    public let target: URL
    public let staged: URL
    public let stagingRoot: URL
    public let version: String
    public let oldPID: Int32
    public let oldExecutable: String
    public let relaunch: Bool
    public let statusDomain: String
    public let diagnosticLog: URL

    public init(target: URL, staged: URL, stagingRoot: URL, version: String,
                oldPID: Int32, oldExecutable: String, relaunch: Bool = true,
                statusDomain: String = UpdatePolicy.bundleID, diagnosticLog: URL? = nil) {
        self.target = target; self.staged = staged; self.stagingRoot = stagingRoot
        self.version = version; self.oldPID = oldPID; self.oldExecutable = oldExecutable
        self.relaunch = relaunch
        self.statusDomain = statusDomain
        self.diagnosticLog = diagnosticLog ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Phonon for Mac/LastUpdate.log")
    }

    public func script() throws -> String {
        guard target.lastPathComponent == UpdatePolicy.appName, staged.lastPathComponent == UpdatePolicy.appName,
              stagingRoot.lastPathComponent.hasPrefix("PhononMacUpdate-"),
              staged.standardizedFileURL.path.hasPrefix(stagingRoot.standardizedFileURL.path + "/"),
              oldPID > 1, version.range(of: "^[0-9]+(\\.[0-9]+){0,3}$", options: .regularExpression) != nil else {
            throw UpdateFailure.invalid("The update installation paths are invalid.")
        }
        let parent = target.deletingLastPathComponent()
        let suffix = UUID().uuidString
        let prepared = parent.appendingPathComponent(".PhononMac-new-\(suffix)")
        let backup = parent.appendingPathComponent(".PhononMac-previous-\(suffix)")
        let lock = parent.appendingPathComponent(".PhononMac-update-lock")
        let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(UpdatePolicy.teamID)\" and identifier \"\(UpdatePolicy.bundleID)\""
        return """
        #!/bin/zsh
        set -euo pipefail
        target=\(Self.quote(target.path))
        staged=\(Self.quote(staged.path))
        staging=\(Self.quote(stagingRoot.path))
        prepared=\(Self.quote(prepared.path))
        backup=\(Self.quote(backup.path))
        lock=\(Self.quote(lock.path))
        oldexe=\(Self.quote(oldExecutable))
        pid=\(oldPID)
        exec > "$staging/install.log" 2>&1
        save_failure() {
          /bin/mkdir -p -m 700 \(Self.quote(diagnosticLog.deletingLastPathComponent().path))
          /usr/bin/tail -c 65536 "$staging/install.log" > \(Self.quote(diagnosticLog.path))
        }
        for attempt in {1..300}; do
          current=$(/bin/ps -p "$pid" -o comm= 2>/dev/null || true)
          [[ "$current" == "$oldexe" ]] || break
          /bin/sleep 0.2
        done
        current=$(/bin/ps -p "$pid" -o comm= 2>/dev/null || true)
        if [[ "$current" == "$oldexe" ]]; then
          /usr/bin/defaults write \(Self.quote(statusDomain)) updateInstallResult 'The settings app did not close. The update was not installed.'
          save_failure
          /bin/rm -rf "$staging"
          exit 1
        fi
        if ! /bin/mkdir "$lock"; then
          /usr/bin/defaults write \(Self.quote(statusDomain)) updateInstallResult 'Another Phonon update is already running.'
          save_failure
          /bin/rm -rf "$staging"
          exit 1
        fi
        restore() {
          trap - ERR
          set +e
          restored=1
          if [[ -d "$backup" ]]; then
            /bin/rm -rf "$target"
            /bin/mv "$backup" "$target" || restored=0
          fi
          /bin/rm -rf "$prepared"
          /bin/rmdir "$lock" 2>/dev/null || true
          if [[ "$restored" == 1 ]]; then
            /usr/bin/defaults write \(Self.quote(statusDomain)) updateInstallResult 'The update failed. The previous app was kept. Please try again.'
          else
            /usr/bin/defaults write \(Self.quote(statusDomain)) updateInstallResult 'The update failed and could not restore the previous app. Please reinstall Phonon manually.'
          fi
          save_failure
          if [[ "$restored" == 1 ]]; then /bin/rm -rf "$staging"; fi
          \(relaunch ? "/usr/bin/open \"$target\" >/dev/null 2>&1 || true" : ":")
          exit 1
        }
        trap restore ERR
        /usr/bin/ditto "$staged" "$prepared"
        /usr/bin/codesign --verify --deep --strict --test-requirement \(Self.quote("=" + requirement)) "$prepared"
        [[ -d "$target" ]] && /bin/mv "$target" "$backup"
        /bin/mv "$prepared" "$target"
        /usr/bin/codesign --verify --deep --strict --test-requirement \(Self.quote("=" + requirement)) "$target"
        /usr/bin/defaults write \(Self.quote(statusDomain)) updateInstallResult \(Self.quote("Version \(version) was installed. Restart VoiceOver when convenient to load the updated voice."))
        trap - ERR
        /bin/rm -rf "$backup" || true
        /bin/rmdir "$lock" || true
        \(relaunch ? "/usr/bin/open \"$target\"" : ":")
        /bin/rm -rf "$staging"
        """
    }
    private static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
