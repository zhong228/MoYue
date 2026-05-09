import SwiftUI
import Combine

// MARK: - Clock + Battery ViewModel

@MainActor
final class ClockBatteryModel: ObservableObject {
    @Published private(set) var displayTime: String = ""
    @Published private(set) var batteryIcon: String = "battery.100"

    private var timerCancellable: AnyCancellable?
    private var batteryLevelCancellable: AnyCancellable?
    private var batteryStateCancellable: AnyCancellable?
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshTime()
        refreshBattery()
        timerCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshTime() }
        batteryLevelCancellable = NotificationCenter.default
            .publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .sink { [weak self] _ in self?.refreshBattery() }
        batteryStateCancellable = NotificationCenter.default
            .publisher(for: UIDevice.batteryStateDidChangeNotification)
            .sink { [weak self] _ in self?.refreshBattery() }
    }

    private func refreshTime() { displayTime = formatter.string(from: Date()) }

    private func refreshBattery() {
        let level = UIDevice.current.batteryLevel
        switch UIDevice.current.batteryState {
        case .charging, .full: batteryIcon = "battery.100.bolt"
        default:
            if level > 0.75 { batteryIcon = "battery.100" }
            else if level > 0.5 { batteryIcon = "battery.75" }
            else if level > 0.25 { batteryIcon = "battery.50" }
            else { batteryIcon = "battery.25" }
        }
    }
}

// MARK: - Bottom Overlay Footer

struct ReaderOverlayFooter: View {
    let pageInfo: String
    let progress: String
    let textColor: Color
    let footerPadding: CGFloat
    @StateObject private var clock = ClockBatteryModel()

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Text("\(pageInfo)  ·  \(progress)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(textColor.opacity(0.4))
                Spacer()
                HStack(spacing: 4) {
                    Text(clock.displayTime).font(.system(size: 10).monospacedDigit())
                    Image(systemName: clock.batteryIcon).font(.system(size: 10))
                }
                .foregroundColor(textColor.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, footerPadding)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Inline Footer

struct ReaderInlineFooter: View {
    let pageInfo: String
    let progress: String
    let textColor: Color
    let footerPadding: CGFloat
    @StateObject private var clock = ClockBatteryModel()

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Text("\(pageInfo)  ·  \(progress)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(textColor.opacity(0.4))
                Spacer()
                HStack(spacing: 4) {
                    Text(clock.displayTime).font(.system(size: 10).monospacedDigit())
                    Image(systemName: clock.batteryIcon).font(.system(size: 10))
                }
                .foregroundColor(textColor.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, footerPadding)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第\(pageInfo)頁，進度\(progress)，\(clock.displayTime)")
    }
}

// MARK: - Previews

#if DEBUG
private struct FooterPreview: View {
    @State private var footerPadding: CGFloat = 4

    var body: some View {
        VStack(spacing: 0) {
            // Simulated page
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Color(.systemGray6)

                    // Simulated text content
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(0..<15, id: \.self) { i in
                            Text("這是模擬的第 \(i + 1) 行正文內容，用來展示排版區底部到 footer 之間的距離關係。")
                                .font(.system(size: 12))
                                .foregroundColor(.primary.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, ReaderLayoutMetrics.footerHeight + footerPadding)

                    // Footer area boundary
                    Rectangle()
                        .fill(.clear)
                        .frame(height: ReaderLayoutMetrics.footerHeight + 2)
                        .overlay(alignment: .top) {
                            Rectangle().frame(height: 1).foregroundColor(.red.opacity(0.5))
                        }
                        .overlay(alignment: .bottom) {
                            Rectangle().frame(height: 1).foregroundColor(.red.opacity(0.5))
                        }
                        .padding(.bottom, footerPadding)

                    // Footer
                    VStack {
                        Spacer()
                        ReaderOverlayFooter(
                            pageInfo: "42 / 156",
                            progress: "26.9%",
                            textColor: .white,
                            footerPadding: footerPadding
                        )
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("footerPadding").font(.headline)
                HStack {
                    Text("\(Int(footerPadding))pt")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .frame(width: 50, alignment: .trailing)
                    Slider(value: $footerPadding, in: 0...24, step: 1)
                }

                Text("紅框 = footer 區域 (高度 16pt)").font(.caption).foregroundColor(.red.opacity(0.5))
                Text("文字結束位置 = footer頂部，下方空白 = footerPadding").font(.caption).foregroundColor(.secondary)
            }
            .padding(12)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Footer") {
    FooterPreview()
}
#endif
