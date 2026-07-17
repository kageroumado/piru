import MapKit
import SwiftUI

/// A place chosen for a dose: a display name plus its coordinate. Value type
/// handed back from ``LocationPickerView`` to whatever is capturing a location.
struct PickedLocation: Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
}

/// One as-you-type place completion, as a value type the view can render safely.
///
/// The picker deliberately never exposes the raw `[MKLocalSearchCompletion]`: the
/// completer replaces that array asynchronously on its delegate callback, and a
/// `ForEach` reading it by index crashes when it shrinks mid-update. This struct
/// carries only what a row draws (`title` / `subtitle`) plus the completion
/// needed to resolve a coordinate, with a **content-derived** identity so
/// unchanged suggestions keep their SwiftUI identity across keystrokes (stable
/// diffing) and the view can never index out of bounds.
struct LocationSuggestion: Identifiable, Equatable {
    let title: String
    let subtitle: String
    /// The MapKit completion this row resolves to. Excluded from identity and
    /// equality — those are content-based (`title` + `subtitle`).
    let completion: MKLocalSearchCompletion

    var id: String {
        subtitle.isEmpty ? title : "\(title)\u{1}\(subtitle)"
    }

    static func == (lhs: LocationSuggestion, rhs: LocationSuggestion) -> Bool {
        lhs.title == rhs.title && lhs.subtitle == rhs.subtitle
    }
}

/// Drives the location picker: as-you-type address/POI completions
/// (`MKLocalSearchCompleter`), resolving a completion to a coordinate
/// (`MKLocalSearch`), and a one-shot "current location" via `CLLocationManager`
/// reverse-geocoded to a readable name (`CLGeocoder`).
///
/// `@MainActor` throughout; the Core Location / MapKit delegate callbacks are
/// delivered on the main thread, so they hop back in via `assumeIsolated`.
@MainActor
@Observable
final class LocationSearchModel: NSObject, MKLocalSearchCompleterDelegate, CLLocationManagerDelegate {
    /// As-you-type place completions as value types (see ``LocationSuggestion``).
    var suggestions: [LocationSuggestion] = []
    var isLocating = false
    var authDenied = false

    /// Search text; setting it feeds the completer (and clears results when blank).
    var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                suggestions = []
            } else {
                completer.queryFragment = trimmed
            }
        }
    }

    /// Both MapKit/Core Location objects are created lazily on first use, not in
    /// `init`. This model is the default value of a `@State` property, and SwiftUI
    /// re-evaluates a `@State` default expression on *every* re-render of the
    /// owning view — keeping the first instance and discarding the rest. If the
    /// completer and manager were built in `init`, each throwaway model would spin
    /// up (and tear down) a `CLLocationManager` and `MKLocalSearchCompleter` with
    /// delegate wiring, dozens of times per session. Deferring them means a
    /// discarded model costs nothing, and nothing touches Core Location until the
    /// user actually searches or asks for their current location.
    @ObservationIgnored private lazy var completer: MKLocalSearchCompleter = {
        let completer = MKLocalSearchCompleter()
        completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = self
        return completer
    }()

    @ObservationIgnored private lazy var manager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        return manager
    }()

    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Current location

    /// Request the device's current location and reverse-geocode it to a named
    /// place. Returns `nil` if access is denied or the fix fails. Prompts for
    /// when-in-use authorization the first time.
    ///
    /// Single-flight: a second call while one is pending would overwrite the
    /// stored continuations and leak the first (hanging its caller), so it
    /// bails out immediately instead.
    func requestCurrentLocation() async -> PickedLocation? {
        guard !isLocating else { return nil }
        isLocating = true
        defer { isLocating = false }

        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            await withCheckedContinuation { authContinuation = $0 }
        }

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            authDenied = false
        default:
            authDenied = true
            return nil
        }

        guard let location = try? await withCheckedThrowingContinuation({ continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }) else { return nil }

        let name = await reverseGeocodedName(for: location)
            ?? location.coordinate.formattedDegrees
        return PickedLocation(
            name: name,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
        )
    }

    private func reverseGeocodedName(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else { return nil }
        if let name = item.name, !name.isEmpty { return name }
        return item.address?.shortAddress ?? item.address?.fullAddress
    }

    // MARK: - Resolving a search completion

    /// Resolve a completer suggestion into a concrete place with a coordinate.
    func resolve(_ suggestion: LocationSuggestion) async -> PickedLocation? {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: suggestion.completion))
        guard let response = try? await search.start(), let item = response.mapItems.first else { return nil }
        let coordinate = item.location.coordinate
        return PickedLocation(
            name: item.name ?? suggestion.title,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
        )
    }

    // MARK: - MKLocalSearchCompleterDelegate

    nonisolated func completerDidUpdateResults(_: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            // Deduplicate by identity. MapKit routinely returns completions that
            // share a title+subtitle (chain POIs, ambiguous addresses), and
            // ``LocationSuggestion``'s identity is content-derived — so the raw
            // results can carry colliding ids. Two elements with the same id in a
            // `ForEach` desyncs SwiftUI's id-keyed child storage from the element
            // count and crashes it with an out-of-bounds index during diffing.
            var seen = Set<LocationSuggestion.ID>()
            suggestions = completer.results.compactMap { completion in
                let suggestion = LocationSuggestion(
                    title: completion.title,
                    subtitle: completion.subtitle,
                    completion: completion,
                )
                return seen.insert(suggestion.id).inserted ? suggestion : nil
            }
        }
    }

    nonisolated func completer(_: MKLocalSearchCompleter, didFailWithError _: Error) {
        MainActor.assumeIsolated { suggestions = [] }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            guard let location = locations.last else { return }
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            locationContinuation?.resume(throwing: error)
            locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        MainActor.assumeIsolated {
            authContinuation?.resume()
            authContinuation = nil
        }
    }
}

