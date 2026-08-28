import SwiftData
import SwiftUI

struct HelpView: View {
    @Query private var substanceColors: [SubstanceColor]
    @Query private var recentEntries: [DoseEntry]
    @Environment(\.appNavigator) private var navigator
    @State private var copiedSummary = false
    @State private var showShareSession = false
    @State private var activeSubstances: [ActiveSubstance] = []
    /// Resolved once per data change in `.task`, not on every `body` pass — the
    /// computation does a `SubstanceLibrary` (GRDB) lookup per recent dose.
    @State private var activeCategories: [SubstanceCategory] = []

    init() {
        let cutoff = Date.now.addingTimeInterval(-72 * 3_600)
        _recentEntries = Query(
            filter: #Predicate<DoseEntry> { $0.timestamp > cutoff },
            sort: \DoseEntry.timestamp,
            order: .reverse,
        )
    }

    private var last24hEntries: [DoseEntry] {
        let cutoff = Date.now.addingTimeInterval(-24 * 3_600)
        return recentEntries.filter { $0.timestamp > cutoff }
    }

    /// Recompute token: the dose-log revision plus the color assignments.
    private var refreshToken: Int {
        var hasher = Hasher()
        hasher.combine(DoseLogService.shared.revision)
        hasher.combine(ColorsFingerprint.make(substanceColors))
        return hasher.finalize()
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    reassuranceSection
                    emergencySection
                    if !activeSubstances.isEmpty {
                        activeSubstancesSection
                    }
                    if !activeCategories.isEmpty {
                        recoverySection
                    }
                    if !last24hEntries.isEmpty {
                        recentDosesSection
                    }
                    if !activeSubstances.isEmpty || !last24hEntries.isEmpty {
                        copySection
                    }
                }
                .listRowBackground(CardBackground())
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .sheet(isPresented: $showShareSession) {
                SessionShareSheet(
                    title: String(localized: "Current Session"),
                    dateText: Date.now.formatted(date: .abbreviated, time: .omitted),
                    entries: shareableEntries,
                    colors: substanceColors,
                    stackRedoses: true,
                )
            }
            .navigationTitle("Get Help")
            .task(id: refreshToken) {
                await SubstanceStore.shared.ensureAllLoaded()
                activeSubstances = ActiveSubstanceCalculator.compute(
                    from: recentEntries,
                    colorMap: substanceColors.colorMap,
                )
                activeCategories = ComedownGuideView.recentGuidedCategories(
                    in: recentEntries,
                    cutoff: Date.now.addingTimeInterval(-48 * 3_600),
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { navigator.dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Close"))
                }
            }
        }
    }

    // MARK: - Reassurance

    private var reassuranceSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)

                Text("You're going to be okay")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                Text("Whatever you're experiencing right now, help is available and you don't have to face it alone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("Take a deep breath.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)

            groundingTip(
                icon: "music.note",
                color: .purple,
                title: "Put on familiar music",
                detail: activeCategories.contains(.psychedelic)
                    ? "Music you know well is one of the most powerful grounding tools \u{2014} especially during a psychedelic experience."
                    : "Familiar songs can ground you and bring comfort. Pick something you know well.",
            )

            groundingTip(
                icon: "person.2.fill",
                color: .pink,
                title: "Call a friend or family member",
                detail: "Someone who knows you can help more than you\u{2019}d expect. You don\u{2019}t have to explain everything \u{2014} just hearing a familiar voice helps.",
            )
        }
    }

    // MARK: - Grounding Tips

    private func groundingTip(icon: String, color: Color, title: LocalizedStringResource, detail: LocalizedStringResource) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Recovery Guide

    private var recoverySection: some View {
        Section {
            ForEach(activeCategories, id: \.self) { category in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: category.icon)
                            .foregroundStyle(category.labelColor)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text(category.displayName)
                            .font(.subheadline.weight(.semibold))
                    }

                    let guide = ComedownGuideView.guide(for: category)
                    ForEach(Array(guide.rightNow.enumerated()), id: \.offset) { _, tip in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\u{2022}")
                                .foregroundStyle(Theme.secondaryLabel)
                            Text(tip)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            NavigationLink {
                ComedownGuideView()
            } label: {
                Label("View Full Recovery Guide", systemImage: "heart.text.clipboard")
                    .font(.subheadline)
            }
        } header: {
            Text("Recovery \u{2014} Right Now")
        } footer: {
            Text("Showing guidance for substances in your system. Tap above for the full guide.")
        }
    }

    // MARK: - Emergency Services

    private struct EmergencyService: Identifiable {
        let id = UUID()
        let title: LocalizedStringResource
        let detail: String
        let systemImage: String
        let url: String
        let tint: Color
    }

    private var regionCode: String {
        Locale.current.region?.identifier ?? "US"
    }

    private var regionName: String? {
        Locale.current.localizedString(forRegionCode: regionCode)
    }

    // swiftlint:disable:next function_body_length
    private var services: [EmergencyService] {
        switch regionCode {
        // Americas

        case "US":
            [
                .init(title: "Emergency Services", detail: "911", systemImage: "phone.fill", url: "tel:911", tint: .red),
                .init(title: "Suicide & Crisis Lifeline", detail: "988", systemImage: "phone.fill", url: "tel:988", tint: .blue),
                .init(title: "Poison Control", detail: "1-800-222-1222", systemImage: "phone.fill", url: "tel:18002221222", tint: .orange),
                .init(title: "SAMHSA Helpline", detail: "1-800-662-4357", systemImage: "phone.fill", url: "tel:18006624357", tint: .purple),
                .init(title: "Crisis Text Line", detail: "Text HOME to 741741", systemImage: "message.fill", url: "sms:741741&body=HOME", tint: .green),
            ]
        case "CA":
            [
                .init(title: "Emergency Services", detail: "911", systemImage: "phone.fill", url: "tel:911", tint: .red),
                .init(title: "Suicide Crisis Helpline", detail: "988", systemImage: "phone.fill", url: "tel:988", tint: .blue),
                .init(title: "Poison Centre", detail: "1-844-767-8187", systemImage: "phone.fill", url: "tel:18447678187", tint: .orange),
                .init(title: "Crisis Text Line", detail: "Text HOME to 686868", systemImage: "message.fill", url: "sms:686868&body=HOME", tint: .green),
            ]
        case "CO":
            [
                .init(title: "Linea de Emergencias", detail: "123", systemImage: "phone.fill", url: "tel:123", tint: .red),
                .init(title: "Linea de Crisis", detail: "106", systemImage: "phone.fill", url: "tel:106", tint: .blue),
            ]
        case "MX":
            [
                .init(title: "Servicios de Emergencia", detail: "911", systemImage: "phone.fill", url: "tel:911", tint: .red),
                .init(title: "Linea de la Vida", detail: "800-911-2000", systemImage: "phone.fill", url: "tel:8009112000", tint: .blue),
            ]
        case "BR":
            [
                .init(title: "SAMU", detail: "192", systemImage: "phone.fill", url: "tel:192", tint: .red),
                .init(title: "CVV (Centro de Valorização da Vida)", detail: "188", systemImage: "phone.fill", url: "tel:188", tint: .blue),
            ]
        case "AR":
            [
                .init(title: "Emergencias", detail: "107", systemImage: "phone.fill", url: "tel:107", tint: .red),
                .init(title: "Centro de Asistencia al Suicida", detail: "135", systemImage: "phone.fill", url: "tel:135", tint: .blue),
            ]
        case "CL":
            [
                .init(title: "Ambulancia", detail: "131", systemImage: "phone.fill", url: "tel:131", tint: .red),
                .init(title: "Salud Responde", detail: "600 360 7777", systemImage: "phone.fill", url: "tel:6003607777", tint: .blue),
            ]
        case "PE":
            [
                .init(title: "SAMU", detail: "106", systemImage: "phone.fill", url: "tel:106", tint: .red),
                .init(title: "Linea 113 Salud", detail: "113", systemImage: "phone.fill", url: "tel:113", tint: .blue),
            ]
        case "EC":
            [
                .init(title: "Emergencias (ECU 911)", detail: "911", systemImage: "phone.fill", url: "tel:911", tint: .red),
            ]
        case "VE":
            [
                .init(title: "Emergencias", detail: "171", systemImage: "phone.fill", url: "tel:171", tint: .red),
            ]
        case "UY":
            [
                .init(title: "Emergencias", detail: "911", systemImage: "phone.fill", url: "tel:911", tint: .red),
                .init(title: "Linea de Prevencion del Suicidio", detail: "0800 8483", systemImage: "phone.fill", url: "tel:08008483", tint: .blue),
            ]
        case "CR":
            [
                .init(title: "Emergencias", detail: "911", systemImage: "phone.fill", url: "tel:911", tint: .red),
            ]
        case "PA", "HN", "SV", "DO":
            [
                .init(title: "Emergencias", detail: "911", systemImage: "phone.fill", url: "tel:911", tint: .red),
            ]
        // Europe
        case "GB":
            [
                .init(title: "Emergency Services", detail: "999", systemImage: "phone.fill", url: "tel:999", tint: .red),
                .init(title: "Samaritans", detail: "116 123", systemImage: "phone.fill", url: "tel:116123", tint: .blue),
                .init(title: "FRANK Drug Helpline", detail: "0300 123 6600", systemImage: "phone.fill", url: "tel:03001236600", tint: .orange),
            ]
        case "IE":
            [
                .init(title: "Emergency Services", detail: "112 / 999", systemImage: "phone.fill", url: "tel:112", tint: .red),
                .init(title: "Samaritans", detail: "116 123", systemImage: "phone.fill", url: "tel:116123", tint: .blue),
                .init(title: "Pieta House", detail: "1800 247 247", systemImage: "phone.fill", url: "tel:1800247247", tint: .purple),
            ]
        case "DE":
            [
                .init(title: "Notruf", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .red),
                .init(title: "Telefonseelsorge", detail: "0800 111 0 111", systemImage: "phone.fill", url: "tel:08001110111", tint: .blue),
                .init(title: "Giftnotruf", detail: "030 19240", systemImage: "phone.fill", url: "tel:03019240", tint: .orange),
            ]
        case "AT":
            [
                .init(title: "Notruf", detail: "144", systemImage: "phone.fill", url: "tel:144", tint: .red),
                .init(title: "Telefonseelsorge", detail: "142", systemImage: "phone.fill", url: "tel:142", tint: .blue),
            ]
        case "CH":
            [
                .init(title: "Sanitatsnotruf", detail: "144", systemImage: "phone.fill", url: "tel:144", tint: .red),
                .init(title: "Die Dargebotene Hand", detail: "143", systemImage: "phone.fill", url: "tel:143", tint: .blue),
                .init(title: "Tox Info Suisse", detail: "145", systemImage: "phone.fill", url: "tel:145", tint: .orange),
            ]
        case "FR":
            [
                .init(title: "SAMU", detail: "15", systemImage: "phone.fill", url: "tel:15", tint: .red),
                .init(title: "SOS Amitie", detail: "09 72 39 40 50", systemImage: "phone.fill", url: "tel:0972394050", tint: .blue),
                .init(title: "Centre Antipoison", detail: "01 40 05 48 48", systemImage: "phone.fill", url: "tel:0140054848", tint: .orange),
            ]
        case "ES":
            [
                .init(title: "Emergencias", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .red),
                .init(title: "Telefono de la Esperanza", detail: "717 003 717", systemImage: "phone.fill", url: "tel:717003717", tint: .blue),
            ]
        case "PT":
            [
                .init(title: "Emergencias", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .red),
                .init(title: "SOS Voz Amiga", detail: "213 544 545", systemImage: "phone.fill", url: "tel:213544545", tint: .blue),
            ]
        case "IT":
            [
                .init(title: "Emergenze", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .red),
                .init(title: "Telefono Amico", detail: "02 2327 2327", systemImage: "phone.fill", url: "tel:0223272327", tint: .blue),
                .init(title: "Centro Antiveleni", detail: "02 6610 1029", systemImage: "phone.fill", url: "tel:0266101029", tint: .orange),
            ]
        case "NL":
            [
                .init(title: "Alarmnummer", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .red),
                .init(title: "113 Zelfmoordpreventie", detail: "0900 0113", systemImage: "phone.fill", url: "tel:09000113", tint: .blue),
            ]
        case "BE":
            [
                .init(title: "Urgences", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .red),
                .init(title: "Centre Antipoisons", detail: "070 245 245", systemImage: "phone.fill", url: "tel:070245245", tint: .orange),
            ]
        case "SE":
            [
                .init(title: "Nodnummer", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .red),
                .init(title: "Mind Sjalvmordslinjen", detail: "90101", systemImage: "phone.fill", url: "tel:90101", tint: .blue),
            ]
        case "NO":
            [
                .init(title: "Nodnummer", detail: "113", systemImage: "phone.fill", url: "tel:113", tint: .red),
                .init(title: "Mental Helse", detail: "116 123", systemImage: "phone.fill", url: "tel:116123", tint: .blue),
                .init(title: "Giftinformasjonen", detail: "22 59 13 00", systemImage: "phone.fill", url: "tel:22591300", tint: .orange),
            ]
        case "DK":
            [
                .init(title: "Nodnummer", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .red),
                .init(title: "Livslinien", detail: "70 201 201", systemImage: "phone.fill", url: "tel:70201201", tint: .blue),
            ]
        case "FI":
            [
                .init(title: "Hatanumero", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .red),
                .init(title: "Kriisipuhelin", detail: "09 2525 0111", systemImage: "phone.fill", url: "tel:0925250111", tint: .blue),
            ]
        case "PL":
            [
                .init(title: "Numer alarmowy", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .red),
                .init(title: "Telefon Zaufania", detail: "116 123", systemImage: "phone.fill", url: "tel:116123", tint: .blue),
            ]
        case "CZ":
            [
                .init(title: "Tisnovka", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .red),
                .init(title: "Linka bezpeci", detail: "116 111", systemImage: "phone.fill", url: "tel:116111", tint: .blue),
            ]
        case "GR":
            [
                .init(title: "EKAB", detail: "166", systemImage: "phone.fill", url: "tel:166", tint: .red),
                .init(title: "Klimaka Crisis Line", detail: "1018", systemImage: "phone.fill", url: "tel:1018", tint: .blue),
            ]
        case "RO", "HU", "HR", "BG", "SK", "SI", "LT", "LV", "EE", "CY", "LU", "MT":
            [
                .init(title: "Emergency", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .red),
            ]
        // Asia & Oceania
        case "AU":
            [
                .init(title: "Emergency Services", detail: "000", systemImage: "phone.fill", url: "tel:000", tint: .red),
                .init(title: "Lifeline", detail: "13 11 14", systemImage: "phone.fill", url: "tel:131114", tint: .blue),
                .init(title: "Poisons Information", detail: "13 11 26", systemImage: "phone.fill", url: "tel:131126", tint: .orange),
            ]
        case "NZ":
            [
                .init(title: "Emergency Services", detail: "111", systemImage: "phone.fill", url: "tel:111", tint: .red),
                .init(title: "Lifeline", detail: "0800 543 354", systemImage: "phone.fill", url: "tel:0800543354", tint: .blue),
                .init(title: "Poisons Centre", detail: "0800 764 766", systemImage: "phone.fill", url: "tel:0800764766", tint: .orange),
            ]
        case "JP":
            [
                .init(title: "Emergency (Ambulance)", detail: "119", systemImage: "phone.fill", url: "tel:119", tint: .red),
                .init(title: "Yorisoi Hotline", detail: "0120-279-338", systemImage: "phone.fill", url: "tel:0120279338", tint: .blue),
            ]
        case "KR":
            [
                .init(title: "Emergency (Ambulance)", detail: "119", systemImage: "phone.fill", url: "tel:119", tint: .red),
                .init(title: "Suicide Prevention Hotline", detail: "1393", systemImage: "phone.fill", url: "tel:1393", tint: .blue),
            ]
        case "CN":
            [
                .init(title: "Emergency (Ambulance)", detail: "120", systemImage: "phone.fill", url: "tel:120", tint: .red),
                .init(title: "Crisis Hotline", detail: "010-8295-1332", systemImage: "phone.fill", url: "tel:01082951332", tint: .blue),
            ]
        case "IN":
            [
                .init(title: "Emergency Services", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .red),
                .init(title: "Vandrevala Foundation", detail: "9999 666 555", systemImage: "phone.fill", url: "tel:9999666555", tint: .blue),
            ]
        case "PH":
            [
                .init(title: "Emergency Services", detail: "911", systemImage: "phone.fill", url: "tel:911", tint: .red),
                .init(title: "Crisis Line", detail: "0917-899-8727", systemImage: "phone.fill", url: "tel:09178998727", tint: .blue),
            ]
        case "SG":
            [
                .init(title: "Emergency (Ambulance)", detail: "995", systemImage: "phone.fill", url: "tel:995", tint: .red),
                .init(title: "Samaritans of Singapore", detail: "1-767", systemImage: "phone.fill", url: "tel:1767", tint: .blue),
            ]
        case "MY":
            [
                .init(title: "Emergency Services", detail: "999", systemImage: "phone.fill", url: "tel:999", tint: .red),
                .init(title: "Befrienders", detail: "03-7956 8145", systemImage: "phone.fill", url: "tel:0379568145", tint: .blue),
            ]
        case "TH":
            [
                .init(title: "Emergency (Ambulance)", detail: "1669", systemImage: "phone.fill", url: "tel:1669", tint: .red),
                .init(title: "Samaritans of Thailand", detail: "02-713-6793", systemImage: "phone.fill", url: "tel:027136793", tint: .blue),
            ]
        case "ID":
            [
                .init(title: "Emergency (Ambulance)", detail: "118", systemImage: "phone.fill", url: "tel:118", tint: .red),
            ]
        case "TW":
            [
                .init(title: "Emergency (Ambulance)", detail: "119", systemImage: "phone.fill", url: "tel:119", tint: .red),
                .init(title: "Suicide Prevention", detail: "1925", systemImage: "phone.fill", url: "tel:1925", tint: .blue),
            ]
        case "HK":
            [
                .init(title: "Emergency Services", detail: "999", systemImage: "phone.fill", url: "tel:999", tint: .red),
                .init(title: "Samaritans", detail: "2389 2222", systemImage: "phone.fill", url: "tel:23892222", tint: .blue),
            ]
        // Middle East & Africa
        case "IL":
            [
                .init(title: "Emergency (Ambulance)", detail: "101", systemImage: "phone.fill", url: "tel:101", tint: .red),
                .init(title: "ERAN Crisis Line", detail: "1201", systemImage: "phone.fill", url: "tel:1201", tint: .blue),
            ]
        case "TR":
            [
                .init(title: "Acil Yardim", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .red),
                .init(title: "Intihar Onleme Hatti", detail: "182", systemImage: "phone.fill", url: "tel:182", tint: .blue),
            ]
        case "AE":
            [
                .init(title: "Emergency (Ambulance)", detail: "998", systemImage: "phone.fill", url: "tel:998", tint: .red),
            ]
        case "SA":
            [
                .init(title: "Emergency (Ambulance)", detail: "997", systemImage: "phone.fill", url: "tel:997", tint: .red),
            ]
        case "ZA":
            [
                .init(title: "Emergency (Ambulance)", detail: "10177", systemImage: "phone.fill", url: "tel:10177", tint: .red),
                .init(title: "SADAG Crisis Line", detail: "0800 567 567", systemImage: "phone.fill", url: "tel:0800567567", tint: .blue),
            ]
        case "KE":
            [
                .init(title: "Emergency Services", detail: "999", systemImage: "phone.fill", url: "tel:999", tint: .red),
                .init(title: "Befrienders Kenya", detail: "0722 178 177", systemImage: "phone.fill", url: "tel:0722178177", tint: .blue),
            ]
        case "NG":
            [
                .init(title: "Emergency Services", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .red),
            ]
        case "EG":
            [
                .init(title: "Emergency (Ambulance)", detail: "123", systemImage: "phone.fill", url: "tel:123", tint: .red),
            ]
        case "RU":
            [
                .init(title: "Emergency Services", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .red),
                .init(title: "Psychological Help", detail: "8-800-2000-122", systemImage: "phone.fill", url: "tel:88002000122", tint: .blue),
            ]
        case "UA":
            [
                .init(title: "Emergency (Ambulance)", detail: "103", systemImage: "phone.fill", url: "tel:103", tint: .red),
                .init(title: "Lifeline Ukraine", detail: "7333", systemImage: "phone.fill", url: "tel:7333", tint: .blue),
            ]
        default:
            [
                .init(title: "Emergency Services", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .red),
            ]
        }
    }

    private var emergencySection: some View {
        Section {
            ForEach(services) { service in
                if let destination = URL(string: service.url) {
                    Link(destination: destination) {
                        HStack {
                            Image(systemName: service.systemImage)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(service.tint)
                                .frame(width: 28)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(service.title)
                                    .font(.subheadline.weight(.medium))
                                Text(service.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        } header: {
            if let name = regionName {
                Text("Emergency Services \u{2014} \(name)")
            } else {
                Text("Emergency Services")
            }
        }
    }

    // MARK: - Active Substances

    private var activeSubstancesSection: some View {
        Section {
            ForEach(activeSubstances) { substance in
                HStack(spacing: 10) {
                    Circle()
                        .fill(substance.color)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(substance.name)
                            .font(.subheadline.weight(.medium))
                        let remaining = Int((1 - substance.eliminatedFraction) * 100)
                        Text("\(substance.totalDosed.doseFormatted) \(substance.unit) total \u{00B7} est. ~\(remaining)% remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Currently In Your System")
        } footer: {
            Text("Estimates based on pharmacokinetic modeling. Actual levels may vary.")
        }
    }

    // MARK: - Recent Doses

    private func colorFor(_ entry: DoseEntry) -> Color {
        substanceColors.colorMap[entry.substance.lowercased()] ?? Theme.accent
    }

    private var recentDosesSection: some View {
        Section("Recent Doses (24h)") {
            ForEach(last24hEntries) { entry in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorFor(entry))
                        .frame(width: 4, height: 40)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(CustomSubstanceStore.shared.displayName(for: entry.substance))
                            .font(.subheadline.weight(.semibold))

                        HStack(spacing: 4) {
                            Text("\(entry.amount.doseFormatted) \(entry.unit)")
                            Middot()
                                .foregroundStyle(.tertiary)
                            Text(entry.route.localizedName)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(entry.timestamp, style: .time)
                            .font(.subheadline.weight(.medium))
                        Text(entry.timestamp, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Copy Summary

    private var copySection: some View {
        Section {
            Button {
                UIPasteboard.general.string = generateSummaryText()
                copiedSummary = true
                Task {
                    try? await Task.sleep(for: UITiming.copiedFlash)
                    copiedSummary = false
                }
            } label: {
                HStack {
                    Spacer()
                    Label(
                        copiedSummary ? "Copied" : "Copy Summary for Emergency Services",
                        systemImage: copiedSummary ? "checkmark.circle.fill" : "doc.on.doc",
                    )
                    .font(.subheadline.weight(.medium))
                    .animation(.none, value: copiedSummary)
                    Spacer()
                }
            }
            if !shareableEntries.isEmpty {
                Button {
                    showShareSession = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Share Current State…", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                }
            }
        } footer: {
            Text("Copies a plain-text summary of substances and recent doses to share with emergency responders.")
        }
    }

    /// Currently-active doses — the session a "Share Current State" hands off.
    private var shareableEntries: [DoseEntry] {
        InteractionChecker.activeEntries(from: recentEntries)
    }

    // MARK: - Summary Text Generation

    private func generateSummaryText() -> String {
        var lines: [String] = []
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        lines.append("SUBSTANCE SUMMARY")
        lines.append("Generated: \(formatter.string(from: .now))")
        lines.append("")

        if !activeSubstances.isEmpty {
            lines.append("CURRENTLY ACTIVE:")
            for substance in activeSubstances {
                let remaining = Int((1 - substance.eliminatedFraction) * 100)
                lines.append("- \(substance.name) — \(substance.totalDosed.doseFormatted) \(substance.unit) total (est. ~\(remaining)% remaining)")
                for dose in substance.doses {
                    lines.append("  \(dose.amount.doseFormatted) \(substance.unit) at \(formatter.string(from: dose.timestamp))")
                }
            }
            lines.append("")
        }

        let entries = last24hEntries
        if !entries.isEmpty {
            lines.append("RECENT DOSES (LAST 24 HOURS):")
            for entry in entries {
                // Lead with the canonical name — this is read by someone
                // treating the person, and a brand or a non-English alias isn't
                // always actionable. The user's own word follows when it
                // differs, so they can still recognize their own log. Raw
                // `entry.substance` was neither: it's whatever string was typed,
                // which may be an alias the catalog has since renamed.
                let canonical = SubstanceLibrary.lookup(entry.substance)?.displayTitle ?? entry.substance
                let logged = DoseTitle.resolve(for: entry)
                let name = logged.caseInsensitiveCompare(canonical) == .orderedSame
                    ? canonical
                    : "\(canonical) (logged as \(logged))"
                var line = "- \(name) \(entry.amount.doseFormatted) \(entry.unit) \(String(localized: entry.route.localizedName).lowercased()) — \(formatter.string(from: entry.timestamp))"
                if let notes = entry.notes, !notes.isEmpty {
                    line += " (\(notes))"
                }
                lines.append(line)
            }
        }

        if activeSubstances.isEmpty, entries.isEmpty {
            lines.append("No active substances or recent doses recorded.")
        }

        lines.append("")
        lines.append("Generated by Piru. Estimates are approximate.")
        return lines.joined(separator: "\n")
    }
}
