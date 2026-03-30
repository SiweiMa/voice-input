import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    private let viewModel = SettingsViewModel()

    init() {
        let rootView = SettingsView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Voice Input"
        window.setContentSize(NSSize(width: 720, height: 620))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        viewModel.reloadFromSettings()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }
}
