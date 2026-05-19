import AppKit
import Foundation
import UniformTypeIdentifiers

enum GuardianBrainPackImportService {
    @MainActor
    static func promptImportFromDisk() -> GuardianBrainCatalogueEntry? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [GuardianBrainPackExportService.guardianBrainUTType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Guardian Brain Pack"
        panel.message = "Select a `.guardianbrain` file exported from Guardian Training."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            return try GuardianBrainCatalogueStore.importPackFile(from: url)
        } catch {
            presentImportError(error)
            return nil
        }
    }

    @MainActor
    static func importFromURL(_ url: URL) -> GuardianBrainCatalogueEntry? {
        do {
            return try GuardianBrainCatalogueStore.importPackFile(from: url)
        } catch {
            presentImportError(error)
            return nil
        }
    }

    @MainActor
    private static func presentImportError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Brain pack import failed"
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.runModal()
    }
}
