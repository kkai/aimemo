//
//  AccessibilityAuditTests.swift
//  aimemoUITests
//
//  Xcode's automated accessibility audit, one screen at a time
//  (docs/ACCESSIBILITY.md). Screens are reached by their spoken labels, the
//  way a VoiceOver user would, and recordings play a fixed script
//  (-uiTestScriptedSession) because the simulator microphone is unreliable.
//
//  Runs against the free app by default. With TEST_RUNNER_AIMEMO_APP=pro, and
//  the Pro app installed on the simulator first, the same tests run against
//  ai-Memo Pro and the History tests run too.
//

import XCTest

@MainActor
final class AccessibilityAuditTests: XCTestCase {

  private static var isPro: Bool {
    ProcessInfo.processInfo.environment["AIMEMO_APP"] == "pro"
  }

  private var app: XCUIApplication!

  /// Set on system Form and List screens (see `audit`).
  private var acceptListFalsePositives = false
  /// Set while the script is still playing (see `audit`).
  private var acceptLiveContentFalsePositives = false

  override func setUp() {
    continueAfterFailure = true
    app = Self.isPro ? XCUIApplication(bundleIdentifier: "de.kaikunze.aimemo-pro") : XCUIApplication()
    app.launchArguments = ["-uiTestScriptedSession"]
  }

