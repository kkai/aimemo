//
//  SummaryGenerator.swift
//  aimemo
//
//  Foundation Models wrapper for AI text summarization (Pro version only)
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

@Observable
class SummaryGenerator {
  var isGenerating = false
  var summaryText: String?
  var error: String?

  var isAvailable: Bool {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      return SystemLanguageModel.default.isAvailable
    }
    #endif
    return false
  }

  func generateSummary(for transcript: String) async {
    guard !transcript.isEmpty else { return }
    guard !isGenerating else { return }

    await MainActor.run {
      self.isGenerating = true
      self.error = nil
    }

    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      do {
        let session = LanguageModelSession {
          """
          You are an expert at summarizing voice transcripts.
          Create a concise summary with bullet points highlighting the main topics and key details.
          Use clear, structured formatting with main points and sub-points where appropriate.
          """
        }

        let response = try await session.respond(to: "Summarize this transcript:\n\n\(transcript)")

        await MainActor.run {
          self.summaryText = response.content
          self.isGenerating = false
        }
      } catch {
        await MainActor.run {
          self.error = error.localizedDescription
          self.isGenerating = false
        }
      }
    } else {
      await MainActor.run {
        self.error = "AI summarization requires iOS 26 or later"
        self.isGenerating = false
      }
    }
    #else
    await MainActor.run {
      self.error = "AI summarization not available on this platform"
      self.isGenerating = false
    }
    #endif
  }

  func clearSummary() {
    summaryText = nil
    error = nil
  }

  /// Short (at most six words) title for a transcript.
  /// Returns nil when the model is unavailable, the transcript is empty,
  /// or generation fails — callers treat nil as "keep the existing title".
  func generateTitle(for transcript: String) async -> String? {
    let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTranscript.isEmpty else { return nil }

    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      guard SystemLanguageModel.default.isAvailable else { return nil }
      do {
        let session = LanguageModelSession {
          """
          You create titles for voice memo transcripts.
          Reply with only the title: at most six words, no quotes, no trailing punctuation.
          """
        }
        let response = try await session.respond(
          to: "Create a title for this voice memo transcript:\n\n\(trimmedTranscript)")
        let title = response.content
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return title.isEmpty ? nil : title
      } catch {
        return nil
      }
    }
    #endif
    return nil
  }
}
