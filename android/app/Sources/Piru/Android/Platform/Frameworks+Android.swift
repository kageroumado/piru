// Apple frameworks with no Android counterpart in this build, as the smallest surface the
// shared code calls, each behaving the way the app already handles the feature being off:
// no widgets to reload, no Health data, no StoreKit, no MapKit search.

import SwiftUI

// MARK: - WidgetKit

/// Android home-screen widgets are not built; nothing listens for a reload.
final class WidgetCenter: @unchecked Sendable {
    static let shared = WidgetCenter()

    func reloadAllTimelines() {}
    func reloadTimelines(ofKind _: String) {}
}

// MARK: - UniformTypeIdentifiers

struct UTType: Hashable, Sendable {
    let identifier: String
    let preferredFilenameExtension: String?

    static let json = UTType(identifier: "public.json", preferredFilenameExtension: "json")
    static let data = UTType(identifier: "public.data", preferredFilenameExtension: nil)
    static let text = UTType(identifier: "public.text", preferredFilenameExtension: "txt")
    static let plainText = UTType(identifier: "public.plain-text", preferredFilenameExtension: "txt")
    static let pdf = UTType(identifier: "com.adobe.pdf", preferredFilenameExtension: "pdf")
    static let commaSeparatedText = UTType(identifier: "public.comma-separated-values-text", preferredFilenameExtension: "csv")
    static let tabSeparatedText = UTType(identifier: "public.tab-separated-values-text", preferredFilenameExtension: "tsv")
    static let png = UTType(identifier: "public.png", preferredFilenameExtension: "png")
    static let image = UTType(identifier: "public.image", preferredFilenameExtension: nil)

    nonisolated init(identifier: String, preferredFilenameExtension: String?) {
        self.identifier = identifier
        self.preferredFilenameExtension = preferredFilenameExtension
    }

    /// A type the app declares, with the extension Piru/Info.plist's UTExportedTypeDeclarations
    /// gives it.
    nonisolated init(exportedAs identifier: String) {
        self.init(identifier: identifier, preferredFilenameExtension: Self.exportedExtensions[identifier])
    }

    private nonisolated static let exportedExtensions = [
        "glass.kagerou.piru.share": "pirushare",
    ]
}

// MARK: - HealthKit (Piru/Utilities/HealthKitVitals.swift, HealthKitBodyMass.swift)

/// Android has no HealthKit; Health Connect is not wired. Every read is "unavailable",
/// which the session vitals and body-weight screens already present.
@MainActor
@Observable
final class HealthKitVitals {
    static let shared = HealthKitVitals()

    var isAvailable: Bool { false }

    func requestFullAccess() async {}

    func connectWouldPrompt() async -> Bool { false }

    func vitals(from _: Date, to _: Date) async -> SessionVitals {
        SessionVitals(heartRate: [], bloodPressure: [])
    }
}

@MainActor
@Observable
final class HealthKitBodyMass {
    static let shared = HealthKitBodyMass()

    enum SyncResult: Equatable {
        case updated(kg: Double)
        case noData
        case unavailable
    }

    var isAvailable: Bool { false }

    func syncLatest() async -> SyncResult { .unavailable }
}

// MARK: - StoreKit (Piru/Data/Services/SkinShop.swift)

/// A store product's display face. Android has no store here, so none exist.
struct Product: Identifiable, Hashable {
    let id: String
    let displayName: String
    let displayPrice: String
}

/// The skin shop without a store: ownership is what SkinDefaults grants for free, and
/// nothing can be bought or restored.
@Observable
@MainActor
final class SkinShop {
    static let shared = SkinShop()

    enum Activity: Equatable {
        case idle
        case purchasing(productID: String)
        case restoring
    }

    enum Notice: Equatable {
        case pending
        case failed
        case nothingToRestore
    }

    private(set) var activity: Activity = .idle
    var notice: Notice?

    func owns(_ skin: Skin) -> Bool {
        SkinDefaults.usable(skin, owned: [])
    }

    var ownsEverything: Bool { false }

    func product(for _: Skin) -> Product? { nil }

    var everythingProduct: Product? { nil }

    func start() {}

    func buy(_: Product, then _: @escaping () -> Void = {}) {}

    func restore() async {
        notice = .nothingToRestore
    }
}

// MARK: - MapKit (Piru/Views/Journal/DailyDose/LocationPickerView.swift)

/// A place chosen for a dose: a display name plus its coordinate.
/// A place and, when one is known, its coordinate. A typed place has none, and the journal
/// stores it as a name with nil coordinates, the way an entry without a place stores nil.
struct PickedLocation: Equatable {
    var name: String
    var latitude: Double?
    var longitude: Double?
}

