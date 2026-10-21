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
  /// 0x2F80FF until 2.6: 4.35:1 as text on its own 12% button fill, under
  /// the 4.5:1 floor. This shade is 4.68:1 there and 5.4:1 on a card.
  static let accent = Color(hex: 0x3A88FF)
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
  /// Spoken name. Without it VoiceOver read the symbol name ("gearshape").
  let label: String
  let action: () -> Void

  /// 44 pt, the minimum touch target; it was 40. Grows with the text size,
  /// but stops at 64: unbounded, it reached 120 pt at the largest size.
  @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 44
  private var size: CGFloat { min(scaledSize, 64) }

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
    .accessibilityLabel(label)
  }
}

// MARK: - Pill action button (Copy / Delete / detail actions)

/// The tinted pill used for the transcript actions. Factored out of
/// `ActionButton` so `ShareLink`, which builds its own button, can wear the
/// same style.
struct ActionButtonStyleModifier: ViewModifier {
  let tint: Color

  func body(content: Content) -> some View {
    content
      .font(.subheadline.weight(.medium))
      .foregroundStyle(tint)
      .frame(maxWidth: .infinity, minHeight: 44)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
          .fill(tint.opacity(0.12))
      )
      .overlay(
        RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
          .stroke(tint.opacity(0.35), lineWidth: 1)
      )
  }
}

extension View {
  func actionButtonStyle(tint: Color) -> some View {
    modifier(ActionButtonStyleModifier(tint: tint))
  }
}

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
      .actionButtonStyle(tint: tint)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Status pill

enum RecordingStatus: Equatable {
  case recording
  /// `byInterruption`: a call, Siri or an alarm paused it, not the user.
  case paused(byInterruption: Bool)
  /// The final window is being decoded; on a long take this is seconds.
  case finishing
  case complete

  var label: String {
    switch self {
    case .recording: return "Recording"
    case .paused(let byInterruption): return byInterruption ? "Paused by a call or alarm" : "Paused"
    case .finishing: return "Finishing…"
    case .complete: return "Complete"
    }
  }

  var tint: Color {
    switch self {
    case .recording: return Theme.danger
    case .paused, .finishing: return Theme.accent
    case .complete: return Theme.success
    }
  }

  var systemName: String {
    switch self {
    case .recording: return "circle.fill"
    case .paused: return "pause.fill"
    case .finishing: return "ellipsis"
    case .complete: return "checkmark.circle"
    }
  }
}

struct StatusPill: View {
  let status: RecordingStatus

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: status.systemName)
        .font(status == .recording ? .caption2.weight(.semibold) : .subheadline.weight(.semibold))
        .accessibilityHidden(true)
      Text(status.label)
        .font(.subheadline.weight(.semibold))
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
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.updatesFrequently)
  }
}

// MARK: - Label with a tinted icon

/// Coloured icon, plain text: the colour marks the kind of message, while the
/// text stays at full contrast.
struct TintedIconLabelStyle: LabelStyle {
  let tint: Color

  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      configuration.icon.foregroundStyle(tint)
      configuration.title
    }
  }
}
