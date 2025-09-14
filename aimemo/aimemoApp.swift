//
//  aimemoApp.swift
//  aimemo
//
//  Created by kai on 13.09.25.
//

import SwiftUI

@main
struct aimemoApp: App {
    @State private var audioProcessor = RealTimeWhisper()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(audioProcessor)
        }
    }
}
