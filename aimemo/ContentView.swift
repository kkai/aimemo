//
//  ContentView.swift
//  aimemo
//
//  Created by kai on 13.09.25.
//

import SwiftUI
import AVFoundation
#if os(iOS)
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif
#elseif os(macOS)
import AppKit
#endif
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(RealTimeWhisper.self) var audioProcessor
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
       
            VStack(alignment: .center)  {
                #if canImport(GoogleMobileAds)
                HStack {
                    Spacer()
                    GADBannerViewController()
                        .frame(width: AdSizeBanner.size.width, height: AdSizeBanner.size.height)
                    Spacer()
                }
                #endif
                Text("aiMemo")
                    .font(.title)
                    .foregroundStyle(.white).padding()
                Text("Start recording speech to convert it to text. Longer recordings might take a while to convert.")
                    .foregroundStyle(.white).padding()
                #if canImport(GoogleMobileAds)
                Text("[Get ai-Memo Pro with no ads](https://apps.apple.com/app/ai-memo-pro/id6503480155)").foregroundStyle(.blue).padding()
                #endif

                // Status label
                Text(audioProcessor.canStop ? "Recording" : "Complete")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .stroke(Color.white, lineWidth: 1)
                    )
                    .padding(.top, 8)

                // Audio waveform visualization
                AudioWaveformView(levels: audioProcessor.audioLevels)
                    .frame(height: 60)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                
                ScrollView {
                    Text(verbatim: audioProcessor.transcribedText)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.textSelection(.enabled).padding()
                
                Spacer()
                HStack {
                    Button("copy to clipboard", action: {
                        Task {
                            #if os(iOS)
                            UIPasteboard.general.setValue(audioProcessor.transcribedText,
                                                          forPasteboardType: UTType.plainText.identifier)
                            #elseif os(macOS)
                            NSPasteboard.general.setString(audioProcessor.transcribedText, forType: .string)
                            #endif
                        }
                    }).buttonStyle(.bordered)
                        .foregroundStyle(.red)
                    
                    Button("delete text", action: {
                        Task {
                            audioProcessor.transcribedText = ""
                        }
                    }).buttonStyle(.bordered)
                        .foregroundStyle(.red)
                }.padding()
                
                // Animated record button
                HStack {
                    Spacer()
                    AnimatedRecordButton(
                        isRecording: Binding(
                            get: { audioProcessor.canStop },
                            set: { _ in }
                        ),
                        onStart: {
                            Task {
                                audioProcessor.canStop = true
                                do {
                                    try audioProcessor.startRealTimeProcessingAndPlayback()
                                } catch {
                                    print("Error starting real-time processing and playback: \(error.localizedDescription)")
                                }
                            }
                        },
                        onStop: {
                            Task {
                                audioProcessor.stopRecord()
                                audioProcessor.canStop = false
                            }
                        }
                    )
                    Spacer()
                }
                .padding(.vertical, 20)
                
            }
        }
    }
}

#Preview {
    ContentView()
}
