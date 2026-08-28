import XCTest

@testable import PhotoCuration

private var utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.date(from: iso)!
}

private func photo(
    _ id: String,
    at iso: String = "2024-06-01T12:00:00Z",
    scenes: [String] = [],
    faces: Int = 0,
    names: [String] = [],
    favorite: Bool = false,
    aesthetics: Double = 0.7,
    sharpness: Double = 0.9,
    text: Double = 0,
    screenshot: Bool = false,
    hash: UInt64 = 0,
    grid: String? = nil
) -> PhotoFeatures {
    PhotoFeatures(
        id: id,
        creationDate: date(iso),
        isScreenshot: screenshot,
        isFavorite: favorite,
        sharpness: sharpness,
        aestheticScore: aesthetics,
        textCoverage: text,
        faceCount: faces,
        namedFaceIdentifiers: names,
        sceneLabels: scenes.map { SceneLabel(identifier: $0, confidence: 0.9) },
        location: CoarseLocation(type: .unknown, gridKey: grid),
        perceptualHash: hash
    )
}

final class FilteringTests: XCTestCase {
    func testExcludesScreenshotsDocumentsAndBlur() {
        let outcome = PhotoFilter.apply(to: [
            photo("keep", hash: 0b0001),
            photo("shot", screenshot: true, hash: 0b0010),
            photo("receipt", text: 0.5, hash: 0b0100),
            photo("blurry", sharpness: 0.1, hash: 0b1000),
            photo("ugly", aesthetics: 0.05, hash: 0b1_0000)
        ])

        XCTAssertEqual(outcome.kept.map(\.id), ["keep"])
        XCTAssertEqual(outcome.excluded["shot"], .screenshot)
        XCTAssertEqual(outcome.excluded["receipt"], .documentOrReceipt)
        XCTAssertEqual(outcome.excluded["blurry"], .blurry)
        XCTAssertEqual(outcome.excluded["ugly"], .lowQuality)
    }

    func testKeepsBestOfNearDuplicates() {
        let outcome = PhotoFilter.apply(to: [
            photo("worse", aesthetics: 0.5, hash: 0xFF00),
            photo("better", aesthetics: 0.9, hash: 0xFF01)
        ])

        XCTAssertEqual(outcome.kept.map(\.id), ["better"])
        XCTAssertEqual(outcome.excluded["worse"], .duplicate)
    }

    func testDistinctImagesAreNotDuplicates() {
        let outcome = PhotoFilter.apply(to: [
            photo("a", hash: 0x0000_0000_0000_0000),
            photo("b", hash: 0xFFFF_FFFF_FFFF_FFFF)
        ])
        XCTAssertEqual(outcome.kept.count, 2)
    }
}

final class ClusteringTests: XCTestCase {
    func testSplitsOnTimeGap() {
        let clusters = PhotoClusterer.cluster([
            photo("a", at: "2024-06-01T09:00:00Z"),
            photo("b", at: "2024-06-01T10:00:00Z"),
            photo("c", at: "2024-06-03T10:00:00Z")
        ])
        XCTAssertEqual(clusters.map { $0.photos.map(\.id) }, [["a", "b"], ["c"]])
    }

    func testSplitsOnLocationChange() {
        let clusters = PhotoClusterer.cluster([
            photo("a", at: "2024-06-01T09:00:00Z", grid: "paris"),
            photo("b", at: "2024-06-01T09:30:00Z", grid: "rome")
        ])
        XCTAssertEqual(clusters.count, 2)
    }

    func testUnknownLocationDoesNotSplit() {
        let clusters = PhotoClusterer.cluster([
            photo("a", at: "2024-06-01T09:00:00Z", grid: "paris"),
            photo("b", at: "2024-06-01T09:30:00Z")
        ])
        XCTAssertEqual(clusters.count, 1)
    }
}

final class TaggingTests: XCTestCase {
    func testGroupPhotoIsTaggedAsFriends() {
        let tags = PhotoTagger.tags(for: photo("a", scenes: ["beach"], faces: 4), calendar: utcCalendar)
        XCTAssertEqual(tags.primaryCategory, .groupOfFriends)
        XCTAssertTrue(tags.secondaryCategories.contains(.beach))
        XCTAssertEqual(tags.peopleCount, 4)
    }

    func testSceneOnlyPhotoUsesSceneCategory() {
        let tags = PhotoTagger.tags(for: photo("a", scenes: ["mountain valley"]), calendar: utcCalendar)
        XCTAssertEqual(tags.primaryCategory, .mountain)
    }

    func testUnknownSceneFallsBackToOther() {
        let tags = PhotoTagger.tags(for: photo("a", scenes: ["abstract"]), calendar: utcCalendar)
        XCTAssertEqual(tags.primaryCategory, .other)
    }

