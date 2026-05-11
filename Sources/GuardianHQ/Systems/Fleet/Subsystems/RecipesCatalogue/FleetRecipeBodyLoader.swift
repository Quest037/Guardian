import Foundation
import os

// MARK: - Load error

/// Failure produced by ``FleetRecipeBodyLoader/load(recipeName:inSubdirectory:bundle:)``.
///
/// The loader's job is "bytes → ``FleetRecipeBody``"; catalogue-level structural
/// validation (against the live command + recipe registries) still happens inside
/// ``FleetRecipesCatalogue/register(_:)`` when the descriptor is registered. So this
/// error type only covers the three things that can go wrong before validation:
/// the resource being missing, the file being unreadable, or the JSON failing to
/// decode into the body shape.
enum FleetRecipeBodyLoadError: Error, Equatable, CustomStringConvertible {

    /// No resource matching `<recipeName>.json` was found in the supplied bundle
    /// under the supplied subdirectory.
    case resourceNotFound(recipeName: FleetRecipeName, subdirectory: String)

    /// The resource exists but its bytes could not be read (sandbox failure, race
    /// against bundle copy, etc.). The underlying error is stringified for
    /// inspection.
    case readFailed(recipeName: FleetRecipeName, underlying: String)

    /// `FleetRecipeBodyParser.decode(jsonData:)` rejected the file's contents.
    /// The wrapped error preserves the parser's diagnostic detail.
    case parseFailed(recipeName: FleetRecipeName, errors: FleetRecipeBodyParseErrors)

    var description: String {
        switch self {
        case .resourceNotFound(let name, let subdir):
            return "recipe body '\(name.rawValue).json' not found in subdirectory '\(subdir)'"
        case .readFailed(let name, let underlying):
            return "recipe body '\(name.rawValue).json' could not be read: \(underlying)"
        case .parseFailed(let name, let errors):
            return "recipe body '\(name.rawValue).json' failed to parse: \(errors.description)"
        }
    }
}

// MARK: - Loader

/// Resolves a hybrid-shape recipe body from a bundle resource.
///
/// **Hybrid contract** (see README "Layer 1 subsystems"): descriptor metadata is
/// authored as a Swift literal inside the subsystem's `registerAll()`, and the
/// step graph (body) lives as a per-recipe JSON file under that subsystem's
/// bodies directory (built-ins are `Calibration/CalibrationBodies/` and
/// `Errors/ErrorBodies/` — directory names must be unique inside the bundle
/// because SPM flattens `.copy(<dir>)` targets to the bundle root). This loader:
/// 1. Looks up the resource named `<recipeName>.json` under the supplied
///    subdirectory in the supplied bundle.
/// 2. Reads its bytes.
/// 3. Decodes via ``FleetRecipeBodyParser/decode(jsonData:)`` (decode only —
///    structural validation against the live registries is intentionally deferred
///    to ``FleetRecipesCatalogue/register(_:)``, which already runs the parser's
///    `validate(_:against:recipes:commands:)` pass when a descriptor's `body` is
///    non-nil).
///
/// Failure cases are surfaced as ``FleetRecipeBodyLoadError`` so subsystem
/// registrations can log a precise diagnostic and refuse the registration (the
/// recommended behaviour — body-less descriptors are still legal but the runner
/// refuses them at entry, so loud failure at app boot is strictly better than
/// silent body-less registration).
@MainActor
enum FleetRecipeBodyLoader {

    private static let log = OSLog(
        subsystem: "guardian.fleet.recipesCatalogue",
        category: "bodyLoader"
    )

    /// Load and decode a recipe body from a bundle resource.
    ///
    /// - Parameters:
    ///   - recipeName: The recipe whose body to load. The resource filename is
    ///     `<recipeName.rawValue>.json` — keeping the recipe name and the file
    ///     name in lockstep means there is one obvious place to look for any
    ///     recipe's step graph.
    ///   - subdirectory: Bundle-relative subdirectory containing the body files.
    ///     Each subsystem owns a uniquely-named bodies directory (e.g.
    ///     `"CalibrationBodies"`, `"ErrorBodies"`); plugins follow the same
    ///     convention. Tests pass their fixtures directory.
    ///   - bundle: The bundle to resolve the resource against. Production code
    ///     passes `Bundle.module` from the GuardianHQ target. Tests pass
    ///     `Bundle.module` from their own target (a different bundle).
    /// - Returns: `.success` with the decoded body, or `.failure` carrying a
    ///   diagnostic.
    static func load(
        recipeName: FleetRecipeName,
        inSubdirectory subdirectory: String,
        bundle: Bundle
    ) -> Result<FleetRecipeBody, FleetRecipeBodyLoadError> {

        guard let url = bundle.url(
            forResource: recipeName.rawValue,
            withExtension: "json",
            subdirectory: subdirectory
        ) else {
            os_log(
                .error,
                log: log,
                "Recipe body not found: %{public}@.json in %{public}@",
                recipeName.rawValue,
                subdirectory
            )
            return .failure(.resourceNotFound(
                recipeName: recipeName,
                subdirectory: subdirectory
            ))
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            os_log(
                .error,
                log: log,
                "Recipe body %{public}@.json could not be read: %{public}@",
                recipeName.rawValue,
                String(describing: error)
            )
            return .failure(.readFailed(
                recipeName: recipeName,
                underlying: String(describing: error)
            ))
        }

        switch FleetRecipeBodyParser.decode(jsonData: data) {
        case .success(let body):
            return .success(body)
        case .failure(let parseError):
            os_log(
                .error,
                log: log,
                "Recipe body %{public}@.json failed to decode: %{public}@",
                recipeName.rawValue,
                parseError.description
            )
            return .failure(.parseFailed(
                recipeName: recipeName,
                errors: FleetRecipeBodyParseErrors([parseError])
            ))
        }
    }
}
