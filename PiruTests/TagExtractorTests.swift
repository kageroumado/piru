import Foundation
import Testing
@testable import Piru

@Suite("TagExtractor")
struct TagExtractorTests {
    // MARK: - extractTags

    @Test
    func `Extracts single hashtag`() {
        let tags = TagExtractor.extractTags(from: "Feeling okay #headache")
        #expect(tags == ["headache"])
    }

    @Test
    func `Extracts multiple hashtags`() {
        let tags = TagExtractor.extractTags(from: "#headache #sleep #nausea")
        #expect(tags == ["headache", "sleep", "nausea"])
    }

    @Test
    func `Tags are lowercased`() {
        let tags = TagExtractor.extractTags(from: "#Headache #SLEEP")
        #expect(tags == ["headache", "sleep"])
    }

    @Test
    func `Deduplicates case-insensitive`() {
        let tags = TagExtractor.extractTags(from: "#sleep #Sleep #SLEEP")
        #expect(tags == ["sleep"])
    }

    @Test
    func `Empty string returns empty array`() {
        #expect(TagExtractor.extractTags(from: "").isEmpty)
    }

    @Test
    func `No hashtags returns empty array`() {
        #expect(TagExtractor.extractTags(from: "Just a regular note").isEmpty)
    }

    @Test
    func `Hashtag in middle of text`() {
        let tags = TagExtractor.extractTags(from: "Took dose, feeling #anxious but okay")
        #expect(tags == ["anxious"])
    }

    @Test
    func `Hashtag with numbers`() {
        let tags = TagExtractor.extractTags(from: "#day3 #dose2")
        #expect(tags == ["day3", "dose2"])
    }

    @Test
    func `Hashtag with underscores`() {
        let tags = TagExtractor.extractTags(from: "#mild_headache #good_mood")
        #expect(tags == ["mild_headache", "good_mood"])
    }

    @Test
    func `Ignores lone hash symbol`() {
        #expect(TagExtractor.extractTags(from: "# nothing here").isEmpty)
    }

    @Test
    func `Preserves order of first occurrence`() {
        let tags = TagExtractor.extractTags(from: "#z #a #m")
        #expect(tags == ["z", "a", "m"])
    }

    // MARK: - suggestions

    @Test
    func `Suggestions list is non-empty`() {
        #expect(!TagExtractor.suggestions.isEmpty)
    }

    @Test
    func `Suggestions contain common symptom tags`() {
        #expect(TagExtractor.suggestions.contains("headache"))
        #expect(TagExtractor.suggestions.contains("anxiety"))
        #expect(TagExtractor.suggestions.contains("sleep"))
        #expect(TagExtractor.suggestions.contains("nausea"))
    }

    @Test
    func `All suggestions are lowercase`() {
        for tag in TagExtractor.suggestions {
            #expect(tag == tag.lowercased())
        }
    }
}
