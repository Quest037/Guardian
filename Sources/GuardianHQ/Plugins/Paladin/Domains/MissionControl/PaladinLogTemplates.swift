import Foundation

// MARK: - Paladin-owned MissionRun log template keys

extension MissionRunLogTemplateKey {
    /// Paladin assistant engaging execution (distinct from MC ``executionStarted``).
    static let paladinExecutionStarted = "paladin.mre.execution.started"
}

// MARK: - Paladin template catalog (plugin extension to ``StructuredLogTemplateCatalog``)

/// Registers Paladin-owned ``MissionRunLogTemplateKey`` patterns with the app-wide
/// ``StructuredLogTemplateCatalog`` so MCR rendering and plain-text export resolve them the same
/// way as core templates — without Paladin entries having to live in the core catalog file.
///
/// Registration is idempotent and triggered from ``PaladinMissionAssistant/registerProfile()``,
/// which runs on every assistant construction (and is cheap to call repeatedly). This keeps
/// Paladin's logging surface fully self-contained inside its own module.
///
/// Pattern for adding more Paladin lines: define a new key constant in the
/// ``MissionRunLogTemplateKey`` extension above, then add a ``StructuredLogTemplateCatalog/registerTemplate(pluginID:forKey:defaultPattern:mcr:)``
/// call in ``registerTemplates()`` below. No core-catalog changes required.
enum PaladinLogTemplateCatalog {
    static func registerTemplates() {
        StructuredLogTemplateCatalog.registerTemplate(
            pluginID: .paladin,
            forKey: MissionRunLogTemplateKey.paladinExecutionStarted,
            defaultPattern: "Paladin execution started.",
            mcr: "Paladin · execution started"
        )
    }
}
