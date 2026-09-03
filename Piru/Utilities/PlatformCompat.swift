import SwiftUI

#if canImport(UIKit)
    import UIKit

    typealias PlatformImage = UIImage
    typealias PlatformColor = UIColor
    typealias PlatformFont = UIFont
    typealias PlatformView = UIView
#elseif canImport(AppKit)
    import AppKit

    typealias PlatformImage = NSImage
    typealias PlatformColor = NSColor
    typealias PlatformFont = NSFont
    typealias PlatformView = NSView

    extension NSImage {
        nonisolated func pngData() -> Data? {
            guard let tiffData = tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiffData)
            else { return nil }
            return rep.representation(using: .png, properties: [:])
        }
    }
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
            self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
            self.init(nsImage: platformImage)
        #endif
    }
}

extension ImageRenderer {
    var platformImage: PlatformImage? {
        #if canImport(UIKit)
            uiImage
        #elseif canImport(AppKit)
            nsImage
        #endif
    }
}

enum PlatformPasteboard {
    static func copy(_ string: String) {
        #if canImport(UIKit)
            UIPasteboard.general.string = string
        #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        #endif
    }

    #if canImport(UIKit)
        static func copy(image: UIImage) {
            UIPasteboard.general.image = image
        }

        static func copy(data: Data, type: String) {
            UIPasteboard.general.setData(data, forPasteboardType: type)
        }
    #elseif canImport(AppKit)
        static func copy(image: NSImage) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }

        static func copy(data: Data, type: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(data, forType: NSPasteboard.PasteboardType(type))
        }
    #endif
}

enum PlatformHaptics {
    static func success() {
        #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func impact() {
        #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}

extension View {
    func dismissKeyboard() {
        #if canImport(UIKit)
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil,
            )
        #elseif canImport(AppKit)
            NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
    }
}

#if canImport(UIKit)
    func openPlatformSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
#elseif canImport(AppKit)
    func openPlatformSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:")!)
    }

    func openNotificationSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!,
        )
    }
#endif

// MARK: - System Color Shims

extension Color {
    static var platformSystemBackground: Color {
        #if canImport(UIKit)
            Color(.systemBackground)
        #else
            Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var platformSecondarySystemBackground: Color {
        #if canImport(UIKit)
            Color(.secondarySystemBackground)
        #else
            Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var platformSecondarySystemGroupedBackground: Color {
        #if canImport(UIKit)
            Color(.secondarySystemGroupedBackground)
        #else
            Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var platformSecondarySystemFill: Color {
        #if canImport(UIKit)
            Color(.secondarySystemFill)
        #else
            Color(nsColor: .quaternaryLabelColor)
        #endif
    }

    static var platformTertiarySystemFill: Color {
        #if canImport(UIKit)
            Color(.tertiarySystemFill)
        #else
            Color(nsColor: .separatorColor)
        #endif
    }

    static var platformQuaternaryLabel: Color {
        #if canImport(UIKit)
            Color(.quaternaryLabel)
        #else
            Color(nsColor: .quaternaryLabelColor)
        #endif
    }

    static var platformTertiaryLabel: Color {
        #if canImport(UIKit)
            Color(.tertiaryLabel)
        #else
            Color(nsColor: .tertiaryLabelColor)
        #endif
    }

    static var platformSystemGray: Color {
        #if canImport(UIKit)
            Color(.systemGray)
        #else
            Color(nsColor: .systemGray)
        #endif
    }
}

// MARK: - View Modifier Shims

extension View {
    func inlineNavigationTitle() -> some View {
        #if canImport(UIKit)
            self.navigationBarTitleDisplayMode(.inline)
        #else
            self
        #endif
    }

    func insetGroupedListStyle() -> some View {
        #if os(iOS)
            self.listStyle(.insetGrouped)
        #else
            self.listStyle(.inset)
        #endif
    }

    func decimalKeyboard() -> some View {
        #if canImport(UIKit)
            self.keyboardType(.decimalPad)
        #else
            self
        #endif
    }

    func neverAutocapitalize() -> some View {
        #if canImport(UIKit)
            self.textInputAutocapitalization(.never)
        #else
            self
        #endif
    }

    func wordsAutocapitalize() -> some View {
        #if canImport(UIKit)
            self.textInputAutocapitalization(.words)
        #else
            self
        #endif
    }

    func permanentEditMode() -> some View {
        #if canImport(UIKit)
            self.environment(\.editMode, .constant(.active))
        #else
            self
        #endif
    }

    func compactListSectionSpacing() -> some View {
        #if canImport(UIKit)
            self.listSectionSpacing(16)
        #else
            self
        #endif
    }

    func readableWidth() -> some View {
        #if os(macOS)
            self.frame(maxWidth: 720)
        #else
            self
        #endif
    }
}

// MARK: - Toolbar Placement Shims

extension ToolbarItemPlacement {
    static var platformTopBarTrailing: ToolbarItemPlacement {
        #if os(iOS)
            .topBarTrailing
        #else
            .automatic
        #endif
    }

    static var platformTopBarLeading: ToolbarItemPlacement {
        #if os(iOS)
            .topBarLeading
        #else
            .automatic
        #endif
    }
}
