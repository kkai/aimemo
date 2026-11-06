//
//  ShareTranscriptMenu.swift
//  aimemo
//
//  The Share button: plain text, Markdown, and subtitles when timed
//

import SwiftUI

/// One Share pill for both the recording screen and the Pro detail view.
/// Plain text goes straight to the share sheet as before; Markdown and the
/// subtitle formats go as files, so Notes, Files, Mail and video editors
/// receive something they can open by name.
struct ShareTranscriptMenu: View {
  let export: TranscriptExport
  var tint: Color = Theme.accent

  var body: some View {
    Menu {
      ShareLink(item: export.text) {
        Label("Share Text", systemImage: "text.alignleft")
      }
      ForEach(TranscriptExport.Format.allCases) { format in
        if export.supports(format) {
          let file = TranscriptFile(export: export, format: format)
          ShareLink(item: file, preview: SharePreview(file.fileName, image: Image(systemName: "doc.text"))) {
            Label(format.label, systemImage: format == .markdown ? "doc.richtext" : "captions.bubble")
          }
        }
      }
      if !export.hasTimings {
        Text("Subtitles need a transcript with timings, which the next recording will have.")
      }
    } label: {
      HStack(spacing: 8) {
        Image(systemName: "square.and.arrow.up")
        Text("Share")
      }
      .actionButtonStyle(tint: tint)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Share")
    .accessibilityHint("Share as text, Markdown or subtitles")
  }
}
