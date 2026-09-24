import Foundation

extension TimelineModelCache {
    /// Off-main prewarm: compute and cache the ``TimelineCurveModel/Derived``
    /// geometry for a batch of dose sets, so the matching ``TimelineGraphView``
    /// cards later render as synchronous cache hits — `init` seeds its model from
    /// the cache, so there's no placeholder→graph flip and no per-card detached
    /// task while scrolling. The journal calls this right after it (re)builds its
    /// day groups; sets already cached are skipped, so a re-scroll costs nothing.
    func prewarm(
        _ inputs: [(substances: [ActiveSubstanceState], markers: [DoseMarker])],
        stackRedoses: Bool,
        dayBounded: Bool,
    ) {
        // Claim misses up front on the main actor (the cache is main-isolated) —
        // a claim makes this batch the sole computer of each key, so a visible
        // card whose own load arrives meanwhile awaits the result instead of
        // computing the same model in parallel — then do the expensive curve
        // math off-main and insert the results back.
        let pending: [(key: TimelineGraphView.DerivedKey, substances: [ActiveSubstanceState], markers: [DoseMarker])] =
            inputs.compactMap { input in
                guard !input.substances.isEmpty || !input.markers.isEmpty else { return nil }
                let key = TimelineGraphView.DerivedKey(
                    substances: input.substances, markers: input.markers,
                    stackRedoses: stackRedoses, dayBounded: dayBounded,
                )
                guard claim(key) else { return nil }
                return (key, input.substances, input.markers)
            }
        guard !pending.isEmpty else { return }
        let now = Date.now
        Task.detached(priority: .utility) {
            // Insert per item, not batched at the end: `inputs` arrive in
            // display order, so the visible cards' waiters resolve first,
            // while later days are still computing.
            for item in pending {
                let model = TimelineCurveModel.computeDerived(
                    substances: item.substances, markers: item.markers,
                    stackRedoses: stackRedoses, dayBounded: dayBounded, currentTime: now,
                )
                await MainActor.run {
                    TimelineModelCache.shared.insert(model, for: item.key)
                }
            }
        }
    }
}
