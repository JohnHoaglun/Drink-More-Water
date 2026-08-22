import Foundation
import AVFoundation

let input = URL(fileURLWithPath: CommandLine.arguments[0])
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let maxSeconds = Double(CommandLine.arguments[2]) ?? 29.0

do {
    let srcFile = try AVAudioFile(forReading: input)
    let format = srcFile.processingFormat
    let sampleRate = format.sampleRate
    let channelCount = format.channelCount
    let frameCount = srcFile.length
    
    let maxFrames = AVAudioFramePosition(Int64(maxSeconds * sampleRate))
    let writeFrames = min(frameCount, maxFrames)
    
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(writeFrames)) else {
        print("Buffer creation failed")
        exit(1)
    }
    try srcFile.read(into: buffer)
    buffer.frameLength = AVAudioFrameCount(writeFrames)
    
    let outFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)!
    let settings = outFormat.settings
    let outFile = try AVAudioFile(forWriting: output, settings: settings)
    try outFile.write(from: buffer)
    
    let duration = Double(writeFrames) / sampleRate
    print("Trimmed to \(String(format: "%.1f", duration))s -> \(output.path)")
    
} catch {
    print("Error: \(error)")
    exit(1)
}
