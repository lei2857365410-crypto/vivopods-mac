import SwiftUI

/// 系统音量滑块（osascript 版，跟你验证过的命令一致）
struct VolumeSliderView: View {
    @State private var volume: Double = 0.5
    @State private var isMuted = false
    @State private var lastVolumeBeforeMute: Double = 0.5

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Slider(value: $volume, in: 0...1)
                .controlSize(.small)
                .onChange(of: volume) { _, newValue in
                    setSystemVolume(newValue)
                    if newValue > 0 && isMuted { isMuted = false }
                }

            Button {
                toggleMute()
            } label: {
                Image(systemName: isMuted ? "speaker.wave.2" : "speaker.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(isMuted ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 18)
        }
        .onAppear {
            refreshFromSystem()
        }
    }

    private func refreshFromSystem() {
        // 读取当前系统音量
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "output volume of (get volume settings)"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8),
               let vol = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                volume = Double(vol) / 100.0
                isMuted = (vol == 0)
            }
        } catch {
            print("读取音量失败: \(error)")
        }
    }

    private func toggleMute() {
        if isMuted {
            let restore = lastVolumeBeforeMute > 0 ? lastVolumeBeforeMute : 0.5
            volume = restore
            isMuted = false
        } else {
            lastVolumeBeforeMute = volume
            volume = 0
            isMuted = true
        }
        setSystemVolume(volume)
    }

    private func setSystemVolume(_ value: Double) {
        let percent = Int(value * 100)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "set volume output volume \(percent)"]
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("设置音量失败: \(error)")
        }
    }
}