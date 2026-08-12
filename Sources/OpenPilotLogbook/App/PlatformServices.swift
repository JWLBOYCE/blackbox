import AppKit
import Foundation

@MainActor
protocol PlatformServices {
    func chooseFolder(title: String, prompt: String) -> URL?
    func reveal(_ urls: [URL])
    func open(_ url: URL)
}

@MainActor
struct MacPlatformServices: PlatformServices {
    func chooseFolder(title: String, prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
