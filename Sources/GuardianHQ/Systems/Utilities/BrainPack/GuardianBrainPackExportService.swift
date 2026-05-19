import AppKit
import Foundation
import UniformTypeIdentifiers

enum GuardianBrainPackExportService {
    static var guardianBrainUTType: UTType {
        UTType(filenameExtension: GuardianBrainPackFormat.fileExtension)
            ?? .json
    }

    /// Writes a `.guardianbrain` file via save panel. Returns destination URL on success.
    @MainActor
    static func promptSaveToDisk(pack: GuardianBrainPack) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [guardianBrainUTType]
        panel.canCreateDirectories = true
        let safeName = pack.manifest.displayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(safeName)-\(pack.manifest.brainVersion.semverString).\(GuardianBrainPackFormat.fileExtension)"
        panel.title = "Export Guardian Brain Pack"
        panel.message = "Choose where to save this autonomy brain for Guardian Mission."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try write(pack: pack, to: url)
            return url
        } catch {
            return nil
        }
    }

    static func write(pack: GuardianBrainPack, to url: URL) throws {
        let data = try GuardianBrainPackCodec.sealedData(for: pack)
        try data.write(to: url, options: .atomic)
    }

    @MainActor
    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
