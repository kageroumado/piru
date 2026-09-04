import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// The "Share Substance" surface: a custom sheet reached from the substance
/// screen's share button. Renders the colorful ``SubstanceShareCard`` specimen
/// image with a **detail-level** segmented picker (Minimal / Standard / Rich)
/// that re-renders the preview live, plus Copy and Share actions. Reuses the
/// same ``ShareSheetPresenter`` / ``ImageQuickLook`` infrastructure as
/// ``SessionShareSheet``.
struct SubstanceShareSheet: View {
    let substance: Substance
    let route: SubstanceRoute?

    @Environment(\.dismiss) private var dismiss

    @State private var detail: ShareDetailLevel = .standard
    @State private var molecule: MoleculeStructure?
    @State private var reportedEffects: [ReportedEffect] = []
    @State private var mechanism: MechanismOfAction?
    @State private var monoamineProfile: MonoamineProfile?
    @State private var moleculeLoaded = false
    @State private var images: [ShareDetailLevel: PlatformImage] = [:]
    @State private var imageFileURL: URL?
    @State private var imageSourceView: PlatformView?
    @State private var justCopied = false
    @State private var contentHeight: CGFloat = 460
    @State private var safeAreaBottom: CGFloat = 34

    private static let chromeAllowance: CGFloat = 64
    private var fittedHeight: CGFloat {
        contentHeight + Self.chromeAllowance + safeAreaBottom
    }

    private var currentImage: PlatformImage? {
        images[detail]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xxl) {
                    detailPicker
                    imageCard
                    actions
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.bottom, Spacing.xxl)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .navigationTitle("Share Substance")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(Text("Close"))
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { safeAreaBottom = max(0, $0) }
        }
        .presentationDetents([.height(fittedHeight), .large])
        .presentationDragIndicator(.visible)
        .task { await loadData() }
        .onChange(of: detail) { _, _ in renderIfNeeded() }
    }

    // MARK: picker

    private var detailPicker: some View {
        Picker("Detail level", selection: $detail) {
            ForEach(ShareDetailLevel.allCases) { level in
                Text(level.displayName).tag(level)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: image card

    private var imageCard: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color.primary.opacity(0.04))
                if let currentImage {
                    Image(platformImage: currentImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(Spacing.lg)
                        .overlay { ZoomSourceView { imageSourceView = $0 } }
                        .overlay(alignment: .bottomTrailing) {
                            Label("Tap to view", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.caption2.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(.regularMaterial, in: Capsule())
                                .padding(Spacing.xxl)
                                .allowsHitTesting(false)
                        }
                        .onTapGesture { openViewer() }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(Text("View substance card"))
                } else {
                    ProgressView().tint(Theme.accent)
                }
            }
            .frame(height: 360)
        }
    }

    // MARK: actions

    private var actions: some View {
        HStack(spacing: Spacing.lg) {
            Button { copy() } label: {
                Label(justCopied ? "Copied" : "Copy", systemImage: justCopied ? "checkmark" : "doc.on.doc")
                    .sectionLabel()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .tint(Theme.secondaryLabel)
            .disabled(currentImage == nil)

            Button { share() } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .sectionLabel()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .tint(Theme.accent)
            .disabled(currentImage == nil)
        }
    }

    // MARK: rendering

    private func loadData() async {
        if !moleculeLoaded {
            molecule = substance.smiles != nil
                ? SubstanceStore.shared.moleculeStructure(forSubstanceName: substance.name)
                : nil
            reportedEffects = SubstanceStore.shared.reportedEffects(forSubstanceName: substance.name)
            mechanism = MechanismOfActionDatabase.resolvedMechanism(
                dbMechanism: substance.mechanismOfAction,
                category: substance.category,
            )
            monoamineProfile = MonoamineProfile.from(
                bindings: SubstanceStore.shared.bindings(forSubstanceName: substance.name),
                isSoldAsMDMA: SubstanceStore.shared.hasFlag(
                    PharmacologyParameters.Flag.missoldAsMDMA, forSubstanceName: substance.name,
                ),
            )
            moleculeLoaded = true
        }
        renderIfNeeded()
    }

    private func renderIfNeeded() {
        guard moleculeLoaded, images[detail] == nil else {
            refreshFileURL()
            return
        }
        let card = SubstanceShareCard(
            substance: substance, route: route, molecule: molecule,
            reportedEffects: reportedEffects, mechanism: mechanism,
            monoamineProfile: monoamineProfile, detail: detail,
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let image = renderer.platformImage {
            images[detail] = image
        }
        refreshFileURL()
    }

    /// Re-encode the current image to a temp file so QuickLook opens instantly.
    private func refreshFileURL() {
        guard let image = currentImage, let data = image.pngData() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("piru-\(substance.name.replacingOccurrences(of: " ", with: "-"))-\(detail.rawValue).png")
        try? data.write(to: url)
        imageFileURL = url
    }

    // MARK: actions impl

    private func openViewer() {
        if let imageFileURL {
            ImageQuickLook.present(url: imageFileURL, from: imageSourceView)
        }
    }

    private func copy() {
        guard let currentImage else { return }
        PlatformPasteboard.copy(image: currentImage)
        justCopied = true
        Task {
            try? await Task.sleep(for: UITiming.copiedFlash)
            justCopied = false
        }
    }

    private func share() {
        guard let currentImage else { return }
        // Include the app link so recipients get a tappable kagerou.glass/piru
        // alongside the image (where Piru's info lives).
        var items: [Any] = [currentImage]
        if let url = URL(string: "https://kagerou.glass/piru") { items.append(url) }
        ShareSheetPresenter.present(items)
    }
}