/// A sheet for attaching a place to a dose: tap "Current Location" or search for
/// an address / point of interest. Picking one calls `onPick` and dismisses.
struct LocationPickerView: View {
    /// Previously used places (most recent first), shown while not searching.
    var recents: [PickedLocation] = []
    let onPick: (PickedLocation) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model = LocationSearchModel()
    @State private var query = ""
    /// Search starts active: the sheet's job is finding a place, so it opens
    /// keyboard-up instead of as a mostly-empty page.
    @State private var searchActive = true

    var body: some View {
        // Snapshot both collections once so the `.isEmpty` section gating and the
        // `ForEach` below agree, and dedupe `recents` by the exact key its
        // `ForEach` uses (`name`) — duplicate ids crash `ForEach`'s diffing (see
        // ``completerDidUpdateResults`` for the same guard on live results).
        let suggestions = model.suggestions
        let recents = recents.uniqued(by: \.name)
        return NavigationStack {
            List {
                Section {
                    Button {
                        Task {
                            if let picked = await model.requestCurrentLocation() {
                                onPick(picked)
                                dismiss()
                            }
                        }
                    } label: {
                        Label("Current Location", systemImage: "location.fill")
                            .foregroundStyle(Theme.accent)
                    }
                    .disabled(model.isLocating)
                    .accessibilityValue(model.isLocating ? Text("Locating…") : Text(verbatim: ""))
                    .listRowBackground(CardBackground())
                } footer: {
                    if model.authDenied {
                        Text("Location access is off. Turn it on in Settings to use your current location.")
                    }
                }

                if suggestions.isEmpty, !recents.isEmpty {
                    Section("Recents") {
                        ForEach(recents, id: \.name) { place in
                            Button {
                                onPick(place)
                                dismiss()
                            } label: {
                                Label {
                                    Text(place.name)
                                        .foregroundStyle(.primary)
                                } icon: {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                        .accessibilityHidden(true)
                                }
                            }
                            .listRowBackground(CardBackground())
                        }
                    }
                }

                if !suggestions.isEmpty {
                    Section("Results") {
                        ForEach(suggestions) { suggestion in
                            Button {
                                Task {
                                    if let picked = await model.resolve(suggestion) {
                                        onPick(picked)
                                        dismiss()
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                        .foregroundStyle(.primary)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryLabel)
                                    }
                                }
                            }
                            .listRowBackground(CardBackground())
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .searchable(text: $query, isPresented: $searchActive, prompt: "Search for a place or address")
            .onChange(of: query) { model.query = query }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
        // Half-height by default — a place search doesn't need a full page,
        // and with the keyboard up it reads as a compact finder (Maps-style).
        .presentationDetents([.medium, .large])
    }
}

private extension CLLocationCoordinate2D {
    /// A plain "lat, long" fallback label when reverse geocoding yields no name.
    var formattedDegrees: String {
        String(format: "%.4f, %.4f", latitude, longitude)
    }
}

private extension Sequence {
    /// The elements in order, keeping only the first for each distinct key —
    /// so a `ForEach` keyed on that value can never see a duplicate id.
    func uniqued<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}
