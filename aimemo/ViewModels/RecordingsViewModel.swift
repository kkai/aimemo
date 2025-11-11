//
//  RecordingsViewModel.swift
//  aimemo
//
//  ViewModel for managing recordings list, search, and filtering
//

import Foundation
import SwiftUI
import SwiftData

@Observable
class RecordingsViewModel {
  var searchText: String = ""
  var isShowingEditSheet: Bool = false
  var recordingToEdit: Recording?

  // Filter recordings based on search text
  func filteredRecordings(_ recordings: [Recording]) -> [Recording] {
    guard !searchText.isEmpty else { return recordings }

    let lowercasedSearch = searchText.lowercased()
    return recordings.filter { recording in
      // Search in title
      if let title = recording.title, title.lowercased().contains(lowercasedSearch) {
        return true
      }

      // Search in transcript text
      if recording.transcriptText.lowercased().contains(lowercasedSearch) {
        return true
      }

      // Search in formatted date
      if recording.formattedDate.lowercased().contains(lowercasedSearch) {
        return true
      }

      return false
    }
  }

  func editRecording(_ recording: Recording) {
    recordingToEdit = recording
    isShowingEditSheet = true
  }

  func shareRecording(_ recording: Recording) -> [Any] {
    var items: [Any] = []

    // Create formatted text to share
    var shareText = ""
    if let title = recording.title, !title.isEmpty {
      shareText += "\(title)\n"
    }
    shareText += "\(recording.formattedDate)\n"
    shareText += "Duration: \(recording.formattedDuration)\n\n"
    shareText += recording.transcriptText

    items.append(shareText)

    return items
  }
}
