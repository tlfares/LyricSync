import SwiftUI
import AVFoundation

extension Notification.Name {
    static let waveformStopAll = Notification.Name("waveformStopAllAudio")
}

struct WaveformEditorView: View {
    let audioURL: URL
    let initialTime: TimeInterval
    let verseText: String
    let onConfirm: (TimeInterval) -> Void
    let onCancel: () -> Void

    @State private var waveform: WaveformData?
    @State private var currentTime: TimeInterval
    @State private var isLoading = true
    @State private var audioPlayer: AVAudioPlayer?
    @State private var screenWidth: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var playWork: DispatchWorkItem?
    @State private var cleanupToken = CleanupToken()
    @State private var dragStartOffset: CGFloat = 0
    @State private var didSetInitialOffset = false
    @State private var playbackTimer: Timer?
    @State private var playbackProgress: TimeInterval?

    init(audioURL: URL, initialTime: TimeInterval, verseText: String, onConfirm: @escaping (TimeInterval) -> Void, onCancel: @escaping () -> Void) {
        self.audioURL = audioURL
        self.initialTime = initialTime
        self.verseText = verseText
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _currentTime = State(initialValue: initialTime)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                versePreview

                if isLoading {
                    Spacer()
                    ProgressView("Loading waveform…")
                    Spacer()
                } else {
                    cursorHeader
                        .padding(.top, 16)

                    waveformArea
                        .padding(.vertical, 12)

                    playbackBar
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                }
            }
#if os(macOS)
            .frame(minWidth: 500, minHeight: 350)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cleanup(); onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") { stopAudio(); onConfirm(currentTime) }
                        .bold()
                }
            }
            .task { await loadWaveform() }
            .onDisappear { cleanup() }
            .onReceive(NotificationCenter.default.publisher(for: .waveformStopAll)) { _ in
                stopAudio()
            }
        }
    }

    private var versePreview: some View {
        Text(verseText)
            .font(.system(.body, design: .default))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .padding(.top, 8)
    }

    private var cursorHeader: some View {
        Text(formatted(currentTime))
            .font(.system(.title, design: .monospaced))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.snappy, value: currentTime)
    }

    private var pointWidth: CGFloat {
        guard let w = waveform, screenWidth > 0 else { return 2 }
        let raw = (screenWidth * 10) / CGFloat(w.samples.count)
        return max(0.3, min(10, raw))
    }

    private var totalWaveformWidth: CGFloat {
        guard let w = waveform, screenWidth > 0 else { return 0 }
        return CGFloat(w.samples.count) * pointWidth
    }

    private var waveformArea: some View {
        GeometryReader { geo in
            let sw = geo.size.width
            let ch = geo.size.height

            if let w = waveform {
                let pw = pointWidth

                Canvas { context, size in
                    let midY = size.height / 2
                    let maxH = size.height * 0.85
                    let path = Path { p in
                        guard !w.samples.isEmpty else { return }
                        for (i, sample) in w.samples.enumerated() {
                            let x = CGFloat(i) * pw - scrollOffset
                            let h = CGFloat(sample) * maxH
                            p.move(to: CGPoint(x: x, y: midY - h))
                            p.addLine(to: CGPoint(x: x, y: midY + h))
                        }
                    }
                    context.stroke(path, with: .color(.accentColor.opacity(0.7)), lineWidth: 1)
                }
                .frame(width: sw, height: ch)
                .clipped()
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let delta = value.translation.width
                            if abs(delta) > 1 {
                                let halfW = sw / 2
                                let t = totalWaveformWidth
                                let minScroll = -halfW
                                let maxScroll = t - halfW
                                scrollOffset = max(minScroll, min(maxScroll, dragStartOffset - delta))
                                updateTime()
                                debouncePlay()
                            }
                        }
                        .onEnded { _ in
                            dragStartOffset = scrollOffset
                        }
                )
                .onTapGesture {
                    playAtCurrent()
                }
                .overlay(alignment: .center) {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2)
                        .shadow(color: .accentColor.opacity(0.5), radius: 4)
                }
                .overlay(alignment: .topLeading) {
                    if let progress = playbackProgress {
                        let redX = (progress / w.totalDuration) * totalWaveformWidth - scrollOffset
                        Rectangle()
                            .fill(.red)
                            .frame(width: 1.5)
                            .offset(x: redX)
                    }
                }
                .onAppear {
                    if !didSetInitialOffset {
                        screenWidth = sw
                        let halfW = sw / 2
                        let t = totalWaveformWidth
                        let targetX = (initialTime / w.totalDuration) * t
                        scrollOffset = max(-halfW, min(t - halfW, targetX - halfW))
                        didSetInitialOffset = true
                        dragStartOffset = scrollOffset
                        updateTime()
                        debouncePlay()
                    }
                }
            }
        }
        .frame(height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var playbackBar: some View {
        HStack(spacing: 12) {
            Text(formatted(currentTime))
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Slider(value: $currentTime, in: 0...(waveform?.totalDuration ?? 1)) { editing in
                if !editing { playAtCurrent() }
            }
            .tint(.accentColor)
            Text(formatted(waveform?.totalDuration ?? 0))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
        }
    }

    private func updateTime() {
        guard screenWidth > 0 else { return }
        let time = timeAt(x: scrollOffset + screenWidth / 2)
        currentTime = max(0, min(time, waveform?.totalDuration ?? 0))
    }

    private func timeAt(x: CGFloat) -> TimeInterval {
        let w = totalWaveformWidth
        guard let dur = waveform?.totalDuration, w > 0 else { return 0 }
        let ratio = x / w
        return ratio * dur
    }

    private func formatted(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        let ms = Int((t - TimeInterval(Int(t))) * 100)
        return String(format: "%02d:%02d.%02d", m, s, ms)
    }

    private func loadWaveform() async {
        do {
            let w = try await WaveformData.generate(from: audioURL)
            waveform = w
            isLoading = false
        } catch {
            isLoading = false
        }
    }

    private func playAtCurrent() {
        stopAudio()
        do {
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.currentTime = currentTime
            player.play()
            audioPlayer = player
            startPlaybackTimer()
        } catch {}
    }

    private func startPlaybackTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard self.audioPlayer?.isPlaying == true else {
                self.stopPlaybackTimer()
                return
            }
            Task { @MainActor in
                self.playbackProgress = self.audioPlayer?.currentTime
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackProgress = nil
    }

    private func stopAudio() {
        playWork?.cancel()
        audioPlayer?.stop()
        audioPlayer = nil
        stopPlaybackTimer()
    }

    private func cleanup() {
        cleanupToken.isCleanedUp = true
        playWork?.cancel()
        audioPlayer?.stop()
        audioPlayer = nil
        stopPlaybackTimer()
    }

    private func debouncePlay() {
        playWork?.cancel()
        let token = cleanupToken
        let work = DispatchWorkItem {
            guard !token.isCleanedUp else { return }
            Task { @MainActor in
                guard !token.isCleanedUp else { return }
                playAtCurrent()
            }
        }
        playWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private class CleanupToken {
        var isCleanedUp = false
    }
}
