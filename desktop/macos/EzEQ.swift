import AppKit
import SwiftUI

private let bandLabels = ["60 Hz", "150 Hz", "400 Hz", "1 kHz", "2.4 kHz", "15 kHz"]

struct Profile: Codable, Equatable {
    var bands: [Double]
    var volume: Double
    static let flat = Profile(bands: Array(repeating: 0, count: 6), volume: 0)

    var valid: Bool {
        bands.count == 6 && bands.allSatisfy { (-12...12).contains($0) } && (-61...6).contains(volume)
    }
}

struct Preset: Codable {
    var name: String
    var bands: [Double]?
    var volume: Double?

    var profile: Profile? {
        get {
            guard let bands, let volume else { return nil }
            let value = Profile(bands: bands, volume: volume)
            return value.valid ? value : nil
        }
        set {
            bands = newValue?.bands
            volume = newValue?.volume
        }
    }
}

private struct Settings: Codable {
    let bands: [Double]
    let volume: Double
    let presets: [Preset]

    static var file: URL {
        URL.applicationSupportDirectory.appending(path: "EzEQ/settings.json")
    }

    static func load() -> (Profile, [Preset]) {
        var slots = (1...5).map { Preset(name: "Preset \($0)") }
        guard let data = try? Data(contentsOf: file),
              let stored = try? JSONDecoder().decode(Settings.self, from: data) else {
            return (.flat, slots)
        }
        for (index, saved) in stored.presets.prefix(5).enumerated() {
            let name = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { slots[index].name = String(name.prefix(40)) }
            slots[index].profile = saved.profile
        }
        let profile = Profile(bands: stored.bands, volume: stored.volume)
        return (profile.valid ? profile : .flat, slots)
    }
}

final class EzEQModel: ObservableObject {
    @Published var profile: Profile
    @Published private(set) var presets: [Preset]
    @Published private(set) var previous: Profile?
    @Published private(set) var running = false
    @Published private(set) var audioStatus = "Audio stopped."
    @Published private(set) var settingsError: String?
    private var saveTask: DispatchWorkItem?
    private var watchdog: DispatchWorkItem?
    private let route = AudioRoute()

    init() {
        let (savedProfile, savedPresets) = Settings.load()
        _profile = Published(initialValue: savedProfile)
        _presets = Published(initialValue: savedPresets)
    }

    func start() {
        watchdog?.cancel()
        do {
            try route.start(profile) { [weak self] in
                guard let self, self.running else { return }
                self.start()
            }
            running = true
            audioStatus = "Equalizing the current system output."
            watchAudio()
        } catch {
            running = false
            audioStatus = "\(error.localizedDescription) Check the selected output and EzEQ’s audio capture permission."
        }
    }

    private func watchAudio() {
        let verify = DispatchWorkItem { [weak self] in
            guard let self, self.running else { return }
            if self.route.takeAudioActivity() {
                self.watchAudio()
            } else {
                self.stop()
                self.audioStatus = "Audio capture stopped. Check the output and EzEQ’s system audio permission."
            }
        }
        watchdog = verify
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: verify)
    }

    func stop() {
        watchdog?.cancel()
        watchdog = nil
        running = false
        route.stop()
        audioStatus = "Audio stopped."
    }

    func update() {
        route.update(profile)
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.save() }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
    }

    func replace(_ value: Profile) {
        guard profile != value else { return }
        previous = profile
        profile = value
    }

    func savePreset(_ index: Int) {
        presets[index].profile = profile
        save()
    }

    func rename(_ index: Int, to text: String) {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            presets[index].name = String(name.prefix(40))
            save()
        }
    }

    func save() {
        saveTask?.cancel()
        saveTask = nil
        do {
            try FileManager.default.createDirectory(at: Settings.file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Settings(bands: profile.bands, volume: profile.volume, presets: presets))
            try data.write(to: Settings.file, options: .atomic)
            settingsError = nil
        } catch {
            settingsError = "Could not save settings. \(error.localizedDescription)"
        }
    }
}

private struct Curve: Shape {
    let bands: [Double]

