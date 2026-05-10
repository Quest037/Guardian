import Foundation

/// Stable `MissionRunEvent.templateKey` string ids for Mission Run / Mission Control.
///
/// Concrete keys live in `extension MissionRunLogTemplateKey` blocks next to the subsystem that emits them,
/// so ownership stays obvious when multiple agents edit the tree. Plugin / assistant modules
/// extend this same type from their own files (see e.g. ``PaladinLogTemplateCatalog``).
///
/// Default + MCR wording for known keys lives in ``StructuredLogTemplateCatalog`` — registered
/// inline for core entries, or via ``StructuredLogTemplateCatalog/registerTemplate(pluginID:forKey:defaultPattern:mcr:)``
/// for plugin-owned ones.
enum MissionRunLogTemplateKey {}
