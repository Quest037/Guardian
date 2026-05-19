import AppKit
import Foundation

enum TrainingEnvironmentImportExportService {
    @MainActor
    static func promptImportFolder() -> TrainingEnvironmentPackage? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Import training environment"
        panel.message = "Choose a folder containing manifest.json and a world file."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            return try TrainingEnvironmentCatalogue.importPackage(from: url)
        } catch {
            presentError("Import failed", error: error)
            return nil
        }
    }

    @MainActor
    static func promptExportFolder(package: TrainingEnvironmentPackage) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Export training environment"
        panel.message = "Choose a folder. Guardian will copy \(package.manifest.id) into it."
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let dest = parent.appendingPathComponent(package.manifest.id, isDirectory: true)
        do {
            try TrainingEnvironmentCatalogue.exportPackage(package, to: dest)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            presentError("Export failed", error: error)
        }
    }

    @MainActor
    private static func presentError(_ title: String, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.runModal()
    }
}
