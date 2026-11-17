// File transfer on Android: `.fileImporter` and `.fileExporter` open the Storage Access
// Framework's pickers, and ShareSheet/ShareSheetPresenter open the share chooser with the file
// as a content:// URI (Skip/AndroidDocuments.kt). An imported document arrives as a copy in the
// app's cache, so the upstream import code reads a plain file URL, as it does on iOS.

import Foundation
import SkipBridge
import SwiftUI

/// Receives the pickers' results from Kotlin. One picker is open at a time, so each kind holds
/// a single pending completion.
/* SKIP @bridge */ public final class AndroidDocumentResults: @unchecked Sendable {
    /* SKIP @bridge */ public static let shared = AndroidDocumentResults()

    /// `nil` when the user cancelled.
    var onImport: ((Result<URL, any Error>?) -> Void)?
    var onExport: ((Result<URL, any Error>?) -> Void)?

    private init() {}

    /* SKIP @bridge */ public func didImport(_ path: String?, _ failure: String?) {
        let completion = onImport
        onImport = nil
        completion?(Self.outcome(path.map { URL(fileURLWithPath: $0) }, failure))
    }

    /* SKIP @bridge */ public func didExport(_ uri: String?, _ failure: String?) {
        let completion = onExport
        onExport = nil
        completion?(Self.outcome(uri.flatMap { URL(string: $0) }, failure))
    }

    private static func outcome(_ url: URL?, _ failure: String?) -> Result<URL, any Error>? {
        if let url { return .success(url) }
        if let failure { return .failure(AndroidDocumentError.failed(failure)) }
        return nil
    }
}

enum AndroidDocumentError: LocalizedError {
    case unavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "The file picker could not be opened.")
        case let .failed(message): message
        }
    }
}

/// Calls into Skip/AndroidDocuments.kt.
enum AndroidDocuments {
    private static var kotlin: AnyDynamicObject? {
        try? AnyDynamicObject(forStaticsOfClassName: "piru.module.AndroidDocuments")
    }

    static func open(_ types: [UTType]) -> Bool {
        let mimeTypes = types.map(\.mimeType).joined(separator: ",")
        return (try? kotlin?.openDocument(mimeTypes) as Bool?) == true
    }

    static func create(filename: String, contentType: UTType, source: URL) -> Bool {
        (try? kotlin?.createDocument(filename, contentType.mimeType, source.path) as Bool?) == true
    }

    static func share(file: URL) -> Bool {
        let type = UTType(filenameExtension: file.pathExtension) ?? .data
        return (try? kotlin?.shareFile(file.path, type.mimeType) as Bool?) == true
    }

    static func share(text: String) -> Bool {
        (try? kotlin?.shareText(text) as Bool?) == true
    }

    /// Shares the files and text in `items`: the first file, or else the text joined. Images
    /// arrive only as `PlatformImage`, which no renderer on Android produces, so they have
    /// nothing to send.
    @discardableResult
    static func share(items: [Any]) -> Bool {
        if let file = items.lazy.compactMap({ $0 as? URL }).first(where: \.isFileURL) {
            return share(file: file)
        }
        let text = items.compactMap { item -> String? in
            if let string = item as? String { return string }
            if let url = item as? URL { return url.absoluteString }
            return nil
        }
        return text.isEmpty ? false : share(text: text.joined(separator: "\n"))
    }
}

extension UTType {
    /// The MIME type Android's pickers and share targets filter on.
    var mimeType: String {
        switch identifier {
        case "public.json": "application/json"
        case "public.text", "public.plain-text": "text/plain"
        case "com.adobe.pdf": "application/pdf"
        case "public.comma-separated-values-text": "text/csv"
        case "public.tab-separated-values-text": "text/tab-separated-values"
        case "public.png": "image/png"
        case "public.image": "image/*"
        case "net.daringfireball.markdown": "text/markdown"
        // What Android's file managers report for an extension they don't know, so a received
        // share opens in Piru (the manifest's file intent filters).
        case "glass.kagerou.piru.share": "application/octet-stream"
        default: "*/*"
        }
    }

    init?(filenameExtension: String) {
        switch filenameExtension.lowercased() {
        case "json": self = .json
        case "txt": self = .plainText
        case "pdf": self = .pdf
        case "csv": self = .commaSeparatedText
        case "tsv": self = .tabSeparatedText
        case "png": self = .png
        case "md": self = UTType(identifier: "net.daringfireball.markdown", preferredFilenameExtension: "md")
        case "pirushare": self = .piruShare
        default: return nil
        }
    }
}

// MARK: - Importer and exporter

private struct AndroidImporter: ViewModifier {
    @Binding var isPresented: Bool
    let types: [UTType]
    let onCompletion: (Result<URL, any Error>) -> Void

