import Foundation

/// Semver for one logical brain (`major.minor.patch`). Major selects a named line (see ``GuardianBrainMajorLines``).
struct GuardianBrainVersion: Equatable, Hashable, Sendable, Comparable {
  var major: Int
  var minor: Int
  var patch: Int

  static let initial = GuardianBrainVersion(major: 0, minor: 0, patch: 1)

  enum BumpKind: Equatable, Sendable {
    case patch
    case minor
    case major
  }

  init(major: Int, minor: Int, patch: Int) {
    self.major = major
    self.minor = minor
    self.patch = patch
  }

  var semverString: String { "\(major).\(minor).\(patch)" }

  var majorLineCodename: String { GuardianBrainMajorLines.codename(forMajor: major) }

  /// Operator-facing label, e.g. `subodai · 0.3.45`.
  var displayLabel: String { "\(majorLineCodename) · \(semverString)" }

  /// Directory name under `Application Support/Guardian/brains/<brain_id>/`.
  var catalogueDirectoryName: String { semverString }

  func bumped(_ kind: BumpKind = .patch) -> GuardianBrainVersion {
    switch kind {
    case .patch:
      return GuardianBrainVersion(major: major, minor: minor, patch: patch + 1)
    case .minor:
      return GuardianBrainVersion(major: major, minor: minor + 1, patch: 0)
    case .major:
      return GuardianBrainVersion(major: major + 1, minor: 0, patch: 0)
    }
  }

  /// Maps monotonic integer catalogue revisions from early builds to `0.0.n`.
  static func fromLegacyInteger(_ value: Int) -> GuardianBrainVersion {
    if value <= 0 { return .initial }
    return GuardianBrainVersion(major: 0, minor: 0, patch: value)
  }

  init(parsing semver: String) throws {
    let trimmed = semver.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3,
          let major = Int(parts[0]), major >= 0,
          let minor = Int(parts[1]), minor >= 0,
          let patch = Int(parts[2]), patch >= 0
    else {
      throw GuardianBrainVersionError.invalidSemver(semver)
    }
    self.init(major: major, minor: minor, patch: patch)
  }

  /// Parses semver (`3.2.45`) or legacy integer directory / JSON tokens (`12` → `0.0.12`).
  static func parseCatalogueToken(_ token: String) throws -> GuardianBrainVersion {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.contains(".") {
      return try GuardianBrainVersion(parsing: trimmed)
    }
    if let legacy = Int(trimmed) {
      return fromLegacyInteger(legacy)
    }
    throw GuardianBrainVersionError.invalidSemver(token)
  }

  static func < (lhs: GuardianBrainVersion, rhs: GuardianBrainVersion) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
    return lhs.patch < rhs.patch
  }
}

enum GuardianBrainVersionError: LocalizedError, Equatable {
  case invalidSemver(String)

  var errorDescription: String? {
    switch self {
    case .invalidSemver(let raw):
      return "Brain version must be semver major.minor.patch (e.g. 0.3.45). Got “\(raw)”."
    }
  }
}

extension GuardianBrainVersion: Codable {
  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let intValue = try? container.decode(Int.self) {
      self = GuardianBrainVersion.fromLegacyInteger(intValue)
      return
    }
    let stringValue = try container.decode(String.self)
    self = try GuardianBrainVersion(parsing: stringValue)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(semverString)
  }
}
