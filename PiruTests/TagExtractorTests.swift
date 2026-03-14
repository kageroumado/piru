import Testing
import Foundation
@testable import Piru

@Suite("TagExtractor")
struct TagExtractorTests {

    // MARK: - extractTags

    @Test("Extracts single hashtag")
    func singleTag() {
        let tags = TagExtractor.extractTags(from: "Feeling okay #headache")
        #expect(tags == ["headache"])
    }

    @Test("Extracts multiple hashtags")
    func multipleTags() {
        let tags = TagExtractor.extractTags(from: "#headache #sleep #nausea")
        #expect(tags == ["headache", "sleep", "nausea"])
    }

    @Test("Tags are lowercased")
    func tagsLowercased() {
        let tags = TagExtractor.extractTags(from: "#Headache #SLEEP")
        #expect(tags == ["headache", "sleep"])
    }

    @Test("Deduplicates case-insensitive")
    func deduplicatesCaseInsensitive() {
        let tags = TagExtractor.extractTags(from: "#sleep #Sleep #SLEEP")
        #expect(tags == ["sleep"])
    }

    @Test("Empty string returns empty array")
    func emptyString() {
        #expect(TagExtractor.extractTags(from: "").isEmpty)
    }

    @Test("No hashtags returns empty array")
    func noHashtags() {
        #expect(TagExtractor.extractTags(from: "Just a regular note").isEmpty)
    }

    @Test("Hashtag in middle of text")
    func hashtagInMiddle() {
        let tags = TagExtractor.extractTags(from: "Took dose, feeling #anxious but okay")
        #expect(tags == ["anxious"])
    }

    @Test("Hashtag with numbers")
    func hashtagWithNumbers() {
        let tags = TagExtractor.extractTags(from: "#day3 #dose2")
        #expect(tags == ["day3", "dose2"])
    }

    @Test("Hashtag with underscores")
    func hashtagWithUnderscores() {
        let tags = TagExtractor.extractTags(from: "#mild_headache #good_mood")
        #expect(tags == ["mild_headache", "good_mood"])
    }

    @Test("Ignores lone hash symbol")
    func loneHash() {
        #expect(TagExtractor.extractTags(from: "# nothing here").isEmpty)
    }

    @Test("Preserves order of first occurrence")
    func preservesOrder() {
        let tags = TagExtractor.extractTags(from: "#z #a #m")
        #expect(tags == ["z", "a", "m"])
    }

    // MARK: - suggestions

    @Test("Suggestions list is non-empty")
    func suggestionsNonEmpty() {
        #expect(!TagExtractor.suggestions.isEmpty)
    }

    @Test("Suggestions contain common symptom tags")
    func suggestionsContainCommon() {
        #expect(TagExtractor.suggestions.contains("headache"))
        #expect(TagExtractor.suggestions.contains("anxiety"))
        #expect(TagExtractor.suggestions.contains("sleep"))
        #expect(TagExtractor.suggestions.contains("nausea"))
    }

    @Test("All suggestions are lowercase")
    func suggestionsLowercase() {
        for tag in TagExtractor.suggestions {
            #expect(tag == tag.lowercased())
        }
    }
}
