import Foundation

/// Scrapes PIHKAL and TIHKAL Part 2 from Erowid. Each book has a per-compound
/// HTML page at a stable URL pattern:
///
///   https://erowid.org/library/books_online/pihkal/pihkalNNN.shtml   (001–179)
///   https://erowid.org/library/books_online/tihkal/tihkalNNN.shtml   (001–055)
///
/// We parse the DOSAGE and DURATION sections out of the HTML, plus the
/// compound name from the page heading. The text used is "with permission" per
/// the notice on https://erowid.org/library/books_online/pihkal/pihkal.shtml
/// and we surface that permission line in every output entry's `sources`.
struct ErowidSource {
    let cache: HTTPCache

    private static let pihkalAttribution =
        "PIHKAL by Alexander & Ann Shulgin (Transform Press, 1991) — text used with permission per https://erowid.org/library/books_online/pihkal/pihkal.shtml"
    private static let tihkalAttribution =
        "TIHKAL by Alexander & Ann Shulgin (Transform Press, 1997) — text used with permission per https://erowid.org/library/books_online/tihkal/tihkal.shtml"

    enum Book {
        case pihkal
        case tihkal
        var dirName: String {
            self == .pihkal ? "pihkal" : "tihkal"
        }
        var maxIndex: Int {
            self == .pihkal ? 179 : 55
        }
        /// PIHKAL uses 3-digit zero-padded filenames; TIHKAL uses 2-digit.
        var padWidth: Int {
            self == .pihkal ? 3 : 2
        }
        var tag: String {
            self == .pihkal ? "PIHKAL" : "TIHKAL"
        }
        var attribution: String {
            self == .pihkal ? pihkalAttribution : tihkalAttribution
        }
        var category: String {
            // PIHKAL = phenethylamines, mostly psychedelics. TIHKAL =
            // tryptamines + a handful of monoamine modulators.
            self == .pihkal ? "Psychedelic" : "Psychedelic"
        }
        var familyTag: String {
            self == .pihkal ? "phenethylamine" : "tryptamine"
        }
    }

