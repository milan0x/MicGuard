//
//  AudioDeviceManager.swift
//  MicGuard
//
//  Core class for audio device enumeration and control using CoreAudio
//

import Foundation
import CoreAudio
import Combine
import AppKit

// MARK: - Audio Device Model

struct AudioDevice: Identifiable, Equatable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isInput: Bool
    let isOutput: Bool
    let transportType: UInt32

    init(id: AudioDeviceID, uid: String, name: String, isInput: Bool, isOutput: Bool, transportType: UInt32 = 0) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isInput = isInput
        self.isOutput = isOutput
        self.transportType = transportType
    }

    /// Heuristic: virtual / aggregate devices are usually rejected by macOS as the
    /// system default. False positives possible (e.g. Loopback by Rogue Amoeba).
    /// Reactive detection in the popover view model catches whatever this misses.
    var isLikelyUnsettable: Bool {
        transportType == kAudioDeviceTransportTypeVirtual
            || transportType == kAudioDeviceTransportTypeAggregate
    }

    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        return lhs.uid == rhs.uid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }
}

// MARK: - Protocol for Testability

protocol AudioDeviceManaging {
    var inputDevices: [AudioDevice] { get }
    var outputDevices: [AudioDevice] { get }
    var defaultInputDevice: AudioDevice? { get }
    var defaultOutputDevice: AudioDevice? { get }
    
    @discardableResult
    func setDefaultInputDevice(_ device: AudioDevice) -> Bool
    @discardableResult
    func setDefaultOutputDevice(_ device: AudioDevice) -> Bool
    func getInputVolume(for device: AudioDevice) -> Float?
    func setInputVolume(_ volume: Float, for device: AudioDevice) -> Bool
    func getOutputVolume(for device: AudioDevice) -> Float?
    func setOutputVolume(_ volume: Float, for device: AudioDevice) -> Bool
    func isDeviceRunning(_ device: AudioDevice) -> Bool
    func device(forUID uid: String) -> AudioDevice?
    func inputDevices(withName name: String) -> [AudioDevice]
    func outputDevices(withName name: String) -> [AudioDevice]

    var devicesChangedPublisher: PassthroughSubject<Void, Never> { get }
    var defaultInputChangedPublisher: PassthroughSubject<AudioDevice?, Never> { get }
    var defaultOutputChangedPublisher: PassthroughSubject<AudioDevice?, Never> { get }
    var inputDeviceRunningChangedPublisher: PassthroughSubject<Void, Never> { get }
}

// MARK: - AudioDeviceManager Implementation

class AudioDeviceManager: AudioDeviceManaging {
    
    // MARK: - Publishers
    
    let devicesChangedPublisher = PassthroughSubject<Void, Never>()
    let defaultInputChangedPublisher = PassthroughSubject<AudioDevice?, Never>()
    let defaultOutputChangedPublisher = PassthroughSubject<AudioDevice?, Never>()
    let inputDeviceRunningChangedPublisher = PassthroughSubject<Void, Never>()

    // MARK: - Properties

    private(set) var inputDevices: [AudioDevice] = []
    private(set) var outputDevices: [AudioDevice] = []

    private var deviceListListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultInputListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultOutputListenerBlock: AudioObjectPropertyListenerBlock?

    // Per-device running-state listeners. Keyed by deviceID so we can detach
    // a device's listener when it disappears from the system.
    private var inputRunningListenerBlocks: [(AudioDeviceID, AudioObjectPropertyListenerBlock)] = []
    private var streamActiveListenerBlocks: [(AudioStreamID, AudioObjectPropertyListenerBlock)] = []
    
    // MARK: - Computed Properties
    
    var defaultInputDevice: AudioDevice? {
        guard let deviceID = getDefaultDeviceID(isInput: true) else { return nil }
        return inputDevices.first { $0.id == deviceID }
    }
    
    var defaultOutputDevice: AudioDevice? {
        guard let deviceID = getDefaultDeviceID(isInput: false) else { return nil }
        return outputDevices.first { $0.id == deviceID }
    }
    
    // MARK: - Initialization
    
