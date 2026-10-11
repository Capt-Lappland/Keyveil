import AppKit
import Combine
import SwiftUI

/// Surface treatment for the overlay, split out from the panel so the pixels it
/// produces can be rendered and measured on their own.
///
/// The overlay is a wall of 15 pt text shown on top of whatever the user was
/// doing, so its readability cannot depend on the desktop behind it: a white
/// document, a bright wallpaper, or a busy code editor must all leave the
/// shortcuts legible.
///
/// The surface is therefore two layers:
///
/// 1. a **contrast layer** that always paints an appearance-adaptive background,
///    and
/// 2. the **optical material** on top, which is free to be as thin as it likes
///    because layer 1 already carries the contrast.
///
/// `glassEffect` is deliberately not the only thing standing between the text and
/// the desktop: it is an optical effect that macOS composites against the real
/// window server, so it contributes nothing to a surface rendered offscreen, and
/// it is at its thinnest exactly when the backdrop is brightest.
enum PanelSurfaceStyle {
    /// Opacity of the appearance-matched base fill.
    ///
    /// This is what keeps the labels readable over an arbitrary desktop. It stays
    /// high because the panel must hold its own value: at low opacity a light
    /// panel becomes a mid-grey film over a dark app, which is where the cyan menu
    /// headings used to wash out. Dark appearance needs more still, because a dark
    /// panel over a white page is the case that costs the most contrast — the
    /// backdrop lifts the panel towards the colour of its own labels.
    /// Translucency is carried by the material layered on top, not by starving
    /// this fill.
    static func baseOpacity(for colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? 0.95 : 0.90
    }

    /// Used instead when the user asks for Reduce Transparency.
    static let opaqueBaseOpacity = 1.0

    /// The greyscale value of the base fill: near-white for light appearance,
    /// near-black for dark, so the panel always contrasts with its own labels and
    /// with the opposite-valued backdrop.
    static func baseWhite(for colorScheme: ColorScheme) -> CGFloat {
        colorScheme == .dark ? 0.11 : 0.97
    }

    static func baseColor(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: NSColor(white: baseWhite(for: colorScheme), alpha: 1))
    }

    /// The edge has to be visible against a backdrop of the same value as the
    /// panel itself, which is exactly the case a light panel over a white document
    /// creates. A light panel therefore needs a dark outline and a dark panel a
    /// light one; a white rim would vanish into the white page.
    static func borderWhite(for colorScheme: ColorScheme) -> CGFloat {
        colorScheme == .dark ? 0.85 : 0.28
    }

    static func borderOpacity(for colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? 0.35 : 0.45
    }

    /// Painted outside the panel so it separates from the desktop. The AppKit
    /// window shadow is disabled because it renders as a rectangular rim around a
    /// borderless transparent panel, so the shadow is drawn here instead and
    /// follows the rounded shape.
    ///
    /// It has to stay inside `surfaceInset`. The window is transparent and only as
    /// large as the panel plus that inset, so a larger shadow has nowhere to fade:
    /// it is cut off flat at the window bounds and reads as a translucent grey box
    /// around the panel rather than as a shadow.
    ///
    /// The reach is `radius + offset` downwards but `radius` in every other
    /// direction, so the vertical case is the one that decides whether it fits.
    static let shadowRadius: CGFloat = 9
    static let shadowOffsetY: CGFloat = 4

    /// How far `ShortcutPanelView` insets its content, and therefore the room the
    /// window leaves around the surface.
    static let surfaceInset: CGFloat = 14

    /// Furthest the shadow paints from the surface edge.
    static var shadowReach: CGFloat {
        max(shadowRadius, shadowRadius + shadowOffsetY)
    }

    /// True when the shadow can fade out before it reaches the window edge.
    static var shadowFitsInsideWindow: Bool {
        shadowReach <= surfaceInset
    }

    static func shadowOpacity(for colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? 0.50 : 0.22
    }
}

struct PanelSurface: View {
    let cornerRadius: CGFloat
    let reduceTransparency: Bool
    let increaseContrast: Bool
    let colorScheme: ColorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var baseOpacity: Double {
        reduceTransparency
            ? PanelSurfaceStyle.opaqueBaseOpacity
            : PanelSurfaceStyle.baseOpacity(for: colorScheme)
    }

    var body: some View {
        ZStack {
            // Layer 1: the appearance-matched base. This is what keeps the labels
            // readable regardless of what is behind the panel.
            shape.fill(
                PanelSurfaceStyle.baseColor(for: colorScheme).opacity(baseOpacity)
            )

            // Layer 2: the optical material, which supplies the translucency.
            if !reduceTransparency {
                if #available(macOS 26.0, *) {
                    shape.fill(Color.white.opacity(0.001))
                        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }

            // Layer 3: an edge that stays visible over a same-valued backdrop.
            shape.strokeBorder(strokeStyle, lineWidth: increaseContrast ? 1.5 : 1)
        }
        // No `compositingGroup()`/`clipShape()` here. Every layer above is already
        // drawn into `shape`, so the corners are rounded without a clip — and a
        // clip on the panel-sized subtree forces an offscreen pass on every redraw,
        // which measured 24 ms per frame against 4 ms without it. That is what made
        // scrolling stutter.
        .shadow(
            color: .black.opacity(PanelSurfaceStyle.shadowOpacity(for: colorScheme)),
            radius: PanelSurfaceStyle.shadowRadius,
            y: PanelSurfaceStyle.shadowOffsetY
        )
    }

    private var strokeStyle: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color.primary.opacity(0.42))
        }

        let edge = Color(white: PanelSurfaceStyle.borderWhite(for: colorScheme))
            .opacity(PanelSurfaceStyle.borderOpacity(for: colorScheme))

        if #available(macOS 26.0, *) {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        edge,
                        .cyan.opacity(0.16),
                        .purple.opacity(0.12),
                        edge.opacity(0.6)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(edge)
    }
}

struct LiquidGlassSurface: View {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @State private var displayOptionsRevision = 0

    private var reduceTransparency: Bool {
        _ = displayOptionsRevision
        return NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    private var increaseContrast: Bool {
        _ = displayOptionsRevision
        return NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    var body: some View {
        PanelSurface(
            cornerRadius: cornerRadius,
            reduceTransparency: reduceTransparency,
            increaseContrast: increaseContrast,
            colorScheme: colorScheme
        )
        .onAppear {
            if reduceTransparency {
                Diagnostics.presentation.notice("Using an opaque overlay for Reduce Transparency")
            }
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
            )
        ) { _ in
            displayOptionsRevision &+= 1
        }
    }
}
