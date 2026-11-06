//
//  TranscriptFile.swift
//  aimemo
//
//  A rendered export as a shareable file
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// One export in one format, written to a temporary file only when the share
/// sheet asks for it. `ShareLink` takes it directly, so the Markdown, SRT and
/// VTT items in the Share menu are three instances of this.
struct TranscriptFile: Transferable {
  let export: TranscriptExport
  let format: TranscriptExport.Format

  var fileName: String { export.fileName(for: format) }

  /// The rendered text. Empty only for a subtitle format without timings,
  /// which the menu never offers.
  var contents: String { export.render(format) ?? "" }

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .plainText) { file in
      SentTransferredFile(try file.write(), allowAccessingOriginalFile: false)
    }
  }

  /// Writes the file under a fresh temporary folder, so two exports with the
  /// same title do not overwrite each other mid-share.
  func write() throws -> URL {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("Exports", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent(fileName)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
  }
}
