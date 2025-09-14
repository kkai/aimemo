//
//  ContentView.swift
//  aimemo
//
//  Created by kai on 13.09.25.
//

import SwiftUI
import AVFoundation
#if os(iOS)
import GoogleMobileAds
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
                #if os(iOS)
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
                #if os(iOS)
                Text("[Get ai-Memo Pro with no ads](https://apps.apple.com/app/ai-memo-pro/id6503480155)").foregroundStyle(.blue).padding()
                #endif
                
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
                
                HStack {
                    Button("start to transcribe", action: {
                        Task {
                            audioProcessor.canStop = true
                            do {
                                try audioProcessor.startRealTimeProcessingAndPlayback()
                            } catch {
                                print("Error starting real-time processing and playback: \(error.localizedDescription)")
                            }
                        }
                    }).buttonStyle(.bordered)
                        .foregroundStyle(.red)
                        .disabled(audioProcessor.canStop)
                    
                    Button("stop to transcribe", action: {
                        Task {
                            audioProcessor.stopRecord()
                            audioProcessor.canStop = false
                        }
                    }).buttonStyle(.bordered)
                        .foregroundStyle(.red)
                        .disabled(!audioProcessor.canStop)
                }
                
            }
        }
    }
}

#Preview {
    ContentView()
}
