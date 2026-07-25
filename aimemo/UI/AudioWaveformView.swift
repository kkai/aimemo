//
//  AudioWaveformView.swift
//  aimemo
//
//  Created by kai on 10.11.25.
//

import SwiftUI

struct AudioWaveformView: View {
  var levels: [Float]

  private let barCount = 100
  private let barSpacing: CGFloat = 2
  private let minBarHeight: CGFloat = 4

  // Blue → purple across the bar count, sampled per-bar so the whole waveform
  // reads as one left-to-right gradient (not a gradient inside each thin bar).
  private func barColor(at index: Int) -> Color {
    let t = Double(index) / Double(max(1, barCount - 1))
    let from = (0x2E / 255.0, 0x5B / 255.0, 0xFF / 255.0)
    let to = (0x7A / 255.0, 0x4D / 255.0, 0xFF / 255.0)
    return Color(
      .sRGB,
      red: from.0 + (to.0 - from.0) * t,
      green: from.1 + (to.1 - from.1) * t,
      blue: from.2 + (to.2 - from.2) * t,
      opacity: 1
    )
  }

  var body: some View {
    GeometryReader { geometry in
      let barWidth = max(2, (geometry.size.width - CGFloat(barCount - 1) * barSpacing) / CGFloat(barCount))
      HStack(alignment: .center, spacing: barSpacing) {
        ForEach(0..<barCount, id: \.self) { index in
          if index < levels.count {
            // Active bar with amplitude, colored along the blue→purple gradient
            Capsule()
              .fill(barColor(at: index))
              .frame(
                width: barWidth,
                height: max(minBarHeight, CGFloat(levels[index]) * geometry.size.height)
              )
          } else {
            // Placeholder bar (the faint dotted-line look at the ends)
            Capsule()
              .fill(Theme.textSecondary.opacity(0.25))
              .frame(width: barWidth, height: minBarHeight)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .animation(.easeInOut(duration: 0.1), value: levels)
  }
}

#Preview {
  AudioWaveformView(levels: [0.1, 0.3, 0.5, 0.7, 0.9, 0.7, 0.5, 0.3, 0.1])
    .frame(height: 60)
    .background(Color.black)
}
