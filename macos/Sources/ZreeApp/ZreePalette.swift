import AppKit
import SwiftUI

/// Palette sampled from the app icon (tree #559955, trunk #112233,
/// background gradient #FAFAF6 -> #DCEBE0), so the UI and the icon agree.
enum ZreePalette {
    static let leaf = Color(red: 0.235, green: 0.490, blue: 0.341)        // #3C7D57
    static let leafLight = Color(red: 0.561, green: 0.796, blue: 0.643)   // #8FCBA4
    static let mint = Color(red: 0.863, green: 0.922, blue: 0.878)        // #DCEBE0
    static let paper = Color(red: 0.980, green: 0.980, blue: 0.965)       // #FAFAF6
    static let ink = Color(red: 0.102, green: 0.149, blue: 0.125)         // #1A2620
    static let trunk = Color(red: 0.133, green: 0.196, blue: 0.247)       // #22323F

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    /// Editing surface: the icon's paper background, inverted for dark mode.
    static let editorBackground = dynamic(
        light: NSColor(srgbRed: 0.980, green: 0.980, blue: 0.965, alpha: 1),
        dark: NSColor(srgbRed: 0.071, green: 0.102, blue: 0.086, alpha: 1)
    )

    static let editorText = dynamic(
        light: NSColor(srgbRed: 0.102, green: 0.149, blue: 0.125, alpha: 1),
        dark: NSColor(srgbRed: 0.894, green: 0.929, blue: 0.902, alpha: 1)
    )

    static var accent: Color {
        Color(nsColor: dynamic(
            light: NSColor(srgbRed: 0.235, green: 0.490, blue: 0.341, alpha: 1),
            dark: NSColor(srgbRed: 0.561, green: 0.796, blue: 0.643, alpha: 1)
        ))
    }
}
