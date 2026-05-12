# Operator prompts — attribution, routing, and future chrome

**Concept (locked):** Headless assistants (e.g. **Paladin**) do **not** draw UI. They call **Mission Control / MRE** APIs; when rules of engagement require operator consent, **Mission Control** registers the operator prompt (MC-R bottom prompt, router, etc.). The prompt must make clear **who initiated the ask**:

- **Default source copy** when the core Mission Control / MRE stack surfaces a prompt: treat as **Mission Control** (or **MRE**) — not a plugin.
- **Assistant- or plugin-initiated** flows: the prompt should name the **issuer** (e.g. Paladin) so the operator understands what automation proposed the action, even though Mission Control owns the chrome.

Escalation path in short: **assistant → MRE / store → RoE disposition → (if ask/defer/handoff) Mission Control operator prompt** with correct attribution.

---

## References

- ``OperatorPromptEvent`` / ``OperatorPromptOrigin`` — `Sources/GuardianHQ/Systems/OperatorPrompts/OperatorPromptEvent.swift`
- ``MissionRunRecipeOperatorPromptBridge`` — Mission Control run prompts
- ``MissionRunEngagementAction`` / disposition — RoE gate before prompts
- README **Floating reserve pool** / Paladin headless note — assistant vs Mission Control UI ownership
