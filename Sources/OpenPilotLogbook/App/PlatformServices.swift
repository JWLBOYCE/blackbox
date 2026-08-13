import AppKit
import Foundation

@MainActor
protocol PlatformServices {
    func chooseFolder(title: String, prompt: String, completion: @escaping @MainActor (URL?) -> Void)
    func reveal(_ urls: [URL])
    func open(_ url: URL)
}

@MainActor
final class MacPlatformServices: PlatformServices {
    private let folderPanels = FolderPanelCoordinator()

    func chooseFolder(title: String, prompt: String, completion: @escaping @MainActor (URL?) -> Void) {
        folderPanels.chooseFolder(title: title, prompt: prompt, completion: completion)
    }

    func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

/// Retains the native folder chooser for its complete presentation lifetime.
/// AppKit normally owns a visible sheet, but keeping an explicit strong
/// reference also covers the interval before the sheet is attached and gives
/// UI automation a stable window identifier independent of the button title.
@MainActor
private final class FolderPanelCoordinator {
    private var activePanel: NSOpenPanel?

    func chooseFolder(title: String, prompt: String, completion: @escaping @MainActor (URL?) -> Void) {
        if let activePanel {
            activePanel.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSOpenPanel()
        panel.identifier = NSUserInterfaceItemIdentifier("blackbox.folder-panel")
        panel.title = title
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        activePanel = panel

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            let selectedURL = response == .OK ? panel?.url : nil
            self?.activePanel = nil
            completion(selectedURL)
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }
}
