import AppKit
import Foundation

@MainActor
enum FolderPicker {
    static func chooseFolder(prompt: String, startingAt path: String? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.prompt = "Choose"
        panel.message = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if let path, !path.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path)
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
