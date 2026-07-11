//
//  RecordingTests.swift
//  aimemoTests
//
//  Pure computed-property tests plus in-memory SwiftData persistence tests
//  for the Pro recording history model.
//

import Foundation
import SwiftData
import Testing
@testable import aimemo

struct RecordingTests {
  private func makeRecording(
    duration: TimeInterval = 10, transcript: String = "hello", title: String? = nil
  ) -> Recording {
    Recording(timestamp: .now, duration: duration, transcriptText: transcript, title: title)
  }

  @Test func displayTitleUsesTitleWhenPresent() {
    #expect(makeRecording(title: "Standup notes").displayTitle == "Standup notes")
  }

  @Test func displayTitleFallsBackToDateWhenNil() {
    let recording = makeRecording(title: nil)
    #expect(recording.displayTitle == recording.formattedDate)
  }

  @Test func displayTitleFallsBackToDateWhenEmpty() {
    let recording = makeRecording(title: "")
    #expect(recording.displayTitle == recording.formattedDate)
  }

  @Test(arguments: [
    (0.0, "0:00"),
    (59.0, "0:59"),
    (61.0, "1:01"),
    (3599.0, "59:59"),
    (3661.0, "61:01"),  // hours roll into minutes
    (59.9, "0:59"),  // sub-second truncation, no rounding
  ])
  func formattedDurationFormatsSeconds(duration: Double, expected: String) {
    #expect(makeRecording(duration: duration).formattedDuration == expected)
  }

  @Test func transcriptPreviewShortTextUnchanged() {
    let text = String(repeating: "a", count: 42)
    #expect(makeRecording(transcript: text).transcriptPreview == text)
  }

  @Test func transcriptPreviewBoundaryExactly100Unchanged() {
    let text = String(repeating: "a", count: 100)
    #expect(makeRecording(transcript: text).transcriptPreview == text)
  }

  @Test func transcriptPreviewTruncatesAt100() {
    let text = String(repeating: "a", count: 150)
    let preview = makeRecording(transcript: text).transcriptPreview
    #expect(preview == String(repeating: "a", count: 100) + "...")
    #expect(preview.count == 103)
  }

  @Test func initAssignsUniqueIDs() {
    #expect(makeRecording().id != makeRecording().id)
  }
}

@MainActor
@Suite struct RecordingPersistenceTests {
  private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: Recording.self, configurations: config)
  }

  @Test func insertAndFetchRoundTrips() throws {
    // Keep the container alive for the test body: mainContext does not
    // retain it, and SwiftData traps once the container deallocates.
    let container = try makeContainer()
    let context = container.mainContext
    context.insert(Recording(timestamp: .now, duration: 12, transcriptText: "hello world"))
    try context.save()
    let fetched = try context.fetch(FetchDescriptor<Recording>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.transcriptText == "hello world")
    #expect(fetched.first?.duration == 12)
  }

  @Test func fetchSortedByTimestampDescending() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    for offset in [0.0, 60.0, 120.0] {
      context.insert(
        Recording(
          timestamp: base.addingTimeInterval(offset), duration: 1,
          transcriptText: "t+\(offset)"))
    }
    try context.save()
    // Same ordering RecordingsListView uses via @Query.
    let descriptor = FetchDescriptor<Recording>(
      sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
    let fetched = try context.fetch(descriptor)
    #expect(fetched.map(\.transcriptText) == ["t+120.0", "t+60.0", "t+0.0"])
  }

  @Test func deleteRemovesRecording() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let recording = Recording(timestamp: .now, duration: 5, transcriptText: "bye")
    context.insert(recording)
    try context.save()
    context.delete(recording)
    try context.save()
    #expect(try context.fetch(FetchDescriptor<Recording>()).isEmpty)
  }

  @Test func titleEditPersists() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let recording = Recording(timestamp: .now, duration: 5, transcriptText: "text")
    context.insert(recording)
    try context.save()
    recording.title = "Renamed"
    try context.save()
    let fetched = try context.fetch(FetchDescriptor<Recording>())
    #expect(fetched.first?.title == "Renamed")
    #expect(fetched.first?.displayTitle == "Renamed")
  }

  @Test func initDefaultsSummaryNil() throws {
    #expect(Recording(timestamp: .now, duration: 1, transcriptText: "t").summary == nil)
  }

  @Test func summaryPersists() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let recording = Recording(timestamp: .now, duration: 5, transcriptText: "text")
    context.insert(recording)
    try context.save()
    recording.summary = "- Key point one\n- Key point two"
    try context.save()
    let fetched = try context.fetch(FetchDescriptor<Recording>())
    #expect(fetched.first?.summary == "- Key point one\n- Key point two")
  }
}
