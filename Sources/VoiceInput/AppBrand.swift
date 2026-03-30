import AppKit
import SwiftUI

extension NSColor {
    static let voiceInk = NSColor(srgbRed: 0.09, green: 0.11, blue: 0.16, alpha: 1)
    static let voiceSlate = NSColor(srgbRed: 0.16, green: 0.20, blue: 0.29, alpha: 1)
    static let voiceMist = NSColor(srgbRed: 0.92, green: 0.94, blue: 0.97, alpha: 1)
    static let voiceEmber = NSColor(srgbRed: 0.95, green: 0.38, blue: 0.21, alpha: 1)
    static let voiceSun = NSColor(srgbRed: 0.98, green: 0.71, blue: 0.32, alpha: 1)
    static let voiceSky = NSColor(srgbRed: 0.41, green: 0.74, blue: 0.93, alpha: 1)
}

extension Color {
    static let voiceInk = Color(nsColor: .voiceInk)
    static let voiceSlate = Color(nsColor: .voiceSlate)
    static let voiceMist = Color(nsColor: .voiceMist)
    static let voiceEmber = Color(nsColor: .voiceEmber)
    static let voiceSun = Color(nsColor: .voiceSun)
    static let voiceSky = Color(nsColor: .voiceSky)
}

enum AppBrand {
    static func statusBarImage(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.black.setFill()

            let barWidth = rect.width * 0.14
            let spacing = rect.width * 0.08
            let heights: [CGFloat] = [0.38, 0.62, 0.84, 0.54]
            let totalWidth = (barWidth * CGFloat(heights.count)) + (spacing * CGFloat(heights.count - 1))
            let startX = rect.midX - (totalWidth / 2) - (rect.width * 0.05)

            for (index, factor) in heights.enumerated() {
                let height = rect.height * factor
                let originX = startX + CGFloat(index) * (barWidth + spacing)
                let originY = rect.midY - (height / 2)
                let barRect = NSRect(x: originX, y: originY, width: barWidth, height: height)
                NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            }

            let slash = NSBezierPath()
            slash.lineWidth = rect.width * 0.10
            slash.lineCapStyle = .round
            slash.move(to: NSPoint(x: rect.maxX - (rect.width * 0.24), y: rect.midY - (rect.height * 0.24)))
            slash.line(to: NSPoint(x: rect.maxX - (rect.width * 0.11), y: rect.midY - (rect.height * 0.03)))
            slash.stroke()

            return true
        }

        image.isTemplate = true
        return image
    }
}

struct AppLogoView: View {
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.voiceSun.opacity(0.18))
                .frame(width: size * 1.12, height: size * 1.12)
                .blur(radius: size * 0.12)
                .offset(x: -size * 0.08, y: size * 0.06)

            Circle()
                .fill(Color.voiceSky.opacity(0.16))
                .frame(width: size * 0.92, height: size * 0.92)
                .blur(radius: size * 0.12)
                .offset(x: size * 0.18, y: -size * 0.12)

            ZStack {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.voiceInk, .voiceSlate],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)

                VoiceBubbleShape()
                    .fill(
                        LinearGradient(
                            colors: [.voiceEmber, .voiceSun, .voiceSky],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(size * 0.16)
                    .shadow(color: .voiceEmber.opacity(0.18), radius: size * 0.08, y: size * 0.03)

                HStack(alignment: .center, spacing: size * 0.045) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.95))
                        .frame(width: size * 0.08, height: size * 0.28)

                    ForEach([0.22, 0.36, 0.5, 0.34], id: \.self) { factor in
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.95))
                            .frame(width: size * 0.055, height: size * CGFloat(factor))
                    }
                }
                .offset(x: -size * 0.03, y: -size * 0.03)

                RoundedRectangle(cornerRadius: size * 0.05, style: .continuous)
                    .fill(Color.white.opacity(0.95))
                    .frame(width: size * 0.19, height: size * 0.045)
                    .offset(x: -size * 0.02, y: size * 0.17)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.14), radius: size * 0.18, y: size * 0.08)
        }
        .frame(width: size * 1.18, height: size * 1.1)
    }
}

private struct VoiceBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let corner = rect.width * 0.28
        let bubbleRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height * 0.82
        )

        var path = Path(roundedRect: bubbleRect, cornerRadius: corner)

        path.move(to: CGPoint(x: rect.midX + rect.width * 0.1, y: bubbleRect.maxY - rect.height * 0.02))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.28, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.18, y: bubbleRect.maxY - rect.height * 0.18))
        path.closeSubpath()

        return path
    }
}
