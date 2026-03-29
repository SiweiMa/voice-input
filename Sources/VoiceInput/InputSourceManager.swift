import Carbon
import Foundation

final class InputSourceManager {
    struct SwitchToken {
        let originalSource: TISInputSource
    }

    static let shared = InputSourceManager()

    func temporarilySwitchToASCIIIfNeeded() -> SwitchToken? {
        guard let currentSource = currentKeyboardSource() else {
            return nil
        }

        guard isCJKSource(currentSource) else {
            return nil
        }

        guard let asciiSource = bestASCIISource() else {
            return nil
        }

        let status = TISSelectInputSource(asciiSource)
        guard status == noErr else {
            return nil
        }

        return SwitchToken(originalSource: currentSource)
    }

    func restore(_ token: SwitchToken?) {
        guard let token else { return }
        _ = TISSelectInputSource(token.originalSource)
    }

    private func currentKeyboardSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    private func bestASCIISource() -> TISInputSource? {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsASCIICapable as String: true,
        ] as CFDictionary

        guard
            let array = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
            !array.isEmpty
        else {
            return nil
        }

        let preferredIDs = [
            "com.apple.keylayout.ABC",
            "com.apple.keylayout.US",
        ]

        for sourceID in preferredIDs {
            if let match = array.first(where: { self.inputSourceID(for: $0) == sourceID }) {
                return match
            }
        }

        return array.first
    }

    private func isCJKSource(_ source: TISInputSource) -> Bool {
        let languages = inputSourceLanguages(for: source).map { $0.lowercased() }
        if languages.contains(where: { $0.hasPrefix("zh") || $0.hasPrefix("ja") || $0.hasPrefix("ko") }) {
            return true
        }

        let sourceID = inputSourceID(for: source).lowercased()
        return sourceID.contains("inputmethod.scim") ||
            sourceID.contains("inputmethod.tcim") ||
            sourceID.contains("inputmethod.kotoeri") ||
            sourceID.contains("inputmethod.korean")
    }

    private func inputSourceID(for source: TISInputSource) -> String {
        guard let rawValue = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return ""
        }

        return Unmanaged<CFString>.fromOpaque(rawValue).takeUnretainedValue() as String
    }

    private func inputSourceLanguages(for source: TISInputSource) -> [String] {
        guard let rawValue = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return []
        }

        let languages = Unmanaged<CFArray>.fromOpaque(rawValue).takeUnretainedValue() as [AnyObject]
        return languages.compactMap { $0 as? String }
    }
}
