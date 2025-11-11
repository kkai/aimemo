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

  private let outerSize: CGFloat = 90
  private let strokeWidth: CGFloat = 4

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
        // Outer white circle
        Circle()
          .stroke(Color.white, lineWidth: strokeWidth)
          .frame(width: outerSize, height: outerSize)

        // Inner morphing shape
        if isRecording {
          // Recording state: rounded rectangle
          RoundedRectangle(cornerRadius: 8)
            .fill(Color.red)
            .frame(width: outerSize * 0.5, height: outerSize * 0.5)
            .transition(.scale.combined(with: .opacity))
        } else {
          // Idle state: circle
          Circle()
            .fill(Color.red)
            .frame(width: outerSize * 0.7, height: outerSize * 0.7)
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
