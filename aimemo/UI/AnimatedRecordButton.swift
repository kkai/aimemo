//
//  AnimatedRecordButton.swift
//  aimemo
//
//  Created by kai on 10.11.25.
//

import SwiftUI

struct AnimatedRecordButton: View {
  @Binding var isRecording: Bool
  var onStart: () -> Void
  var onStop: () -> Void

  private let outerSize: CGFloat = 96
  private let ringWidth: CGFloat = 6

  var body: some View {
    Button(action: {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
        if isRecording {
          onStop()
        } else {
          onStart()
        }
      }
    }) {
      ZStack {
        // Dark outer ring
        Circle()
          .stroke(Color(hex: 0x1C1C1E), lineWidth: ringWidth)
          .frame(width: outerSize, height: outerSize)

        // Red disc, with a subtle white inner hairline
        Circle()
          .fill(Color(hex: 0xFF3B30))
          .frame(width: outerSize - ringWidth * 2, height: outerSize - ringWidth * 2)
          .overlay(
            Circle().stroke(Color.white.opacity(0.9), lineWidth: 2)
          )

        // Glyph: mic when idle, stop square while recording
        if isRecording {
          RoundedRectangle(cornerRadius: 6)
            .fill(Color.white)
            .frame(width: outerSize * 0.28, height: outerSize * 0.28)
            .transition(.scale.combined(with: .opacity))
        } else {
          Image(systemName: "mic.fill")
            .font(.system(size: outerSize * 0.34, weight: .medium))
            .foregroundStyle(Color.white)
            .transition(.scale.combined(with: .opacity))
        }
      }
    }
    .buttonStyle(PlainButtonStyle())
  }
}

#Preview {
  VStack(spacing: 40) {
    Text("Not Recording")
      .foregroundColor(.white)
    AnimatedRecordButton(
      isRecording: .constant(false),
      onStart: { print("Start") },
      onStop: { print("Stop") }
    )

    Text("Recording")
      .foregroundColor(.white)
    AnimatedRecordButton(
      isRecording: .constant(true),
      onStart: { print("Start") },
      onStop: { print("Stop") }
    )
  }
  .frame(maxWidth: .infinity, maxHeight: .infinity)
  .background(Color.black)
}
