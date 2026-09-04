import SwiftUI

#if canImport(VisionKit)
    import VisionKit
#endif

/// Tools ▸ Identify a Box. A reference, not a checker: point the camera at any
/// medication box and see what the library knows about what is inside — the
/// tourist reading a foreign brand of a substance they already know.
///
/// The screen is a doorway. What was read shows as chips with a confidence
/// mark each, the substance itself opens the Library's own detail, and the two
/// actions hand off to logging and inventory with the box's strength and pack
/// count already staged. When nothing local matches, it shows what it read
/// and links out — never a web scrape in the app.
struct IdentifyBoxView: View {
    @State private var showScanner = false
    /// What the last scan resolved to; `nil` before the first scan.
    @State private var result: BoxIdentification?
    @State private var cameraStatus: CameraStatus = .unknown

    private enum CameraStatus {
        case unknown
        case unsupported
        case available
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let result {
                    IdentifyChipsCard(chips: result.chips)
                    if let name = result.canonicalName {
                        IdentifySubstanceCard(canonicalName: name, brand: result.brand)
                        IdentifyActionsCard(result: result)
                    } else {
                        IdentifyExternalLinksCard(result: result)
                    }
                } else {
                    introCard
                }
                scanButton
                disclaimer
            }
            .padding(.horizontal)
            .padding(.top, Spacing.xs)
            .padding(.bottom, 80)
        }
        .background(Theme.background)
        #if os(iOS)
            .fullScreenCover(isPresented: $showScanner) {
                LabelScannerView { reading in
                    Task { result = await BoxIdentifier.identify(reading) }
                }
            }
        #endif
            .task {
                #if os(iOS)
                    cameraStatus = DataScannerViewController.isSupported ? .available : .unsupported
                #else
                    cameraStatus = .unsupported
                #endif
                #if DEBUG
                    if result == nil, let reading = ScanFixtures.launchReading() {
                        result = await BoxIdentifier.identify(reading)
                    }
                #endif
            }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            GlanceCardHeader(icon: Tool.identify.icon, title: Text("What is this box?")) {
                EmptyView()
            }
            Text("Point the camera at a medication box — the brand, the printed name, or the barcode — and Piru opens what it knows about the substance inside: the pharmacology, the doses on record, the interactions.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
            Text("Barcodes are matched offline against the US and French registries the app ships with. Anything else resolves by name.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    @ViewBuilder
    private var scanButton: some View {
        switch cameraStatus {
        case .available:
            Button {
                showScanner = true
            } label: {
                Label(result == nil ? "Scan a Box" : "Scan Another", systemImage: "barcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.accent)
        case .unsupported:
            Label("Scanning isn't available on this device.", systemImage: "camera.fill")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .unknown:
            EmptyView()
        }
    }

    private var disclaimer: some View {
        Text("What a box says is what is shown. Not medical advice.")
            .captionSecondary()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - What was read

/// The chips: one per thing the reading established, each with its confidence
/// mark. OCR is noisy on foil and curved boxes, so the mark is part of the
/// answer, not decoration.
private struct IdentifyChipsCard: View {
    let chips: [ReadChip]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            GlanceCardHeader(icon: "text.viewfinder", title: Text("Read from the box")) {
                EmptyView()
            }
            if chips.isEmpty {
                Text("Nothing legible was read.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            } else {
                FlowLayout(spacing: Spacing.md) {
                    ForEach(chips) { chip in
                        ReadChipView(chip: chip)
                    }
                }
            }
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }
}

private struct ReadChipView: View {
    let chip: ReadChip

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .accessibilityHidden(true)
            Text(chip.text)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Image(systemName: confidenceIcon)
                .font(.caption2)
                .foregroundStyle(confidenceColor)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(.fill.tertiary, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var icon: String {
        switch chip.kind {
        case .barcode: "barcode"
        case .brand: "tag"
        case .substance: "pills"
        case .strength: "scalemass"
        case .form: "capsule"
        case .count: "number"
        }
    }

    private var confidenceIcon: String {
        switch chip.confidence {
        case .high: "checkmark.circle.fill"
        case .medium: "circle.lefthalf.filled"
        case .low: "questionmark.circle"
        }
    }

    private var confidenceColor: Color {
        switch chip.confidence {
        case .high: .Confidence.High.text
        case .medium: .Confidence.Medium.text
        case .low: Theme.secondaryLabel
        }
    }

    private var accessibilityText: String {
        let kind = switch chip.kind {
        case .barcode: String(localized: "Barcode")
        case .brand: String(localized: "Brand")
        case .substance: String(localized: "Substance")
        case .strength: String(localized: "Strength")
        case .form: String(localized: "Form")
        case .count: String(localized: "Pack size")
        }
        let confidence = switch chip.confidence {
        case .high: String(localized: "confident")
        case .medium: String(localized: "probable")
        case .low: String(localized: "unrecognized")
        }
        return "\(kind): \(chip.text), \(confidence)"
    }
}

// MARK: - The substance

/// The substance as the Library lists it, pushing the Library's own detail —
/// the tool is a doorway, not a second detail view.
private struct IdentifySubstanceCard: View {
    let canonicalName: String
    let brand: String?

    var body: some View {
        if let substance = SubstanceLibrary.lookup(canonicalName) {
            NavigationLink(value: PushRoute.substance(name: substance.name)) {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    GlanceCardHeader(icon: "books.vertical", title: Text(brand.map { String(localized: "\($0) is") } ?? String(localized: "In the library"))) {
                        GlanceCardChevron()
                    }
                    SubstanceRowView(substance: substance)
                }
                .padding(Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .themeCard()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Actions

private struct IdentifyActionsCard: View {
    let result: BoxIdentification
    @Environment(\.appNavigator) private var navigator

    var body: some View {
        HStack(spacing: Spacing.xl) {
            Button {
                navigator.present(.quickLog(routine: nil, prefillSubstance: result.canonicalName, prefillDose: dosePrefill))
            } label: {
                Label("Log This", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

            Button {
                navigator.present(.inventoryItemForm(id: nil, prefillSubstance: result.canonicalName, prefill: result.inventoryPrefill))
            } label: {
                Label("Add to Inventory", systemImage: "shippingbox")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    /// Only a strength read off the box stages a complete dose; without one the
    /// quick-log opens its editor at the substance's reference dose as usual.
    private var dosePrefill: DosePrefill? {
        guard let strength = result.strength, let unit = result.strengthUnit else { return nil }
        return DosePrefill(amount: strength, unit: unit, productName: result.brand)
    }
}

extension BoxIdentification {
    /// The inventory add form's prefill: the pack count in its own unit, the
    /// milligram strength when the box printed one, and the box as a note.
    var inventoryPrefill: InventoryPrefill {
        let strengthMG: Double? = if let strength, strengthUnit == "mg" { strength } else { nil }
        let noteParts = [brand, chips.first { $0.kind == .count }?.text].compactMap(\.self)
        return InventoryPrefill(
            count: packCount?.count,
            unit: packCount?.inventoryUnit,
            strengthMG: strengthMG,
            note: noteParts.isEmpty ? nil : noteParts.joined(separator: " · "),
        )
    }
}

// MARK: - Nothing local

/// Links only: a search on the best token at PubChem and Wikipedia, plus the
/// national registry the barcode's GS1 prefix points at.
private struct IdentifyExternalLinksCard: View {
    let result: BoxIdentification

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            GlanceCardHeader(icon: "questionmark.circle", title: Text("Not in the library")) {
                EmptyView()
            }
            Text(result.searchToken.map { String(localized: "Nothing bundled matches this box. Look up “\($0)” elsewhere:") }
                ?? String(localized: "Nothing bundled matches this box, and no name was legible enough to search."))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
            ForEach(links, id: \.url) { link in
                Link(destination: link.url) {
                    HStack {
                        Label(link.title, systemImage: link.icon)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .captionSecondary()
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    private struct ExternalLink {
        let title: String
        let icon: String
        let url: URL
    }

    private var links: [ExternalLink] {
        var out: [ExternalLink] = []
        if let token = result.searchToken?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            if let url = URL(string: "https://pubchem.ncbi.nlm.nih.gov/#query=\(token)") {
                out.append(ExternalLink(title: String(localized: "Search PubChem"), icon: "atom", url: url))
            }
            if let url = URL(string: "https://en.wikipedia.org/w/index.php?search=\(token)") {
                out.append(ExternalLink(title: String(localized: "Search Wikipedia"), icon: "book", url: url))
            }
        }
        if let registry = result.barcodeCountry.flatMap(Self.registry(for:)) {
            out.append(registry)
        }
        return out
    }

    /// The public medicines registry for a GS1 country prefix.
    private static func registry(for country: String) -> ExternalLink? {
        let entry: (String, String)? = switch country {
        case "US": ("DailyMed (US)", "https://dailymed.nlm.nih.gov/dailymed/")
        case "FR": ("Base de données publique des médicaments (FR)", "https://base-donnees-publique.medicaments.gouv.fr/")
        case "DE": ("PharmNet.Bund (DE)", "https://www.pharmnet-bund.de/")
        case "GB": ("emc (UK)", "https://www.medicines.org.uk/emc/")
        case "CH": ("Swissmedicinfo (CH)", "https://www.swissmedicinfo.ch/")
        case "ES": ("CIMA (ES)", "https://cima.aemps.es/")
        case "IT": ("AIFA (IT)", "https://farmaci.agenziafarmaco.gov.it/")
        case "NL": ("Geneesmiddeleninformatiebank (NL)", "https://www.geneesmiddeleninformatiebank.nl/")
        case "BE": ("FAMHP (BE)", "https://www.famhp.be/")
        case "JP": ("PMDA (JP)", "https://www.pmda.go.jp/")
        default: nil
        }
        guard let entry, let url = URL(string: entry.1) else { return nil }
        return ExternalLink(title: entry.0, icon: "building.columns", url: url)
    }
}
