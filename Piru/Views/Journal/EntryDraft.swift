import SwiftUI

/// The in-flight edit state for ``EntryDetailView``. Every editable fact of the
/// dose lives here as one `@Observable` unit — seeded from the committed entry
/// on `begin(from:)`, committed back on Done, discarded on Cancel (the next
/// `begin` re-seeds, so stale drafts never leak).
@Observable
@MainActor
final class EntryDraft {
    var amount = ""
    var unit = "mg"
    var route: RouteOfAdministration = .oral
    var saltForm: String?
    var isomer: String?
    var timestamp = Date.now
    var notes = ""
    var tags: [String] = []
    var location: PickedLocation?
    /// The amount is an estimate, not a measured figure — carried onto the entry
    /// and shown as a `~` prefix.
    var isApproximate = false

    // By-volume editing (alcohol %ABV → grams) — mirror of EntryFormView's state.
    var byVolumeMode = false
    var volumeText = ""
    var abvText = ""
    var drinkName = ""
    var volumeUnit: UnitVolume = ByVolumeDefaults.preferredVolumeUnit

    /// The draft amount keeps a String binding (not `value:format:`) so the
    /// dose-level tint and badge update per keystroke. Invariant dot-decimal
    /// first (`begin(from:)` populates the field with dot-decimal text), then a
    /// locale-aware parse for locale keyboards.
    var parsedAmount: Double? {
        let parsed = Double(amount.replacingOccurrences(of: ",", with: "."))
            ?? (try? Double(amount, format: .number))
        guard let value = parsed, value > 0 else { return nil }
        return value
    }

    var enteredVolumeML: Double? {
        guard let value = Double(volumeText.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return Measurement(value: value, unit: volumeUnit).converted(to: .milliliters).value
    }

    var enteredABV: Double? {
        guard let value = Double(abvText.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return value
    }

    var trimmedDrinkName: String? {
        let trimmed = drinkName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func byVolumeGrams(capability: ByVolumeDosing?) -> Double? {
        guard let capability, let ml = enteredVolumeML, let abv = enteredABV else { return nil }
        let grams = capability.canonicalAmount(volumeML: ml, strength: abv)
        return grams > 0 ? grams : nil
    }

    func applyDrinkPreset(_ preset: DrinkPreset) {
        volumeText = ByVolumeDefaults.format(preset.volume.converted(to: volumeUnit).value)
        abvText = ByVolumeDefaults.format(preset.defaultABV)
    }

    func syncByVolumeAmount(capability: ByVolumeDosing?) {
        guard byVolumeMode else { return }
        unit = capability?.canonicalUnit ?? "g"
        amount = byVolumeGrams(capability: capability).map { ByVolumeDefaults.format($0) } ?? ""
    }

    /// Seed the drafts from a committed entry when entering edit mode.
    func begin(from entry: DoseEntry, hasByVolumeCapability: Bool) {
        amount = entry.amount == entry.amount.rounded()
            ? String(Int(entry.amount))
            : String(entry.amount)
        unit = entry.unit
        route = entry.route
        saltForm = entry.saltForm
        isomer = entry.isomer
        timestamp = entry.timestamp
        notes = entry.notes ?? ""
        tags = entry.tags
        isApproximate = entry.isApproximate
        if let name = entry.locationName, let lat = entry.latitude, let lng = entry.longitude {
            location = PickedLocation(name: name, latitude: lat, longitude: lng)
        } else {
            location = nil
        }

        // By-volume round-trip: if this entry was logged by volume, restore the
        // drink-mode fields from its structured volume/ABV/name.
        byVolumeMode = false
        if hasByVolumeCapability, let ml = entry.volumeML, let abv = entry.abv {
            byVolumeMode = true
            // Display the stored milliliters in the current unit without mutating
            // `volumeUnit` (which would fire the conversion onChange on the
            // already-seeded text).
            volumeText = ByVolumeDefaults.format(
                Measurement(value: ml, unit: .milliliters).converted(to: volumeUnit).value,
            )
            abvText = ByVolumeDefaults.format(abv)
            drinkName = entry.drinkName ?? ""
        }
    }
}
