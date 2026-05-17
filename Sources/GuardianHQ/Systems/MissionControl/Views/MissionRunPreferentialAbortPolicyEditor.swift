import SwiftUI

/// Reusable ordered-list editor for ``MissionRunAbortTactic`` chains (Mission Control abort preferences).
struct MissionRunPreferentialAbortPolicyEditor: View {
    @Binding var chain: [MissionRunAbortTactic]
    var showFootnote: Bool = true
    /// Tighter vertical rhythm (e.g. MC‑R **Run Rules** drawer): 5pt between tactic rows and before **Add tactic**.
    var compactVerticalRhythm: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var tacticListOuterSpacing: CGFloat {
        compactVerticalRhythm ? GuardianSpacing.stackDense : GuardianSpacing.sm
    }

    private var tacticRowStackSpacing: CGFloat {
        compactVerticalRhythm ? GuardianSpacing.stackDense : GuardianSpacing.xs
    }

    private var tacticRowVerticalPadding: CGFloat {
        compactVerticalRhythm ? 0 : GuardianSpacing.xxs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: tacticListOuterSpacing) {
            ScrollView {
                VStack(alignment: .leading, spacing: tacticRowStackSpacing) {
                    ForEach(0 ..< chain.count, id: \.self) { idx in
                        HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                            VStack(spacing: 0) {
                                Button {
                                    moveUp(index: idx)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(GuardianPointerPlainButtonStyle())
                                .disabled(idx == 0)
                                .guardianPointerOnHover()

                                Button {
                                    moveDown(index: idx)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(GuardianPointerPlainButtonStyle())
                                .disabled(idx == chain.count - 1)
                                .guardianPointerOnHover()
                            }
                            .foregroundStyle(theme.textSecondary)

                            tacticRow(at: idx)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                commitChain { rows in
                                    guard idx < rows.count else { return }
                                    rows.remove(at: idx)
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(GuardianPointerPlainButtonStyle())
                            .foregroundStyle(GuardianSemanticColors.dangerForeground)
                            .guardianPointerOnHover()
                        }
                        .padding(.vertical, tacticRowVerticalPadding)
                    }
                }
            }
            .preferentialChainScrollSizing(compactVerticalRhythm: compactVerticalRhythm)

            HStack(alignment: .top, spacing: GuardianSpacing.sm) {
                Menu {
                    ForEach(MissionRunAbortTactic.addMenuKindOrdering, id: \.self) { k in
                        Button(MissionRunAbortTactic(kind: k, mapPointKind: k == .nearestOpenMapPoint ? .rally : nil).setupMenuLabel) {
                            append(k)
                        }
                    }
                } label: {
                    Label("Add tactic", systemImage: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .guardianPointerOnHover()

                if showFootnote {
                    Text(
                        "Order is tried top to bottom. Nearest open point uses live position and open map pins; Park stays last for a safe fallback."
                    )
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { chain = MissionRunAbortTactic.normalizedPreferenceChain(chain) }
    }

    /// Assign through the binding — in-place `append` / `swapAt` / subscript sets are dropped when the getter rebuilds from mission template.
    private func commitChain(_ mutate: (inout [MissionRunAbortTactic]) -> Void) {
        var next = chain
        mutate(&next)
        chain = MissionRunAbortTactic.normalizedPreferenceChain(next)
    }

    private func moveUp(index: Int) {
        guard index > 0 else { return }
        commitChain { rows in rows.swapAt(index, index - 1) }
    }

    private func moveDown(index: Int) {
        guard index < chain.count - 1 else { return }
        commitChain { rows in rows.swapAt(index, index + 1) }
    }

    @ViewBuilder
    private func tacticRow(at index: Int) -> some View {
        HStack(alignment: .center, spacing: GuardianSpacing.sm) {
            Picker("", selection: kindPickerSelection(at: index)) {
                ForEach(MissionRunAbortTactic.addMenuKindOrdering, id: \.self) { k in
                    Text(MissionRunAbortTactic(kind: k, mapPointKind: k == .nearestOpenMapPoint ? .rally : nil).setupMenuLabel)
                        .tag(k)
                }
            }
            .labelsHidden()
            .frame(minWidth: 170, alignment: .leading)

            if index < chain.count, chain[index].kind == .nearestOpenMapPoint {
                Picker("", selection: mapPointKindBinding(at: index)) {
                    ForEach(MissionPointKind.allCases) { k in
                        Text(k.rawValue.capitalized).tag(k)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 110, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, GuardianSpacing.xxs)
    }

    private func kindPickerSelection(at index: Int) -> Binding<MissionRunAbortTactic.Kind> {
        Binding(
            get: { chain[index].kind },
            set: { new in
                commitChain { rows in
                    guard index < rows.count else { return }
                    rows[index].kind = new
                    if new != .nearestOpenMapPoint {
                        rows[index].mapPointKind = nil
                    } else if rows[index].mapPointKind == nil {
                        rows[index].mapPointKind = .rally
                    }
                }
            }
        )
    }

    private func mapPointKindBinding(at index: Int) -> Binding<MissionPointKind> {
        Binding(
            get: { chain[index].mapPointKind ?? .rally },
            set: { new in
                commitChain { rows in
                    guard index < rows.count else { return }
                    rows[index].mapPointKind = new
                }
            }
        )
    }

    private func append(_ kind: MissionRunAbortTactic.Kind) {
        let mk: MissionPointKind? = kind == .nearestOpenMapPoint ? .rally : nil
        commitChain { rows in
            rows.append(MissionRunAbortTactic(kind: kind, mapPointKind: mk))
        }
    }
}

// MARK: - Optional override (task / roster slot)

/// Task or slot editor: `nil` inherits; non-`nil` is a full override chain.
struct MissionRunOptionalPreferentialAbortPolicyEditor: View {
    @Binding var overrideChain: [MissionRunAbortTactic]?
    let inheritedChain: [MissionRunAbortTactic]

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            if overrideChain == nil {
                Text("Inherited: \(MissionRunAbortTactic.summarizedForLogging(inheritedChain))")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Customize chain") {
                    overrideChain = MissionRunAbortTactic.copyingForIndependentEdit(inheritedChain)
                }
                .buttonStyle(.borderedProminent)
                .guardianPointerOnHover()
            } else {
                MissionRunPreferentialAbortPolicyEditor(chain: nonOptionalBinding, showFootnote: true)

                Button("Use inherited chain") {
                    overrideChain = nil
                }
                .buttonStyle(.bordered)
                .guardianPointerOnHover()
            }
        }
    }

    private var nonOptionalBinding: Binding<[MissionRunAbortTactic]> {
        Binding(
            get: { overrideChain ?? inheritedChain },
            set: { newValue in
                overrideChain = MissionRunAbortTactic.normalizedPreferenceChain(newValue)
            }
        )
    }
}

// MARK: - Complete preference chain editors

/// Ordered-list editor for ``MissionRunCompleteTactic`` chains (recovery / complete policy).
struct MissionRunPreferentialCompletePolicyEditor: View {
    @Binding var chain: [MissionRunCompleteTactic]
    var showFootnote: Bool = true
    var compactVerticalRhythm: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var tacticListOuterSpacing: CGFloat {
        compactVerticalRhythm ? GuardianSpacing.stackDense : GuardianSpacing.sm
    }

    private var tacticRowStackSpacing: CGFloat {
        compactVerticalRhythm ? GuardianSpacing.stackDense : GuardianSpacing.xs
    }

    private var tacticRowVerticalPadding: CGFloat {
        compactVerticalRhythm ? 0 : GuardianSpacing.xxs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: tacticListOuterSpacing) {
            ScrollView {
                VStack(alignment: .leading, spacing: tacticRowStackSpacing) {
                    ForEach(0 ..< chain.count, id: \.self) { idx in
                        HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                            VStack(spacing: 0) {
                                Button {
                                    moveUp(index: idx)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(GuardianPointerPlainButtonStyle())
                                .disabled(idx == 0)
                                .guardianPointerOnHover()

                                Button {
                                    moveDown(index: idx)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(GuardianPointerPlainButtonStyle())
                                .disabled(idx == chain.count - 1)
                                .guardianPointerOnHover()
                            }
                            .foregroundStyle(theme.textSecondary)

                            tacticRow(at: idx)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                commitChain { rows in
                                    guard idx < rows.count else { return }
                                    rows.remove(at: idx)
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(GuardianPointerPlainButtonStyle())
                            .foregroundStyle(GuardianSemanticColors.dangerForeground)
                            .guardianPointerOnHover()
                        }
                        .padding(.vertical, tacticRowVerticalPadding)
                    }
                }
            }
            .preferentialChainScrollSizing(compactVerticalRhythm: compactVerticalRhythm)

            HStack(alignment: .top, spacing: GuardianSpacing.sm) {
                Menu {
                    ForEach(MissionRunCompleteTactic.addMenuKindOrdering, id: \.self) { k in
                        Button(MissionRunCompleteTactic(kind: k, mapPointKind: k == .nearestOpenMapPoint ? .rally : nil).setupMenuLabel) {
                            append(k)
                        }
                    }
                } label: {
                    Label("Add tactic", systemImage: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .guardianPointerOnHover()

                if showFootnote {
                    Text(
                        "Order is tried top to bottom. Nearest open mission point uses live position and open map pins; Park stays last unless the chain is only None (no wind-down)."
                    )
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { chain = MissionRunCompleteTactic.normalizedPreferenceChain(chain) }
    }

    private func commitChain(_ mutate: (inout [MissionRunCompleteTactic]) -> Void) {
        var next = chain
        mutate(&next)
        chain = MissionRunCompleteTactic.normalizedPreferenceChain(next)
    }

    private func moveUp(index: Int) {
        guard index > 0 else { return }
        commitChain { rows in rows.swapAt(index, index - 1) }
    }

    private func moveDown(index: Int) {
        guard index < chain.count - 1 else { return }
        commitChain { rows in rows.swapAt(index, index + 1) }
    }

    @ViewBuilder
    private func tacticRow(at index: Int) -> some View {
        HStack(alignment: .center, spacing: GuardianSpacing.sm) {
            Picker("", selection: kindPickerSelection(at: index)) {
                ForEach(MissionRunCompleteTactic.addMenuKindOrdering, id: \.self) { k in
                    Text(MissionRunCompleteTactic(kind: k, mapPointKind: k == .nearestOpenMapPoint ? .rally : nil).setupMenuLabel)
                        .tag(k)
                }
            }
            .labelsHidden()
            .frame(minWidth: 170, alignment: .leading)

            if index < chain.count, chain[index].kind == .nearestOpenMapPoint {
                Picker("", selection: mapPointKindBinding(at: index)) {
                    ForEach(MissionPointKind.allCases) { k in
                        Text(k.rawValue.capitalized).tag(k)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 110, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, GuardianSpacing.xxs)
    }

    private func kindPickerSelection(at index: Int) -> Binding<MissionRunCompleteTactic.Kind> {
        Binding(
            get: { chain[index].kind },
            set: { new in
                commitChain { rows in
                    guard index < rows.count else { return }
                    rows[index].kind = new
                    if new == .nearestOpenMapPoint, rows[index].mapPointKind == nil {
                        rows[index].mapPointKind = .rally
                    } else if new != .nearestOpenMapPoint {
                        rows[index].mapPointKind = nil
                    }
                }
            }
        )
    }

    private func mapPointKindBinding(at index: Int) -> Binding<MissionPointKind> {
        Binding(
            get: { chain[index].mapPointKind ?? .rally },
            set: { new in
                commitChain { rows in
                    guard index < rows.count else { return }
                    rows[index].mapPointKind = new
                }
            }
        )
    }

    private func append(_ kind: MissionRunCompleteTactic.Kind) {
        let mk: MissionPointKind? = kind == .nearestOpenMapPoint ? .rally : nil
        commitChain { rows in
            rows.append(MissionRunCompleteTactic(kind: kind, mapPointKind: mk))
        }
    }
}

struct MissionRunOptionalPreferentialCompletePolicyEditor: View {
    @Binding var overrideChain: [MissionRunCompleteTactic]?
    let inheritedChain: [MissionRunCompleteTactic]

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            if overrideChain == nil {
                Text("Inherited: \(MissionRunCompleteTactic.summarizedForLogging(inheritedChain))")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Customize chain") {
                    overrideChain = MissionRunCompleteTactic.copyingForIndependentEdit(inheritedChain)
                }
                .buttonStyle(.borderedProminent)
                .guardianPointerOnHover()
            } else {
                MissionRunPreferentialCompletePolicyEditor(chain: nonOptionalBinding, showFootnote: true)

                Button("Use inherited chain") {
                    overrideChain = nil
                }
                .buttonStyle(.bordered)
                .guardianPointerOnHover()
            }
        }
    }

    private var nonOptionalBinding: Binding<[MissionRunCompleteTactic]> {
        Binding(
            get: { overrideChain ?? inheritedChain },
            set: { newValue in
                overrideChain = MissionRunCompleteTactic.normalizedPreferenceChain(newValue)
            }
        )
    }
}

// MARK: - Reserve swap preference chain editors

/// Ordered-list editor for ``MissionRunReserveSwapTactic`` chains (displaced active after reserve swap-in).
struct MissionRunPreferentialReserveSwapPolicyEditor: View {
    @Binding var chain: [MissionRunReserveSwapTactic]
    var showFootnote: Bool = true
    var compactVerticalRhythm: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var tacticListOuterSpacing: CGFloat {
        compactVerticalRhythm ? GuardianSpacing.stackDense : GuardianSpacing.sm
    }

    private var tacticRowStackSpacing: CGFloat {
        compactVerticalRhythm ? GuardianSpacing.stackDense : GuardianSpacing.xs
    }

    private var tacticRowVerticalPadding: CGFloat {
        compactVerticalRhythm ? 0 : GuardianSpacing.xxs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: tacticListOuterSpacing) {
            ScrollView {
                VStack(alignment: .leading, spacing: tacticRowStackSpacing) {
                    ForEach(0 ..< chain.count, id: \.self) { idx in
                        HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                            VStack(spacing: 0) {
                                Button {
                                    moveUp(index: idx)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(GuardianPointerPlainButtonStyle())
                                .disabled(idx == 0)
                                .guardianPointerOnHover()

                                Button {
                                    moveDown(index: idx)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(GuardianPointerPlainButtonStyle())
                                .disabled(idx == chain.count - 1)
                                .guardianPointerOnHover()
                            }
                            .foregroundStyle(theme.textSecondary)

                            tacticRow(at: idx)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                commitChain { rows in
                                    guard idx < rows.count else { return }
                                    rows.remove(at: idx)
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(GuardianPointerPlainButtonStyle())
                            .foregroundStyle(GuardianSemanticColors.dangerForeground)
                            .guardianPointerOnHover()
                        }
                        .padding(.vertical, tacticRowVerticalPadding)
                    }
                }
            }
            .preferentialChainScrollSizing(compactVerticalRhythm: compactVerticalRhythm)

            HStack(alignment: .top, spacing: GuardianSpacing.sm) {
                Menu {
                    ForEach(MissionRunReserveSwapTactic.addMenuKindOrdering, id: \.self) { k in
                        Button(MissionRunReserveSwapTactic(kind: k, mapPointKind: k == .nearestOpenMapPoint ? .rally : nil).setupMenuLabel) {
                            append(k)
                        }
                    }
                } label: {
                    Label("Add tactic", systemImage: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .guardianPointerOnHover()

                if showFootnote {
                    Text(
                        "Order is tried top to bottom. Nearest open mission point uses live position and open map pins; Park stays last unless the chain is only None (no wind-down)."
                    )
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { chain = MissionRunReserveSwapTactic.normalizedPreferenceChain(chain) }
    }

    private func commitChain(_ mutate: (inout [MissionRunReserveSwapTactic]) -> Void) {
        var next = chain
        mutate(&next)
        chain = MissionRunReserveSwapTactic.normalizedPreferenceChain(next)
    }

    private func moveUp(index: Int) {
        guard index > 0 else { return }
        commitChain { rows in rows.swapAt(index, index - 1) }
    }

    private func moveDown(index: Int) {
        guard index < chain.count - 1 else { return }
        commitChain { rows in rows.swapAt(index, index + 1) }
    }

    @ViewBuilder
    private func tacticRow(at index: Int) -> some View {
        HStack(alignment: .center, spacing: GuardianSpacing.sm) {
            Picker("", selection: kindPickerSelection(at: index)) {
                ForEach(MissionRunReserveSwapTactic.addMenuKindOrdering, id: \.self) { k in
                    Text(MissionRunReserveSwapTactic(kind: k, mapPointKind: k == .nearestOpenMapPoint ? .rally : nil).setupMenuLabel)
                        .tag(k)
                }
            }
            .labelsHidden()
            .frame(minWidth: 170, alignment: .leading)

            if index < chain.count, chain[index].kind == .nearestOpenMapPoint {
                Picker("", selection: mapPointKindBinding(at: index)) {
                    ForEach(MissionPointKind.allCases) { k in
                        Text(k.rawValue.capitalized).tag(k)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 110, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, GuardianSpacing.xxs)
    }

    private func kindPickerSelection(at index: Int) -> Binding<MissionRunReserveSwapTactic.Kind> {
        Binding(
            get: { chain[index].kind },
            set: { new in
                commitChain { rows in
                    guard index < rows.count else { return }
                    rows[index].kind = new
                    if new == .nearestOpenMapPoint, rows[index].mapPointKind == nil {
                        rows[index].mapPointKind = .rally
                    } else if new != .nearestOpenMapPoint {
                        rows[index].mapPointKind = nil
                    }
                }
            }
        )
    }

    private func mapPointKindBinding(at index: Int) -> Binding<MissionPointKind> {
        Binding(
            get: { chain[index].mapPointKind ?? .rally },
            set: { new in
                commitChain { rows in
                    guard index < rows.count else { return }
                    rows[index].mapPointKind = new
                }
            }
        )
    }

    private func append(_ kind: MissionRunReserveSwapTactic.Kind) {
        let mk: MissionPointKind? = kind == .nearestOpenMapPoint ? .rally : nil
        commitChain { rows in
            rows.append(MissionRunReserveSwapTactic(kind: kind, mapPointKind: mk))
        }
    }
}

struct MissionRunOptionalPreferentialReserveSwapPolicyEditor: View {
    @Binding var overrideChain: [MissionRunReserveSwapTactic]?
    let inheritedChain: [MissionRunReserveSwapTactic]

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            if overrideChain == nil {
                Text("Inherited: \(MissionRunReserveSwapTactic.summarizedForLogging(inheritedChain))")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Customize chain") {
                    overrideChain = MissionRunReserveSwapTactic.copyingForIndependentEdit(inheritedChain)
                }
                .buttonStyle(.borderedProminent)
                .guardianPointerOnHover()
            } else {
                MissionRunPreferentialReserveSwapPolicyEditor(chain: nonOptionalBinding, showFootnote: true)

                Button("Use inherited chain") {
                    overrideChain = nil
                }
                .buttonStyle(.bordered)
                .guardianPointerOnHover()
            }
        }
    }

    private var nonOptionalBinding: Binding<[MissionRunReserveSwapTactic]> {
        Binding(
            get: { overrideChain ?? inheritedChain },
            set: { newValue in
                overrideChain = MissionRunReserveSwapTactic.normalizedPreferenceChain(newValue)
            }
        )
    }
}

// MARK: - Preferential chain scroll height

/// Default editors reserve a minimum scroll height so sparse chains don’t jump layout; compact (MC‑R **Run Rules** drawer)
/// sizes the scroll area to the tactic rows so **Add tactic** sits tight under the last step.
fileprivate extension View {
    @ViewBuilder
    func preferentialChainScrollSizing(compactVerticalRhythm: Bool) -> some View {
        if compactVerticalRhythm {
            frame(maxHeight: 260)
        } else {
            frame(minHeight: 132, maxHeight: 260)
        }
    }
}
