import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The consolidated "Share Session" surface: one custom sheet reached from the
/// session screen's share button (and Help / Settings). Offers three artifacts —
/// a session **Image** (always), a current-state **PDF**, and current-state
/// **Markdown** (both only while a session is active) — each with a rasterized
/// preview plus quick Copy and full Share. Replaces the old ⋯-menu export item
/// + system share sheet.
struct SessionShareSheet: View {
    let title: String
    let dateText: String
    let entries: [DoseEntry]
    let colors: [SubstanceColor]
    let stackRedoses: Bool
    /// Per-dose heart-rate responses, so the image carries the same HR chips the rows
    /// on screen do. Handed in rather than read here: HealthKit access belongs to the
    /// session screen, and an empty map simply renders rows without chips.
    var doseHR: [UUID: DoseHRResponse] = [:]
    /// The session itself, for the trip report (its notes). Nil from hosts that
    /// have only entries (Help / Settings).
    var session: Session?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var image: UIImage?
    @State private var pdfData: Data?
    @State private var pdfThumbnail: UIImage?
    @State private var markdown: String?
    /// The trip report, when the session has notes.
    @State private var tripReport: String?
    @State private var preparing = true
    @State private var justCopied: CopyTarget?
    @State private var contentHeight: CGFloat = 420
    @State private var safeAreaBottom: CGFloat = 34
    /// A transparent view over the image thumbnail — the source of QuickLook's
    /// zoom transition.
    @State private var imageSourceView: UIView?
    /// The image pre-encoded to a file during `prepare()`, so opening the viewer
    /// is instant (no on-tap PNG encode).
    @State private var imageFileURL: URL?

    private enum CopyTarget: Equatable { case image, pdf, markdown, tripReport }

    /// Inline nav bar + grabber allowance — the chrome above the scroll content
    /// that `.height` detents must include but `contentHeight` (the VStack) omits.
    private static let chromeAllowance: CGFloat = 64

