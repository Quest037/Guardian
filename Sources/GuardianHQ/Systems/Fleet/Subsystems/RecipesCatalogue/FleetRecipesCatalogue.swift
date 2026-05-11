import Combine
import Foundation
import os

// MARK: - Catalogue

/// **Layer 1 — universal recipe registry.**
///
/// Holds the ``FleetRecipeDescriptor`` for every registered recipe in the universal
/// `recipe.*` namespace. The DSL parser, runner, and escalation contract (Stage B1
/// items 3-9) land on top of this registry; v1 ships just the registration surface so
/// subsystems (Calibration, Errors) and plugins have a stable point to attach.
///
/// **Lifecycle:** singleton, populated once at app start by
/// ``FleetRecipesCatalogueBootstrap/ensureRegistered()`` (idempotent). Subsystems
/// register their recipes inside the bootstrap; plugins register through their own
/// bootstrap once Stage F manifest namespace claims land.
///
/// **Thread isolation:** `@MainActor`. Registrations and lookups are main-thread;
/// the future runner will hop to background work via async/await + ``FleetCommandsCatalogue``.
@MainActor
final class FleetRecipesCatalogue: ObservableObject {

    // MARK: Singleton

    static let shared = FleetRecipesCatalogue()
    private init() {}

    // MARK: Storage

    /// Registered descriptors, keyed by name.
    @Published private(set) var descriptors: [FleetRecipeName: FleetRecipeDescriptor] = [:]

    private let log = OSLog(subsystem: "guardian.fleet.recipesCatalogue", category: "registry")

    // MARK: Registration

