import AppKit
import Foundation

@MainActor
protocol PlatformServices {
    func chooseFolder(title: String, prompt: String, completion: @escaping @MainActor (URL?) -> Void)
    func reveal(_ urls: [URL])
    func open(_ url: URL)
}

@MainActor
struct MacPlatformServices: PlatformServices {
    func chooseFolder(title: String, prompt: String, completion: @escaping @MainActor (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .OK ? panel.url : nil)
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
