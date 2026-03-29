import AppKit
import QuartzCore

final class RecordingOverlayController {
    private let panel: NSPanel
    private let visualEffectView = NSVisualEffectView()
    private let waveformView = WaveformView()
    private let textField = NSTextField(labelWithString: "")

    private var currentWidth: CGFloat = 220
    private var isShown = false
    private var hideWorkItem: DispatchWorkItem?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: currentWidth, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none

        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 28
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        waveformView.translatesAutoresizingMaskIntoConstraints = false

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = .systemFont(ofSize: 15, weight: .medium)
        textField.textColor = .labelColor
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: currentWidth, height: 56))
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.masksToBounds = false

        panel.contentView = contentView
        contentView.addSubview(visualEffectView)
        visualEffectView.addSubview(waveformView)
        visualEffectView.addSubview(textField)

        NSLayoutConstraint.activate([
            visualEffectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: contentView.topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            waveformView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 18),
            waveformView.centerYAnchor.constraint(equalTo: visualEffectView.centerYAnchor),
            waveformView.widthAnchor.constraint(equalToConstant: 44),
            waveformView.heightAnchor.constraint(equalToConstant: 32),

            textField.leadingAnchor.constraint(equalTo: waveformView.trailingAnchor, constant: 14),
            textField.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -22),
            textField.centerYAnchor.constraint(equalTo: visualEffectView.centerYAnchor),
        ])
    }

    func show() {
        hideWorkItem?.cancel()
        updateStatus("Listening...")
        updateAudioLevel(0)
        resizeIfNeeded(for: textField.stringValue, animated: false)

        if !isShown {
            let frame = targetFrame(forWidth: currentWidth)
            panel.setFrame(frame, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            isShown = true
            animateEntry()
        } else {
            panel.orderFrontRegardless()
        }
    }

    func updateTranscript(_ text: String) {
        let displayText = text.isEmpty ? "Listening..." : text
        textField.stringValue = displayText
        resizeIfNeeded(for: displayText, animated: true)
    }

    func updateStatus(_ text: String) {
        textField.stringValue = text
        resizeIfNeeded(for: text, animated: true)
    }

    func updateAudioLevel(_ level: CGFloat) {
        waveformView.update(level: level)
    }

    func hide(after delay: TimeInterval = 0) {
        hideWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.animateExit()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func hide() {
        hide(after: 0)
    }

    private func resizeIfNeeded(for text: String, animated: Bool) {
        let targetWidth = measuredWidth(for: text)
        guard abs(targetWidth - currentWidth) > 1 else { return }

        currentWidth = targetWidth
        let frame = targetFrame(forWidth: targetWidth)

        if animated, isShown {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func measuredWidth(for text: String) -> CGFloat {
        let font = textField.font ?? .systemFont(ofSize: 15, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textWidth = ceil((text as NSString).size(withAttributes: attributes).width)
        let total = 18 + 44 + 14 + textWidth + 22
        return min(max(total, 160), 560)
    }

    private func targetFrame(forWidth width: CGFloat) -> NSRect {
        let screen = screenForOverlay()
        let visibleFrame = screen.visibleFrame
        let originX = visibleFrame.midX - (width / 2)
        let originY = visibleFrame.minY + 42
        return NSRect(x: originX, y: originY, width: width, height: 56)
    }

    private func screenForOverlay() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func animateEntry() {
        panel.alphaValue = 0
        visualEffectView.layer?.removeAllAnimations()

        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.88
        spring.toValue = 1.0
        spring.initialVelocity = 10
        spring.damping = 16
        spring.mass = 1
        spring.stiffness = 180
        spring.duration = 0.35
        spring.isRemovedOnCompletion = true
        visualEffectView.layer?.add(spring, forKey: "entryScale")

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func animateExit() {
        guard isShown else { return }

        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 1.0
        scaleAnimation.toValue = 0.92
        scaleAnimation.duration = 0.22
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        visualEffectView.layer?.add(scaleAnimation, forKey: "exitScale")

        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 0
            },
            completionHandler: { [weak self] in
                guard let self else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.isShown = false
            }
        )
    }
}