  private func launch(largestText: Bool = false, seedHistory: Bool = false) {
    if largestText {
      app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                              "UICTContentSizeCategoryAccessibilityXXXL"]
    }
    if seedHistory { app.launchArguments.append("-uiTestSeedHistory") }
    app.launch()
    XCTAssertTrue(app.buttons["Start recording"].waitForExistence(timeout: 10))
  }

  private func audit(_ file: StaticString = #filePath, _ line: UInt = #line) throws {
    try app.performAccessibilityAudit { issue in
      // One line per issue in the test log, so a finding can be traced to its
      // element without opening the result bundle.
      print("AUDIT | \(issue.compactDescription) | \(issue.element?.elementType.rawValue ?? 0) | \(issue.element?.label ?? "-") | \(issue.element.map { "\($0.frame)" } ?? "") | \(issue.detailedDescription)")
      // System Form/List screens (Settings, History) are flagged although
      // their rows scale and wrap; checked at AX5 by hand.
      if self.acceptListFalsePositives, [.dynamicType, .textClipped].contains(issue.auditType) { return true }
      // While a take runs, the timer ticks and the transcript grows between
      // the audit's captures, and it reports contrast on whatever moved (the
      // timer, the buttons under the growing card) plus one unattributed
      // "inaccessible text". testPaused audits the identical screen standing
      // still and passes; the colours are 4.68:1 (buttons) and 6.09:1
      // (timer), computed in docs/ACCESSIBILITY.md.
      if self.acceptLiveContentFalsePositives {
        if issue.auditType == .contrast { return true }
        if issue.auditType == .elementDetection, issue.element == nil { return true }
        // The elapsed label is static text, so the hit-area rule does not
        // apply to it; the audit reports it only when its frame changed
        // between captures (the time ticked, or the language badge appeared
        // mid-import), which is the same moving-content artefact as above.
        if issue.auditType == .hitRegion, issue.element?.label.hasPrefix("Elapsed") == true { return true }
      }
      return false
    }
  }

  private func startRecording() {
    app.buttons["Start recording"].tap()
    XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
    // Let the script put a few words on screen.
    sleep(3)
  }

  // MARK: - Recording screen

  func testIdle() throws {
    launch()
    XCTAssertTrue(app.buttons["Settings"].exists)
    try audit()
  }

  func testIdleAtLargestTextSize() throws {
    launch(largestText: true)
    try audit()
  }

  func testRecording() throws {
    launch()
    startRecording()
    XCTAssertTrue(app.staticTexts["Recording"].exists)
    acceptLiveContentFalsePositives = true
    try audit()
  }

  func testPaused() throws {
    launch()
    startRecording()
    app.buttons["Pause"].tap()
    XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Paused"].exists)
    try audit()
  }

  func testPauseResumeKeepsRecording() throws {
    launch()
    startRecording()
    app.buttons["Pause"].tap()
    XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
    app.buttons["Resume"].tap()
    XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Recording"].exists)
  }

  func testFinished() throws {
    launch()
    startRecording()
    app.buttons["Stop recording"].tap()
    XCTAssertTrue(app.staticTexts["Complete"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["Pause"].exists, "no Pause once the recording has stopped")
    try audit()
  }

  func testRecordingAtLargestTextSize() throws {
    launch(largestText: true)
    startRecording()
    acceptLiveContentFalsePositives = true
    try audit()
  }

  func testFinishedShareMenuOffersTextAndMarkdown() throws {
    launch()
    startRecording()
    app.buttons["Stop recording"].tap()
    XCTAssertTrue(app.staticTexts["Complete"].waitForExistence(timeout: 10))
    app.buttons["Share"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Share Text"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Markdown"].exists)
    // The scripted session reports no timings, so no subtitle formats.
    XCTAssertFalse(app.buttons["SRT subtitles"].exists)
  }

  // MARK: - Transcribing a file

  /// A minute of the English fixture, so the importing screen stands still
  /// long enough to audit. Written to the host's temporary folder, which the
  /// simulator can read.
  private static func longFixture() throws -> URL {
    let source = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("aimemoTests/Resources/audio/en.wav")
    let bytes = [UInt8](try Data(contentsOf: source))
    func u32(_ i: Int) -> Int {
      Int(bytes[i]) | Int(bytes[i + 1]) << 8 | Int(bytes[i + 2]) << 16 | Int(bytes[i + 3]) << 24
    }
    var i = 12, payload: [UInt8] = []
    while i + 8 <= bytes.count {
      let id = String(bytes: bytes[i..<i + 4], encoding: .ascii) ?? ""
      let size = u32(i + 4)
      if id == "data" { payload = Array(bytes[(i + 8)..<min(i + 8 + size, bytes.count)]); break }
      i += 8 + size + (size & 1)
    }
    let data = [UInt8](repeating: 0, count: 0) + Array((0..<13).flatMap { _ in payload })
    func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 24 & 0xff)] }
    func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8 & 0xff)] }
    var wav: [UInt8] = Array("RIFF".utf8) + le32(36 + data.count) + Array("WAVE".utf8)
    wav += Array("fmt ".utf8) + le32(16) + le16(1) + le16(1) + le32(16_000) + le32(32_000) + le16(2) + le16(16)
    wav += Array("data".utf8) + le32(data.count) + data
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("aimemo-ui-long.wav")
    try Data(wav).write(to: url)
    return url
  }

  func testImporting() throws {
    let file = try Self.longFixture()
    app.launchArguments += ["-uiTestImportFile", file.path]
    launch()
    XCTAssertTrue(app.buttons["Cancel transcription"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Transcribing file'")).firstMatch.exists)
    // The transcript grows while whisper decodes; same tolerance as a live take.
    acceptLiveContentFalsePositives = true
    try audit()
    app.buttons["Cancel transcription"].tap()
    XCTAssertTrue(app.buttons["Transcribe a file"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["Cancel transcription"].exists)
  }

  // MARK: - Settings

  func testSettings() throws {
    launch()
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    acceptListFalsePositives = true
    try audit()
  }

  // MARK: - History (Pro)

  func testHistory() throws {
    try XCTSkipUnless(Self.isPro, "History is Pro only")
    launch(seedHistory: true)
    app.buttons["History"].tap()
    XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
    acceptListFalsePositives = true
    try audit()
  }

  func testDetail() throws {
    try XCTSkipUnless(Self.isPro, "History is Pro only")
    launch(seedHistory: true)
    app.buttons["History"].tap()
    let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Thursday planning'")).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    row.tap()
    XCTAssertTrue(app.buttons["Copy to Clipboard"].waitForExistence(timeout: 5))
    try audit()
  }
}
