//
//  ContentView.swift
//  TrollBattery
//

import SwiftUI

// MARK: - 主题色

private enum Palette {
    static let card = Color(UIColor.secondarySystemGroupedBackground)
    static let page = Color(UIColor.systemGroupedBackground)
    static let primaryText = Color(UIColor.label)
    static let secondaryText = Color(UIColor.secondaryLabel)
    static let tertiaryText = Color(UIColor.tertiaryLabel)
    static let divider = Color(UIColor.separator).opacity(0.35)

    static let green = Color(red: 0.18, green: 0.78, blue: 0.44)
    static let blue = Color(red: 0.20, green: 0.60, blue: 1.00)
    static let orange = Color(red: 1.00, green: 0.58, blue: 0.12)
    static let red = Color(red: 0.94, green: 0.32, blue: 0.31)
    static let purple = Color(red: 0.58, green: 0.44, blue: 0.98)
    static let teal = Color(red: 0.16, green: 0.72, blue: 0.78)
}

struct ContentView: View {

    @StateObject private var model = BatteryModel()
    @State private var showRawDetail = false

    private var snapshot: BatterySnapshot { model.snapshot }

    var body: some View {
        ZStack {
            Palette.page.edgesIgnoringSafeArea(.all)

            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    powerCard
                    detailCard
                    chartCard
                    controlCard
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    // MARK: - 顶部：健康度 + 电量

    private var headerCard: some View {
        Card {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Text("巨魔电池")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Palette.primaryText)
                    Spacer()
                    SourceBadge(source: snapshot.source)
                }

                HStack(spacing: 8) {
                    RingView(
                        progress: (snapshot.healthPercent ?? 0) / 100.0,
                        colors: healthGradient,
                        title: "电池健康度",
                        value: snapshot.healthPercent.map { String(format: "%.1f%%", $0) } ?? "N/A",
                        caption: capacityCaption
                    )

                    RingView(
                        progress: (snapshot.levelPercent ?? 0) / 100.0,
                        colors: levelGradient,
                        title: "当前电量",
                        value: snapshot.levelPercent.map { String(format: "%.0f%%", $0) } ?? "N/A",
                        caption: snapshot.statusText
                    )
                }

                HStack(spacing: 6) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 11, weight: .semibold))
                    Text(statusLine)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(statusColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(statusColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // MARK: - 实时功率

    private var powerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "实时充电功率", icon: "bolt.fill", tint: Palette.orange)

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(powerText)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monoDigits()
                        .foregroundColor(snapshot.powerWatts == nil ? Palette.tertiaryText : powerTint)
                    Text(snapshot.powerWatts == nil ? "" : "W")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Palette.secondaryText)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(snapshot.powerDirection)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Palette.secondaryText)
                        Text(snapshot.isCharging == true ? "充电功率" : "功耗")
                            .font(.system(size: 10))
                            .foregroundColor(Palette.tertiaryText)
                    }
                }

                Divider().background(Palette.divider)

                HStack(spacing: 0) {
                    MiniStat(
                        title: "电流",
                        value: snapshot.currentAmps.map { String(format: "%.0f mA", $0 * 1000) } ?? "N/A",
                        tint: Palette.blue
                    )
                    MiniStat(
                        title: "电压",
                        value: snapshot.voltageMV.map { String(format: "%.2f V", Double($0) / 1000.0) } ?? "N/A",
                        tint: Palette.teal
                    )
                    MiniStat(
                        title: "温度",
                        value: snapshot.temperatureC.map { String(format: "%.1f ℃", $0) } ?? "N/A",
                        tint: temperatureTint
                    )
                }
            }
        }
    }

    // MARK: - 容量明细

    private var detailCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "电池容量明细", icon: "battery.100", tint: Palette.green)

                VStack(spacing: 0) {
                    InfoRow(title: "设计容量", value: snapshot.designCapacity.map { "\($0) mAh" } ?? "N/A")
                    rowDivider
                    InfoRow(title: "当前最大容量", value: snapshot.currentMaxCapacity.map { "\($0) mAh" } ?? "N/A")
                    rowDivider
                    InfoRow(title: "当前剩余容量", value: snapshot.rawCurrentCapacity.map { "\($0) mAh" } ?? "N/A")
                    rowDivider
                    InfoRow(title: "循环次数", value: snapshot.cycleCount.map { "\($0) 次" } ?? "N/A")
                    rowDivider
                    InfoRow(title: "已损耗", value: lossText)
                    rowDivider
                    InfoRow(title: "充满剩余", value: minutesText(snapshot.timeToFullMinutes))
                    rowDivider
                    InfoRow(title: "续航预估", value: minutesText(snapshot.timeToEmptyMinutes))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    // MARK: - 功率曲线

    private var chartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "功率曲线", icon: "waveform.path.ecg", tint: Palette.purple)
                    Spacer()
                    Text("\(model.history.count) 个采样点")
                        .font(.system(size: 10))
                        .foregroundColor(Palette.tertiaryText)
                }
                PowerHistoryChart(samples: model.history)
                    .frame(height: 110)
            }
        }
    }

    // MARK: - 控制区

    private var controlCard: some View {
        Card {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("自动刷新")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Palette.primaryText)
                        Text(model.autoRefresh ? "每 2 秒采集一次" : "已暂停采集")
                            .font(.system(size: 11))
                            .foregroundColor(Palette.tertiaryText)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.autoRefresh },
                        set: { model.setAutoRefresh($0) }
                    ))
                    .labelsHidden()
                }

                Button(action: { model.refresh() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                        Text("立即刷新")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Palette.blue.opacity(0.14))
                    .foregroundColor(Palette.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if !snapshot.source.isFull {
                PermissionHint(source: snapshot.source)
            }
            Button(action: { showRawDetail.toggle() }) {
                Text(showRawDetail ? "隐藏诊断信息" : "查看诊断信息")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.tertiaryText)
            }
            .buttonStyle(PlainButtonStyle())

            if showRawDetail {
                VStack(alignment: .leading, spacing: 4) {
                    Text(diagnosticText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Palette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(Palette.card)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Text("数据来源：AppleSmartBattery · 仅供本机参考")
                .font(.system(size: 10))
                .foregroundColor(Palette.tertiaryText)
        }
    }

    // MARK: - 计算属性

    private var healthGradient: [Color] {
        guard let health = snapshot.healthPercent else { return [Palette.tertiaryText.opacity(0.5), Palette.tertiaryText.opacity(0.2)] }
        if health >= 85 { return [Palette.green, Palette.teal] }
        if health >= 70 { return [Palette.orange, Palette.red.opacity(0.8)] }
        return [Palette.red, Palette.orange]
    }

    private var levelGradient: [Color] {
        guard let level = snapshot.levelPercent else { return [Palette.tertiaryText.opacity(0.5), Palette.tertiaryText.opacity(0.2)] }
        if snapshot.isCharging == true { return [Palette.green, Palette.teal] }
        if level <= 20 { return [Palette.red, Palette.orange] }
        return [Palette.blue, Palette.purple]
    }

    private var powerTint: Color {
        if snapshot.isCharging == true { return Palette.green }
        if snapshot.isPluggedIn == true { return Palette.orange }
        return Palette.blue
    }

    private var temperatureTint: Color {
        guard let temp = snapshot.temperatureC else { return Palette.tertiaryText }
        if temp >= 40 { return Palette.red }
        if temp >= 35 { return Palette.orange }
        return Palette.teal
    }

    private var statusIcon: String {
        if snapshot.isCharging == true { return "bolt.fill" }
        if snapshot.isFull == true { return "checkmark.circle.fill" }
        if snapshot.isPluggedIn == true { return "powerplug.fill" }
        return "arrow.down.circle"
    }

    private var statusColor: Color {
        if snapshot.isCharging == true { return Palette.green }
        if snapshot.isFull == true { return Palette.teal }
        if snapshot.isPluggedIn == true { return Palette.orange }
        return Palette.secondaryText
    }

    private var statusLine: String {
        var parts: [String] = [snapshot.statusText]
        if let level = snapshot.levelPercent {
            parts.append(String(format: "%.0f%%", level))
        }
        if snapshot.hasPowerData == false && snapshot.source.isFull {
            parts.append("功率数据读取中")
        }
        return parts.joined(separator: " · ")
    }

    private var powerText: String {
        guard let power = snapshot.powerWatts else { return "—" }
        if power < 0.01 { return "0.00" }
        return String(format: "%.2f", power)
    }

    private var capacityCaption: String? {
        guard let maxCap = snapshot.currentMaxCapacity, let design = snapshot.designCapacity else { return nil }
        return "\(maxCap) / \(design) mAh"
    }

    private var lossText: String {
        guard let health = snapshot.healthPercent else { return "N/A" }
        return String(format: "%.1f%%", max(0, 100 - health))
    }

    private func minutesText(_ minutes: Int?) -> String {
        guard let minutes = minutes else { return "N/A" }
        if minutes >= 60 {
            return String(format: "%d 小时 %d 分", minutes / 60, minutes % 60)
        }
        return "\(minutes) 分钟"
    }

    private var diagnosticText: String {
        """
        source      : \(snapshot.source.rawValue)
        service     : \(snapshot.serviceName ?? "nil")
        level       : \(snapshot.levelPercent.map { String(format: "%.1f", $0) } ?? "nil")
        design      : \(snapshot.designCapacity.map(String.init) ?? "nil")
        rawMax      : \(snapshot.currentMaxCapacity.map(String.init) ?? "nil")
        rawCurrent  : \(snapshot.rawCurrentCapacity.map(String.init) ?? "nil")
        cycles      : \(snapshot.cycleCount.map(String.init) ?? "nil")
        voltage/mV  : \(snapshot.voltageMV.map(String.init) ?? "nil")
        amps/mA     : \(snapshot.instantAmperageMA.map(String.init) ?? "nil")
        temp        : \(snapshot.temperatureC.map { String(format: "%.2f", $0) } ?? "nil")
        charging    : \(snapshot.isCharging.map { "\($0)" } ?? "nil")
        plugged     : \(snapshot.isPluggedIn.map { "\($0)" } ?? "nil")
        """
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Palette.divider)
            .frame(height: 0.6)
    }
}

