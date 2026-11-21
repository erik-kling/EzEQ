import CoreAudio
import Foundation

private let system = AudioObjectID(kAudioObjectSystemObject)

private func address(_ selector: AudioObjectPropertySelector,
                     _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

private struct AudioFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func check(_ result: OSStatus, _ operation: String) throws {
    if result != noErr {
        throw AudioFailure(message: "\(operation) failed (Core Audio \(result)).")
    }
}

private func readProperty<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                             _ initial: T) throws -> T {
    var property = address(selector)
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    try withUnsafeMutableBytes(of: &value) {
        try check(AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0.baseAddress!),
                  "Reading the audio device configuration")
    }
    return value
}

private func channelCount(_ object: AudioObjectID, _ scope: AudioObjectPropertyScope) throws -> UInt32 {
    var property = address(kAudioDevicePropertyStreamConfiguration, scope)
    guard AudioObjectHasProperty(object, &property) else { return 0 }
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size), "Checking audio channels")
    let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { data.deallocate() }
    try check(AudioObjectGetPropertyData(object, &property, 0, nil, &size, data), "Reading audio channels")
    return UnsafeMutableAudioBufferListPointer(data.assumingMemoryBound(to: AudioBufferList.self))
        .reduce(0) { $0 + $1.mNumberChannels }
}

final class AudioRoute {
    private(set) var output = AudioObjectID(kAudioObjectUnknown)
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var io: AudioDeviceIOProcID?
    private var dsp: OpaquePointer?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var rateListener: AudioObjectPropertyListenerBlock?
    func takeAudioActivity() -> Bool {
        dsp.map { ezeq_dsp_take_audio_activity($0) } ?? false
    }

    func start(_ profile: Profile, onRouteChange: @escaping () -> Void) throws {
        stop()
        do {
            try open(profile)
            let listener: AudioObjectPropertyListenerBlock = { _, _ in onRouteChange() }
            var deviceProperty = address(kAudioHardwarePropertyDefaultOutputDevice)
            try check(AudioObjectAddPropertyListenerBlock(system, &deviceProperty, .main, listener),
                      "Watching the selected audio output")
            outputListener = listener
            let rate: AudioObjectPropertyListenerBlock = { _, _ in onRouteChange() }
            var rateProperty = address(kAudioDevicePropertyNominalSampleRate)
            try check(AudioObjectAddPropertyListenerBlock(output, &rateProperty, .main, rate),
                      "Watching the output sample rate")
            rateListener = rate
        } catch {
            stop()
            throw error
        }
    }

    private func open(_ profile: Profile) throws {
        output = try readProperty(system, kAudioHardwarePropertyDefaultOutputDevice, AudioObjectID(0))
        guard output != kAudioObjectUnknown,
              try channelCount(output, kAudioDevicePropertyScopeOutput) >= 2 else {
            throw AudioFailure(message: "Select an output with at least two channels in System Settings → Sound.")
        }
        let outputUID = try readProperty(output, kAudioDevicePropertyDeviceUID, "" as CFString)
        let inputChannels = try channelCount(output, kAudioDevicePropertyScopeInput) + 2
        var pid = getpid()
        var processID = AudioObjectID(kAudioObjectUnknown)
        var processSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var lookup = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        try check(AudioObjectGetPropertyData(system, &lookup, UInt32(MemoryLayout<pid_t>.size),
                                             &pid, &processSize, &processID), "Finding the EzEQ audio process")
        guard processID != kAudioObjectUnknown else {
            throw AudioFailure(message: "EzEQ could not identify its own audio process.")
        }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [processID])
        description.name = "EzEQ"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        try check(AudioHardwareCreateProcessTap(description, &tap), "Starting system audio capture")

        let configuration: [String: Any] = [
            kAudioAggregateDeviceNameKey: "EzEQ Audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregate),
                  "Connecting capture to the audio output")
        let format = try readProperty(tap, kAudioTapPropertyFormat, AudioStreamBasicDescription())
        let rate = try readProperty(aggregate, kAudioDevicePropertyNominalSampleRate, 0.0)
        guard format.mChannelsPerFrame == 2, format.mFormatID == kAudioFormatLinearPCM,
              format.mBitsPerChannel == 32, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              rate > 0, let processor = ezeq_dsp_create(rate) else {
            throw AudioFailure(message: "The current output could not start a stereo EQ stream.")
        }
        dsp = processor
        ezeq_dsp_set_input_channels(processor, inputChannels)
        update(profile)
        try check(AudioDeviceCreateIOProcID(aggregate, ezeq_audio_io, UnsafeMutableRawPointer(processor), &io),
                  "Preparing audio playback")
        guard let io else {
            throw AudioFailure(message: "The audio device did not create a playback callback.")
        }
        try check(AudioDeviceStart(aggregate, io), "Playing equalized audio")
    }

    func update(_ profile: Profile) {
        if let dsp {
            profile.bands.withUnsafeBufferPointer { ezeq_dsp_update(dsp, $0.baseAddress!, profile.volume) }
        }
    }

    func stop() {
        if let outputListener {
            var property = address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(system, &property, .main, outputListener)
            self.outputListener = nil
        }
        if let rateListener {
            var property = address(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListenerBlock(output, &property, .main, rateListener)
            self.rateListener = nil
        }
        if let io {
            AudioDeviceStop(aggregate, io)
            AudioDeviceDestroyIOProcID(aggregate, io)
            self.io = nil
        }
        if aggregate != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregate)
            aggregate = kAudioObjectUnknown
        }
        if tap != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tap)
            tap = kAudioObjectUnknown
        }
        if let dsp { ezeq_dsp_destroy(dsp) }
        dsp = nil
        output = kAudioObjectUnknown
    }

    deinit { stop() }
}