/// Android's picker takes a typed place name, or one of the recent places. There is no
/// place search without MapKit, so a typed place carries no coordinate of its own.
struct LocationPickerView: View {
    var recents: [PickedLocation] = []
    let onPick: (PickedLocation) -> Void

    @Environment(\.dismiss) var dismiss
    @State var name = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(String(localized: "Place"), text: $name)
                    Button(String(localized: "Use This Place")) {
                        onPick(PickedLocation(name: name, latitude: nil, longitude: nil))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !recents.isEmpty {
                    Section(String(localized: "Recent")) {
                        ForEach(recents.indices, id: \.self) { index in
                            Button(recents[index].name) {
                                onPick(recents[index])
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Location"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
    }
}

/// The tray's "current location" source. Android location needs a runtime permission flow
/// this build does not have, so it never produces a place.
@Observable
@MainActor
final class LocationSearchModel {
    var isLocating = false
    var authDenied = false

    func requestCurrentLocation() async -> PickedLocation? { nil }
}

struct CLLocation {
    let coordinate: CLLocationCoordinate2D

    init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct MKCoordinateRegion {
    var center: CLLocationCoordinate2D

    init(center: CLLocationCoordinate2D, latitudinalMeters _: Double, longitudinalMeters _: Double) {
        self.center = center
    }
}

enum MapCameraPosition {
    case region(MKCoordinateRegion)
}

struct Marker: View {
    let title: String
    let coordinate: CLLocationCoordinate2D

    init(_ title: String, coordinate: CLLocationCoordinate2D) {
        self.title = title
        self.coordinate = coordinate
    }

    var body: some View {
        Label(title, systemImage: "mappin.circle.fill")
    }
}

/// The dose's place as a card instead of a map: an embedded map needs Google Play services.
struct Map<Content: View>: View {
    private let content: Content

    init(initialPosition _: MapCameraPosition, @ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.platformSecondarySystemBackground
            content
                .font(.headline)
                .foregroundStyle(Theme.accent)
        }
    }
}

/// Opens the place in whatever maps app handles `geo:` URIs.
final class MKMapItem {
    let location: CLLocation
    var name: String?

    init(location: CLLocation, address _: Any?) {
        self.location = location
    }

    @MainActor
    func openInMaps() {
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        guard latitude.isFinite, longitude.isFinite else { return }
        let label = (name ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "geo:\(latitude),\(longitude)?q=\(latitude),\(longitude)(\(label))") {
            Task { await UIApplication.shared.open(url) }
        }
    }
}

// MARK: - TipKit (Piru/Utilities/OnboardingTips.swift)

/// Contextual tips are an iOS affordance; Android shows none, so every entry point is a no-op
/// and the tip types exist only to be named.
enum OnboardingTips {
    static func configure() {}
    static func markOnboardingComplete() {}
    static func updateEngagement(hasLoggedDose _: Bool) {}
    static func logDoseInvoked() {}
    static func retireDataTipAfterSessionMenuTip() async {}
}

protocol Tip {}

struct LogDoseTip: Tip {}
struct SettingsDataTip: Tip {}
struct SessionMenuTip: Tip {}
struct GraphGestureTip: Tip {}
struct ShareSessionTip: Tip {}

extension View {
    func popoverTip(_: some Tip, arrowEdge _: Edge? = nil) -> some View { self }
}

// MARK: - FileDocument

/// The document protocol behind `.fileExporter`, which saves `fileWrapper(...).regularFileContents`
/// (Documents+Android.swift).
protocol FileDocument {
    typealias ReadConfiguration = FileDocumentReadConfiguration
    typealias WriteConfiguration = FileDocumentWriteConfiguration

    static var readableContentTypes: [UTType] { get }
    init(configuration: ReadConfiguration) throws
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper
}

struct FileDocumentReadConfiguration {
    let contentType: UTType
    let file: FileWrapper
}

struct FileDocumentWriteConfiguration {
    let contentType: UTType
    let existingFile: FileWrapper?
}

final class FileWrapper {
    let regularFileContents: Data?

    init(regularFileWithContents contents: Data) {
        regularFileContents = contents
    }
}

// MARK: - Quick Look (ImageQuickLook+iOS.swift)

/// Quick Look previews are iOS's; Android opens nothing.
enum ImageQuickLook {
    static func present(url _: URL, from _: AnyObject?) {}
}

/// The zoom-transition source view Quick Look animates from; there is none to track.
struct ZoomSourceView: View {
    init(onResolve _: @escaping (AnyObject?) -> Void) {}

    var body: some View { Color.clear }
}
