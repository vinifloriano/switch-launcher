import AVFoundation

public enum UISound: CaseIterable, Sendable {
    /// Cursor moved.
    case move
    /// Confirm / open.
    case select
    /// Back / cancel.
    case back
    /// Software starting.
    case launch
    /// Not possible.
    case error
    /// The HOME button "click".
    case home
    /// Toggle or choice changed.
    case toggle
    /// Startup chime.
    case boot
    /// Wake from sleep.
    case wake
    /// Screenshot shutter.
    case capture
    /// Quick Settings panel opening.
    case panel
}

/// Plays short UI sounds that are synthesized at startup, so no audio files ship with the app.
@MainActor
public final class UISoundPlayer {
    public var isEnabled = true
    public var volume: Float = 0.7 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [UISound: AVAudioPCMBuffer] = [:]

    public init() {
        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.mainMixerNode.outputVolume = volume
        for sound in UISound.allCases {
            buffers[sound] = Synth.render(Synth.recipe(for: sound), format: format)
        }
    }

    public func play(_ sound: UISound) {
        guard isEnabled, let buffer = buffers[sound] else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer)
        player.play()
    }
}

enum Synth {
    struct Tone {
        var start: Double
        var duration: Double
        var fromHz: Double
        var toHz: Double
        var amplitude: Double
        /// Higher decays faster.
        var decay: Double = 6
        var harmonic: Double = 0
    }

    static func recipe(for sound: UISound) -> [Tone] {
        switch sound {
        case .move:
            return [Tone(start: 0, duration: 0.035, fromHz: 1_550, toHz: 1_350, amplitude: 0.35, decay: 9, harmonic: 0.25)]
        case .select:
            return [
                Tone(start: 0, duration: 0.05, fromHz: 990, toHz: 1_180, amplitude: 0.35, decay: 5),
                Tone(start: 0.045, duration: 0.09, fromHz: 1_480, toHz: 1_560, amplitude: 0.3, decay: 6, harmonic: 0.2),
            ]
        case .back:
            return [Tone(start: 0, duration: 0.08, fromHz: 900, toHz: 620, amplitude: 0.32, decay: 6)]
        case .launch:
            return [
                Tone(start: 0, duration: 0.32, fromHz: 523, toHz: 1_568, amplitude: 0.28, decay: 3, harmonic: 0.2),
                Tone(start: 0.12, duration: 0.3, fromHz: 1_046, toHz: 2_093, amplitude: 0.18, decay: 4),
            ]
        case .error:
            return [
                Tone(start: 0, duration: 0.09, fromHz: 240, toHz: 230, amplitude: 0.4, decay: 4, harmonic: 0.5),
                Tone(start: 0.11, duration: 0.11, fromHz: 200, toHz: 190, amplitude: 0.4, decay: 4, harmonic: 0.5),
            ]
        case .home:
            return [
                Tone(start: 0, duration: 0.025, fromHz: 2_500, toHz: 2_200, amplitude: 0.45, decay: 10, harmonic: 0.4),
                Tone(start: 0.065, duration: 0.03, fromHz: 1_900, toHz: 1_700, amplitude: 0.45, decay: 10, harmonic: 0.4),
            ]
        case .toggle:
            return [Tone(start: 0, duration: 0.045, fromHz: 1_200, toHz: 1_520, amplitude: 0.33, decay: 6)]
        case .boot:
            return [523.25, 659.25, 783.99, 1_046.5].enumerated().map { i, hz in
                Tone(start: Double(i) * 0.09, duration: 0.55, fromHz: hz, toHz: hz, amplitude: 0.2, decay: 4, harmonic: 0.15)
            }
        case .wake:
            return [Tone(start: 0, duration: 0.18, fromHz: 660, toHz: 990, amplitude: 0.3, decay: 4)]
        case .capture:
            return [
                Tone(start: 0, duration: 0.03, fromHz: 3_200, toHz: 2_400, amplitude: 0.35, decay: 12, harmonic: 0.6),
                Tone(start: 0.06, duration: 0.05, fromHz: 2_000, toHz: 1_400, amplitude: 0.35, decay: 10, harmonic: 0.6),
            ]
        case .panel:
            return [Tone(start: 0, duration: 0.12, fromHz: 700, toHz: 1_250, amplitude: 0.28, decay: 4)]
        }
    }

    static func render(_ tones: [Tone], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let length = (tones.map { $0.start + $0.duration }.max() ?? 0) + 0.02
        let frames = AVAudioFrameCount(length * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { samples[i] = 0 }

        for tone in tones {
            let startFrame = Int(tone.start * rate)
            let count = Int(tone.duration * rate)
            var phase = 0.0
            for n in 0..<count where startFrame + n < Int(frames) {
                let progress = Double(n) / Double(count)
                let hz = tone.fromHz + (tone.toHz - tone.fromHz) * progress
                phase += 2 * .pi * hz / rate
                let attack = min(1, Double(n) / (0.002 * rate))
                let envelope = attack * exp(-tone.decay * progress) * (1 - progress)
                let wave = sin(phase) + tone.harmonic * sin(2 * phase)
                samples[startFrame + n] += Float(tone.amplitude * envelope * wave)
            }
        }
        return buffer
    }
}
