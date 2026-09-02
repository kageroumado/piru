import MapKit
import SwiftUI

/// The user's own words and place, merged into one card — notes, tags, and
/// location were three separate one-row sections before.
struct EntryContextSection: View {
    let entry: DoseEntry

    var body: some View {
        let notes = entry.notes ?? ""
        if !notes.isEmpty || !entry.tags.isEmpty || entry.locationName != nil {
            Section("Your Notes") {
                if !notes.isEmpty {
                    Text(notes)
                }
                if !entry.tags.isEmpty {
                    TagChipsView(tags: entry.tags)
                }
                if let locationName = entry.locationName {
                    if let coordinate = entry.coordinate {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: coordinate,
                            latitudinalMeters: 400,
                            longitudinalMeters: 400,
                        ))) {
                            Marker(locationName, coordinate: coordinate)
                                .tint(Theme.accent)
                        }
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                    }
                    Button {
                        openInMaps(name: locationName, coordinate: entry.coordinate)
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(Theme.accent)
                            Text(locationName)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .captionSecondary()
                        }
                    }
                    .accessibilityHint(Text("Opens in Maps"))
                }
            }
        }
    }

    /// Open the dose's saved place in Maps. No-op if it has a name but no
    /// coordinate (which our picker never produces).
    private func openInMaps(name: String, coordinate: CLLocationCoordinate2D?) {
        guard let coordinate else { return }
        let item = MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil,
        )
        item.name = name
        item.openInMaps()
    }
}