    /// Idempotent registration. Last write wins per name.
    ///
    /// Rejects (returns `false`) when:
    /// - the descriptor's name fails ``FleetRecipeName/isValidRawValue(_:)``;
    /// - the descriptor has a non-`nil` ``FleetRecipeDescriptor/pluginID`` but the name
    ///   is outside that plugin’s ``GuardianPluginManifest/publishedRecipeNamespaces``
    ///   claims in ``GuardianPluginRegistry``, or the manifest is missing;
    /// - the descriptor declares a contained child that is not already registered;
    /// - the descriptor declares a contained child that itself has a non-empty
    ///   `containsRecipes` (composition-depth limit of 1);
    /// - the descriptor's `defaultRetryPolicy` exceeds the locked caps and the
    ///   descriptor does **not** set `relaxRetryCaps = true`.
    ///
    /// Cap violations on a `relaxRetryCaps == true` descriptor are logged as a
    /// warning but the registration proceeds — that opt-out is the documented
    /// escape hatch for rare authoring needs.
    @discardableResult
    func register(_ descriptor: FleetRecipeDescriptor) -> Bool {
        guard FleetRecipeName.isValidRawValue(descriptor.name.rawValue) else {
            os_log(
                .fault,
                log: log,
                "Refusing to register recipe with invalid name: %{public}@",
                descriptor.name.rawValue
            )
            return false
        }

        if let pluginID = descriptor.pluginID {
            guard let manifest = GuardianPluginRegistry.shared.manifest(for: pluginID) else {
                os_log(
                    .fault,
                    log: log,
                    "Refusing to register %{public}@: no GuardianPluginManifest for plugin %{public}@.",
                    descriptor.name.rawValue,
                    pluginID.rawValue
                )
                return false
            }
            guard manifest.allowsPublishing(recipeRaw: descriptor.name.rawValue) else {
                os_log(
                    .fault,
                    log: log,
                    "Refusing to register %{public}@: name is outside plugin %{public}@ publishedRecipeNamespaces claims.",
                    descriptor.name.rawValue,
                    pluginID.rawValue
                )
                return false
            }
        }

        for childName in descriptor.containsRecipes {
            guard let child = descriptors[childName] else {
                os_log(
                    .fault,
                    log: log,
                    "Refusing to register %{public}@: contained child %{public}@ not yet registered.",
                    descriptor.name.rawValue,
                    childName.rawValue
                )
                return false
            }
            guard child.containsRecipes.isEmpty else {
                os_log(
                    .fault,
                    log: log,
                    "Refusing to register %{public}@: composition depth limit (1) violated by child %{public}@.",
                    descriptor.name.rawValue,
                    childName.rawValue
                )
                return false
            }
        }

        let capViolations = FleetRecipeRetryPolicy.violations(for: descriptor.defaultRetryPolicy)
        if !capViolations.isEmpty {
            let detail = capViolations.map(\.description).joined(separator: "; ")
            if descriptor.relaxRetryCaps {
                os_log(
                    .info,
                    log: log,
                    "Recipe %{public}@ exceeds retry caps but relaxRetryCaps=true: %{public}@",
                    descriptor.name.rawValue,
                    detail
                )
            } else {
                os_log(
                    .fault,
                    log: log,
                    "Refusing to register %{public}@: retry caps exceeded (%{public}@). Set relaxRetryCaps=true to opt out.",
                    descriptor.name.rawValue,
                    detail
                )
                return false
            }
        }

        // Cancel-recipe (cleanup) reference validation. Mirrors the
        // `containsRecipes` rule: the referenced cleanup must already be
        // registered AND must itself be a leaf (no cleanup of cleanup).
        if let cancelName = descriptor.cancelRecipe {
            guard let cleanup = descriptors[cancelName] else {
                os_log(
                    .fault,
                    log: log,
                    "Refusing to register %{public}@: cancelRecipe %{public}@ not yet registered.",
                    descriptor.name.rawValue,
                    cancelName.rawValue
                )
                return false
            }
            if cleanup.cancelRecipe != nil {
                os_log(
                    .fault,
                    log: log,
                    "Refusing to register %{public}@: cancelRecipe %{public}@ has its own cancelRecipe (cleanup nesting not allowed).",
                    descriptor.name.rawValue,
                    cancelName.rawValue
                )
                return false
            }
            if !cleanup.containsRecipes.isEmpty {
                os_log(
                    .fault,
                    log: log,
                    "Refusing to register %{public}@: cancelRecipe %{public}@ is composite (cleanup must be atomic).",
                    descriptor.name.rawValue,
                    cancelName.rawValue
                )
                return false
            }
        }

        // Body validation against the live registries. Catches the parse-time
        // recipe-composition depth violation (item 8) alongside the rest of the
        // DSL structural rules. Body-less descriptors skip this entirely so Stage C
        // can register descriptors and bodies in independent passes.
        if let body = descriptor.body {
            let parseErrors = FleetRecipeBodyParser.validate(
                body,
                against: descriptor,
                recipes: self,
                commands: FleetCommandsCatalogue.shared
            )
            if !parseErrors.isEmpty {
                let detail = parseErrors.map(\.description).joined(separator: "; ")
                os_log(
                    .fault,
                    log: log,
                    "Refusing to register %{public}@: body validation failed (%{public}@).",
                    descriptor.name.rawValue,
                    detail
                )
                return false
            }
        }

        descriptors[descriptor.name] = descriptor
        return true
    }

    // MARK: Lookup

    func descriptor(for name: FleetRecipeName) -> FleetRecipeDescriptor? {
        descriptors[name]
    }

    func descriptor(forRawValue raw: String) -> FleetRecipeDescriptor? {
        guard let name = try? FleetRecipeName(validating: raw) else { return nil }
        return descriptors[name]
    }

    /// All descriptors whose namespace path begins with the given prefix (matched
    /// against segments after the leading `recipe.`).
    ///
    /// Examples for `recipe.fleet.calibrate.compass`:
    /// - prefix `["fleet"]` matches
    /// - prefix `["fleet", "calibrate"]` matches
    /// - prefix `["fleet", "diagnose"]` does **not** match
    func descriptors(underNamespacePrefix prefix: [String]) -> [FleetRecipeDescriptor] {
        descriptors.values.filter { $0.name.isUnderNamespacePrefix(prefix) }
    }

    /// All descriptors owned by a given plugin id (matched by descriptor's
    /// ``FleetRecipeDescriptor/pluginID``). Useful for Stage F plugin diagnostics.
    func descriptors(ownedBy pluginID: GuardianPluginID) -> [FleetRecipeDescriptor] {
        descriptors.values.filter { $0.pluginID == pluginID }
    }

    /// Test-only reset. Clears all registrations so each test can bootstrap from a
    /// known empty state. Marked `_testOnly` to discourage runtime use.
    func _testOnlyReset() {
        descriptors.removeAll()
    }
}
