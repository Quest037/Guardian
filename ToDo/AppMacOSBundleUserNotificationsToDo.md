# macOS app bundle + UserNotifications

Goal: ship a **real `Guardian HQ.app`** (not only the SwiftPM flat `GuardianHQ` executable) so macOS **TCC / `UNUserNotificationCenter`** behave like a normal app, and so we can **test and rely on UserNotifications** (MC-R background awareness, operator prompts when out-of-app).

**Today:** `Package.swift` produces an **executable**; `MainBundle-Info.plist` is linked for minimal bundle id when running from Xcode’s flat product. `scripts/package-macos-app.sh` builds `build/Guardian HQ.app` by copying the binary + `Packaging/GuardianHQ-App-Info.plist` → `Contents/Info.plist` and the SwiftPM resource bundle next to the executable. `UserNotificationService` (`Sources/GuardianHQ/App/UserNotificationService.swift`) configures `UNUserNotificationCenter`, registers categories, requests auth **only** when `Bundle.main.bundleURL` is `.app`, and implements `deliver(…)` plus Mission Control / Paladin helpers — but **`requestAuthorization` is skipped** outside an app bundle, and **`stubNotifyMissionRunOperatorPrompt`** is still a stub (README OOA / Stage D).

---

## Phase A — Repeatable `.app` for local test

- [ ] **Document the happy path** in `README.md` (one subsection): `scripts/package-macos-app.sh` → `open "build/Guardian HQ.app"`; note that **Xcode Run** on the SPM executable alone will **not** grant notifications (matches in-code trace + `UNError` 1 / `notificationsNotAllowed`).
- [ ] **Version alignment:** `Packaging/GuardianHQ-App-Info.plist` `CFBundleShortVersionString` / `CFBundleVersion` vs `Sources/GuardianHQ/MainBundle-Info.plist` / `Sources/GuardianHQ/App/AppMetadata.swift` — decide single source of truth (script sed from `AppMetadata`, or documented manual bump checklist).
- [ ] **Codesign (adhoc) for local:** sign the `.app` (and embedded helper binaries if any) so Gatekeeper / “damaged app” does not block testers; document `codesign --force --deep -s - …` for dev.
- [ ] **Optional:** Add a **Cursor / Makefile** target name that mirrors the script (wrapper only) so “build app” is one command from docs.

---

## Phase B — Xcode macOS App target (optional but “real product”)

- [ ] Add **`GuardianHQ.xcodeproj`** (or workspace) with a **macOS App** target that **depends on this Swift package** (`GuardianHQ` library product) *or* embeds the package — whichever matches team preference; goal is **Archive → .app** without relying only on the shell packager.
- [ ] Wire **Run** scheme to the **.app** so developers who live in Xcode still hit `Bundle.main.bundleURL.pathExtension == "app"`.
- [ ] **Export / archive** notes: Development vs Distribution signing, hardened runtime if required for notarization later.

---

## Phase C — UserNotifications: authorization + delivery QA

- [ ] **Manual test matrix** (document in this file until automated): first launch inside `.app` → permission prompt → **Allow** → `deliver` shows banner + Notification Center; **Deny** → `deliver` skipped with trace; **Focus / Do Not Disturb** behaviour noted.
- [ ] **`UNUserNotificationCenterDelegate`:** `didReceive` / `willPresent` — today completion handlers are minimal; define behaviour: tap notification → bring app forward + **deep link** (e.g. open Mission Control run / MC-R tab) using `userInfo` (`guardian.kind`, `guardian.runID` already reserved in `deliver`).
- [ ] **Categories + actions:** extend beyond `UserNotificationCategory.general`; add MC-R–specific categories if we need action buttons (e.g. “Open run”, “Dismiss”) without violating confirm-dialog rules for destructive work.
- [ ] **Time Sensitive / Critical Alert:** only if product needs interrupt; requires entitlement + App Store justification — treat as separate gate.

---

## Phase D — Operator prompts + routing (`ToDo/TODO.md` cross-links)

- [ ] **`ProcessPromptPolicy` / `OperatorPromptDeliveryTarget`:** route selected prompts to `UserNotificationService.deliver` when target is `.userNotification(…)` and operator is out-of-app / background (replace or complement stub path); keep in-app toast + bottom prompt behaviour unchanged when focused.
- [ ] **Replace `stubNotifyMissionRunOperatorPrompt`** with real payload (title/subtitle/body/thread id from `OperatorPromptEvent` / run context); ensure **no “future version”** operator copy per `.cursor/rules/no-future-version-user-copy.mdc`.
- [ ] **Paladin / plugins:** align `PaladinNotificationPlugin` + any new kinds with same delegate + deep-link contract.
- [ ] **Tests:** where pure logic exists (routing decision, `userInfo` shape, Codable), add `XCTest`; UN integration remains manual / UI test unless we add a thin protocol mock for `UNUserNotificationCenter`.

---

## Phase E — CI / release (later)

- [ ] **CI:** optional job that runs `scripts/package-macos-app.sh` release + `codesign` to catch broken packaging.
- [ ] **Notarization + stapling** — product decision; not required for local UserNotifications testing with adhoc sign.

---

## References

- `scripts/package-macos-app.sh` — builds `build/Guardian HQ.app`
- `Packaging/GuardianHQ-App-Info.plist` — packaged `Info.plist`
- `Sources/GuardianHQ/App/UserNotificationService.swift` — `UNUserNotificationCenter` adapter + `.app` gate
- `Sources/GuardianHQ/App/GuardianHQApp.swift` — `configure()` / `AppDelegate` hooks
- `Sources/GuardianHQ/Systems/MissionControl/MissionControlUserNotifications.swift` — MC-specific `deliver` wrappers
- `Sources/GuardianHQ/Systems/OperatorPrompts/` — delivery targets + policy
- `README.md` — OOA / `userNotification(style:)` mentions; extend with “Build the .app” subsection when Phase A lands

---

## When this file is empty

Migrate any **locked** packaging or entitlement rules to `README.md`, delete this file, and restore a short one-liner in `ToDo/TODO.md` **App System** if anything remains optional.
