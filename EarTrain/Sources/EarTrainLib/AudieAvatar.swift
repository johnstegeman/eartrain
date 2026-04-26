import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Resource helpers

public extension AudieAvatarView {
    /// The Audie PNG from EarTrainLib's resource bundle.
    /// Use this to set NSApp.applicationIconImage from the EarTrain executable target.
    static var nsImage: NSImage? {
        // Prefer the multi-resolution .icns (rounded corners baked in); fall back to PNG.
        if let url = Bundle.module.url(forResource: "Audie", withExtension: "icns"),
           let img = NSImage(contentsOf: url) { return img }
        if let url = Bundle.module.url(forResource: "audie", withExtension: "png"),
           let img = NSImage(contentsOf: url) { return img }
        return nil
    }
}

// MARK: - AudiePNGImage

/// Shows the bundled audie.png at a given size. Falls back to the programmatic
/// AudieAvatarView if the resource can't be loaded (e.g. during Xcode previews).
public struct AudiePNGImage: View {
    public var size: CGFloat

    public init(size: CGFloat = 120) { self.size = size }

    public var body: some View {
        if let img = AudieAvatarView.nsImage {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            AudieAvatarView(size: size)
        }
    }
}

// MARK: - AudieAvatarView

/// Small cartoon face used inside chat bubbles and wherever Audie appears inline.
/// Scales cleanly from ~20pt (chat label) up to ~120pt (onboarding / about screen).
public struct AudieAvatarView: View {
    public var size: CGFloat = 28

    public init(size: CGFloat = 28) { self.size = size }

    public var body: some View {
        ZStack {
            // Head
            Circle()
                .fill(EarTrainColors.accent)
                .frame(width: size, height: size)

            // Eyes
            HStack(spacing: size * 0.20) {
                eyeDot
                eyeDot
            }
            .offset(y: -size * 0.07)

            // Smile
            AudieSmiledArc()
                .stroke(Color.black.opacity(0.70), style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round))
                .frame(width: size * 0.42, height: size * 0.22)
                .offset(y: size * 0.13)

            // Tiny sound-wave arcs to the right — Audie's "hearing" motif
            ForEach([0, 1], id: \.self) { i in
                AudieSoundArc(gap: CGFloat(i))
                    .stroke(Color.black.opacity(0.35 - Double(i) * 0.10),
                            style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round))
                    .frame(width: size * (0.18 + CGFloat(i) * 0.12),
                           height: size * (0.28 + CGFloat(i) * 0.18))
                    .offset(x: size * (0.32 + CGFloat(i) * 0.11), y: 0)
            }
        }
        .frame(width: size, height: size)
    }

    private var eyeDot: some View {
        Circle()
            .fill(Color.black.opacity(0.72))
            .frame(width: size * 0.11, height: size * 0.11)
    }
}

// MARK: - AudieIconView

/// Full app-icon canvas (use at 512 or 1024 pt, then render to PNG).
/// Background is the app's dark surface; Audie's face sits centred in an amber disc.
public struct AudieIconView: View {
    public var size: CGFloat = 512

    public init(size: CGFloat = 512) { self.size = size }

    private var faceSize: CGFloat { size * 0.72 }

    public var body: some View {
        ZStack {
            // Background — macOS icon rounded square is applied by the system,
            // so just fill the whole frame with the app background colour.
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(Color(hex: "#1a1a1a"))
                .frame(width: size, height: size)

            // Amber head disc
            Circle()
                .fill(EarTrainColors.accent)
                .frame(width: faceSize, height: faceSize)

            // Eyes
            HStack(spacing: faceSize * 0.20) {
                iconEye
                iconEye
            }
            .offset(y: -faceSize * 0.07)

            // Smile
            AudieSmiledArc()
                .stroke(Color.black.opacity(0.68),
                        style: StrokeStyle(lineWidth: faceSize * 0.075, lineCap: .round))
                .frame(width: faceSize * 0.40, height: faceSize * 0.22)
                .offset(y: faceSize * 0.14)

            // Sound-wave arcs — 3 rings, right side
            ForEach([0, 1, 2], id: \.self) { i in
                AudieSoundArc(gap: CGFloat(i))
                    .stroke(Color.black.opacity(0.28 - Double(i) * 0.07),
                            style: StrokeStyle(lineWidth: faceSize * 0.055, lineCap: .round))
                    .frame(width: faceSize * (0.16 + CGFloat(i) * 0.11),
                           height: faceSize * (0.26 + CGFloat(i) * 0.18))
                    .offset(x: faceSize * (0.32 + CGFloat(i) * 0.12), y: 0)
            }
        }
        .frame(width: size, height: size)
    }

    private var iconEye: some View {
        Circle()
            .fill(Color.black.opacity(0.70))
            .frame(width: faceSize * 0.11, height: faceSize * 0.11)
    }
}

// MARK: - Shared shape helpers

/// A bottom-arc "smile" path within its bounding rect.
struct AudieSmiledArc: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(
            center: CGPoint(x: rect.midX, y: rect.minY),
            radius: rect.width * 0.5,
            startAngle: .degrees(15),
            endAngle: .degrees(165),
            clockwise: false
        )
        return p
    }
}

/// A single right-facing arc used for the sound-wave motif.
/// `gap` = 0 is the innermost arc; larger values produce wider, taller arcs.
struct AudieSoundArc: Shape {
    var gap: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(
            center: CGPoint(x: rect.minX, y: rect.midY),
            radius: rect.width,
            startAngle: .degrees(-45),
            endAngle: .degrees(45),
            clockwise: false
        )
        return p
    }
}
