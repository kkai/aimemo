//
//  ProUpsellCard.swift
//  aimemo
//
//  Upsell card shown on the recording screen in the free version only.
//

import SwiftUI

struct ProUpsellCard: View {
  let url = URL(string: "https://apps.apple.com/app/ai-memo-pro/id6503480155")!

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("More in ai-Memo Pro")
        .font(.headline)
        .foregroundStyle(Theme.textPrimary)

      Text("Recording history and all four Whisper models.")
        .font(.subheadline)
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      Link(destination: url) {
        HStack(spacing: 4) {
          Text("Get ai-Memo Pro")
            .font(.subheadline.weight(.semibold))
          Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .accessibilityHidden(true)
        }
        .foregroundStyle(Theme.accent)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
      }
      .padding(.top, 2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface()
  }
}
