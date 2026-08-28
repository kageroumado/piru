import CryptoKit
import SwiftUI

struct Substance: Identifiable {
    let id: UUID
    let name: String

    /// A deterministic identity derived from the canonical name, so the *same*
    /// substance gets the *same* `id` across every construction — a decode, an
    /// overlay merge, a search re-resolve. `ForEach` can then reuse a row when a
    /// search narrows ("caffe" → "caffei") instead of tearing down and rebuilding
    /// every row (a fresh `UUID()` per construction made the whole collection look
    /// replaced each keystroke). Canonical names are unique in the bundled DB, so
    /// this stays collision-free; `Equatable`/`Hashable` still key on `id`, which
    /// now means "same substance by name".
    nonisolated static func deterministicID(forName name: String) -> UUID {
        var bytes = [UInt8](SHA256.hash(data: Data(name.lowercased().utf8)))
        // Stamp RFC-4122 version (4) + variant bits so it's a well-formed UUID.
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15],
        ))
    }
    /// Optional human-facing title override (e.g. "2,5-DMBZP" for the compound
    /// whose canonical `name` is "1-(2,5-Dimethoxybenzyl) piperazine"). When set,
    /// the UI shows this as the primary title and demotes `name` to the subtitle.
    /// `name` stays canonical for search/dedup/logging. See `displayTitle`/`displaySubtitle`.
    let displayName: String?
    let aliases: [String]
    /// User-defined per-substance units ("1 capsule = 30 mg"), stamped on by the
    /// ``SubstanceLibrary`` façade from ``CustomUnitStore`` at resolution time and
    /// merged ahead of the curated table in ``unitAliases``. A `var` amid the
    /// surrounding `let`s precisely because it's applied after construction, at the
    /// single overlay choke point; empty for any `Substance` built outside the façade.
    var customUnitAliases: [UnitAlias] = []
    let category: SubstanceCategory
    /// Additional browse homes beyond `category` (the resolved primary). Lets an
    /// intentionally cross-class compound surface under more than one family
    /// (e.g. Tianeptine under both Antidepressant and Opioid). Curated-only,
    /// loaded in the batch path; empty for everything else. The primary
    /// `category` still drives card color/icon and the default home.
    let extraBrowseCategories: [SubstanceCategory]
    let defaultRoute: RouteOfAdministration
    let routes: [SubstanceRoute]
    let effects: [String]
    let subjectiveEffects: [SubjectiveEffect]
    let toleranceInfo: ToleranceInfo?
    let halfLifeMinutes: Double?
    let sources: [String]
    let mechanismOfAction: MechanismOfAction?
    /// Display-policy classification governing dose/duration/browse visibility.
    let displayClass: CompoundDisplayClass
    /// Parsed OTC/Rx/controlled status, when known (`rx`, `otc`,
    /// `rx_otc_dependent`, `controlled_schedule_N`).
    let regulatoryStatus: String?
    /// True when the total duration exceeds 24h (the vitamin problem); OTC
    /// duration is suppressed when set. Recreational/dual-use are exempt.
    let durationImplausible: Bool
    /// Clinical indications (what it's prescribed for), for medical/OTC display.
    let indications: [String]
    /// Contraindications + boxed warnings, for medical/OTC display.
    let contraindications: [Contraindication]
    /// Cross-benzo diazepam equivalency (benzodiazepines only).
    let diazepamEquivalent: DiazepamEquivalent?
    /// PSID FAMILY — the stable substance-identity anchor (InChIKey connectivity
    /// block 1, or a sentinel-digit name-hash for structure-less / collision
    /// rows). Fold-family siblings (a racemate and its enantiomers, IR and XR)
    /// share this, so it is *not* unique per row; the full form identity is
    /// `substanceUID` + the facet scalars. Loaded in **both** the batch and
    /// detail paths — `DoseEntry.substanceUID` will reference it. See ``PSID``.
    let substanceUID: String?
    /// Chemical identifiers (detail-only; nil in the batch/browse path).
    let cas: String?
    let inchikey: String?
    let formula: String?
    /// PubChem Compound ID, for linking out to the curated chemistry record.
    /// Detail-only (nil in the batch/browse path), like the other identifiers.
    let pubchemCID: Int?
    /// Hand-curated popularity score in [0,1] (0 = not curated). Drives the
    /// "Popularity" sort in category browse; loaded in the batch path.
    let popularity: Double
    /// True for a genuinely thin catalog entry — zero dose AND duration AND
    /// protocol data from any source (the pipeline's `flag_dose_less_stubs`).
    /// Drives the "Limited data" list badge. NOT the same as "no dose ladder":
    /// a brew like Ayahuasca has no mg ladder but plenty of duration/effect data,
    /// so it isn't a stub. Loaded in the batch path.
    let isStub: Bool
    /// Orthogonal class metadata: mechanism (`DRI`, `NMDA-antagonist`), chemical
    /// family (`cathinone`, `arylcyclohexylamine`), provenance (`PIHKAL`,
    /// `research-chemical`), legal/safety status (`US-Schedule-I`, `no-human-data`).
    /// Compounds often belong to multiple families; tags compose where `category` cannot.
    let tags: [String]
    /// Molar mass in g/mol, when known. Populated for peptides (where it drives
    /// IU↔mg reasoning and is shown in the handling card) and any compound with a
    /// curated molecular weight. Maps to the `substances.molecular_weight` column.
    let molarMass: Double?
    /// Peptide/biologic-specific reference data. Non-nil switches the detail view
    /// to a peptide presentation (sequence, handling, reconstitution) in place of
    /// the psychoactive trip model. nil for ordinary small molecules.
    let peptideProfile: PeptideProfile?
    /// Primary references (DOIs / PMIDs / URLs / labels) for this compound's
    /// curated claims. Detail-only (empty in the batch/browse path).
    let references: [Citation]
    /// Canonical drug.community page slug, for deep-linking `/drug/<slug>`.
    /// drug.community's page resolves only this canonical form (no alias
    /// fallback), so it can't be derived from the app's own name. Detail-only
    /// (nil in the batch/browse path); nil when there's no drug.community entry.
    let drugCommunitySlug: String?
    /// FreeOD Wiki page slug, for deep-linking `freeodwiki.org/药物/<slug>` (the
    /// page titles are Chinese, so the slug can't be derived from `name`).
    /// Detail-only; nil when there's no FreeOD entry.
    let freeodwikiSlug: String?
    /// Long-form overview prose ("what it is / history / risk profile"),
    /// resolved locale-first (native Chinese when the app runs in Chinese,
    /// machine-translated English as a fallback). Detail-only; nil when no
    /// source supplies an overview. Distinct from `mechanismOfAction`.
    let overview: SubstanceOverview?
    /// Canonical isomeric SMILES, when known. Detail-only (nil in the batch/
    /// browse path); shown in the Chemistry disclosure for the structurally
    /// curious. Maps to `substances.smiles`.
    let smiles: String?
    /// IUPAC systematic name, when known. Detail-only; maps to
    /// `substances.iupac_name`.
    let iupacName: String?
    /// Predicted/forensic physicochemical descriptors (logP/TPSA/LD50/…).
    /// Detail-only; nil when no column is populated. **Not clinical** — see
    /// ``Physicochemical``.
    let physicochemical: Physicochemical?
    /// Hand-curated, ordered common street/brand names shown in the detail
    /// header (≤~4). Distinct from ``aliases`` (the full, unordered search
    /// index): this is the short editorial "also known as" set for popular
    /// substances only. Detail-only; empty when not curated — never
    /// auto-derived from `aliases`.
    let popularAliases: [String]
    /// Curated evidence-checked corrections to common claims (the "Common
    /// misconceptions" section). Popular-substances-only; empty for the long
    /// tail. Detail-only. See ``MythBust``.
    let misconceptions: [MythBust]
    /// Hand-curated notable combinations (the "Combinations" section).
    /// Popular-substances-only; empty for the long tail. Detail-only. See
    /// ``Combination``.
    let combinations: [Combination]
    /// Curated hydration/thermoregulation guidance (the "Water & heat" card).
    /// Only for substances that raise body temperature or alter fluid balance;
    /// nil otherwise. Detail-only. See ``WaterHeatGuidance``.
    let waterHeat: WaterHeatGuidance?

    nonisolated init(
        name: String,
        displayName: String? = nil,
        aliases: [String],
        category: SubstanceCategory,
        extraBrowseCategories: [SubstanceCategory] = [],
        defaultRoute: RouteOfAdministration,
        routes: [SubstanceRoute],
        effects: [String],
        subjectiveEffects: [SubjectiveEffect] = [],
        toleranceInfo: ToleranceInfo? = nil,
        halfLifeMinutes: Double? = nil,
        sources: [String] = [],
        mechanismOfAction: MechanismOfAction? = nil,
        tags: [String] = [],
        displayClass: CompoundDisplayClass = .recreational,
        regulatoryStatus: String? = nil,
        durationImplausible: Bool = false,
        indications: [String] = [],
        contraindications: [Contraindication] = [],
        diazepamEquivalent: DiazepamEquivalent? = nil,
        substanceUID: String? = nil,
        cas: String? = nil,
        inchikey: String? = nil,
        formula: String? = nil,
        pubchemCID: Int? = nil,
        popularity: Double = 0,
        isStub: Bool = false,
        molarMass: Double? = nil,
        peptideProfile: PeptideProfile? = nil,
        references: [Citation] = [],
        drugCommunitySlug: String? = nil,
        freeodwikiSlug: String? = nil,
        overview: SubstanceOverview? = nil,
        smiles: String? = nil,
        iupacName: String? = nil,
        physicochemical: Physicochemical? = nil,
        popularAliases: [String] = [],
        misconceptions: [MythBust] = [],
        combinations: [Combination] = [],
        waterHeat: WaterHeatGuidance? = nil,
    ) {
        self.id = Self.deterministicID(forName: name)
        self.name = name
        self.displayName = displayName
        self.aliases = aliases
        self.category = category
        self.extraBrowseCategories = extraBrowseCategories
        self.defaultRoute = defaultRoute
        self.routes = routes
        self.effects = effects
        self.subjectiveEffects = subjectiveEffects
        self.toleranceInfo = toleranceInfo
        self.halfLifeMinutes = halfLifeMinutes
        self.sources = sources
        self.mechanismOfAction = mechanismOfAction
        self.tags = tags
        self.displayClass = displayClass
        self.regulatoryStatus = regulatoryStatus
        self.durationImplausible = durationImplausible
        self.indications = indications
        self.contraindications = contraindications
        self.diazepamEquivalent = diazepamEquivalent
        self.substanceUID = substanceUID
        self.cas = cas
        self.inchikey = inchikey
        self.formula = formula
        self.pubchemCID = pubchemCID
        self.popularity = popularity
        self.isStub = isStub
        self.molarMass = molarMass
        self.peptideProfile = peptideProfile
        self.references = references
        self.drugCommunitySlug = drugCommunitySlug
        self.freeodwikiSlug = freeodwikiSlug
        self.overview = overview
        self.smiles = smiles
        self.iupacName = iupacName
        self.physicochemical = physicochemical
        self.popularAliases = popularAliases
        self.misconceptions = misconceptions
        self.combinations = combinations
        self.waterHeat = waterHeat
    }

    /// Title shown in lists and the detail header — the region-appropriate
    /// spelling for drugs with US/international name variants (Acetaminophen vs
    /// Paracetamol), else the curated override, else the canonical `name`. A
    /// leading pictograph is stripped (see ``titlePictograph``).
    ///
    /// `nonisolated` (pure — regional-name resolve + pictograph strip over the
    /// struct's own stored fields) so off-main callers can read it: the Library's
    /// sort runs in a `Task.detached` where the project-default `MainActor`
    /// isolation would otherwise forbid the access (a Release-only warning).
    nonisolated var displayTitle: String {
        let base = RegionalSubstanceName.resolve(canonicalName: name) ?? displayName ?? name
        return Substance.strippingLeadingPictograph(base).text
    }

    /// A leading pictograph in the curated display name — e.g. PsychonautWiki's
    /// "🍰 Cake" April-Fools entry — telegraphs the in-joke wherever the title
    /// shows (search, browse lists). It's stripped from ``displayTitle`` and
    /// surfaced here so the *detail* screen can play along instead of spoiling it.
    var titlePictograph: String? {
        Substance.strippingLeadingPictograph(displayName ?? name).pictograph
    }

    /// Splits a leading emoji (a default-emoji-presentation scalar) off a title:
    /// "🍰 Cake" → ("Cake", "🍰"). Ordinary names pass through unchanged.
    nonisolated static func strippingLeadingPictograph(_ s: String) -> (text: String, pictograph: String?) {
        guard let first = s.first,
              let scalar = first.unicodeScalars.first,
              scalar.properties.isEmojiPresentation
        else {
            return (s, nil)
        }
        let rest = String(s.dropFirst()).drop(while: \.isWhitespace)
        return (String(rest), String(first))
    }

    /// Aliases cleaned for display (search uses the separate normalized index,
    /// so this never affects findability). Collapses hyphen / spacing / casing
    /// variants ("2C-B" / "2cb" / "2c-b") to one — keeping the best-cased form —
    /// and drops aliases that merely restate the name. Useful clutter for search,
    /// noise for a human reading "Also known as".
    var displayAliases: [String] {
        let drop: Set<String> = [Substance.aliasKey(name), Substance.aliasKey(displayTitle)]
        var best: [String: String] = [:]
        var order: [String] = []
        for alias in aliases {
            let key = Substance.aliasKey(alias)
            if key.isEmpty || drop.contains(key) { continue }
            if let existing = best[key] {
                if Substance.aliasCasingScore(alias) > Substance.aliasCasingScore(existing) {
                    best[key] = alias
                }
            } else {
                best[key] = alias
                order.append(key)
            }
        }
        let resolved = order.compactMap { best[$0] }
        // In a non-Chinese UI, push CJK aliases (FreeOD's Chinese street names) to
        // the end so an English title isn't immediately followed by Han — Latin
        // names a reader recognizes lead. A stable partition keeps source order
        // within each group. In a Chinese UI the source order already reads well.
        guard !SubstanceReadModel.contentLanguage.isChinese else { return resolved }
        // Single pass: computing `containsHan` once per alias rather than twice
        // (the old `filter(!han) + filter(han)` evaluated it for every alias twice).
        var latin: [String] = []
        var han: [String] = []
        for alias in resolved {
            if alias.containsHan { han.append(alias) } else { latin.append(alias) }
        }
        return latin + han
    }

    /// Casing/spacing-insensitive identity key for an alias. Built in one
    /// pass into a single string — the `.map(String.init).joined()` form
    /// allocated a `String` per scalar, on the per-row render path — with an
    /// inline test for the ASCII range so the bridged `CharacterSet` call is
    /// paid only for non-ASCII scalars (CJK, Greek).
    static func aliasKey(_ s: String) -> String {
        var key = ""
        key.reserveCapacity(s.count)
        for scalar in s.lowercased().unicodeScalars {
            let isASCIIAlnum = (scalar.value >= 0x30 && scalar.value <= 0x39)
                || (scalar.value >= 0x61 && scalar.value <= 0x7A)
            if isASCIIAlnum || (scalar.value > 0x7F && CharacterSet.alphanumerics.contains(scalar)) {
                key.unicodeScalars.append(scalar)
            }
        }
        return key
    }

    /// Prefer the better-cased variant: more capitals (proper "2C-B" over "2cb"),
    /// then a hyphenated form over a run-together one.
    static func aliasCasingScore(_ s: String) -> Int {
        s.filter(\.isUppercase).count * 10 + (s.contains("-") ? 1 : 0)
    }

    /// Secondary line for rows: the canonical (expanded) name when it differs
    /// from the shown title, otherwise the cleaned aliases (up to 3).
    var displaySubtitle: String? {
        if displayName != nil, name != displayTitle { return name }
        let cleaned = displayAliases
        guard !cleaned.isEmpty else { return nil }
        return cleaned.prefix(3).joined(separator: ", ")
    }

    /// External chemistry reference, preferring an exact PubChem CID, then an
    /// InChIKey search, then a name search — so every substance resolves.
    var pubChemURL: URL? {
        if let cid = pubchemCID {
            return URL(string: "https://pubchem.ncbi.nlm.nih.gov/compound/\(cid)")
        }
        let query = inchikey ?? name
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://pubchem.ncbi.nlm.nih.gov/#query=\(encoded)")
    }

    /// True when no route on this substance has any usable dose data. Used by
    /// the detail view to switch to a "see references" presentation for
    /// research chemicals whose only available information is the literature.
    var hasNoDoseData: Bool {
        guard !routes.isEmpty else { return true }
        return routes.allSatisfy { !$0.doses.hasAnyValue }
    }

    /// True when this compound should use the peptide-specific detail
    /// presentation (sequence / handling / reconstitution / protocol dosing)
    /// rather than the psychoactive trip model. Driven by category or the
    /// presence of curated peptide data.
    var usesPeptidePresentation: Bool {
        category == .peptide || (peptideProfile?.hasAnyValue ?? false)
    }

    /// The protocol-dosing schedule to surface, preferring the default route,
    /// then any route that carries one. nil when no protocol dosing is curated.
    var primaryProtocolDosing: ProtocolDosing? {
        routes.first { $0.route == defaultRoute }?.protocolDosing
            ?? routes.compactMap(\.protocolDosing).first
    }

    var defaultUnit: String {
        routes.first { $0.route == defaultRoute }?.unit
            ?? routes.first?.unit
            ?? "mg"
    }

    func doseRange(for route: RouteOfAdministration) -> DoseRange? {
        routes.first { $0.route == route }?.doses
    }

    func unit(for route: RouteOfAdministration) -> String {
        routes.first { $0.route == route }?.unit ?? defaultUnit
    }

    func duration(for route: RouteOfAdministration) -> DurationProfile? {
        routes.first { $0.route == route }?.duration
    }

    // MARK: - Salt forms

    // Overload-family convention — `…(for:)` vs `…(for:saltForm:)`:
    //
    // The route-only accessors — `doseRange(for:)`, `unit(for:)`,
    // `duration(for:)`, and `convert(amount:from:toRoute:)` — intentionally
    // return the route's **default-salt** data (the top-level fields, which
    // mirror `saltForms.first`). They exist so salt-unaware code stays correct
    // without threading a salt through every call site.
    //
    // The `…(for:saltForm:)` variants narrow to a *specific* form, falling back
    // to the default when the salt is `nil` or unknown. Any surface that
    // displays or computes for a SPECIFIC logged/selected salt (the dose-level
    // ladder, the unit shown next to an amount, a salt-aware conversion) MUST
    // use the salt overload — otherwise it silently shows the default form's
    // numbers/unit for a different salt. New call sites: default to the salt
    // overload whenever a salt is in scope; reach for the route-only one only
    // when no salt selection exists.

    /// The dose-bearing variant of a route matching BOTH form axes — the salt
    /// counter-ion and the stereoisomer. Returns `nil` when the route has no
    /// variant list or no exact match, so callers fall back to the route's
    /// top-level (default-form) fields. A salt-only substance carries `isomer ==
    /// nil` on every variant, so passing `isomer: nil` reduces to a salt match
    /// (and vice-versa) — the two axes stay independent.
    private func doseVariant(
        for route: RouteOfAdministration, saltForm: String?, isomer: String?,
    ) -> DoseVariant? {
        routes.first { $0.route == route }?
            .saltForms?.first { $0.saltForm == saltForm && $0.isomer == isomer }
    }

    /// Distinct salt/ester forms across all routes, ordered (default first,
    /// then by first appearance). Empty for the vast majority of substances.
    /// Drives the "does this substance have a salt dimension at all" check.
    /// Skips the `nil`-salt racemic entry that isomer families now carry.
    var availableSaltForms: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for route in routes {
            for variant in route.saltForms ?? [] {
                if let salt = variant.saltForm, seen.insert(salt).inserted { ordered.append(salt) }
            }
        }
        return ordered
    }

    /// Salt forms available for a specific route, in stored order (default
    /// first). The salt picker is shown only when this has more than one entry.
    func saltForms(for route: RouteOfAdministration) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for variant in routes.first(where: { $0.route == route })?.saltForms ?? [] {
            if let salt = variant.saltForm, seen.insert(salt).inserted { ordered.append(salt) }
        }
        return ordered
    }

    /// The salt form selected by default — the default route's first salt form,
    /// falling back to any route's first form. `nil` when the substance has no
    /// salt dimension.
    var defaultSaltForm: String? {
        (routes.first { $0.route == defaultRoute } ?? routes.first)?
            .saltForms?.compactMap(\.saltForm).first
    }

    // MARK: - Isomer forms (Stage A)

    /// Distinct isomer codes across all routes (the racemic `nil` form is the
    /// default and is excluded). Drives the "does this substance have an isomer
    /// axis" check — empty for the overwhelming majority.
    var availableIsomers: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for route in routes {
            for variant in route.saltForms ?? [] {
                if let iso = variant.isomer, seen.insert(iso).inserted { ordered.append(iso) }
            }
        }
        return ordered
    }

    /// The named isomer options for a route — racemic first (titled with the
    /// substance's own name), then each resolved enantiomer titled with its
    /// recognized name ("Esketamine", "Armodafinil"). Empty when the route has
    /// no isomer axis; the isomer picker is shown only when this has >1 entry.
    /// `code == nil` is the racemic/unspecified selection.
    func isomerOptions(for route: RouteOfAdministration) -> [(code: String?, displayName: String)] {
        guard let variants = routes.first(where: { $0.route == route })?.saltForms,
              variants.contains(where: { $0.isomer != nil })
        else { return [] }
        var seenCodes = Set<String>()
        var sawRacemic = false
        var out: [(code: String?, displayName: String)] = []
        for variant in variants {
            if let iso = variant.isomer {
                guard seenCodes.insert(iso).inserted else { continue }
                out.append((iso, variant.isomerDisplayName ?? "\(name) (\(iso))"))
            } else if !sawRacemic {
                sawRacemic = true
                out.append((nil, name))
            }
        }
        return out
    }

    /// The recognized title for an isomer `code` across this substance's forms
    /// ("Dexmethylphenidate" for `"D"`, "Esketamine" for `"S"`), searched over
    /// every route; `nil` when the code names no known form. Used to snapshot a
    /// resolved form's display title onto a logged dose.
    func isomerDisplayName(for code: String) -> String? {
        for route in routes {
            if let variant = route.saltForms?.first(where: { $0.isomer == code }),
               let name = variant.isomerDisplayName {
                return name
            }
        }
        return nil
    }

    /// Default isomer selection for a route — racemic (`nil`) when the family
    /// has a racemic form, else the first resolved enantiomer. `nil` for
    /// substances with no isomer axis too (harmless — no picker is shown).
    func defaultIsomer(for route: RouteOfAdministration) -> String? {
        guard let variants = routes.first(where: { $0.route == route })?.saltForms,
              variants.contains(where: { $0.isomer != nil })
        else { return nil }
        if variants.contains(where: { $0.isomer == nil }) { return nil } // racemic is default
        return variants.first?.isomer
    }

    /// Dose ladder for a route, narrowed to a specific form (salt × isomer) when
    /// given and present. Falls back to the route's default (top-level) ladder
    /// when the form is `nil`/unspecified or not found — so form-unaware callers
    /// stay correct.
    func doseRange(
        for route: RouteOfAdministration, saltForm: String?, isomer: String? = nil,
    ) -> DoseRange? {
        guard let r = routes.first(where: { $0.route == route }) else { return nil }
        return doseVariant(for: route, saltForm: saltForm, isomer: isomer)?.doses ?? r.doses
    }

    /// Unit for a route, narrowed to a specific form when present (forms may
    /// differ: elemental mg vs compound mg). Falls back to the route/default unit.
    func unit(
        for route: RouteOfAdministration, saltForm: String?, isomer: String? = nil,
    ) -> String {
        guard let r = routes.first(where: { $0.route == route }) else { return defaultUnit }
        return doseVariant(for: route, saltForm: saltForm, isomer: isomer)?.unit ?? r.unit
    }

    /// Duration profile for a route, narrowed to a specific form when present.
    /// Falls back to the route's default duration.
    func duration(
        for route: RouteOfAdministration, saltForm: String?, isomer: String? = nil,
    ) -> DurationProfile? {
        guard let r = routes.first(where: { $0.route == route }) else { return nil }
        return doseVariant(for: route, saltForm: saltForm, isomer: isomer)?.duration ?? r.duration
    }

    /// Mass fraction of the elemental active for a salt form on a route (e.g.
    /// 0.14 for Magnesium glycinate). `nil` when unknown / not applicable.
    func elementalFraction(
        for route: RouteOfAdministration, saltForm: String?, isomer: String? = nil,
    ) -> Double? {
        guard saltForm != nil else { return nil }
        return doseVariant(for: route, saltForm: saltForm, isomer: isomer)?.elementalFraction
    }

    /// The amount of *elemental* active (e.g. elemental magnesium) in `amount`
    /// of the given salt form on a route — `amount × elementalFraction`. `nil`
    /// when the salt has no known elemental fraction (the common case), so the
    /// UI shows the breakdown only where it's meaningful (Magnesium, Lithium…).
    func elementalAmount(
        of amount: Double, for route: RouteOfAdministration, saltForm: String?, isomer: String? = nil,
    ) -> Double? {
        elementalFraction(for: route, saltForm: saltForm, isomer: isomer).map { amount * $0 }
    }

    /// Best available duration: exact route → similar route → generic fallback.
    /// Only falls back when a single route has duration data (implying it's generic).
    /// When multiple routes have distinct durations, returns nil rather than guessing.
    ///
    /// The salt/isomer overload exists because the timeline used to ignore both:
    /// the detail card picked the variant profile while the journal graph took the
    /// route's top-level one, so a D-isomer dose was drawn with the racemic curve —
    /// a visibly different length from the one the card had just shown for it.
    func resolveDuration(
        for route: RouteOfAdministration, saltForm: String?, isomer: String?,
    ) -> DurationProfile? {
        if let exact = duration(for: route, saltForm: saltForm, isomer: isomer) { return exact }
        return resolveDuration(for: route)
    }

    func resolveDuration(for route: RouteOfAdministration) -> DurationProfile? {
        if let exact = duration(for: route) { return exact }
        let routesWithDuration = routes.filter { $0.duration != nil }
        // Single route with data is likely generic — safe to use for any route
        if routesWithDuration.count == 1 { return routesWithDuration.first?.duration }
        return nil
    }

    /// The longest total duration any route claims, or `nil` when no route
    /// carries a duration profile at all (the chronic medications — SSRIs and
    /// friends — which have a half-life and no acute table).
    ///
    /// This is the number a "lasts beyond the duration shown" claim must clear.
    /// The **maximum** across routes rather than a resolved single route,
    /// because the reader is looking at a table of every route and would compare
    /// against the longest row in it; taking the max is also the conservative
    /// choice, since it makes such a claim harder to make rather than easier.
    var longestRouteDurationMinutes: Double? {
        routes.compactMap { $0.duration?.estimatedTotalMinutes }.max()
    }

    /// Longest total effect a dose can have and still be drawn as a timeline
    /// curve. Beyond this an "acute" onset→peak→offset shape is the wrong model:
    /// the effect outlasts any sane graph window, so the dose is a point-in-time
    /// marker instead. Matches the data pipeline's `duration_implausible`
    /// threshold (`pipeline/build/sqlite.py`).
    static let maxAcuteTimelineMinutes: Double = 24 * 60

    /// Duration to use when *drawing a dose on a timeline* (curve thumbnails, the
    /// day-detail graph, the active-session accessory) — `nil` means "don't draw
    /// a curve; render a marker instead."
    ///
    /// Returns `nil` for long-acting / maintenance compounds whose modeled
    /// effect exceeds ``maxAcuteTimelineMinutes`` (memantine, bupropion, SSRIs,
    /// GLP-1 agonists, depot injectables, vitamins, …). Their acute curve would
    /// be a flat line stretching the shared x-axis and crushing every real curve
    /// beside it. The decision is taken from the *actual* profile that would be
    /// drawn — so it's correct for custom substances and route-specific profiles
    /// that the precomputed `durationImplausible` flag can miss. Distinct from
    /// ``resolveDuration(for:)``, which returns the raw profile regardless.
    func timelineDuration(
        for route: RouteOfAdministration, saltForm: String? = nil, isomer: String? = nil,
    ) -> DurationProfile? {
        if let profile = resolveDuration(for: route, saltForm: saltForm, isomer: isomer),
           profile.estimatedTotalMinutes > 0,
           profile.estimatedTotalMinutes <= Self.maxAcuteTimelineMinutes {
            return profile
        }
        // The requested route has no usable acute profile, but the substance may
        // have one on another route. Borrowing it is far closer to reality than
        // falling through to a blood-half-life synthesis, whose elimination t½
        // can vastly outlast subjective effects — e.g. logging amphetamine
        // *rectal* (no profile) would otherwise synthesize a ~45 h curve from
        // its ~10 h t½, when the felt effect is the ~6–8 h oral curve. Synthesis
        // stays reserved for substances with no acute curve on any route.
        return representativeAcuteDuration()
    }

    /// A stand-in acute profile for routes that lack their own: the default
    /// route's profile when it's a sane acute curve, otherwise the shortest
    /// acute profile across all routes (the most conservative — least likely to
    /// overstate how long effects last). `nil` when no route has an acute curve.
    private func representativeAcuteDuration() -> DurationProfile? {
        func acute(_ profile: DurationProfile?) -> DurationProfile? {
            guard let profile, profile.estimatedTotalMinutes > 0,
                  profile.estimatedTotalMinutes <= Self.maxAcuteTimelineMinutes else { return nil }
            return profile
        }
        if let def = acute(duration(for: defaultRoute)) { return def }
        return routes.compactMap { acute($0.duration) }
            .min { $0.estimatedTotalMinutes < $1.estimatedTotalMinutes }
    }

    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        return name.lowercased().contains(q)
            || aliases.contains { $0.lowercased().contains(q) }
    }

    /// All routes ordered: substance-specific first, then remaining system routes.
    var orderedRoutes: [RouteOfAdministration] {
        let subRoutes = routes.map(\.route)
        let otherRoutes = RouteOfAdministration.allCases.filter { !subRoutes.contains($0) }
        return subRoutes + otherRoutes
    }
}

