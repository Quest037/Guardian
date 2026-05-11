import SwiftUI

/// Global **4pt spacing grid** and a few **semantic** distances shared across operator UI.
///
/// ### Page vs card vs toolbar (rhythm)
/// - **Page gutter** — outer inset for scrollable main columns and sidebars (often ``denseGutter`` or ``md``). Example: Mission Control setup scroll edges.
/// - **Card interior** — padding **inside** ``GuardianCard`` / inset panels; keep aligned with ``GuardianCardLayout/defaultBodyPadding`` via ``cardBodyInset`` (14pt).
/// - **Dense toolbar** — horizontal gaps in header/footer **strips** and chip rows; prefer ``xs``–``sm`` so controls align with ``GuardianChromeSize`` row heights.
///
/// Prefer these tokens over raw literals in new work; domain files may expose local enums (e.g. ``MissionRunPrepLayout``) that **alias** values here for one screen’s tuning.
enum GuardianSpacing {

    /// Base grid unit (4pt).
    static let unit: CGFloat = 4

    // MARK: - Named steps (multiples of `unit`)

    static let xxs: CGFloat = unit * 1
    static let xs: CGFloat = unit * 2
    static let sm: CGFloat = unit * 3
    static let md: CGFloat = unit * 4
    static let lg: CGFloat = unit * 5
    static let xl: CGFloat = unit * 6
    static let xxl: CGFloat = unit * 8

    // MARK: - Half-step & micro (still 4pt-aligned where possible)

    /// Tight row / chip gap (6pt — between ``xxs`` and ``xs``).
    static let xsTight: CGFloat = 6

    /// Hairline-adjacent micro gap (2pt).
    static let micro: CGFloat = 2

    /// Ultra-tight stack rhythm (1pt; e.g. label stacks).
    static let hairlineStack: CGFloat = 1

    /// Dense stack / chip row gap (5pt).
    static let stackDense: CGFloat = 5

    // MARK: - Semantic (cross-surface)

    /// Scroll strip / MC-S style horizontal inset (10pt; between ``xs`` and ``sm`` for dense chrome).
    static let denseGutter: CGFloat = 10

    /// Default ``GuardianCard`` body padding (14pt) — keep in sync with ``GuardianCardLayout/defaultBodyPadding``.
    static let cardBodyInset: CGFloat = 14

    /// Comfortable vertical gap between major setup blocks (18pt).
    static let sectionStack: CGFloat = 18

    /// Tight label stack under a title (3pt; sub-grid, not on the 4pt rail).
    static let titleStackTight: CGFloat = 3

    /// Long scrolling shells (Theme catalog rails, hero stacks) — 28pt major rhythm.
    static let stackMajor: CGFloat = 28

    /// Large panel / task card outer comfort inset (22pt).
    static let panelComfortInset: CGFloat = 22

    /// Top bar / window chrome horizontal comfort (15pt).
    static let barInsetComfort: CGFloat = 15

    /// Tight chrome inset for pills / badges (7pt; horizontal or vertical).
    static let chromeTightInset: CGFloat = 7

    /// Slightly wider chip / tab horizontal padding than ``denseGutter`` (9pt).
    static let chromeChipHorizontal: CGFloat = 9

    /// Floating control trailing reserve so content clears overlays (26pt).
    static let floatingTrailingReserve: CGFloat = 26

    /// Map chrome: clearance above attribution / legal strip (85pt).
    static let mapAttributionClearance: CGFloat = 85

    /// ``GuardianInlineNotice`` vertical padding (11pt).
    static let inlineNoticeVertical: CGFloat = 11

    // MARK: - Mission Control — setup / roster prep (MC-S)

    /// Mission Control setup: outer padding around large task / schedule cards (22pt).
    static let missionTaskCardOuterInset: CGFloat = panelComfortInset

    /// Mission Control setup: schedule card interior padding (20pt).
    static let missionScheduleCardInset: CGFloat = lg

    /// Mission Control setup: spacing inside schedule stack blocks (16pt).
    static let missionScheduleBlockGap: CGFloat = md

    /// Roster grid column gap (18pt).
    static let missionRosterGridGap: CGFloat = sectionStack

    /// Minimum width for roster column in prep layout (300pt — layout width, not spacing).
    static let missionRosterGridMinWidth: CGFloat = 300

    /// Breakpoint: stack map above accordion below this width (780pt).
    static let missionRosterMapAccordionBreakpoint: CGFloat = 780
}
