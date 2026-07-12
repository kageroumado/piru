import SwiftData
import SwiftUI

struct SubstanceColorPickerView: View {
    let substanceName: String
    let takenColors: [String: String] // hex -> substance name
    /// Invoked when the user confirms or skips. The caller owns dismissal —
    /// either by toggling a local `@State` `isPresented` flag or by mutating
    /// the navigator (e.g. presenting the next picker via `replacingTop`).
    /// The picker itself does not call `dismiss()` so it can be composed with
    /// the navigator's atomic sheet swapping without the system tearing the
    /// stack down between picks.
    var onPick: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserColor.createdAt) private var userColors: [UserColor]

    @State private var selectedHex: String?
    @State private var showCustomPicker = false
    @State private var customColor: Color = .white
    @State private var hexInput = ""
    @State private var customName = ""
    @State private var customError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    previewSection
                    presetGrid
                    userColorsSection
                    customColorSection
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .background(Theme.background)
            .navigationTitle("Choose Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        let fallback = firstAvailableHex ?? PresetColor.defaultHex
                        onPick(fallback)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onPick(selectedHex ?? PresetColor.defaultHex)
                    } label: {
                        Image(systemName: "checkmark").fontWeight(.semibold)
                    }
                    .disabled(selectedHex == nil)
                    .accessibilityLabel("Done")
                }
            }
        }
    }

    private var firstAvailableHex: String? {
        PresetColor.all.first { !takenColors.keys.contains($0.hex) }?.hex
    }

    private var previewColor: Color {
        if let hex = selectedHex {
            return Color(hex: hex)
        }
        return Color.gray.opacity(0.3)
    }

    private var allTakenHexes: Set<String> {
        Set(takenColors.keys)
    }

    // MARK: - Preview

    private var previewSection: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(previewColor)
                .frame(width: 5, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(CustomSubstanceStore.shared.displayName(for: substanceName))
                    .font(.title3.weight(.semibold))
                Text("Pick a color for this substance")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: - Preset Grid

    @ViewBuilder
    private var presetGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(PresetColor.all) { preset in
                gridCircle(hex: preset.hex, name: preset.name)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - User Colors

    private var userColorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Text("Your Colors")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.horizontal)

            if userColors.isEmpty {
                Text("Custom shades you create will appear here.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(userColors) { uc in
                        gridCircle(hex: uc.hex, name: uc.name)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Shared Circle

    @ViewBuilder
    private func gridCircle(hex: String, name: String) -> some View {
        let isSelected = selectedHex == hex
        let takenBy = takenColors[hex]
        let isTaken = takenBy != nil

        let circleButton = Button {
            selectedHex = hex
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 38, height: 38)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .overlay {
                        if isSelected {
                            Circle().strokeBorder(.primary, lineWidth: 2)
                        }
                    }
                Text(isTaken ? (takenBy ?? name) : name)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(width: 44)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])

        if let takenBy {
            circleButton.accessibilityValue(Text("Used by \(takenBy)"))
        } else {
            circleButton
        }
    }

    // MARK: - Custom Color Creator

    private var customColorSection: some View {
        VStack(spacing: 12) {
            Divider()

            if showCustomPicker {
                customPickerExpanded
            } else {
                customPickerButton
            }
        }
    }

    private var customPickerButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                showCustomPicker = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "paintpalette")
                    .accessibilityHidden(true)
                Text("Create Custom Shade")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var customPickerExpanded: some View {
        VStack(spacing: 16) {
            // Color picker
            ColorPicker("Pick a color", selection: $customColor, supportsOpacity: false)
                .padding(.horizontal)
                .onChange(of: customColor) {
                    hexInput = customColor.toHex()
                    customError = nil
                }

            // Hex text field
            hexInputRow

            // Name field
            HStack {
                TextField("Color name (optional)", text: $customName)
                    .font(.subheadline)
            }
            .padding(.horizontal)

            // Preview
            customPreviewRow

            if let error = customError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            // Add button
            Button {
                addCustomColor()
            } label: {
                Text("Add Color")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundStyle(.white)
                    .background(Color(hex: sanitizedHex), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .disabled(!isHexValid)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var hexInputRow: some View {
        HStack(spacing: 8) {
            Text("#")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Theme.secondaryLabel)
            TextField("FFAACC", text: $hexInput)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onChange(of: hexInput) {
                    let cleaned = hexInput.filter(\.isHexDigit)
                    if cleaned != hexInput {
                        hexInput = String(cleaned.prefix(6))
                    } else {
                        hexInput = String(hexInput.prefix(6))
                    }
                    if hexInput.count == 6 {
                        customColor = Color(hex: hexInput)
                    }
                    customError = nil
                }
            if isHexValid {
                Circle()
                    .fill(Color(hex: sanitizedHex))
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var customPreviewRow: some View {
        if isHexValid {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: sanitizedHex))
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                Text("#\(sanitizedHex)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer()
            }
            .padding(.horizontal)
        }
    }

    private var sanitizedHex: String {
        hexInput.filter(\.isHexDigit).prefix(6).uppercased()
    }

    private var isHexValid: Bool {
        sanitizedHex.count == 6
    }

    private func addCustomColor() {
        let hex = sanitizedHex
        guard hex.count == 6 else {
            customError = String(localized: "Enter a valid 6-digit hex code")
            return
        }

        // Check against existing preset colors
        if PresetColor.all.contains(where: { $0.hex == hex }) {
            customError = String(localized: "This shade already exists in the preset palette")
            return
        }

        // Check against existing user colors
        if userColors.contains(where: { $0.hex == hex }) {
            customError = String(localized: "You've already created this shade")
            return
        }

        // Save the user color
        let name = customName.isEmpty ? "#\(hex)" : customName
        let uc = UserColor(hex: hex, name: name)
        modelContext.insert(uc)

        // Select it
        customError = nil
        selectedHex = hex
        customName = ""
        hexInput = ""
        withAnimation(.easeInOut(duration: 0.25)) {
            showCustomPicker = false
        }
    }
}

// MARK: - Color to Hex

extension Color {
    func toHex() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        return String(format: "%02X%02X%02X", ri, gi, bi)
    }
}