// MARK: - iOS 14 兼容层

private extension View {
    /// monospacedDigit() 从 iOS 15 起才可用，低版本静默降级。
    @ViewBuilder
    func monoDigits() -> some View {
        if #available(iOS 15.0, *) {
            self.monospacedDigit()
        } else {
            self
        }
    }
}

// MARK: - 组件

private struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
    }
}

private struct SectionTitle: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Palette.secondaryText)
        }
    }
}

private struct SourceBadge: View {
    let source: BatteryDataSource

    private var tint: Color {
        switch source {
        case .iokit: return Palette.green
        case .powerSources: return Palette.orange
        case .device: return Palette.red
        case .unavailable: return Palette.tertiaryText
        }
    }

    var body: some View {
        Text(source.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14))
            .clipShape(Capsule())
    }
}

private struct RingView: View {
    let progress: Double
    let colors: [Color]
    let title: String
    let value: String
    let caption: String?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color(UIColor.tertiarySystemFill), lineWidth: 11)

                Circle()
                    .trim(from: 0, to: CGFloat(max(0.001, min(1.0, progress))))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: colors + [colors.first ?? colors[0]]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 11, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.45))

                VStack(spacing: 1) {
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monoDigits()
                        .foregroundColor(Palette.primaryText)
                    if let caption = caption {
                        Text(caption)
                            .font(.system(size: 9))
                            .foregroundColor(Palette.tertiaryText)
                    }
                }
            }
            .frame(width: 118, height: 118)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MiniStat: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(Palette.tertiaryText)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monoDigits()
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(Palette.primaryText)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monoDigits()
                .foregroundColor(Palette.secondaryText)
        }
        .padding(.vertical, 10)
    }
}

private struct PermissionHint: View {
    let source: BatteryDataSource

    private var message: String {
        switch source {
        case .powerSources:
            return "当前仅拿到系统电源接口数据，容量与功率字段不可用。多为 IOKit 权限被拦截所致。"
        case .device:
            return "当前仅拿到基础电量数据。请确认应用由 TrollStore 安装，且 entitlements 已注入。"
        case .unavailable:
            return "未获取到任何电池数据，请检查系统版本与应用权限。"
        case .iokit:
            return ""
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(Palette.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