    func body(content: Content) -> some View {
        content.onChange(of: isPresented) { _, presented in
            guard presented else { return }
            AndroidDocumentResults.shared.onImport = { outcome in
                isPresented = false
                if let outcome { onCompletion(outcome) }
            }
            if !AndroidDocuments.open(types) {
                AndroidDocumentResults.shared.onImport = nil
                isPresented = false
                onCompletion(.failure(AndroidDocumentError.unavailable))
            }
        }
    }
}

private struct AndroidExporter<D: FileDocument>: ViewModifier {
    @Binding var isPresented: Bool
    let document: D?
    let contentType: UTType
    let defaultFilename: String?
    let onCompletion: (Result<URL, any Error>) -> Void

    func body(content: Content) -> some View {
        content.onChange(of: isPresented) { _, presented in
            guard presented else { return }
            do {
                let source = try writeDocument()
                AndroidDocumentResults.shared.onExport = { outcome in
                    isPresented = false
                    try? FileManager.default.removeItem(at: source)
                    if let outcome { onCompletion(outcome) }
                }
                if !AndroidDocuments.create(filename: source.lastPathComponent, contentType: contentType, source: source) {
                    AndroidDocumentResults.shared.onExport = nil
                    try? FileManager.default.removeItem(at: source)
                    throw AndroidDocumentError.unavailable
                }
            } catch {
                isPresented = false
                onCompletion(.failure(error))
            }
        }
    }

    /// The document's bytes in a cache file named as the saved document will be.
    private func writeDocument() throws -> URL {
        guard let document,
              let data = try document.fileWrapper(configuration: .init(contentType: contentType, existingFile: nil))
              .regularFileContents
        else { throw CocoaError(.fileWriteUnknown) }
        var name = defaultFilename ?? "Piru"
        if let ext = contentType.preferredFilenameExtension, !name.hasSuffix(".\(ext)") {
            name += ".\(ext)"
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}

extension View {
    func fileImporter(
        isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection _: Bool = false,
        onCompletion: @escaping (Result<URL, any Error>) -> Void,
    ) -> some View {
        modifier(AndroidImporter(isPresented: isPresented, types: allowedContentTypes, onCompletion: onCompletion))
    }

    /// Android's picker returns one document; it arrives as a one-element selection.
    func fileImporter(
        isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection _: Bool,
        onCompletion: @escaping (Result<[URL], any Error>) -> Void,
    ) -> some View {
        modifier(AndroidImporter(isPresented: isPresented, types: allowedContentTypes) { result in
            onCompletion(result.map { [$0] })
        })
    }

    func fileExporter(
        isPresented: Binding<Bool>, document: (some FileDocument)?, contentType: UTType, defaultFilename: String? = nil,
        onCompletion: @escaping (Result<URL, any Error>) -> Void,
    ) -> some View {
        modifier(AndroidExporter(
            isPresented: isPresented, document: document, contentType: contentType,
            defaultFilename: defaultFilename, onCompletion: onCompletion,
        ))
    }

    func fileExporter(
        isPresented: Binding<Bool>, document: (some FileDocument)?, contentTypes: [UTType] = [], defaultFilename: String? = nil,
        onCompletion: @escaping (Result<URL, any Error>) -> Void, onCancellation _: @escaping () -> Void = {},
    ) -> some View {
        modifier(AndroidExporter(
            isPresented: isPresented, document: document, contentType: contentTypes.first ?? .data,
            defaultFilename: defaultFilename, onCompletion: onCompletion,
        ))
    }
}

// MARK: - Sharing (Piru/Views/Components/ShareSheet.swift, ShareSheetPresenter.swift)

/// The share sheet a `.sheet` presents: it opens Android's chooser with its items and closes,
/// or says so when there is nothing Android can send.
struct ShareSheet: View {
    let items: [Any]

    @Environment(\.dismiss) private var dismiss
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if failed {
                    ContentUnavailableView("Nothing to Share", systemImage: "square.and.arrow.up")
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            if AndroidDocuments.share(items: items) {
                dismiss()
            } else {
                failed = true
            }
        }
    }
}

/// Programmatic sharing: the chooser opens with the items' first file, or their text.
enum ShareSheetPresenter {
    static func present(_ items: [Any]) {
        AndroidDocuments.share(items: items)
    }
}

// MARK: - ShareLink (Piru/Views/Profiles/Sharing/ShareSessionView.swift)

/// A button that opens the share chooser with the file at `item`. SkipFuseUI's ShareLink sends
/// a URL as text, which for a file would send its path; this sends the file itself, as a
/// content:// URI, and says so when the chooser cannot open.
struct ShareLink<Label: View>: View {
    let item: URL
    let label: Label

    @State private var failed = false

    init(item: URL, preview _: SharePreview, @ViewBuilder label: () -> Label) {
        self.item = item
        self.label = label()
    }

    var body: some View {
        Button {
            failed = !AndroidDocuments.share(file: item)
        } label: {
            label
        }
        .alert("The share sheet could not be opened.", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }
}

/// The chooser titles itself; the preview's title is not shown on Android.
struct SharePreview {
    init(_: Text) {}
}