// MARK: - Substance Codable

extension Substance: Codable {
    enum CodingKeys: String, CodingKey {
        case name
        case displayName
        case aliases
        case category
        case defaultRoute
        case routes
        case effects
        case subjectiveEffects
        case toleranceInfo
        case halfLifeMinutes
        case sources
        case mechanismOfAction
        case tags
        case displayClass
        case regulatoryStatus
        case durationImplausible
        case indications
        case contraindications
        case diazepamEquivalent
        case substanceUID
        case cas
        case inchikey
        case formula
        case pubchemCID
        case popularity
        case isStub
        case molarMass
        case peptideProfile
        case references
        case drugCommunitySlug
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = try c.decode(String.self, forKey: .name)
        self.name = name
        // Deterministic from the canonical name (not persisted — `id` isn't a
        // coding key), so a decoded substance shares identity with its
        // resolver-built twin.
        id = Self.deterministicID(forName: name)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        aliases = try c.decode([String].self, forKey: .aliases)
        category = try c.decode(SubstanceCategory.self, forKey: .category)
        // Browse-only metadata loaded from the DB, never part of the serialized
        // Substance (export/import) — default to none on decode.
        extraBrowseCategories = []
        defaultRoute = try c.decode(RouteOfAdministration.self, forKey: .defaultRoute)
        routes = try c.decode([SubstanceRoute].self, forKey: .routes)
        effects = try c.decode([String].self, forKey: .effects)
        subjectiveEffects = try c.decodeIfPresent([SubjectiveEffect].self, forKey: .subjectiveEffects) ?? []
        toleranceInfo = try c.decodeIfPresent(ToleranceInfo.self, forKey: .toleranceInfo)
        halfLifeMinutes = try c.decodeIfPresent(Double.self, forKey: .halfLifeMinutes)
        sources = try c.decodeIfPresent([String].self, forKey: .sources) ?? []
        mechanismOfAction = try c.decodeIfPresent(MechanismOfAction.self, forKey: .mechanismOfAction)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        displayClass = try c.decodeIfPresent(CompoundDisplayClass.self, forKey: .displayClass) ?? .recreational
        regulatoryStatus = try c.decodeIfPresent(String.self, forKey: .regulatoryStatus)
        durationImplausible = try c.decodeIfPresent(Bool.self, forKey: .durationImplausible) ?? false
        indications = try c.decodeIfPresent([String].self, forKey: .indications) ?? []
        contraindications = try c.decodeIfPresent([Contraindication].self, forKey: .contraindications) ?? []
        diazepamEquivalent = try c.decodeIfPresent(DiazepamEquivalent.self, forKey: .diazepamEquivalent)
        substanceUID = try c.decodeIfPresent(String.self, forKey: .substanceUID)
        cas = try c.decodeIfPresent(String.self, forKey: .cas)
        inchikey = try c.decodeIfPresent(String.self, forKey: .inchikey)
        formula = try c.decodeIfPresent(String.self, forKey: .formula)
        pubchemCID = try c.decodeIfPresent(Int.self, forKey: .pubchemCID)
        popularity = try c.decodeIfPresent(Double.self, forKey: .popularity) ?? 0
        isStub = try c.decodeIfPresent(Bool.self, forKey: .isStub) ?? false
        molarMass = try c.decodeIfPresent(Double.self, forKey: .molarMass)
        peptideProfile = try c.decodeIfPresent(PeptideProfile.self, forKey: .peptideProfile)
        references = try c.decodeIfPresent([Citation].self, forKey: .references) ?? []
        drugCommunitySlug = try c.decodeIfPresent(String.self, forKey: .drugCommunitySlug)
        // Detail/browse-only metadata, never part of the serialized Substance.
        freeodwikiSlug = nil
        overview = nil
        smiles = nil
        iupacName = nil
        physicochemical = nil
        popularAliases = []
        misconceptions = []
        combinations = []
        waterHeat = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encode(aliases, forKey: .aliases)
        try c.encode(category, forKey: .category)
        try c.encode(defaultRoute, forKey: .defaultRoute)
        try c.encode(routes, forKey: .routes)
        try c.encode(effects, forKey: .effects)
        if !subjectiveEffects.isEmpty {
            try c.encode(subjectiveEffects, forKey: .subjectiveEffects)
        }
        try c.encodeIfPresent(toleranceInfo, forKey: .toleranceInfo)
        try c.encodeIfPresent(halfLifeMinutes, forKey: .halfLifeMinutes)
        if !sources.isEmpty {
            try c.encode(sources, forKey: .sources)
        }
        try c.encodeIfPresent(mechanismOfAction, forKey: .mechanismOfAction)
        if !tags.isEmpty {
            try c.encode(tags, forKey: .tags)
        }
        if displayClass != .recreational {
            try c.encode(displayClass, forKey: .displayClass)
        }
        try c.encodeIfPresent(regulatoryStatus, forKey: .regulatoryStatus)
        if durationImplausible {
            try c.encode(durationImplausible, forKey: .durationImplausible)
        }
        if !indications.isEmpty {
            try c.encode(indications, forKey: .indications)
        }
        if !contraindications.isEmpty {
            try c.encode(contraindications, forKey: .contraindications)
        }
        try c.encodeIfPresent(diazepamEquivalent, forKey: .diazepamEquivalent)
        try c.encodeIfPresent(substanceUID, forKey: .substanceUID)
        try c.encodeIfPresent(cas, forKey: .cas)
        try c.encodeIfPresent(inchikey, forKey: .inchikey)
        try c.encodeIfPresent(formula, forKey: .formula)
        try c.encodeIfPresent(pubchemCID, forKey: .pubchemCID)
        if popularity != 0 { try c.encode(popularity, forKey: .popularity) }
        if isStub { try c.encode(isStub, forKey: .isStub) }
        try c.encodeIfPresent(molarMass, forKey: .molarMass)
        if let peptideProfile, peptideProfile.hasAnyValue {
            try c.encode(peptideProfile, forKey: .peptideProfile)
        }
        if !references.isEmpty { try c.encode(references, forKey: .references) }
        try c.encodeIfPresent(drugCommunitySlug, forKey: .drugCommunitySlug)
    }
}

// MARK: - Hashable

extension Substance: Hashable {
    static func == (lhs: Substance, rhs: Substance) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension String {
    /// Whether the string contains any CJK Han character — used to push Chinese
    /// aliases to the end of "Also known as" in a non-Chinese UI.
    var containsHan: Bool {
        unicodeScalars.contains { (0x4E00 ... 0x9FFF).contains($0.value) }
    }
}