    func testTimeOfDayAndSeason() {
        let tags = PhotoTagger.tags(
            for: photo("a", at: "2024-01-15T18:30:00Z"),
            calendar: utcCalendar
        )
        XCTAssertEqual(tags.timeOfDay, .goldenHour)
        XCTAssertEqual(tags.season, .winter)
    }

    func testTagsEncodeWithBackendKeys() throws {
        let data = try JSONEncoder().encode(
            PhotoTagger.tags(for: photo("a", faces: 3), calendar: utcCalendar)
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["primary_category"] as? String, "group_of_friends")
        XCTAssertEqual(json["vocabulary_version"] as? Int, tagVocabularyVersion)
    }
}

final class ScoringTests: XCTestCase {
    private let now = date("2024-06-01T12:00:00Z")

    private func score(_ features: PhotoFeatures) -> Double {
        PhotoScorer.score(
            photo: features,
            tags: PhotoTagger.tags(for: features, calendar: utcCalendar),
            referenceDate: now,
            calendar: utcCalendar
        )
    }

    func testFriendsAndLandscapesOutrankPlainPhotos() {
        let plain = score(photo("plain", scenes: ["abstract"]))
        XCTAssertGreaterThan(score(photo("friends", scenes: ["party"], faces: 4)), plain)
        XCTAssertGreaterThan(score(photo("view", scenes: ["mountain"])), plain)
    }

    func testFavouritesAndNamedFacesBoost() {
        let base = score(photo("a", scenes: ["mountain"]))
        XCTAssertGreaterThan(score(photo("b", scenes: ["mountain"], favorite: true)), base)
        XCTAssertGreaterThan(
            score(photo("c", scenes: ["mountain"], faces: 1, names: ["ann"])), base
        )
    }

    func testThisWeekInPriorYearsBoost() {
        let lastYear = photo("old", at: "2023-06-01T12:00:00Z", scenes: ["mountain"])
        let offSeason = photo("off", at: "2023-02-01T12:00:00Z", scenes: ["mountain"])
        XCTAssertGreaterThan(score(lastYear), score(offSeason))
        XCTAssertTrue(
            PhotoScorer.isThisWeekInPriorYear(
                lastYear.creationDate, reference: now, calendar: utcCalendar
            )
        )
    }
}

final class SelectionTests: XCTestCase {
    private let now = date("2024-06-10T12:00:00Z")

    private func library() -> [PhotoFeatures] {
        (0..<12).map { index in
            photo(
                "p\(index)",
                at: "2024-0\(1 + index % 5)-0\(1 + index % 9)T1\(index % 9):00:00Z",
                scenes: index.isMultiple(of: 2) ? ["mountain"] : ["party"],
                faces: index.isMultiple(of: 3) ? 4 : 0,
                aesthetics: 0.4 + Double(index % 5) / 10,
                hash: UInt64(index &+ 1) &* 0x9E37_79B9_7F4A_7C15
            )
        }
    }

    func testSelectsFivePhotosFromDistinctClusters() {
        let result = PhotoSelector.selectDailyBatch(
            from: library(),
            referenceDate: now,
            options: SelectionOptions(calendar: utcCalendar)
        )
        XCTAssertEqual(result.selected.count, 5)
        XCTAssertEqual(Set(result.selected.map(\.clusterID)).count, 5)
        XCTAssertEqual(result.ranked.first?.id, result.selected.first?.id)
    }

    func testSelectionIsDeterministic() {
        let options = SelectionOptions(calendar: utcCalendar)
        let first = PhotoSelector.selectDailyBatch(
            from: library(), referenceDate: now, options: options
        )
        let second = PhotoSelector.selectDailyBatch(
            from: library(), referenceDate: now, options: options
        )
        XCTAssertEqual(first.selected.map(\.id), second.selected.map(\.id))
    }

    func testHistorySuppressesRepeats() {
        let options = SelectionOptions(calendar: utcCalendar)
        let yesterday = PhotoSelector.selectDailyBatch(
            from: library(), referenceDate: now, options: options
        )
        let used = Set(yesterday.selected.map(\.id))
        let today = PhotoSelector.selectDailyBatch(
            from: library(),
            referenceDate: now,
            history: SelectionHistory(usedPhotoIDs: used),
            options: options
        )
        XCTAssertTrue(Set(today.selected.map(\.id)).isDisjoint(with: used))
    }

    func testExcludedPhotosNeverReachTheBatch() {
        var photos = library()
        photos.append(photo("screenshot", aesthetics: 1, screenshot: true, hash: 0xDEAD))
        let result = PhotoSelector.selectDailyBatch(
            from: photos,
            referenceDate: now,
            options: SelectionOptions(calendar: utcCalendar)
        )
        XCTAssertFalse(result.selected.contains { $0.id == "screenshot" })
        XCTAssertEqual(result.excluded["screenshot"], .screenshot)
    }
}
