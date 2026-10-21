//
//  PauseResumeButton.swift
//  aimemo
//
//  The smaller button beside the record button while a recording runs
//

import SwiftUI

struct PauseResumeButton: View {
  let isPaused: Bool
  let action: () -> Void

  @ScaledMetric(relativeTo: .title2) private var size: CGFloat = 56

  var body: some View {
    Button(action: action) {
      Image(systemName: isPaused ? "play.fill" : "pause.fill")
        .font(.system(size: size * 0.38, weight: .semibold))
        .foregroundStyle(Theme.textPrimary)
        .frame(width: size, height: size)
        .background(Circle().fill(Theme.surface))
        .overlay(Circle().stroke(Theme.surfaceBorder, lineWidth: 1))
        .contentTransition(.symbolEffect(.replace))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(isPaused ? "Resume" : "Pause")
    .accessibilityHint(isPaused ? "Continues the recording." : "Pauses the recording. Nothing is lost.")
  }
}

#Preview {
  HStack(spacing: 24) {
    PauseResumeButton(isPaused: false) {}
    PauseResumeButton(isPaused: true) {}
  }
  .padding()
  .background(Theme.background)
}
