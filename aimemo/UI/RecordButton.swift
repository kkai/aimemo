//
//  RecordButton.swift
//  Animation Fun
//
//  Created by kai on 2024/05/17.
//

import SwiftUI

struct RecordButton: View {
    @Binding var isActive: Bool
    @State var startAction = { }
    @State var stopAction = { }
    
    @State var buttonColor: Color = .red
    @State var borderStrokeColor: Color = .white
    @State var borderStrokeWidth: CGFloat = 2
    @State var borderSpacing: CGFloat = 10
    @State var animation: Animation = .easeInOut
    @State var stoppedStateCornerRadius: CGFloat = 0.10
    @State var stoppedStateSize: CGFloat = 0.5
    
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Circle()
                    .stroke(.black, lineWidth: 2.3)
                Circle()
                    .stroke(borderStrokeColor, lineWidth: borderStrokeWidth)
                
                recordButton(size: geometry.size.width - borderSpacing)
                    .animation(animation, value: isActive)
                    .foregroundColor(buttonColor)
            }
        }
    }
    
    func activate() {
        isActive = true
        startAction()
    }
    
    func deactivate() {
        isActive = false
        stopAction()
    }
    
    private func recordButton(size: CGFloat) -> some View {
        if !isActive {
            return Button(action: { activate() }) {
                RoundedRectangle(cornerRadius: size)
                    .frame(width: size, height: size)
            }
        } else {
            return Button(action: { deactivate() }) {
                RoundedRectangle(cornerRadius: size * stoppedStateCornerRadius)
                    .frame(width: size * stoppedStateSize, height: size * stoppedStateSize)
            }
        }
    }
}

struct RecordButton_Previews: PreviewProvider {
    static var previews: some View {
        RecordButton(isActive: .constant(false))
    }
}
