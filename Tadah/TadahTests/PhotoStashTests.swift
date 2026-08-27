//  PhotoStashTests.swift
//
//  Sign-out deletes the account's to-dos from the device. Photos are never
//  uploaded, so the row's copy is the ONLY copy — these pin the one mechanism
//  that stops a sign-out from destroying someone's scanned documents.

import Testing
import Foundation
@testable import Tadah

@Suite(.serialized)
struct PhotoStashTests {

    private func clean() { PhotoStash.dropAll() }

    @Test func aKeptPhotoComesBackForTheSameItem() {
        clean()
        let id = UUID()
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02])

        PhotoStash.keep(bytes, for: id)
        #expect(PhotoStash.photo(for: id) == bytes)

        // A different to-do never inherits someone else's picture.
        #expect(PhotoStash.photo(for: UUID()) == nil)
        clean()
    }

    @Test func droppingReleasesTheBytes() {
        clean()
        let id = UUID()
        PhotoStash.keep(Data([1, 2, 3]), for: id)
        #expect(PhotoStash.keptCount() == 1)

        PhotoStash.drop(id)
        #expect(PhotoStash.photo(for: id) == nil)
        #expect(PhotoStash.keptCount() == 0)
        clean()
    }

    // Callers hand over every item without checking, so the empty cases must be
    // silent no-ops rather than writing zero-byte files that later read as a photo.
    @Test func nothingIsKeptForAnItemWithNoPhoto() {
        clean()
        let id = UUID()
        PhotoStash.keep(nil, for: id)
        PhotoStash.keep(Data(), for: id)
        #expect(PhotoStash.photo(for: id) == nil)
        #expect(PhotoStash.keptCount() == 0)
        clean()
    }

    @Test func dropAllClearsEverything() {
        clean()
        for _ in 0..<3 { PhotoStash.keep(Data([9]), for: UUID()) }
        #expect(PhotoStash.keptCount() == 3)
        PhotoStash.dropAll()
        #expect(PhotoStash.keptCount() == 0)
    }
}
