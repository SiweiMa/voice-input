import AppKit
import Carbon
import Foundation

final class PasteInjector {
    enum Error: Swift.Error {
        case failedToCreateEventSource
        case accessibilityPermissionDenied
    }

    private struct PasteboardItemSnapshot {
        let contents: [NSPasteboard.PasteboardType: Data]
    }

    func inject(text: String) async throws {
        guard !text.isEmpty else { return }

        guard AXIsProcessTrusted() else {
            throw Error.accessibilityPermissionDenied
        }

        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)
        let switchToken = InputSourceManager.shared.temporarilySwitchToASCIIIfNeeded()

        defer {
            InputSourceManager.shared.restore(switchToken)
            restorePasteboard(snapshot, to: pasteboard)
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try await Task.sleep(nanoseconds: 80_000_000)
        try postCommandV()
        try await Task.sleep(nanoseconds: 140_000_000)
    }

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [PasteboardItemSnapshot] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type] = data
                }
            }
            return PasteboardItemSnapshot(contents: contents)
        }
    }

    private func restorePasteboard(_ snapshot: [PasteboardItemSnapshot], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let items = snapshot.map { item -> NSPasteboardItem in
            let pasteboardItem = NSPasteboardItem()
            for (type, data) in item.contents {
                pasteboardItem.setData(data, forType: type)
            }
            return pasteboardItem
        }

        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private func postCommandV() throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw Error.failedToCreateEventSource
        }

        let keyCode = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
