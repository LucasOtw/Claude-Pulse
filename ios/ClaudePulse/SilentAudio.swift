import AVFoundation

/// Joue du silence en boucle pour qu'iOS laisse l'app tourner en arrière-plan
/// (mode « audio » déclaré dans Info.plist). Mélangé aux autres sons : ta musique n'est pas coupée.
final class SilentAudio {
    private var player: AVAudioPlayer?
    private var observer: NSObjectProtocol?

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        if player == nil {
            player = try? AVAudioPlayer(data: Self.silentWAV())
            player?.numberOfLoops = -1
            player?.volume = 0
        }
        player?.play()

        // Après un appel ou une alarme, iOS met l'audio en pause : on relance.
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            self?.player?.play()
        }
    }

    func stop() {
        player?.stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Une seconde de silence au format WAV (PCM 16 bits mono, 8 kHz), générée en mémoire.
    static func silentWAV(seconds: Int = 1, sampleRate: Int = 8000) -> Data {
        let dataSize = seconds * sampleRate * 2
        var d = Data()
        d.append(contentsOf: Array("RIFF".utf8))
        d.appendLE(UInt32(36 + dataSize))
        d.append(contentsOf: Array("WAVEfmt ".utf8))
        d.appendLE(UInt32(16)) // taille du bloc fmt
        d.appendLE(UInt16(1)) // PCM
        d.appendLE(UInt16(1)) // mono
        d.appendLE(UInt32(sampleRate))
        d.appendLE(UInt32(sampleRate * 2)) // octets par seconde
        d.appendLE(UInt16(2)) // octets par échantillon
        d.appendLE(UInt16(16)) // bits par échantillon
        d.append(contentsOf: Array("data".utf8))
        d.appendLE(UInt32(dataSize))
        d.append(Data(count: dataSize))
        return d
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
