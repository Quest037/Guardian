# Operator prompts — attribution, routing, and future chrome

**Concept (locked):** Headless assistants (e.g. **Paladin**) do **not** draw UI. They call **Mission Control / MRE** APIs; when rules of engagement require operator consent, **Mission Control** registers the operator prompt (MC-R bottom prompt, router, etc.). The prompt must make clear **who initiated the ask**:

- **Default source copy** when the core Mission Control / MRE stack surfaces a prompt: treat as **Mission Control** (or **MRE**) — not a plugin.
- **Assistant- or plugin-initiated** flows: the prompt should name the **issuer** (e.g. Paladin) so the operator understands what automation proposed the action, even though Mission Control owns the chrome.

Escalation path in short: **assistant → MRE / store → RoE disposition → (if ask/defer/handoff) Mission Control operator prompt** with correct attribution.

---

## Near-term (product + plumbing)

- [ ] **First-class prompt source / attribution** — Today some prompts rely on `contextFacts` or body copy for “who asked”. Add a structured field (e.g. on ``OperatorPromptEvent`` or ``OperatorPromptOrigin``) for **display source** (`missionControl` | `mre` | `assistant(pluginID, displayName)` | …) so MC-R / drawer / audit log render consistently without duplicating strings in every publisher. Keep **origin** for routing; add **operator-facing source** for copy and theming hooks.
- [ ] **Reserve swap engagement prompt** — Wire the fixed-reserve swap consent path to the new attribution field once it exists; default label **Mission Control** when the store raises engagement without an assistant issuer; **Paladin** (or issuer display name from registry) when raised via assistant observer path. Align title/body/facts with the single source field.
- [ ] **Recipe escalations vs MRE engagement** — Audit other ``OperatorPromptEvent`` publishers for the same default vs assistant distinction so behaviour matches the model above.

---

## Later (plugin identity in chrome)

- [ ] **Per-issuer prompt accent colour** — Allow assistants/plugins to register a **non-semantic accent** (e.g. Paladin purple, another assistant teal) for operator prompts and related MC-R chrome, distinct from **severity** colours (warning / danger / info). Must stay within design-system constraints (``GuardianTheme`` / tokens); document in Theme plugin if product ships it. Depends on stable **issuer id** + optional **colour token** in assistant profile or plugin manifest extension.

---

## References

- ``OperatorPromptEvent`` / ``OperatorPromptOrigin`` — `Sources/GuardianHQ/Systems/OperatorPrompts/OperatorPromptEvent.swift`
- ``MissionRunRecipeOperatorPromptBridge`` — Mission Control run prompts
- ``MissionRunEngagementAction`` / disposition — RoE gate before prompts
- README **Floating reserve pool** / Paladin headless note — assistant vs Mission Control UI ownership
