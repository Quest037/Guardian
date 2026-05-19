import Foundation

/// Named major-version lines for the Guardian autonomy brain catalogue.
enum GuardianBrainMajorLines {
  /// Major `0` → **subodai**, `1` → **caesar**, `2` → **sikander**, …
  static let codenamesByMajor: [Int: String] = [
    0: "subodai",
    1: "caesar",
    2: "sikander",
    3: "napoleon",
    4: "hannibal",
    5: "anlushan",
    6: "genghis",
    7: "patton",
    8: "ieyasu",
    9: "saladin",
    10: "timur",
  ]

  static func codename(forMajor major: Int) -> String {
    codenamesByMajor[major] ?? "line-\(major)"
  }
}
