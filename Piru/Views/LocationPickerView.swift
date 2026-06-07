import MapKit
import SwiftUI

/// A place chosen for a dose: a display name plus its coordinate. Value type
/// handed back from ``LocationPickerView`` to whatever is capturing a location.
struct PickedLocation: Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
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
    var results: [MKLocalSearchCompletion] = []
    var isLocating = false
    var authDenied = false

    /// Search text; setting it feeds the completer (and clears results when blank).
    var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                results = []
            } else {
                completer.queryFragment = trimmed
            }
        }
    }

    private let completer = MKLocalSearchCompleter()
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = self
        manager.delegate = self
    }

    // MARK: - Current location

    /// Request the device's current location and reverse-geocode it to a named
    /// place. Returns `nil` if access is denied or the fix fails. Prompts for
    /// when-in-use authorization the first time.
    func requestCurrentLocation() async -> PickedLocation? {
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
    func resolve(_ completion: MKLocalSearchCompletion) async -> PickedLocation? {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        guard let response = try? await search.start(), let item = response.mapItems.first else { return nil }
        let coordinate = item.location.coordinate
        return PickedLocation(
            name: item.name ?? completion.title,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
        )
    }

    // MARK: - MKLocalSearchCompleterDelegate

    nonisolated func completerDidUpdateResults(_: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { results = completer.results }
    }

    nonisolated func completer(_: MKLocalSearchCompleter, didFailWithError _: Error) {
        MainActor.assumeIsolated { results = [] }
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

    var body: some View {
        NavigationStack {
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
                        HStack {
                            Label("Current Location", systemImage: "location.fill")
                                .foregroundStyle(Theme.accent)
                            Spacer()
                            if model.isLocating { ProgressView() }
                        }
                    }
                    .disabled(model.isLocating)
                    .listRowBackground(Theme.cardBackground)
                } footer: {
                    if model.authDenied {
                        Text("Location access is off. Turn it on in Settings to use your current location.")
                    }
                }

                if model.results.isEmpty, !recents.isEmpty {
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
                                }
                            }
                            .listRowBackground(Theme.cardBackground)
                        }
                    }
                }

                if !model.results.isEmpty {
                    Section("Results") {
                        ForEach(model.results.indices, id: \.self) { index in
                            let result = model.results[index]
                            Button {
                                Task {
                                    if let picked = await model.resolve(result) {
                                        onPick(picked)
                                        dismiss()
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .foregroundStyle(.primary)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryLabel)
                                    }
                                }
                            }
                            .listRowBackground(Theme.cardBackground)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .searchable(text: $query, prompt: "Search for a place or address")
            .onChange(of: query) { model.query = query }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
    }
}

private extension CLLocationCoordinate2D {
    /// A plain "lat, long" fallback label when reverse geocoding yields no name.
    var formattedDegrees: String {
        String(format: "%.4f, %.4f", latitude, longitude)
    }
}
