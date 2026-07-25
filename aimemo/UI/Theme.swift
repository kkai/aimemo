//
//  Theme.swift
//  aimemo
//
//  Central design system: colors, metrics, and reusable components.
//  The app is dark end-to-end; palette values are fixed (not adaptive).
//

import SwiftUI

// MARK: - Color from hex

extension Color {
  init(hex: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: opacity
    )
  }
}

// MARK: - Tokens

enum Theme {
  // Palette
  static let background = Color(hex: 0x0A0C10)
  static let surface = Color(hex: 0x111419)
  static let surfaceBorder = Color(hex: 0x23272E)
  static let textPrimary = Color(hex: 0xF5F6F7)
  static let textSecondary = Color(hex: 0x8A909A)
  static let accent = Color(hex: 0x2F80FF)
  static let danger = Color(hex: 0xFF453A)
  static let success = Color(hex: 0x30D158)

  // Waveform gradient
  static let waveformGradient = LinearGradient(
    colors: [Color(hex: 0x2E5BFF), Color(hex: 0x7A4DFF)],
    startPoint: .leading,
    endPoint: .trailing
  )

  // Metrics
  static let cardRadius: CGFloat = 18
  static let controlRadius: CGFloat = 12
  static let cardPadding: CGFloat = 18
}

// MARK: - Card surface

private struct CardSurface: ViewModifier {
  var padding: CGFloat = Theme.cardPadding
  func body(content: Content) -> some View {
    content
      .padding(padding)
      .background(
        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
          .fill(Theme.surface)
      )
      .overlay(
        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
          .stroke(Theme.surfaceBorder, lineWidth: 1)
      )
  }
}

extension View {
  func cardSurface(padding: CGFloat = Theme.cardPadding) -> some View {
    modifier(CardSurface(padding: padding))
  }
}

// MARK: - Circular icon button (settings / history)

struct CircleIconButton: View {
  let systemName: String
  let action: () -> Void
  var size: CGFloat = 40

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: size * 0.42, weight: .regular))
        .foregroundStyle(Theme.textPrimary)
        .frame(width: size, height: size)
        .background(Circle().fill(Theme.surface))
        .overlay(Circle().stroke(Theme.surfaceBorder, lineWidth: 1))
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Pill action button (Copy / Delete / detail actions)

struct ActionButton: View {
  let title: String
  let systemName: String
  let tint: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: systemName)
        Text(title)
      }
      .font(.system(size: 15, weight: .medium))
      .foregroundStyle(tint)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .background(
        RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
          .fill(tint.opacity(0.12))
      )
      .overlay(
        RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
          .stroke(tint.opacity(0.35), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Status pill

enum RecordingStatus {
  case recording
  case complete

  var label: String {
    switch self {
    case .recording: return "Recording"
    case .complete: return "Complete"
    }
  }

  var tint: Color {
    switch self {
    case .recording: return Theme.danger
    case .complete: return Theme.success
    }
  }

  var systemName: String {
    switch self {
    case .recording: return "circle.fill"
    case .complete: return "checkmark.circle"
    }
  }
}

struct StatusPill: View {
  let status: RecordingStatus

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: status.systemName)
        .font(.system(size: status == .recording ? 10 : 15, weight: .semibold))
      Text(status.label)
        .font(.system(size: 15, weight: .semibold))
    }
    .foregroundStyle(status == .recording ? Theme.danger : Theme.textPrimary)
    .padding(.horizontal, 16)
    .padding(.vertical, 9)
    .background(
      Capsule().fill(status.tint.opacity(0.14))
    )
    .overlay(
      Capsule().stroke(status.tint.opacity(0.5), lineWidth: 1)
    )
  }
}
