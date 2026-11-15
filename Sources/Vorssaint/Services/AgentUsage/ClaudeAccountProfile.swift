// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// A Claude Code configuration directory, already set up by its owner.
/// An empty path keeps Claude's usual login: explicitly setting its default
/// directory would select a different Keychain entry and .claude.json file.
struct ClaudeAccountProfile: Equatable, Identifiable {
    var directory = ""
    var id: String { directory }
    var isDefault: Bool { directory.isEmpty }

    struct Identity: Equatable {
        let account: String?
        let email: String?
        let organization: String?

        /// Signed in as the same person in the same organization, so under
        /// the same limits, whichever folder Claude Code was handed.
        func isSameAccount(as other: Identity) -> Bool {
            guard organization == other.organization else { return false }
            if let account, let theirs = other.account { return account == theirs }
            guard let email, let theirs = other.email else { return false }
            return email.caseInsensitiveCompare(theirs) == .orderedSame
        }
    }

    struct Reading {
        var identity: Identity?
        var plan: AgentPlan?
        var usageFetched: Date?
    }

    /// The stored choice that follows whichever account Claude Code wrote
    /// to last, as CCS switches between them, instead of one folder.
    static let automaticChoice = "automatic"

    static func followsActivity(in defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: DefaultsKey.notchAgentsClaudeProfile) == automaticChoice
    }

    /// The chosen account; under the automatic choice, `followed`, the one
    /// last found in use, or Claude's usual login before any was found.
    static func selected(in defaults: UserDefaults = .standard, followed: Self? = nil) -> Self {
        let choice = defaults.string(forKey: DefaultsKey.notchAgentsClaudeProfile) ?? ""
        guard choice == automaticChoice else { return Self(directory: choice) }
        return followed ?? Self()
    }

    func configurationURL(home: URL) -> URL {
        isDefault ? home.appending(path: ".claude", directoryHint: .isDirectory)
            : URL(fileURLWithPath: directory, isDirectory: true)
    }

    func profileURL(home: URL) -> URL {
        (isDefault ? home : configurationURL(home: home)).appending(path: ".claude.json")
    }

    /// Never silently fall back to the default account if a chosen folder
    /// disappears. Only metadata is inspected; credentials belong to Claude.
    func isAvailable(home: URL) -> Bool {
        guard !isDefault else { return true }
        guard directory.hasPrefix("/"), directory.utf8.count <= 4_096 else { return false }
        let folder = configurationURL(home: home)
        guard folder.path != "/", folder.resolvingSymlinksInPath() != home.resolvingSymlinksInPath(),
              let metadata = try? FileManager.default.attributesOfItem(atPath: folder.path),
              metadata[.type] as? FileAttributeType == .typeDirectory,
              (metadata[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let permissions = metadata[.posixPermissions] as? NSNumber, permissions.intValue & 0o022 == 0,
              let profile = try? FileManager.default.attributesOfItem(atPath: profileURL(home: home).path),
              profile[.type] as? FileAttributeType == .typeRegular,
              (profile[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (profile[.referenceCount] as? NSNumber)?.intValue == 1 else { return false }
        return true
    }

    /// The session logs counted for this account: its own, and those of
    /// every other profile found signed in to the same account. CCS keeps a
    /// folder for each instance it switches between, and several of them
    /// are often one person's one subscription: one set of limits, so their
    /// sessions count together, wherever Claude Code wrote them.
    func logURLs(home: URL) -> [URL] {
        let own = ownLogURLs(home: home)
        guard !own.isEmpty, let identity = read(home: home).identity else { return own }
        var urls = own
        var seen = Set(own.map { $0.resolvingSymlinksInPath().path })
        for profile in [Self()] + Self.discover(home: home) where profile != self {
            guard let theirs = profile.read(home: home).identity, theirs.isSameAccount(as: identity) else { continue }
            for url in profile.ownLogURLs(home: home) where seen.insert(url.resolvingSymlinksInPath().path).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    /// Whether `other` is this profile, or another signed in to its account.
    func isSameAccount(as other: Self, home: URL) -> Bool {
        guard self != other else { return true }
        guard let mine = read(home: home).identity, let theirs = other.read(home: home).identity else { return false }
        return mine.isSameAccount(as: theirs)
    }

    /// The folders this profile itself keeps its sessions in.
    func ownLogURLs(home: URL) -> [URL] {
        guard isAvailable(home: home) else { return [] }
        let folders = isDefault ? [home.appending(path: ".claude"), home.appending(path: ".config/claude")]
            : [configurationURL(home: home)]
        return folders.map { $0.appending(path: "projects", directoryHint: .isDirectory) }
    }

    /// Only account metadata and the usage timestamp survive decoding, in
    /// memory. No email, account identifier or token enters the usage archive.
    func read(home: URL) -> Reading {
        guard isAvailable(home: home),
              let size = try? profileURL(home: home).resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 4 << 20,
              let data = try? Data(contentsOf: profileURL(home: home)), data.count <= 4 << 20,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return Reading() }
        let account = json["oauthAccount"] as? [String: Any]
        let identity = account.map {
            Identity(account: Self.text($0["accountUuid"]), email: Self.text($0["emailAddress"]),
                     organization: Self.text($0["organizationUuid"]))
        }
        let plan = account.flatMap {
            AgentPlans.claude(organizationType: $0["organizationType"] as? String,
                             rateLimitTier: $0["organizationRateLimitTier"] as? String ?? $0["userRateLimitTier"] as? String)
        }
        let fetched = (json["cachedUsageUtilization"] as? [String: Any])?["fetchedAtMs"] as? NSNumber
        let date = fetched.flatMap { value -> Date? in
            guard CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite, value.doubleValue > 0 else { return nil }
            return Date(timeIntervalSince1970: value.doubleValue / 1_000)
        }
        return Reading(identity: identity, plan: plan, usageFetched: date)
    }

    func name(defaultName: String) -> String {
        guard !isDefault else { return defaultName }
        let name = URL(fileURLWithPath: directory).lastPathComponent
        return String((name.hasPrefix(".claude-") ? String(name.dropFirst(8)) : name).prefix(80))
    }

    /// Common profile locations only; arbitrary folders are chosen explicitly.
    /// Besides Claude's own, these include the folder CCS keeps for each
    /// account it switches between, `~/.ccs/instances/<name>`, which it hands
    /// Claude Code as its configuration directory, so its sessions and
    /// sign-in live there rather than in `~/.claude`.
    static func discover(home: URL) -> [Self] {
        // URL enumeration can resolve a symlink in the home path. Preserve
        // its spelling: Claude keys its sign-in to the config directory.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        let own = names.filter { $0 == ".claude" || $0.hasPrefix(".claude-") }
            .map { home.appending(path: $0, directoryHint: .isDirectory) }
            + [home.appending(path: ".config/claude")]
        let instances = home.appending(path: ".ccs/instances", directoryHint: .isDirectory)
        // CCS keeps its locks beside the accounts; without a .claude.json
        // of their own they are no profile, as any such folder.
        let switched = ((try? FileManager.default.contentsOfDirectory(atPath: instances.path)) ?? [])
            .map { instances.appending(path: $0, directoryHint: .isDirectory) }
        let candidates = own.sorted { $0.path < $1.path } + switched.sorted { $0.path < $1.path }
        return candidates.prefix(32).map { Self(directory: $0.path) }.filter { $0.isAvailable(home: home) }
    }

    /// Of Claude's usual login and the profiles found in their common places,
    /// the one whose session logs changed last: the account Claude Code is
    /// working in. Only file dates are read, never a log's contents.
    static func mostRecentlyUsed(home: URL, among profiles: [Self]? = nil) -> Self {
        var best = Self(), latest = Date.distantPast
        for profile in [Self()] + (profiles ?? discover(home: home)) {
            guard let written = lastLogWrite(profile.ownLogURLs(home: home)), written > latest else { continue }
            best = profile
            latest = written
        }
        return best
    }

    /// When any session log in `folders` was last written. Claude keeps one
    /// folder per project and one log per session inside it.
    static func lastLogWrite(_ folders: [URL]) -> Date? {
        let manager = FileManager.default
        var latest: Date?
        for folder in folders {
            let projects = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                             options: .skipsHiddenFiles)) ?? []
            for project in projects.prefix(2_000) {
                let logs = (try? manager.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey],
                                                             options: .skipsHiddenFiles)) ?? []
                for log in logs where log.pathExtension == "jsonl" {
                    guard let date = try? log.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                          date > latest ?? .distantPast else { continue }
                    latest = date
                }
            }
        }
        return latest
    }

    private static func text(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let clean = value.components(separatedBy: .controlCharacters).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : String(clean.prefix(254))
    }
}
