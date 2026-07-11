//
//  PauseDetector.swift
//  whisper.swiftui
//
//  Created by i on 2024/4/3.
//

import AVFoundation
import Accelerate

class PauseDetector {
    
    let energyThreshold: Float // 能量门限值
    let sampleRate: Float // 采样率
    let bufferDuration: TimeInterval // 缓冲区持续时间
    
    init(energyThreshold: Float, sampleRate: Float, bufferDuration: TimeInterval) {
        self.energyThreshold = energyThreshold
        self.sampleRate = sampleRate
        self.bufferDuration = bufferDuration
    }
    
    func isPause(buffer: AVAudioPCMBuffer) -> Bool {
        guard let samples = buffer.floatChannelData?.pointee else {
            return false
        }
        
        let sampleCount = Int(buffer.frameLength)
        
        var meanEnergy: Float = 0
        vDSP_measqv(samples, 1, &meanEnergy, vDSP_Length(sampleCount))
        
        return meanEnergy < energyThreshold
    }
}
