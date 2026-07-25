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
      Text("Unlock more with aiMemo Pro")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(Theme.textPrimary)

      Text("Recording history, all Whisper models, and more.")
        .font(.system(size: 15))
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      Link(destination: url) {
        HStack(spacing: 4) {
          Text("Get aiMemo Pro")
            .font(.system(size: 15, weight: .semibold))
          Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Theme.accent)
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .padding(.top, 2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface()
  }
}
