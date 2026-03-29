import AppKit

final class WaveformView: NSView {
    private let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private var barLayers: [CALayer] = []
    private var smoothedEnvelope: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        for _ in 0..<weights.count {
            let barLayer = CALayer()
            barLayer.backgroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
            barLayer.cornerRadius = 2.5
            barLayer.actions = [
                "position": CABasicAnimation(),
                "bounds": CABasicAnimation(),
            ]
            layer?.addSublayer(barLayer)
            barLayers.append(barLayer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateBarFrames(animated: false)
    }

    func update(level: CGFloat) {
        let boosted = min(max(level * 1.7, 0), 1)
        let smoothing: CGFloat = boosted > smoothedEnvelope ? 0.40 : 0.15
        smoothedEnvelope = (smoothedEnvelope * (1 - smoothing)) + (boosted * smoothing)
        updateBarFrames(animated: true)
    }

    private func updateBarFrames(animated: Bool) {
        guard bounds.width > 0, bounds.height > 0, barLayers.count == weights.count else { return }

        let width: CGFloat = 6
        let spacing: CGFloat = 3.5
        let totalWidth = (CGFloat(weights.count) * width) + (CGFloat(weights.count - 1) * spacing)
        let startX = (bounds.width - totalWidth) / 2
        let centerY = bounds.midY
        let minHeight: CGFloat = 6
        let maxExtra: CGFloat = 24

        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.08 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        for (index, layer) in barLayers.enumerated() {
            let jitter = CGFloat.random(in: 0.96...1.04)
            let height = minHeight + (maxExtra * smoothedEnvelope * weights[index] * jitter)
            let originX = startX + CGFloat(index) * (width + spacing)
            let originY = centerY - (height / 2)
            layer.frame = NSRect(x: originX, y: originY, width: width, height: height)
        }

        CATransaction.commit()
    }
}
