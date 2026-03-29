import AppKit
import Carbon
import Foundation

@MainActor
final class PasteInjector {
    enum Error: Swift.Error {
        case failedToCreateEventSource
        case accessibilityPermissionDenied
    }

    private enum SnapshotPolicy {
        static let maxItemCount = 10
        static let maxTotalBytes = 5 * 1_024 * 1_024
    }

    private enum ClipboardSnapshot {
        case restorable([PasteboardItemSnapshot])
        case skipped

        var canRestore: Bool {
            if case .restorable = self {
                return true
            }

            return false
        }
    }

    private struct PasteboardItemSnapshot {
        let contents: [NSPasteboard.PasteboardType: Data]
    }

    // Clipboard path:
    // snapshot if cheap -> paste text -> restore snapshot
    // snapshot too large -> paste text -> leave clipboard alone
    func inject(text: String) async throws -> PasteInjectionOutcome {
        guard !text.isEmpty else {
            return PasteInjectionOutcome(clipboardWasRestored: true)
        }

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
        return PasteInjectionOutcome(clipboardWasRestored: snapshot.canRestore)
    }

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> ClipboardSnapshot {
        let items = pasteboard.pasteboardItems ?? []
        guard items.count <= SnapshotPolicy.maxItemCount else {
            return .skipped
        }

        var totalBytes = 0
        var snapshots: [PasteboardItemSnapshot] = []

        for item in items {
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    totalBytes += data.count
                    guard totalBytes <= SnapshotPolicy.maxTotalBytes else {
                        return .skipped
                    }
                    contents[type] = data
                }
            }
            snapshots.append(PasteboardItemSnapshot(contents: contents))
        }

        return .restorable(snapshots)
    }

    private func restorePasteboard(_ snapshot: ClipboardSnapshot, to pasteboard: NSPasteboard) {
        guard case let .restorable(itemsSnapshot) = snapshot else {
            return
        }

        pasteboard.clearContents()

        let items = itemsSnapshot.map { item -> NSPasteboardItem in
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
