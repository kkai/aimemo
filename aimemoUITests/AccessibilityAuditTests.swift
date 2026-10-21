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
