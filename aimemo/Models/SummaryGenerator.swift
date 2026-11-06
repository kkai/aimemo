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
        let message = Self.plainMessage(for: error)
        print("Summary failed: \(error)")
        await MainActor.run {
          self.error = message
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

  /// A sentence for the alert. The framework's own description is
  /// "The operation couldn't be completed. (…GenerationError error -1.)".
  nonisolated static func plainMessage(for error: Error) -> String {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *), let generation = error as? LanguageModelSession.GenerationError {
      switch generation {
      case .exceededContextWindowSize:
        return "This transcript is too long to summarize in one go."
      case .guardrailViolation, .refusal:
        return "Apple Intelligence declined to summarize this transcript."
      case .unsupportedLanguageOrLocale:
        return "Apple Intelligence does not support this language yet."
      case .assetsUnavailable:
        return "The on-device model is not ready. Try again in a moment."
      case .rateLimited:
        return "Too many requests in a row. Try again in a moment."
      case .concurrentRequests:
        return "A summary is already being written."
      case .decodingFailure, .unsupportedGuide:
        return "The model's answer could not be read. Try again."
      @unknown default:
        return "The on-device model could not write a summary. Try again."
      }
    }
    #endif
    return "The on-device model could not write a summary. Try again."
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
