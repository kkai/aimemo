//
//  SummaryGeneratorTests.swift
//  aimemoTests
//
//  Pins the availability gating of the Foundation Models wrapper.
//  The positive path (actual generation) requires an Apple Intelligence
//  device on iOS 26+ and is covered by manual verification.
//

import Testing
@testable import aimemo

@MainActor
struct SummaryGeneratorTests {
  // The test host runs on iOS 18.5, where Foundation Models is unavailable.
  // If this suite ever runs on an iOS 26+ Apple Intelligence host these
  // gating expectations must be revisited.

  @Test func unavailableOnThisRuntime() {
    #expect(!SummaryGenerator().isAvailable)
  }

  @Test func generateTitleReturnsNilWhenUnavailable() async {
    let title = await SummaryGenerator().generateTitle(for: "Some transcript text")
    #expect(title == nil)
  }

  @Test func generateTitleReturnsNilForEmptyTranscript() async {
    let title = await SummaryGenerator().generateTitle(for: "   \n  ")
    #expect(title == nil)
  }

  @Test func generateSummaryOnUnavailableSetsError() async {
    let generator = SummaryGenerator()
    await generator.generateSummary(for: "Some transcript text")
    #expect(generator.error != nil)
    #expect(!generator.isGenerating)
    #expect(generator.summaryText == nil)
  }

  @Test func generateSummaryIgnoresEmptyTranscript() async {
    let generator = SummaryGenerator()
    await generator.generateSummary(for: "")
    #expect(generator.error == nil)
    #expect(!generator.isGenerating)
  }
}