    /// The detent that shows everything: measured content + nav-bar chrome +
    /// the bottom safe-area inset (home indicator), so it doesn't come up short.
    private var fittedHeight: CGFloat {
        contentHeight + Self.chromeAllowance + safeAreaBottom
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    imageCard
                    if markdown != nil {
                        HStack(alignment: .top, spacing: 14) {
                            pdfCard
                            markdownCard
                        }
                    }
                    if tripReport != nil {
                        tripReportCard
                    }
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.bottom, Spacing.xxl)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .navigationTitle("Share Session")
            .navigationBarTitleDisplayMode(.inline)
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
        .task { await prepare() }
    }

    // MARK: Prepare

    @MainActor
    private func prepare() async {
        let rendered = SessionShareImage.render(
            title: title, dateText: dateText, entries: entries,
            colors: colors, stackRedoses: stackRedoses, scheme: colorScheme, doseHR: doseHR,
        )
        image = rendered
        // Pre-encode the image to a file off the main actor so tapping the
        // thumbnail opens QuickLook instantly — the ~@3x PNG encode is the lag,
        // not QuickLook itself.
        if let rendered {
            imageFileURL = await Task.detached(priority: .userInitiated) {
                guard let data = rendered.pngData() else { return nil }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("piru-session-image.png")
                try? data.write(to: url)
                return url
            }.value
        }
        if let export = SessionStateExport.build(from: entries, colors: colors, notes: session?.orderedNotes ?? []) {
            let data = SessionReportPDF.render(export)
            pdfData = data
            pdfThumbnail = PDFDocument(data: data)?.page(at: 0)?
                .thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox)
            markdown = export.markdown()
        }
        if let session {
            let report = TripReport.build(session: session)
            if !report.isEmpty { tripReport = report.markdown() }
        }
        preparing = false
    }

    // MARK: Cards

    private var imageCard: some View {
        artifactCard(icon: "photo", title: "Session Image", subtitle: "Image") {
            preview(image, contentMode: .fill)
                .contentShape(.rect)
                .overlay { ZoomSourceView { imageSourceView = $0 } }
                .overlay(alignment: .bottomTrailing) {
                    if image != nil {
                        Label("Tap to edit", systemImage: "pencil.tip.crop.circle")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.primary)
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.regularMaterial, in: Capsule())
                            .padding(Spacing.md)
                            .allowsHitTesting(false)
                    }
                }
                .onTapGesture { openImageViewer() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(Text("View session image"))
        } actions: {
            actionButton(copyLabel(.image), icon: copyIcon(.image)) { copyImage() }.disabled(image == nil)
            actionButton("Share", icon: "square.and.arrow.up", prominent: true) { share(image) }.disabled(image == nil)
        }
    }

    private var pdfCard: some View {
        artifactCard(icon: "doc.richtext", title: "Session Report", subtitle: "PDF", previewHeight: 120) {
            preview(pdfThumbnail, contentMode: .fill, background: .white)
        } actions: {
            actionButton(copyLabel(.pdf), icon: copyIcon(.pdf), showIcon: false) { copyPDF() }.disabled(pdfData == nil)
            actionButton("Share", icon: "square.and.arrow.up", prominent: true, showIcon: false) { sharePDF() }.disabled(pdfData == nil)
        }
    }

    private var markdownCard: some View {
        artifactCard(icon: "curlybraces", title: "Session Data", subtitle: "Markdown", previewHeight: 120) {
            markdownPreview(markdown)
        } actions: {
            actionButton(copyLabel(.markdown), icon: copyIcon(.markdown), showIcon: false) { copyMarkdown() }.disabled(markdown == nil)
            actionButton("Share", icon: "square.and.arrow.up", prominent: true, showIcon: false) { shareMarkdown() }.disabled(markdown == nil)
        }
    }

    private var tripReportCard: some View {
        artifactCard(icon: "quote.opening", title: "Trip Report", subtitle: "Markdown — notes with T+ offsets", previewHeight: 120) {
            markdownPreview(tripReport)
        } actions: {
            actionButton(copyLabel(.tripReport), icon: copyIcon(.tripReport)) { copyTripReport() }.disabled(tripReport == nil)
            actionButton("Share", icon: "square.and.arrow.up", prominent: true) { shareTripReport() }.disabled(tripReport == nil)
        }
    }

    // MARK: Card scaffold

    /// The card shape — concentric with the sheet's rounded corners (falling back
    /// to a 22pt minimum away from them), so cards nest inside the sheet.
    private var cardShape: ConcentricRectangle {
        ConcentricRectangle(corners: .concentric(minimum: 22), isUniform: true)
    }

    /// The preview shape — concentric inside the card (min 12pt).
    private var previewShape: ConcentricRectangle {
        ConcentricRectangle(corners: .concentric(minimum: 12), isUniform: true)
    }

    private func artifactCard(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey, previewHeight: CGFloat = 150, @ViewBuilder preview: () -> some View, @ViewBuilder actions: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            preview()
                .frame(maxWidth: .infinity)
                .frame(height: previewHeight)
                .clipShape(previewShape)
                .overlay(previewShape.stroke(Color.primary.opacity(Theme.Opacity.hairline), lineWidth: 1))
            HStack(spacing: Spacing.md) {
                Image(systemName: icon).font(.subheadline).foregroundStyle(Theme.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).sectionLabel()
                    Text(subtitle).captionSecondary()
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: Spacing.md) { actions() }
        }
        .padding(14)
        .background { cardShape.fill(.thickMaterial) }
    }

    /// A top-cropped raster preview (image / PDF page), or a spinner while loading.
    private func preview(_ uiImage: UIImage?, contentMode: ContentMode, background: Color = Color.primary.opacity(0.03)) -> some View {
        Rectangle()
            .fill(background)
            .overlay(alignment: .top) {
                if let uiImage {
                    Image(uiImage: uiImage).resizable().aspectRatio(contentMode: contentMode).accessibilityHidden(true)
                } else {
                    ProgressView().tint(Theme.accent)
                }
            }
    }

    /// The Markdown export previewed as a monospace snippet on a light "paper"
    /// ground (like the PDF page preview), so it reads as a document regardless
    /// of the sheet's theme.
    private func markdownPreview(_ text: String?) -> some View {
        Rectangle()
            .fill(Color(white: 0.96))
            .overlay(alignment: .topLeading) {
                if let text {
                    Text(text)
                        .font(.system(size: 6, design: .monospaced))
                        .foregroundStyle(Color(white: 0.15))
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .padding(Spacing.md)
                } else {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
    }

    // MARK: Buttons

    private func actionButton(_ label: LocalizedStringKey, icon: String, prominent: Bool = false, showIcon: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if showIcon {
                    Label(label, systemImage: icon)
                } else {
                    Text(label)
                }
            }
            .sectionLabel()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .tint(prominent ? Theme.accent : Theme.secondaryLabel)
    }

    private func copyLabel(_ target: CopyTarget) -> LocalizedStringKey {
        justCopied == target ? "Copied" : "Copy"
    }
    private func copyIcon(_ target: CopyTarget) -> String {
        justCopied == target ? "checkmark" : "doc.on.doc"
    }

    private func flashCopied(_ target: CopyTarget) {
        justCopied = target
        Task {
            try? await Task.sleep(for: UITiming.copiedFlash)
            if justCopied == target { justCopied = nil }
        }
    }

    // MARK: Actions

    /// Open the session image full-screen in the system QuickLook viewer — which
    /// brings Markup (annotate/crop), rotate, share and print for free — zooming
    /// out of the tapped thumbnail.
    private func openImageViewer() {
        // Use the pre-encoded file; fall back to an on-the-spot encode only if the
        // user taps before `prepare()` finished writing it.
        if let imageFileURL {
            ImageQuickLook.present(url: imageFileURL, from: imageSourceView)
        } else if let image, let data = image.pngData(), let url = write(data, ext: "png") {
            ImageQuickLook.present(url: url, from: imageSourceView)
        }
    }

    private func copyImage() {
        guard let image else { return }
        UIPasteboard.general.image = image
        flashCopied(.image)
    }

    private func copyPDF() {
        guard let pdfData else { return }
        UIPasteboard.general.setData(pdfData, forPasteboardType: UTType.pdf.identifier)
        flashCopied(.pdf)
    }

    private func copyMarkdown() {
        guard let markdown else { return }
        UIPasteboard.general.string = markdown
        flashCopied(.markdown)
    }

    private func copyTripReport() {
        guard let tripReport else { return }
        UIPasteboard.general.string = tripReport
        flashCopied(.tripReport)
    }

    private func shareTripReport() {
        guard let tripReport, let url = write(Data(tripReport.utf8), ext: "md", stem: "piru-trip-report") else { return }
        ShareSheetPresenter.present([url])
    }

    private func share(_ image: UIImage?) {
        guard let image else { return }
        ShareSheetPresenter.present([image])
    }

    private func sharePDF() {
        guard let pdfData, let url = write(pdfData, ext: "pdf") else { return }
        ShareSheetPresenter.present([url])
    }

    private func shareMarkdown() {
        guard let markdown, let url = write(Data(markdown.utf8), ext: "md") else { return }
        ShareSheetPresenter.present([url])
    }

    private func write(_ data: Data, ext: String, stem: String = "piru-session") -> URL? {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd-HHmm"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(stem)-\(stamp.string(from: .now)).\(ext)")
        do { try data.write(to: url); return url } catch { return nil }
    }
}
