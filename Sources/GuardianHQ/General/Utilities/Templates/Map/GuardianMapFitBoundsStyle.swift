import Foundation

/// How ``guardianFitBoundsForPoints`` / ``guardianFitBoundsForFormationContent`` frame the viewport.
enum GuardianMapFitBoundsStyle: Equatable, Sendable {
    /// MC-R triage / live overview — allow tight zoom (``maxZoom`` 19).
    case missionControl
    /// Formation lab — bbox of squad markers only; no ``maxZoom`` cap; minimum ground span.
    case formationContent
}
