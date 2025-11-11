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

  var body: some View {
    GeometryReader { geometry in
      HStack(alignment: .center, spacing: barSpacing) {
        ForEach(0..<barCount, id: \.self) { index in
          if index < levels.count {
            // Active bar with amplitude
            Capsule()
              .fill(Color.white.opacity(0.8))
              .frame(
                width: max(2, (geometry.size.width - CGFloat(barCount - 1) * barSpacing) / CGFloat(barCount)),
                height: max(minBarHeight, CGFloat(levels[index]) * geometry.size.height)
              )
          } else {
            // Placeholder bar when no data
            Capsule()
              .fill(Color.white.opacity(0.2))
              .frame(
                width: max(2, (geometry.size.width - CGFloat(barCount - 1) * barSpacing) / CGFloat(barCount)),
                height: minBarHeight
              )
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
