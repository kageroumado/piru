import SwiftUI

/// The emergency and crisis numbers each help surface lists for the user's region.
enum EmergencyServices {
    struct Service: Identifiable {
        let title: LocalizedStringResource
        let detail: String
        let systemImage: String
        let url: String
        let tint: Color

        /// A region lists each number once, so the link and its caption name the row.
        var id: String {
            "\(url) \(detail)"
        }
    }

    /// The region whose services every help surface lists.
    static var regionCode: String {
        Locale.current.region?.identifier ?? "US"
    }

    // swiftlint:disable:next function_body_length
    static func services(for regionCode: String) -> [Service] {
        switch regionCode {
        // Americas

        case "US":
            [
                .init(title: "Emergency Services", detail: "911", systemImage: "phone.fill", url: "tel:911", tint: .dangerAccent),
                .init(title: "Suicide & Crisis Lifeline", detail: "988", systemImage: "phone.fill", url: "tel:988", tint: .infoAccent),
                .init(title: "Poison Control", detail: "1-800-222-1222", systemImage: "phone.fill", url: "tel:18002221222", tint: .cautionAccent),
                .init(title: "SAMHSA Helpline", detail: "1-800-662-4357", systemImage: "phone.fill", url: "tel:18006624357", tint: .purple),
                .init(title: "Crisis Text Line", detail: "Text HOME to 741741", systemImage: "message.fill", url: "sms:741741&body=HOME", tint: Color.successAccent),
            ]
        case "CA":
            [
                .init(title: "Emergency Services", detail: "911", systemImage: "phone.fill", url: "tel:911", tint: .dangerAccent),
                .init(title: "Suicide Crisis Helpline", detail: "988", systemImage: "phone.fill", url: "tel:988", tint: .infoAccent),
                .init(title: "Poison Centre", detail: "1-844-764-7669", systemImage: "phone.fill", url: "tel:18447647669", tint: .cautionAccent),
                .init(title: "Kids Help Phone", detail: "Text CONNECT to 686868", systemImage: "message.fill", url: "sms:686868&body=CONNECT", tint: Color.successAccent),
            ]
        case "CO":
            [
                .init(title: "Línea de Emergencias", detail: "123", systemImage: "phone.fill", url: "tel:123", tint: .dangerAccent),
                .init(title: "Línea de Salud Mental", detail: "106", systemImage: "phone.fill", url: "tel:106", tint: .infoAccent),
            ]
        case "MX":
            [
                .init(title: "Servicios de Emergencia", detail: "911", systemImage: "phone.fill", url: "tel:911", tint: .dangerAccent),
                .init(title: "Línea de la Vida", detail: "800-911-2000", systemImage: "phone.fill", url: "tel:8009112000", tint: .infoAccent),
            ]
        case "BR":
            [
                .init(title: "SAMU", detail: "192", systemImage: "phone.fill", url: "tel:192", tint: .dangerAccent),
                .init(title: "CVV (Centro de Valorização da Vida)", detail: "188", systemImage: "phone.fill", url: "tel:188", tint: .infoAccent),
            ]
        case "AR":
            [
                .init(title: "Emergencias", detail: "911", systemImage: "phone.fill", url: "tel:911", tint: .dangerAccent),
                .init(title: "Línea de Salud Mental", detail: "0800-999-0091", systemImage: "phone.fill", url: "tel:08009990091", tint: .infoAccent),
            ]
        case "CL":
            [
                .init(title: "Ambulancia", detail: "131", systemImage: "phone.fill", url: "tel:131", tint: .dangerAccent),
                .init(title: "Salud Responde", detail: "600 360 7777", systemImage: "phone.fill", url: "tel:6003607777", tint: .infoAccent),
            ]
        case "PE":
            [
                .init(title: "SAMU", detail: "106", systemImage: "phone.fill", url: "tel:106", tint: .dangerAccent),
                .init(title: "Línea 113 Salud", detail: "113", systemImage: "phone.fill", url: "tel:113", tint: .infoAccent),
            ]
        case "EC":
            [
                .init(title: "Emergencias (ECU 911)", detail: "911", systemImage: "phone.fill", url: "tel:911", tint: .dangerAccent),
            ]
        case "VE":
            [
                .init(title: "Emergencias", detail: "911", systemImage: "phone.fill", url: "tel:911", tint: .dangerAccent),
            ]
        case "UY":
            [
                .init(title: "Emergencias", detail: "911", systemImage: "phone.fill", url: "tel:911", tint: .dangerAccent),
                .init(title: "Línea Vida", detail: "0800 0767", systemImage: "phone.fill", url: "tel:08000767", tint: .infoAccent),
            ]
        case "CR":
            [
                .init(title: "Emergencias", detail: "911", systemImage: "phone.fill", url: "tel:911", tint: .dangerAccent),
            ]
        case "PA", "HN", "SV", "DO":
            [
                .init(title: "Emergencias", detail: "911", systemImage: "phone.fill", url: "tel:911", tint: .dangerAccent),
            ]
        // Europe
        case "GB":
            [
                .init(title: "Emergency Services", detail: "999", systemImage: "phone.fill", url: "tel:999", tint: .dangerAccent),
                .init(title: "Samaritans", detail: "116 123", systemImage: "phone.fill", url: "tel:116123", tint: .infoAccent),
                .init(title: "FRANK Drug Helpline", detail: "0300 123 6600", systemImage: "phone.fill", url: "tel:03001236600", tint: .cautionAccent),
            ]
        case "IE":
            [
                .init(title: "Emergency Services", detail: "112 / 999", systemImage: "phone.fill", url: "tel:112", tint: .dangerAccent),
                .init(title: "Samaritans", detail: "116 123", systemImage: "phone.fill", url: "tel:116123", tint: .infoAccent),
                .init(title: "Pieta", detail: "1800 247 247", systemImage: "phone.fill", url: "tel:1800247247", tint: .purple),
            ]
        case "DE":
            [
                .init(title: "Notruf", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .dangerAccent),
                .init(title: "Telefonseelsorge", detail: "0800 111 0 111", systemImage: "phone.fill", url: "tel:08001110111", tint: .infoAccent),
                .init(title: "Giftnotruf Berlin", detail: "030 19240", systemImage: "phone.fill", url: "tel:03019240", tint: .cautionAccent),
            ]
        case "AT":
            [
                .init(title: "Notruf", detail: "144", systemImage: "phone.fill", url: "tel:144", tint: .dangerAccent),
                .init(title: "Telefonseelsorge", detail: "142", systemImage: "phone.fill", url: "tel:142", tint: .infoAccent),
                .init(title: "Vergiftungsinformationszentrale", detail: "01 406 43 43", systemImage: "phone.fill", url: "tel:014064343", tint: .cautionAccent),
            ]
        case "CH":
            [
                .init(title: "Sanitätsnotruf", detail: "144", systemImage: "phone.fill", url: "tel:144", tint: .dangerAccent),
                .init(title: "Die Dargebotene Hand", detail: "143", systemImage: "phone.fill", url: "tel:143", tint: .infoAccent),
                .init(title: "Tox Info Suisse", detail: "145", systemImage: "phone.fill", url: "tel:145", tint: .cautionAccent),
            ]
        case "FR":
            [
                .init(title: "SAMU", detail: "15", systemImage: "phone.fill", url: "tel:15", tint: .dangerAccent),
                .init(title: "Prévention du suicide", detail: "3114", systemImage: "phone.fill", url: "tel:3114", tint: .infoAccent),
                .init(title: "SOS Amitié", detail: "09 72 39 40 50", systemImage: "phone.fill", url: "tel:0972394050", tint: .purple),
                .init(title: "Centre Antipoison de Paris", detail: "01 40 05 48 48", systemImage: "phone.fill", url: "tel:0140054848", tint: .cautionAccent),
            ]
        case "ES":
            [
                .init(title: "Emergencias", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .dangerAccent),
                .init(title: "Línea 024", detail: "024", systemImage: "phone.fill", url: "tel:024", tint: .infoAccent),
                .init(title: "Teléfono de la Esperanza", detail: "717 003 717", systemImage: "phone.fill", url: "tel:717003717", tint: .purple),
                .init(title: "Información Toxicológica", detail: "91 562 04 20", systemImage: "phone.fill", url: "tel:915620420", tint: .cautionAccent),
            ]
        case "PT":
            [
                .init(title: "Emergências", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .dangerAccent),
                .init(title: "SOS Voz Amiga", detail: "213 544 545", systemImage: "phone.fill", url: "tel:213544545", tint: .infoAccent),
                .init(title: "Centro de Informação Antivenenos", detail: "800 250 250", systemImage: "phone.fill", url: "tel:800250250", tint: .cautionAccent),
            ]
        case "IT":
            [
                .init(title: "Emergenze", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .dangerAccent),
                .init(title: "Telefono Amico", detail: "02 2327 2327", systemImage: "phone.fill", url: "tel:0223272327", tint: .infoAccent),
                .init(title: "Centro Antiveleni", detail: "02 6610 1029", systemImage: "phone.fill", url: "tel:0266101029", tint: .cautionAccent),
            ]
        case "NL":
            [
                .init(title: "Alarmnummer", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .dangerAccent),
                .init(title: "113 Zelfmoordpreventie", detail: "0800-0113", systemImage: "phone.fill", url: "tel:08000113", tint: .infoAccent),
            ]
        case "BE":
            [
                .init(title: "Urgences", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .dangerAccent),
                .init(title: "Zelfmoordlijn 1813", detail: "1813", systemImage: "phone.fill", url: "tel:1813", tint: .infoAccent),
                .init(title: "Centre de Prévention du Suicide", detail: "0800 32 123", systemImage: "phone.fill", url: "tel:080032123", tint: .purple),
                .init(title: "Centre Antipoisons", detail: "070 245 245", systemImage: "phone.fill", url: "tel:070245245", tint: .cautionAccent),
            ]
        case "SE":
            [
                .init(title: "Nödnummer", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .dangerAccent),
                .init(title: "Mind Självmordslinjen", detail: "90101", systemImage: "phone.fill", url: "tel:90101", tint: .infoAccent),
                .init(title: "Giftinformationscentralen", detail: "010-456 67 00", systemImage: "phone.fill", url: "tel:0104566700", tint: .cautionAccent),
            ]
        case "NO":
            [
                .init(title: "Medisinsk nødnummer", detail: "113", systemImage: "phone.fill", url: "tel:113", tint: .dangerAccent),
                .init(title: "Mental Helse", detail: "116 123", systemImage: "phone.fill", url: "tel:116123", tint: .infoAccent),
                .init(title: "Giftinformasjonen", detail: "22 59 13 00", systemImage: "phone.fill", url: "tel:22591300", tint: .cautionAccent),
            ]
        case "DK":
            [
                .init(title: "Nødnummer", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .dangerAccent),
                .init(title: "Livslinien", detail: "70 201 201", systemImage: "phone.fill", url: "tel:70201201", tint: .infoAccent),
                .init(title: "Giftlinjen", detail: "82 12 12 12", systemImage: "phone.fill", url: "tel:82121212", tint: .cautionAccent),
            ]
        case "FI":
            [
                .init(title: "Hätänumero", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .dangerAccent),
                .init(title: "MIELI Kriisipuhelin", detail: "09 2525 0111", systemImage: "phone.fill", url: "tel:0925250111", tint: .infoAccent),
                .init(title: "Myrkytystietokeskus", detail: "0800 147 111", systemImage: "phone.fill", url: "tel:0800147111", tint: .cautionAccent),
            ]
        case "PL":
            [
                .init(title: "Numer alarmowy", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .dangerAccent),
                .init(title: "Telefon Zaufania", detail: "116 123", systemImage: "phone.fill", url: "tel:116123", tint: .infoAccent),
            ]
        case "CZ":
            [
                .init(title: "Tísňová linka", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .dangerAccent),
                .init(title: "Linka první psychické pomoci", detail: "116 123", systemImage: "phone.fill", url: "tel:116123", tint: .infoAccent),
                .init(title: "Toxikologické informační středisko", detail: "224 91 92 93", systemImage: "phone.fill", url: "tel:224919293", tint: .cautionAccent),
            ]
        case "GR":
            [
                .init(title: "EKAB", detail: "166", systemImage: "phone.fill", url: "tel:166", tint: .dangerAccent),
                .init(title: "Klimaka Crisis Line", detail: "1018", systemImage: "phone.fill", url: "tel:1018", tint: .infoAccent),
                .init(title: "Κέντρο Δηλητηριάσεων", detail: "210 77 93 777", systemImage: "phone.fill", url: "tel:2107793777", tint: .cautionAccent),
            ]
        case "RO", "HU", "HR", "BG", "SK", "SI", "LT", "LV", "EE", "CY", "LU", "MT":
            [
                .init(title: "Emergency", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .dangerAccent),
            ]
        // Asia & Oceania
        case "AU":
            [
                .init(title: "Emergency Services", detail: "000", systemImage: "phone.fill", url: "tel:000", tint: .dangerAccent),
                .init(title: "Lifeline", detail: "13 11 14", systemImage: "phone.fill", url: "tel:131114", tint: .infoAccent),
                .init(title: "Poisons Information", detail: "13 11 26", systemImage: "phone.fill", url: "tel:131126", tint: .cautionAccent),
            ]
        case "NZ":
            [
                .init(title: "Emergency Services", detail: "111", systemImage: "phone.fill", url: "tel:111", tint: .dangerAccent),
                .init(title: "1737 Need to Talk?", detail: "1737", systemImage: "phone.fill", url: "tel:1737", tint: .infoAccent),
                .init(title: "Lifeline", detail: "0800 543 354", systemImage: "phone.fill", url: "tel:0800543354", tint: .purple),
                .init(title: "Poisons Centre", detail: "0800 764 766", systemImage: "phone.fill", url: "tel:0800764766", tint: .cautionAccent),
            ]
        case "JP":
            [
                .init(title: "Emergency (Ambulance)", detail: "119", systemImage: "phone.fill", url: "tel:119", tint: .dangerAccent),
                .init(title: "Yorisoi Hotline", detail: "0120-279-338", systemImage: "phone.fill", url: "tel:0120279338", tint: .infoAccent),
                .init(title: "Poison Control", detail: "072-727-2499", systemImage: "phone.fill", url: "tel:0727272499", tint: .cautionAccent),
            ]
        case "KR":
            [
                .init(title: "Emergency (Ambulance)", detail: "119", systemImage: "phone.fill", url: "tel:119", tint: .dangerAccent),
                .init(title: "Suicide Prevention Hotline", detail: "109", systemImage: "phone.fill", url: "tel:109", tint: .infoAccent),
            ]
        case "CN":
            [
                .init(title: "Emergency (Ambulance)", detail: "120", systemImage: "phone.fill", url: "tel:120", tint: .dangerAccent),
                .init(title: "Crisis Hotline", detail: "12356", systemImage: "phone.fill", url: "tel:12356", tint: .infoAccent),
            ]
        case "IN":
            [
                .init(title: "Emergency Services", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .dangerAccent),
                .init(title: "Tele-MANAS", detail: "14416", systemImage: "phone.fill", url: "tel:14416", tint: .infoAccent),
                .init(title: "Vandrevala Foundation", detail: "9999 666 555", systemImage: "phone.fill", url: "tel:9999666555", tint: .purple),
                .init(title: "Poison Control", detail: "1800-116-117", systemImage: "phone.fill", url: "tel:1800116117", tint: .cautionAccent),
            ]
        case "PH":
            [
                .init(title: "Emergency Services", detail: "911", systemImage: "phone.fill", url: "tel:911", tint: .dangerAccent),
                .init(title: "NCMH Crisis Hotline", detail: "0917-899-8727", systemImage: "phone.fill", url: "tel:09178998727", tint: .infoAccent),
            ]
        case "SG":
            [
                .init(title: "Emergency (Ambulance)", detail: "995", systemImage: "phone.fill", url: "tel:995", tint: .dangerAccent),
                .init(title: "Samaritans of Singapore", detail: "1-767", systemImage: "phone.fill", url: "tel:1767", tint: .infoAccent),
            ]
        case "MY":
            [
                .init(title: "Emergency Services", detail: "999", systemImage: "phone.fill", url: "tel:999", tint: .dangerAccent),
                .init(title: "Befrienders", detail: "03-7627 2929", systemImage: "phone.fill", url: "tel:0376272929", tint: .infoAccent),
            ]
        case "TH":
            [
                .init(title: "Emergency (Ambulance)", detail: "1669", systemImage: "phone.fill", url: "tel:1669", tint: .dangerAccent),
                .init(title: "Mental Health Hotline", detail: "1323", systemImage: "phone.fill", url: "tel:1323", tint: .infoAccent),
                .init(title: "Samaritans of Thailand", detail: "02-113-6789", systemImage: "phone.fill", url: "tel:021136789", tint: .purple),
            ]
        case "ID":
            [
                .init(title: "Emergency (Ambulance)", detail: "119", systemImage: "phone.fill", url: "tel:119", tint: .dangerAccent),
            ]
        case "TW":
            [
                .init(title: "Emergency (Ambulance)", detail: "119", systemImage: "phone.fill", url: "tel:119", tint: .dangerAccent),
                .init(title: "Suicide Prevention", detail: "1925", systemImage: "phone.fill", url: "tel:1925", tint: .infoAccent),
            ]
        case "HK":
            [
                .init(title: "Emergency Services", detail: "999", systemImage: "phone.fill", url: "tel:999", tint: .dangerAccent),
                .init(title: "Samaritan Befrienders Hong Kong", detail: "2389 2222", systemImage: "phone.fill", url: "tel:23892222", tint: .infoAccent),
            ]
        // Middle East & Africa
        case "IL":
            [
                .init(title: "Emergency (Ambulance)", detail: "101", systemImage: "phone.fill", url: "tel:101", tint: .dangerAccent),
                .init(title: "ERAN Crisis Line", detail: "1201", systemImage: "phone.fill", url: "tel:1201", tint: .infoAccent),
            ]
        case "TR":
            [
                .init(title: "Acil Yardım", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .dangerAccent),
                .init(title: "Ulusal Zehir Danışma Merkezi", detail: "114", systemImage: "phone.fill", url: "tel:114", tint: .cautionAccent),
            ]
        case "AE":
            [
                .init(title: "Emergency (Ambulance)", detail: "998", systemImage: "phone.fill", url: "tel:998", tint: .dangerAccent),
            ]
        case "SA":
            [
                .init(title: "Emergency (Ambulance)", detail: "997", systemImage: "phone.fill", url: "tel:997", tint: .dangerAccent),
            ]
        case "ZA":
            [
                .init(title: "Emergency (Ambulance)", detail: "10177", systemImage: "phone.fill", url: "tel:10177", tint: .dangerAccent),
                .init(title: "SADAG Crisis Line", detail: "0800 567 567", systemImage: "phone.fill", url: "tel:0800567567", tint: .infoAccent),
                .init(title: "Poisons Information", detail: "0861 555 777", systemImage: "phone.fill", url: "tel:0861555777", tint: .cautionAccent),
            ]
        case "KE":
            [
                .init(title: "Emergency Services", detail: "999", systemImage: "phone.fill", url: "tel:999", tint: .dangerAccent),
                .init(title: "Befrienders Kenya", detail: "0722 178 177", systemImage: "phone.fill", url: "tel:0722178177", tint: .infoAccent),
            ]
        case "NG":
            [
                .init(title: "Emergency Services", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .dangerAccent),
            ]
        case "EG":
            [
                .init(title: "Emergency (Ambulance)", detail: "123", systemImage: "phone.fill", url: "tel:123", tint: .dangerAccent),
            ]
        case "RU":
            [
                .init(title: "Emergency Services", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .dangerAccent),
                .init(title: "Psychological Help", detail: "+7 495 989-50-50", systemImage: "phone.fill", url: "tel:+74959895050", tint: .infoAccent),
            ]
        case "UA":
            [
                .init(title: "Emergency (Ambulance)", detail: "103", systemImage: "phone.fill", url: "tel:103", tint: .dangerAccent),
            ]
        default:
            [
                .init(title: "Emergency Services", detail: "112", systemImage: "phone.fill", url: "tel:112", tint: .dangerAccent),
            ]
        }
    }
}