    func fetchAll() async -> [SourcedSubstance] {
        var out: [SourcedSubstance] = []
        for book in [Book.pihkal, Book.tihkal] {
            let bookStart = out.count
            for i in 1 ... book.maxIndex {
                let idx = String(format: "%0\(book.padWidth)d", i)
                let url = URL(string: "https://erowid.org/library/books_online/\(book.dirName)/\(book.dirName)\(idx).shtml")!
                do {
                    guard let data = try await cache.fetchOptional(url: url, scope: "erowid-\(book.dirName)") else {
                        continue
                    }
                    guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                        continue
                    }
                    if let s = parse(html: html, url: url, book: book) {
                        out.append(s)
                    }
                } catch {
                    Log.warn("Erowid \(book.dirName)\(idx): \(error.localizedDescription)")
                }
            }
            Log.info("Erowid[\(book.dirName)]: \(out.count - bookStart) entries (\(out.count) total)")
        }
        Log.info("Erowid: \(out.count) total Shulgin entries")
        return out
    }

    // MARK: - HTML parsing

    /// Pull DOSAGE and DURATION from the entry HTML. Erowid uses consistent
    /// markup: `<font color="red">#NNN <b>NAME</b></font>` for the heading,
    /// and `DOSAGE:` / `DURATION:` markers as plain text inside `<p>` blocks.
    private func parse(html: String, url: URL, book: Book) -> SourcedSubstance? {
        let plain = stripHTML(html)
        guard let name = extractName(plain) else { return nil }

        let dosageText = extractSection(plain, label: "DOSAGE")
        let durationText = extractSection(plain, label: "DURATION")
        let qualText = extractSection(plain, label: "QUALITATIVE COMMENTS")

        var routes: [JSONRoute] = []
        if let d = dosageText {
            let (dose, route, unit) = parseDosage(d)
            let duration = durationText.flatMap { parseDuration($0) }
            if !dose.isEmpty || duration != nil {
                routes.append(JSONRoute(
                    route: route, unit: unit, doses: dose, duration: duration,
                ))
            }
        }

        // Effects: short snippet of qualitative comments if present.
        var effects: [String] = []
        if let qual = qualText, !qual.isEmpty {
            effects.append(String(qual.prefix(280)).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var tags = Tagger.tags(for: name)
        tags.append(book.tag)
        tags.append(book.familyTag)
        if routes.first(where: { !$0.doses.isEmpty }) == nil {
            tags.append("no-human-data")
        }
        tags = Tagger.merge(tags)

        let warnings = SafetyWarnings.warnings(for: name, tags: tags)
        effects.append(contentsOf: warnings)

        let category = CategoryMapper.overrideForName(name) ?? book.category

        return SourcedSubstance(
            substance: BundledSubstance(
                name: name,
                aliases: [],
                category: category,
                defaultRoute: routes.first?.route ?? "oral",
                routes: routes,
                effects: effects,
                halfLifeMinutes: nil,
                sources: [
                    url.absoluteString,
                    book.attribution,
                ],
                tags: tags,
            ),
            provenance: book == .pihkal ? .erowidPIHKAL : .erowidTIHKAL,
            inchiKey: nil, pubchemCID: nil, cas: nil,
        )
    }

    private func stripHTML(_ html: String) -> String {
        var s = html
        // Replace <br> / </p> / </div> / </tr> with newlines so the section
        // headers come out on their own lines.
        let breakTags = ["<br>", "<br/>", "<br />", "</p>", "</div>", "</tr>"]
        for t in breakTags {
            s = s.replacingOccurrences(of: t, with: "\n", options: .caseInsensitive)
        }
        // Strip remaining tags.
        if let re = try? NSRegularExpression(pattern: "<[^>]+>") {
            let r = NSRange(s.startIndex ..< s.endIndex, in: s)
            s = re.stringByReplacingMatches(in: s, range: r, withTemplate: " ")
        }
        // Decode common HTML entities.
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&mdash;", "—"), ("&ndash;", "–"),
            ("&plusmn;", "±"), ("&micro;", "µ"), ("&hellip;", "…"),
        ]
        for (k, v) in entities {
            s = s.replacingOccurrences(of: k, with: v)
        }
        // Collapse whitespace within each line.
        let lines = s.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "  ", with: " ")
        }
        return lines.joined(separator: "\n")
    }

    /// Pull the compound name from the page. Erowid pages use heading patterns
    /// like `#7 2C-B` (PIHKAL) or `#30. 4,5-MDO-DMT` (TIHKAL — note the dot).
    /// We accept either form.
    private func extractName(_ plain: String) -> String? {
        let lines = plain.components(separatedBy: .newlines)
        let pat = try! NSRegularExpression(pattern: #"^\s*#\s*(\d+)\.?\s+(.+?)\s*$"#)
        for line in lines {
            let r = NSRange(line.startIndex ..< line.endIndex, in: line)
            if let m = pat.firstMatch(in: line, range: r),
               let nameRange = Range(m.range(at: 2), in: line) {
                let raw = String(line[nameRange])
                    .replacingOccurrences(of: "  ", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Strip trailing parenthetical (some pages have synonyms in parens).
                if let paren = raw.firstIndex(of: "(") {
                    return String(raw[..<paren]).trimmingCharacters(in: .whitespaces)
                }
                return raw
            }
        }
        return nil
    }

    /// Pull the text between `LABEL[ ]*:` and the next bold header line. TIHKAL
    /// inserts extra spaces, e.g. `DOSAGE  : unknown`.
    private func extractSection(_ plain: String, label: String) -> String? {
        let lines = plain.components(separatedBy: .newlines)
        let upperLabel = label.uppercased()
        // Match `LABEL` then any amount of whitespace then `:`. Anchor at the
        // start so we don't match `EFFECTIVE DOSAGE:` or similar.
        let headerPattern = try! NSRegularExpression(
            pattern: "^" + NSRegularExpression.escapedPattern(for: upperLabel) + #"\s*:"#,
        )
        var collecting = false
        var captured: [String] = []
        for line in lines {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if !collecting {
                let r = NSRange(stripped.startIndex ..< stripped.endIndex, in: stripped)
                if let m = headerPattern.firstMatch(in: stripped, range: r) {
                    collecting = true
                    let upper = m.range.upperBound
                    if let range = Range(NSRange(location: upper, length: stripped.utf16.count - upper), in: stripped) {
                        let after = String(stripped[range]).trimmingCharacters(in: .whitespaces)
                        if !after.isEmpty { captured.append(after) }
                    }
                    continue
                }
            } else {
                // Stop when we hit another all-caps section header.
                if stripped.range(of: #"^[A-Z][A-Z ,/&-]{2,}\s*:"#, options: .regularExpression) != nil {
                    break
                }
                if stripped.isEmpty, !captured.isEmpty { break }
                if !stripped.isEmpty { captured.append(stripped) }
            }
        }
        let text = captured.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.lowercased() == "unknown" { return nil }
        return text
    }

    /// Parse text like "20 - 40 mg" or "8 mg, orally" or "150 mg" into a
    /// `JSONDoseRange`. Returns (dose, route, unit). Default route is oral
    /// since Shulgin almost always specifies it explicitly only when not.
    private func parseDosage(_ text: String) -> (JSONDoseRange, String, String) {
        var route = "oral"
        let lower = text.lowercased()
        if lower.contains("smoked") || lower.contains("inhalation") { route = "inhalation" }
        else if lower.contains("intravenous") || lower.contains("iv ") { route = "intravenous" }
        else if lower.contains("intramuscular") || lower.contains("im ") { route = "intramuscular" }
        else if lower.contains("sublingual") { route = "sublingual" }
        else if lower.contains("insufflated") || lower.contains("intranasal") { route = "insufflation" }

        var dose = JSONDoseRange()
        var unit = "mg"
        if let parsed = DoseParser.parse(text) {
            unit = parsed.unit
            if let hi = parsed.max {
                dose.common = JSONRange(parsed.min, hi)
            } else {
                // Single value → treat as common midpoint with ±25% spread so
                // the iOS UI shows a usable level indicator.
                let lo = parsed.min * 0.75
                let high = parsed.min * 1.25
                dose.common = JSONRange(lo, high)
            }
        }
        return (dose, route, unit)
    }

    /// "8 - 12 h" → onset/total duration approximations.
    private func parseDuration(_ text: String) -> JSONDurationProfile? {
        let re = try! NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)\s*(?:[-–]\s*([0-9]+(?:\.[0-9]+)?))?\s*(h|hr|hour|min|minutes|m)"#, options: .caseInsensitive)
        let r = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let m = re.firstMatch(in: text, range: r),
              let r0 = Range(m.range(at: 1), in: text),
              let lo = Double(text[r0]) else { return nil }
        var hi = lo
        if m.range(at: 2).location != NSNotFound, let r1 = Range(m.range(at: 2), in: text), let v = Double(text[r1]) {
            hi = v
        }
        guard let r2 = Range(m.range(at: 3), in: text) else { return nil }
        let unit = String(text[r2]).lowercased()
        let mult: Double = unit.hasPrefix("h") ? 60 : 1
        let total = JSONDurationRange(min: lo * mult, max: hi * mult)
        return JSONDurationProfile(onset: nil, comeup: nil, peak: nil, offset: nil, afterglow: nil, total: total)
    }
}
