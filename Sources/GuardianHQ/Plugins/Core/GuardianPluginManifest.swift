import Foundation

/// Human-facing metadata for a registered integration.
struct GuardianPluginManifest: Identifiable, Equatable, Sendable {
    let pluginID: GuardianPluginID
    let displayName: String
    let shortDescription: String

    /// Each string is a **dotted prefix** for `command.*` names this plugin may register (e.g.
    /// `command.plugin.paladin` or `command.plugin.paladin.experimental`). Every prefix must sit
    /// under ``command.<fleetNamespaceTail>`` for this manifest’s ``pluginID``. Empty when the
    /// plugin does not publish fleet commands in the current build.
    let publishedCommandNamespaces: [String]

    /// Same shape as ``publishedCommandNamespaces`` for `recipe.*` registrations. Empty when none.
    let publishedRecipeNamespaces: [String]

    /// Dotted `command.*` prefixes this plugin may **dispatch** (e.g. `command.fleet.vehicle`). Shape-only
    /// validation — unlike ``publishedCommandNamespaces``, claims are **not** restricted to this
    /// ``pluginID``'s tree (Paladin may invoke core fleet commands).
    let invokedCommandNamespaces: [String]

    /// Dotted `recipe.*` prefixes this plugin may run or compose. Same shape rules as ``invokedCommandNamespaces``.
    let invokedRecipeNamespaces: [String]

    var id: String { pluginID.rawValue }

    init(
        pluginID: GuardianPluginID,
        displayName: String,
        shortDescription: String,
        publishedCommandNamespaces: [String] = [],
        publishedRecipeNamespaces: [String] = [],
        invokedCommandNamespaces: [String] = [],
        invokedRecipeNamespaces: [String] = []
    ) {
        self.pluginID = pluginID
        self.displayName = displayName
        self.shortDescription = shortDescription
        self.publishedCommandNamespaces = publishedCommandNamespaces
        self.publishedRecipeNamespaces = publishedRecipeNamespaces
        self.invokedCommandNamespaces = invokedCommandNamespaces
        self.invokedRecipeNamespaces = invokedRecipeNamespaces
    }

    // MARK: Namespace claims (Stage F)

    static func commandNamespaceRoot(for pluginID: GuardianPluginID) -> String {
        "command.\(pluginID.fleetNamespaceTail)"
    }

    static func recipeNamespaceRoot(for pluginID: GuardianPluginID) -> String {
        "recipe.\(pluginID.fleetNamespaceTail)"
    }

    /// `nil` when every claim is empty or correctly rooted under this ``pluginID``.
    func namespaceClaimValidationError() -> String? {
        if let err = Self.validatePrefixes(publishedCommandNamespaces, root: Self.commandNamespaceRoot(for: pluginID), kind: "command") {
            return err
        }
        if let err = Self.validatePrefixes(publishedRecipeNamespaces, root: Self.recipeNamespaceRoot(for: pluginID), kind: "recipe") {
            return err
        }
        if let err = Self.validateInvokedPrefixes(invokedCommandNamespaces, requiredPrefix: "command.", label: "invoked command") {
            return err
        }
        if let err = Self.validateInvokedPrefixes(invokedRecipeNamespaces, requiredPrefix: "recipe.", label: "invoked recipe") {
            return err
        }
        return nil
    }

    /// `true` when ``publishedCommandNamespaces`` is non-empty and `commandRaw` is exactly a listed
    /// prefix or continues it with a dot (e.g. prefix `command.plugin.paladin` allows `command.plugin.paladin.do.x`).
    func allowsPublishing(commandRaw: String) -> Bool {
        for prefix in publishedCommandNamespaces where commandRaw == prefix || commandRaw.hasPrefix(prefix + ".") {
            return true
        }
        return false
    }

    /// Same contract as ``allowsPublishing(commandRaw:)`` for ``publishedRecipeNamespaces`` / `recipe.*` names.
    func allowsPublishing(recipeRaw: String) -> Bool {
        for prefix in publishedRecipeNamespaces where recipeRaw == prefix || recipeRaw.hasPrefix(prefix + ".") {
            return true
        }
        return false
    }

    /// `true` when ``invokedCommandNamespaces`` is non-empty and `commandRaw` matches a listed prefix
    /// (exact or `prefix.` + suffix). Used by Layer 0 dispatch and recipe body validation when a
    /// plugin-owned recipe dispatches fleet commands.
    func allowsInvoking(commandRaw: String) -> Bool {
        for prefix in invokedCommandNamespaces where commandRaw == prefix || commandRaw.hasPrefix(prefix + ".") {
            return true
        }
        return false
    }

    /// Same contract as ``allowsInvoking(commandRaw:)`` for ``invokedRecipeNamespaces`` / nested `recipe.*` runs.
    func allowsInvoking(recipeRaw: String) -> Bool {
        for prefix in invokedRecipeNamespaces where recipeRaw == prefix || recipeRaw.hasPrefix(prefix + ".") {
            return true
        }
        return false
    }

    private static func validateInvokedPrefixes(_ prefixes: [String], requiredPrefix: String, label: String) -> String? {
        for raw in prefixes {
            guard raw.hasPrefix(requiredPrefix), isValidDottedFleetPrefix(raw) else {
                return "Invalid \(label) namespace shape: \(raw)"
            }
        }
        return nil
    }

    private static func validatePrefixes(_ prefixes: [String], root: String, kind: String) -> String? {
        for raw in prefixes {
            guard isValidDottedFleetPrefix(raw) else {
                return "Invalid \(kind) namespace shape: \(raw)"
            }
            guard raw == root || raw.hasPrefix(root + ".") else {
                return "\(kind) namespace \(raw) is not under required root \(root) for plugin"
            }
        }
        return nil
    }

    private static func isValidDottedFleetPrefix(_ raw: String) -> Bool {
        guard raw.count <= 128 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.")
        guard raw.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        guard !raw.hasPrefix("."), !raw.hasSuffix("."), !raw.contains("..") else { return false }
        if raw.hasPrefix("command.") {
            let tail = String(raw.dropFirst("command.".count))
            guard !tail.isEmpty else { return false }
            return tail.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty }
        }
        if raw.hasPrefix("recipe.") {
            let tail = String(raw.dropFirst("recipe.".count))
            guard !tail.isEmpty else { return false }
            return tail.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty }
        }
        return false
    }
}

