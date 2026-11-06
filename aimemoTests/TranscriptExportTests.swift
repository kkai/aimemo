//
//  TranscriptExportTests.swift
//  aimemoTests
//
//  Markdown, SRT and VTT renderings, pinned as strings.
//

import Foundation
import Testing
@testable import aimemo

struct TranscriptExportTests {

  private static let date = Date(timeIntervalSince1970: 1_762_430_400)  // 2025-11-06 12:00 UTC

  private static let segments = [
    TranscriptSegment(text: "Here is the plan for Thursday.", start: 0.5, end: 2.9),
    TranscriptSegment(text: "We move the design review to ten.", start: 3.2, end: 5.75),
  ]

  private func export(title: String? = "Thursday planning",
                      segments: [TranscriptSegment] = TranscriptExportTests.segments,
                      summary: String? = nil) -> TranscriptExport {
    TranscriptExport(title: title, date: Self.date, duration: 125,
                     text: segments.map(\.text).joined(separator: " "),
                     segments: segments, summary: summary)
  }

  // MARK: - SRT / VTT

  @Test func srtNumbersCuesAndUsesCommaMilliseconds() {
    let srt = export().srt
    #expect(srt == """
      1
      00:00:00,500 --> 00:00:02,900
      Here is the plan for Thursday.

      2
      00:00:03,200 --> 00:00:05,750
      We move the design review to ten.

      """)
  }

  @Test func vttHasTheHeaderAndDotMilliseconds() {
    let vtt = export().vtt
    #expect(vtt.hasPrefix("WEBVTT\n\n00:00:00.500 --> 00:00:02.900\nHere is the plan for Thursday.\n"))
    #expect(!vtt.contains(","))
  }

  @Test func overlappingCuesAreTrimmedToTheNextStart() {
    let overlapping = [
      TranscriptSegment(text: "one", start: 0, end: 2.1),
      TranscriptSegment(text: "two", start: 2.0, end: 4),
    ]
    let srt = export(segments: overlapping).srt
    #expect(srt.contains("00:00:02,100 --> 00:00:04,000\ntwo"))
  }

  @Test func zeroLengthCuesGetHalfASecond() {
    let flat = [TranscriptSegment(text: "blip", start: 10, end: 10)]
    #expect(export(segments: flat).srt.contains("00:00:10,000 --> 00:00:10,500"))
  }

  @Test(arguments: [
    (0.0, "00:00:00,000"),
    (61.5, "00:01:01,500"),
    (3661.002, "01:01:01,002"),
    (59.9996, "00:01:00,000"),  // rounds up and carries
  ])
  func stampsRoundToMilliseconds(seconds: Double, expected: String) {
    #expect(TranscriptExport.stamp(seconds, separator: ",") == expected)
  }

  @Test func subtitleFormatsNeedTimings() {
    let untimed = export(segments: [])
    #expect(untimed.render(.srt) == nil)
    #expect(untimed.render(.vtt) == nil)
    #expect(untimed.render(.markdown) != nil)
    #expect(!untimed.supports(.srt))
    #expect(untimed.supports(.markdown))
    #expect(export().supports(.srt))
  }

  // MARK: - Markdown

  @Test func markdownStampsEachSegment() {
    let md = export().markdown
    #expect(md.hasPrefix("# Thursday planning\n\n*"))
    #expect(md.contains("· 2:05*"))
    #expect(md.contains("## Transcript\n\n**[0:00]** Here is the plan for Thursday.\n\n**[0:03]** We move"))
    #expect(!md.contains("## Summary"))
    #expect(md.hasSuffix("\n"))
  }

  @Test func markdownWithoutTimingsIsThePlainText() {
    let md = export(segments: []).markdown
    #expect(md.contains("## Transcript\n\n\n"))  // the text of an empty segment list is empty
    let md2 = TranscriptExport(title: nil, date: Self.date, duration: 4, text: "Just words.").markdown
    #expect(md2.contains("## Transcript\n\nJust words.\n"))
    #expect(md2.hasPrefix("# Voice memo, "))
  }

  @Test func markdownIncludesTheSummaryFirst() {
    let md = export(summary: "- Review moved to ten").markdown
    let summaryAt = md.range(of: "## Summary\n\n- Review moved to ten")!.lowerBound
    let transcriptAt = md.range(of: "## Transcript")!.lowerBound
    #expect(summaryAt < transcriptAt)
  }

  @Test func markdownNamesTheSourceFile() {
    var e = export()
    e.sourceFileName = "Lecture 4.m4a"
    #expect(e.markdown.contains("· from Lecture 4.m4a*"))
  }

  // MARK: - File names

  @Test func fileNameUsesTheTitleAndFormat() {
    #expect(export().fileName(for: .markdown) == "Thursday planning.md")
    #expect(export().fileName(for: .srt) == "Thursday planning.srt")
    #expect(export().fileName(for: .vtt) == "Thursday planning.vtt")
  }

  @Test func fileNameStripsPathCharacters() {
    #expect(export(title: "Q3: plan / review?").fileName(for: .srt) == "Q3- plan - review-.srt")
  }

  @Test func untitledFileNameCarriesTheDate() {
    let name = export(title: nil).fileName(for: .markdown)
    #expect(name.hasPrefix("ai-Memo 20"))
    #expect(name.hasSuffix(".md"))
  }

  @Test func untitledImportUsesTheSourceName() {
    var e = export(title: nil)
    e.sourceFileName = "Board meeting.mov"
    #expect(e.fileName(for: .vtt) == "Board meeting.vtt")
  }

  @Test func clockFormatsMinutesAndHours() {
    #expect(TranscriptExport.clock(65) == "1:05")
    #expect(TranscriptExport.clock(3725) == "1:02:05")
  }

  // MARK: - Files

  @Test func transcriptFileWritesTheRenderedText() throws {
    let file = TranscriptFile(export: export(), format: .srt)
    let url = try file.write()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    #expect(url.lastPathComponent == "Thursday planning.srt")
    #expect(try String(contentsOf: url, encoding: .utf8) == export().srt)
  }
}
