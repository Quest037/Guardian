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
///
/// **Bundle resolution:** ``load(recipeName:inSubdirectory:bundle:)`` searches the
/// caller’s bundle **and** ``Bundle.main`` (deduped), tries `Bundle.url` with and
/// without `subdirectory`, then a few on-disk paths under `bundleURL` /
/// `resourceURL` / `Resources/` so bodies still resolve when SwiftPM / host app
/// packaging differs (MC-R mission recipe bodies must not depend on a single layout).
@MainActor
enum FleetRecipeBodyLoader {

    private static let log = OSLog(
        subsystem: "guardian.fleet.recipesCatalogue",
        category: "bodyLoader"
    )

    private static func uniqueSearchBundles(primary: Bundle) -> [Bundle] {
        var out: [Bundle] = []
        var seen = Set<ObjectIdentifier>()
        func append(_ candidate: Bundle) {
            let id = ObjectIdentifier(candidate)
            guard !seen.contains(id) else { return }
            seen.insert(id)
            out.append(candidate)
        }

        append(primary)
        append(Bundle.main)

        // XCTest / SwiftPM: the module resource bundle (`…_GuardianHQ.bundle`) is often nested under the
        // `.xctest` bundle’s `Resources/`, or sits next to the test executable on disk — `Bundle.module`
        // alone does not always surface those paths for `url(forResource:subdirectory:)`.
        let moduleName = primary.bundleURL.lastPathComponent
        if moduleName.hasSuffix(".bundle"),
           let res = Bundle.main.resourceURL {
            let nested = res.appendingPathComponent(moduleName, isDirectory: true)
            if FileManager.default.fileExists(atPath: nested.path),
               let b = Bundle(url: nested) {
                append(b)
            }
        }
        if let exec = Bundle.main.executableURL {
            var dir = exec.deletingLastPathComponent()
            for _ in 0..<16 {
                let candidate = dir.appendingPathComponent("GuardianHQ_GuardianHQ.bundle", isDirectory: true)
                if FileManager.default.fileExists(atPath: candidate.path),
                   let b = Bundle(url: candidate) {
                    append(b)
                    break
                }
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
        }

        // `Bundle.module` may point at a build intermediate, not the SPM `…_GuardianHQ.bundle`
        // root. Walk ancestors of the module bundle URL and of `Bundle.main` and attach any
        // `GuardianHQ_GuardianHQ.bundle` sibling found next to those parents (matches `swift test` layout).
        let marker = "GuardianHQ_GuardianHQ.bundle"
        let fm = FileManager.default
        for seed in [primary.bundleURL, Bundle.main.bundleURL] {
            var dir = seed
            for _ in 0..<24 {
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                let sibling = parent.appendingPathComponent(marker, isDirectory: true)
                if fm.fileExists(atPath: sibling.path),
                   let b = Bundle(url: sibling) {
                    append(b)
                }
                dir = parent
            }
        }
        return out
    }

    /// Returns a readable JSON file URL for `recipeName` if present in any known layout.
    private static func resolveRecipeBodyFileURL(
        recipeName: FleetRecipeName,
        subdirectory: String,
        primaryBundle: Bundle
    ) -> URL? {
        let base = recipeName.rawValue
        let fileName = "\(base).json"
        let fm = FileManager.default

        for bundle in uniqueSearchBundles(primary: primaryBundle) {
            if let u = bundle.url(forResource: base, withExtension: "json", subdirectory: subdirectory) {
                return u
            }
            if let u = bundle.url(forResource: base, withExtension: "json") {
                return u
            }

            var pathCandidates: [URL] = [
                bundle.bundleURL.appendingPathComponent(subdirectory).appendingPathComponent(fileName),
                bundle.bundleURL.appendingPathComponent("Resources").appendingPathComponent(subdirectory).appendingPathComponent(fileName),
            ]
            if let res = bundle.resourceURL {
                pathCandidates.append(res.appendingPathComponent(subdirectory).appendingPathComponent(fileName))
            }
            for u in pathCandidates where fm.fileExists(atPath: u.path) {
                return u
            }
        }

        // Last resort: when `Bundle.module` / nested SPM bundles do not resolve on disk (some
        // `swift test` / host layouts), read bodies from the checkout tree when it is present.
        // Shipped app archives do not carry `Sources/GuardianHQ/...`; candidates are skipped.
        if let checkout = Self.checkoutBodiesDirectoryIfPresent(subdirectory: subdirectory, fileName: fileName) {
            return checkout
        }
        return nil
    }

    /// Resolves `<repo>/Sources/GuardianHQ/Systems/.../<subdirectory>/<fileName>` by walking
    /// ancestors of this file. Supports both absolute `#filePath` and layouts where the final
    /// directory is not literally named `GuardianHQ` (some toolchains emit relative paths).
    private static func checkoutBodiesDirectoryIfPresent(subdirectory: String, fileName: String) -> URL? {
        let relativeFromGuardianHQ: String
        switch subdirectory {
        case "ErrorBodies":
            relativeFromGuardianHQ = "Systems/Fleet/Subsystems/Errors/ErrorBodies"
        case "CalibrationBodies":
            relativeFromGuardianHQ = "Systems/Fleet/Subsystems/Calibration/CalibrationBodies"
        case "MissionBodies":
            relativeFromGuardianHQ = "Systems/Fleet/Subsystems/Mission/MissionBodies"
        default:
            return nil
        }
        let fm = FileManager.default
        let relSegments = relativeFromGuardianHQ.split(separator: "/").map(String.init)
        func fileURL(repoOrModuleRoot: URL, includeSourcesPrefix: Bool) -> URL {
            var u = repoOrModuleRoot
            if includeSourcesPrefix {
                u = u.appendingPathComponent("Sources", isDirectory: true)
                u = u.appendingPathComponent("GuardianHQ", isDirectory: true)
            }
            for seg in relSegments {
                u = u.appendingPathComponent(seg, isDirectory: true)
            }
            return u.appendingPathComponent(fileName)
        }
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<48 {
            let candidates = [
                fileURL(repoOrModuleRoot: dir, includeSourcesPrefix: true),
                fileURL(repoOrModuleRoot: dir, includeSourcesPrefix: false),
            ]
            for fileURL in candidates where fm.fileExists(atPath: fileURL.path) {
                return fileURL
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

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

        guard let url = resolveRecipeBodyFileURL(
            recipeName: recipeName,
            subdirectory: subdirectory,
            primaryBundle: bundle
        ) else {
            os_log(
                .error,
                log: log,
                "Recipe body not found: %{public}@.json in %{public}@ (searched module + main bundles)",
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
