import SwiftUI
import SwiftData

struct SubstanceColorPickerView: View {
    let substanceName: String
    let takenColors: [String: String] // hex -> substance name
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
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
            .navigationTitle("Choose Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        let fallback = firstAvailableHex ?? "007AFF"
                        onPick(fallback)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onPick(selectedHex ?? "007AFF")
                        dismiss()
                    }
                    .disabled(selectedHex == nil)
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

    @ViewBuilder
    private var previewSection: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(previewColor)
                .frame(width: 5, height: 44)
            VStack(alignment: .leading) {
                Text(substanceName)
                    .font(.title3.weight(.semibold))
                Text("Pick a color for this substance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

    @ViewBuilder
    private var userColorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Text("Your Colors")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if userColors.isEmpty {
                Text("Custom shades you create will appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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

        Button {
            if !isTaken {
                selectedHex = hex
            }
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 38, height: 38)
                    .opacity(isTaken ? 0.35 : 1.0)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        } else if isTaken {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .overlay {
                        if isSelected {
                            Circle().strokeBorder(.primary, lineWidth: 2)
                        }
                    }
                Text(isTaken ? (takenBy ?? name) : name)
                    .font(.system(size: 8))
                    .foregroundStyle(isTaken ? .secondary : .tertiary)
                    .lineLimit(1)
                    .frame(width: 44)
            }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isTaken)
    }

    // MARK: - Custom Color Creator

    @ViewBuilder
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

    @ViewBuilder
    private var customPickerButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                showCustomPicker = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "paintpalette")
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

    @ViewBuilder
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

    @ViewBuilder
    private var hexInputRow: some View {
        HStack(spacing: 8) {
            Text("#")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            TextField("FFAACC", text: $hexInput)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onChange(of: hexInput) {
                    let cleaned = hexInput.filter { $0.isHexDigit }
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
                Text("#\(sanitizedHex)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
        }
    }

    private var sanitizedHex: String {
        hexInput.filter { $0.isHexDigit }.prefix(6).uppercased()
    }

    private var isHexValid: Bool {
        sanitizedHex.count == 6
    }

    private func addCustomColor() {
        let hex = sanitizedHex
        guard hex.count == 6 else {
            customError = "Enter a valid 6-digit hex code"
            return
        }

        // Check against taken substance colors
        if let owner = takenColors[hex] {
            customError = "Already used by \(owner)"
            return
        }

        // Check against existing preset colors
        if PresetColor.all.contains(where: { $0.hex == hex }) {
            customError = "This shade already exists in the preset palette"
            return
        }

        // Check against existing user colors
        if userColors.contains(where: { $0.hex == hex }) {
            customError = "You've already created this shade"
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
