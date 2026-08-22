#!/usr/bin/env swift
import Foundation
import AVFoundation

guard CommandLine.argc >= 2 else {
    print("Usage: trim_audio <input> <output> [max_seconds]")
    exit(1)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let maxSeconds = Double(CommandLine.arguments[3]) ?? 29.0

do {
    let srcFile = try AVAudioFile(forReading: inputURL)
    let format = srcFile.processingFormat
    let sampleRate = format.sampleRate
    let channelCount = format.channelCount
    
    // Create output format
    guard let outFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelCount: channelCount) else {
        print("Failed to create output format")
        exit(1)
    }
    
    // Calculate max frames
    let maxFrames = UInt64(maxSeconds * sampleRate)
    let writeFrames = min(srcFile.length, maxFrames)
    
    // Read audio buffer
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(writeFrames)) else {
        print("Failed to create buffer")
        exit(1)
    }
    try srcFile.read(into: buffer)
    buffer.frameLength = AVAudioFrameCount(writeFrames)
    
    // Write as CAF
    let settings = outFormat.settings
    let outFile = try AVAudioFile(forWriting: outputURL, settings: settings)
    try outFile.write(from: buffer)
    
    let duration = Double(writeFrames) / sampleRate
    print("Trimmed: \(duration.formatted(.number.precision(.fractionLength(1))))s")
    
} catch {
    print("Error: \(error)")
    exit(1)
}