    init() {
        refreshDeviceList()
        setupListeners()
        
        // Register cleanup on app termination (defense against force-quit)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.removeListeners()
        }
    }
    
    deinit {
        removeListeners()
    }
    
    // MARK: - Device Enumeration
    
    func refreshDeviceList() {
        let deviceIDs = getAllDeviceIDs()
        
        var inputs: [AudioDevice] = []
        var outputs: [AudioDevice] = []
        
        for deviceID in deviceIDs {
            guard let device = createAudioDevice(from: deviceID) else { continue }
            
            if device.isInput {
                inputs.append(device)
            }
            if device.isOutput {
                outputs.append(device)
            }
        }
        
        inputDevices = inputs
        outputDevices = outputs
    }
    
    func device(forUID uid: String) -> AudioDevice? {
        return inputDevices.first { $0.uid == uid } ?? outputDevices.first { $0.uid == uid }
    }

    func inputDevices(withName name: String) -> [AudioDevice] {
        return inputDevices.filter { $0.name == name }
    }

    func outputDevices(withName name: String) -> [AudioDevice] {
        return outputDevices.filter { $0.name == name }
    }
    
    // MARK: - Device Control
    
    @discardableResult
    func setDefaultInputDevice(_ device: AudioDevice) -> Bool {
        return setDefaultDevice(deviceID: device.id, isInput: true)
    }
    
    @discardableResult
    func setDefaultOutputDevice(_ device: AudioDevice) -> Bool {
        return setDefaultDevice(deviceID: device.id, isInput: false)
    }
    
    // MARK: - Volume Control
    
    func getInputVolume(for device: AudioDevice) -> Float? {
        return getVolume(deviceID: device.id, isInput: true)
    }
    
    @discardableResult
    func setInputVolume(_ volume: Float, for device: AudioDevice) -> Bool {
        return setVolume(volume, deviceID: device.id, isInput: true)
    }

    func getOutputVolume(for device: AudioDevice) -> Float? {
        return getVolume(deviceID: device.id, isInput: false)
    }

    @discardableResult
    func setOutputVolume(_ volume: Float, for device: AudioDevice) -> Bool {
        return setVolume(volume, deviceID: device.id, isInput: false)
    }
    
    // MARK: - Activity Detection

    func isDeviceRunning(_ device: AudioDevice) -> Bool {
        // Check if device is running somewhere (any process on the system)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var isRunningSomewhere: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            device.id,
            &propertyAddress,
            0, nil,
            &size,
            &isRunningSomewhere
        )

        return status == noErr && isRunningSomewhere != 0
    }
    
    // MARK: - Private Methods - Device Enumeration
    
    private func getAllDeviceIDs() -> [AudioDeviceID] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        
        guard status == noErr else { return [] }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else { return [] }
        return deviceIDs
    }
    
    private func createAudioDevice(from deviceID: AudioDeviceID) -> AudioDevice? {
        guard let name = getDeviceName(deviceID: deviceID),
              let uid = getDeviceUID(deviceID: deviceID) else {
            return nil
        }

        let hasInput = hasStreams(deviceID: deviceID, isInput: true)
        let hasOutput = hasStreams(deviceID: deviceID, isInput: false)

        // Skip devices with no streams
        guard hasInput || hasOutput else { return nil }

        return AudioDevice(
            id: deviceID,
            uid: uid,
            name: name,
            isInput: hasInput,
            isOutput: hasOutput,
            transportType: getTransportType(deviceID: deviceID)
        )
    }

    private func getTransportType(deviceID: AudioDeviceID) -> UInt32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &value)
        return status == noErr ? value : 0
    }
    
    private func getDeviceName(deviceID: AudioDeviceID) -> String? {
        return getCFStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceNameCFString)
    }

    private func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        return getCFStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID)
    }

    private func getCFStringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &size,
            &value
        )

        guard status == noErr, let cfString = value?.takeRetainedValue() else { return nil }
        return cfString as String
    }
    
    private func hasStreams(deviceID: AudioDeviceID, isInput: Bool) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize
        )
        
        guard status == noErr else { return false }
        return dataSize > 0
    }
    
    // MARK: - Private Methods - Default Device
    
    private func getDefaultDeviceID(isInput: Bool) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &size,
            &deviceID
        )
        
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }
    
    private func setDefaultDevice(deviceID: AudioDeviceID, isInput: Bool) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var mutableDeviceID = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        )
        
        return status == noErr
    }
    
    // MARK: - Private Methods - Volume Control
    
    private func getVolume(deviceID: AudioDeviceID, isInput: Bool) -> Float? {
        // Try master channel first
        if let volume = getVolumeForChannel(deviceID: deviceID, isInput: isInput, channel: kAudioObjectPropertyElementMain) {
            return volume
        }
        
        // Fallback to channel 1
        return getVolumeForChannel(deviceID: deviceID, isInput: isInput, channel: 1)
    }
    
    private func getVolumeForChannel(deviceID: AudioDeviceID, isInput: Bool, channel: UInt32) -> Float? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
        
        guard AudioObjectHasProperty(deviceID, &propertyAddress) else { return nil }
        
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &size,
            &volume
        )
        
        guard status == noErr else { return nil }
        return volume
    }
    
    private func setVolume(_ volume: Float, deviceID: AudioDeviceID, isInput: Bool) -> Bool {
        let clampedVolume = max(0, min(1, volume))
        
        // Try master channel first
        if setVolumeForChannel(clampedVolume, deviceID: deviceID, isInput: isInput, channel: kAudioObjectPropertyElementMain) {
            return true
        }
        
        // Fallback: Set channels 1 and 2 individually
        let ch1Success = setVolumeForChannel(clampedVolume, deviceID: deviceID, isInput: isInput, channel: 1)
        let ch2Success = setVolumeForChannel(clampedVolume, deviceID: deviceID, isInput: isInput, channel: 2)
        
        return ch1Success || ch2Success
    }
    
    private func setVolumeForChannel(_ volume: Float, deviceID: AudioDeviceID, isInput: Bool, channel: UInt32) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
        
        guard AudioObjectHasProperty(deviceID, &propertyAddress) else { return false }
        
        var mutableVolume = volume
        let status = AudioObjectSetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            UInt32(MemoryLayout<Float32>.size),
            &mutableVolume
        )
        
        return status == noErr
    }
    
    // MARK: - Running State Listeners

    /// Attach the device-running listener and stream-active listeners to ALL real
    /// input devices, not just the current default. This makes the mic-in-use
    /// indicator fire instantly when any app starts/stops capturing from any mic —
    /// without it, non-default devices only get caught by the 2s polling fallback.
    private func registerAllInputRunningListeners() {
        unregisterAllInputRunningListeners()

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        for device in inputDevices {
            // Skip virtual / aggregate — they tend to fire spurious "running" events
            // (Teams Audio is "running" any time Teams routes audio) which would
            // create false ON indicator triggers.
            if device.isLikelyUnsettable { continue }

            let block: AudioObjectPropertyListenerBlock = { [weak self] (_, _) in
                DispatchQueue.main.async {
                    self?.inputDeviceRunningChangedPublisher.send()
                }
            }
            AudioObjectAddPropertyListenerBlock(device.id, &address, nil, block)
            inputRunningListenerBlocks.append((device.id, block))

            registerStreamActiveListeners(deviceID: device.id)
        }
    }

    private func unregisterAllInputRunningListeners() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        for (deviceID, block) in inputRunningListenerBlocks {
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, nil, block)
        }
        inputRunningListenerBlocks.removeAll()

        unregisterStreamActiveListeners()
    }

    private func registerStreamActiveListeners(deviceID: AudioDeviceID) {
        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &streamsAddress, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return }

        let streamCount = Int(dataSize) / MemoryLayout<AudioStreamID>.size
        var streamIDs = [AudioStreamID](repeating: 0, count: streamCount)

        guard AudioObjectGetPropertyData(deviceID, &streamsAddress, 0, nil, &dataSize, &streamIDs) == noErr else {
            return
        }

        for streamID in streamIDs {
            var activeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyIsActive,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            let block: AudioObjectPropertyListenerBlock = { [weak self] (_, _) in
                DispatchQueue.main.async {
                    self?.inputDeviceRunningChangedPublisher.send()
                }
            }

            AudioObjectAddPropertyListenerBlock(streamID, &activeAddress, nil, block)
            streamActiveListenerBlocks.append((streamID, block))
        }
    }

    private func unregisterStreamActiveListeners() {
        for (streamID, block) in streamActiveListenerBlocks {
            var activeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyIsActive,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(streamID, &activeAddress, nil, block)
        }
        streamActiveListenerBlocks.removeAll()
    }

    // MARK: - Listeners

    private func setupListeners() {
        // Device list changes
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        deviceListListenerBlock = { [weak self] (_, _) in
            DispatchQueue.main.async {
                MGLog.debug("[MicGuard.CoreAudio] kAudioHardwarePropertyDevices fired")
                self?.refreshDeviceList()
                // Re-attach per-device running-state listeners so newly-plugged
                // mics participate in the event-driven detection.
                self?.registerAllInputRunningListeners()
                self?.devicesChangedPublisher.send()
            }
        }
        
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            nil,
            deviceListListenerBlock!
        )
        
        // Default input changes
        var inputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        defaultInputListenerBlock = { [weak self] (_, _) in
            DispatchQueue.main.async {
                let dev = self?.defaultInputDevice
                MGLog.debug("[MicGuard.CoreAudio] kAudioHardwarePropertyDefaultInputDevice fired → \(dev?.name ?? "nil")")
                self?.defaultInputChangedPublisher.send(dev)
                // Refresh per-device listeners — most relevant if device list changed,
                // but cheap enough to also re-affirm when default switches.
                self?.registerAllInputRunningListeners()
            }
        }
        
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &inputAddress,
            nil,
            defaultInputListenerBlock!
        )
        
        // Default output changes
        var outputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        defaultOutputListenerBlock = { [weak self] (_, _) in
            DispatchQueue.main.async {
                self?.defaultOutputChangedPublisher.send(self?.defaultOutputDevice)
            }
        }
        
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &outputAddress,
            nil,
            defaultOutputListenerBlock!
        )

        // Running state listeners on ALL real input devices so we catch
        // mic-in-use changes regardless of which device is the current default.
        registerAllInputRunningListeners()
    }

    private func removeListeners() {
        unregisterAllInputRunningListeners()

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        if let block = deviceListListenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &devicesAddress,
                nil,
                block
            )
        }
        
        var inputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        if let block = defaultInputListenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &inputAddress,
                nil,
                block
            )
        }
        
        var outputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        if let block = defaultOutputListenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &outputAddress,
                nil,
                block
            )
        }
    }
}