    func path(in rect: CGRect) -> Path {
        let step = rect.width / 6
        let points = bands.enumerated().map { index, gain in
            CGPoint(x: step * (CGFloat(index) + 0.5), y: rect.midY - CGFloat(gain) / 12 * (rect.height / 2 - 4))
        }
        var path = Path()
        path.move(to: points[0])
        for (a, b) in zip(points, points.dropFirst()) {
            path.addCurve(to: b, control1: CGPoint(x: a.x + step / 3, y: a.y),
                          control2: CGPoint(x: b.x - step / 3, y: b.y))
        }
        return path
    }
}

struct EqualizerView: View {
    @ObservedObject var model: EzEQModel
    @FocusState private var focused: Int?
    @State private var editing: Int?
    @State private var presetName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ForEach(model.presets.indices, id: \.self) { index in
                    presetBox(index).frame(maxWidth: .infinity)
                }
                Menu("Save preset") {
                    ForEach(model.presets.indices, id: \.self) { index in
                        Button("\(index + 1). \(model.presets[index].name)") { model.savePreset(index) }
                    }
                }.fixedSize()
            }
            Curve(bands: model.profile.bands)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(height: 66)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                ForEach(bandLabels.indices, id: \.self) { index in
                    VStack(spacing: 8) {
                        Text(db(model.profile.bands[index])).monospacedDigit()
                        Slider(value: $model.profile.bands[index], in: -12...12, step: 0.1)
                            .frame(width: 140)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 28, height: 144)
                            .accessibilityLabel(bandLabels[index])
                        Text(bandLabels[index])
                    }.frame(maxWidth: .infinity)
                }
            }
            Divider()
            HStack {
                Text("Volume")
                Slider(value: $model.profile.volume, in: -61...6, step: 0.5)
                    .accessibilityLabel("Output volume")
                Text(model.profile.volume == -61 ? "Mute" : db(model.profile.volume))
                    .monospacedDigit().frame(width: 62)
                Button("Previous") {
                    if let value = model.previous { model.replace(value) }
                }.disabled(model.previous == nil)
                Button("Reset") { model.replace(.flat) }
            }
            HStack {
                VStack(alignment: .leading) {
                    Text(model.audioStatus)
                    Text("Choose speakers, headphones, or a DAC in System Settings → Sound.")
                        .foregroundStyle(.secondary)
                    if let error = model.settingsError {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Spacer()
                Button(model.running ? "Stop audio" : "Start audio") {
                    if model.running { model.stop() } else { model.start() }
                }
            }
        }
        .padding(18)
        .frame(minWidth: 650, minHeight: 405)
        .onChange(of: model.profile) { _, _ in model.update() }
        .onChange(of: focused) { _, value in
            if value == nil { finishRename() }
        }
        .onDisappear { model.stop(); model.save() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.stop()
            model.save()
        }
    }

    @ViewBuilder
    private func presetBox(_ index: Int) -> some View {
        if editing == index {
            TextField("Preset name", text: $presetName)
                .focused($focused, equals: index)
                .onSubmit { finishRename() }
                .onAppear { focused = index }
        } else {
            Text(model.presets[index].name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 24)
                .padding(.horizontal, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
                .gesture(TapGesture(count: 2).onEnded {
                    finishRename()
                    presetName = model.presets[index].name
                    editing = index
                }.exclusively(before: TapGesture().onEnded { applyPreset(index) }))
                .contextMenu {
                    Button("Apply preset") { applyPreset(index) }
                        .disabled(model.presets[index].profile == nil)
                    Button("Rename preset") {
                        finishRename()
                        presetName = model.presets[index].name
                        editing = index
                    }
                }
                .help("Click to apply. Double-click to rename.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { applyPreset(index) }
        }
    }

    private func applyPreset(_ index: Int) {
        finishRename()
        if let value = model.presets[index].profile { model.replace(value) }
    }

    private func finishRename() {
        if let index = editing {
            editing = nil
            model.rename(index, to: presetName)
            focused = nil
        }
    }

    private func db(_ value: Double) -> String {
        value == 0 ? "0 dB" : String(format: "%+.1f dB", value)
    }
}

@main struct EzEQApp: App {
    @StateObject private var model = EzEQModel()

    var body: some Scene {
        Window("EzEQ", id: "main") { EqualizerView(model: model) }
            .windowResizability(.contentMinSize)
    }
}
