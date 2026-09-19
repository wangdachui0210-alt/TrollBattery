//
//  TrollBatteryLiveActivity.swift
//  TrollBatteryWidget
//
//  灵动岛 + 锁屏实时活动界面。
//  本 target 的 deployment target 为 iOS 16.1，因此可直接使用 ActivityKit 全部 API。
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - 配色

private enum WidgetPalette {
    static let green = Color(red: 0.18, green: 0.78, blue: 0.44)
    static let blue = Color(red: 0.20, green: 0.60, blue: 1.00)
    static let orange = Color(red: 1.00, green: 0.58, blue: 0.12)
    static let teal = Color(red: 0.16, green: 0.72, blue: 0.78)
    static let white = Color.white
    static let dim = Color.white.opacity(0.55)
}

// MARK: - 派生文案

private func statusTint(_ state: BatteryActivityAttributes.ContentState) -> Color {
    if state.isCharging { return WidgetPalette.green }
    if state.isFull { return WidgetPalette.teal }
    if state.isPluggedIn { return WidgetPalette.orange }
    return WidgetPalette.blue
}

private func statusIcon(_ state: BatteryActivityAttributes.ContentState) -> String {
    if state.isCharging { return "bolt.fill" }
    if state.isFull { return "checkmark.circle.fill" }
    if state.isPluggedIn { return "powerplug.fill" }
    return "arrow.down.circle.fill"
}

private func wattsText(_ state: BatteryActivityAttributes.ContentState) -> String {
    if state.watts < 0.01 { return "0.0" }
    return String(format: "%.1f", state.watts)
}

private func levelText(_ state: BatteryActivityAttributes.ContentState) -> String {
    String(format: "%.0f%%", state.levelPercent)
}

private func currentText(_ state: BatteryActivityAttributes.ContentState) -> String {
    String(format: "%d mA", state.currentMA)
}

private func voltageText(_ state: BatteryActivityAttributes.ContentState) -> String {
    String(format: "%.2f V", Double(state.voltageMV) / 1000.0)
}

private func temperatureText(_ state: BatteryActivityAttributes.ContentState) -> String {
    state.temperatureC > 0 ? String(format: "%.1f ℃", state.temperatureC) : "—"
}

private func clockText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
}

// MARK: - Live Activity

struct TrollBatteryLiveActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BatteryActivityAttributes.self) { context in
            LockScreenLiveView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(WidgetPalette.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // 展开态：顶部左侧状态
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Image(systemName: statusIcon(context.state))
                            .font(.system(size: 11, weight: .bold))
                        Text(context.state.statusText)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(statusTint(context.state))
                    .padding(.leading, 4)
                }

                // 展开态：顶部右侧电量
                DynamicIslandExpandedRegion(.trailing) {
                    Text(levelText(context.state))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(WidgetPalette.white)
                        .padding(.trailing, 4)
                }

                // 展开态：底部主体
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(wattsText(context.state))
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(statusTint(context.state))
                            Text("W")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(WidgetPalette.dim)
                            Spacer()
                            Text("更新 \(clockText(context.state.updatedAt))")
                                .font(.system(size: 10))
                                .foregroundColor(WidgetPalette.dim)
                        }

                        HStack(spacing: 0) {
                            metric(title: "电流", value: currentText(context.state))
                            metric(title: "电压", value: voltageText(context.state))
                            metric(title: "温度", value: temperatureText(context.state))
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)
                }

            } compactLeading: {
                Image(systemName: statusIcon(context.state))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(statusTint(context.state))

            } compactTrailing: {
                Text(wattsText(context.state))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(statusTint(context.state))

            } minimal: {
                Image(systemName: statusIcon(context.state))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(statusTint(context.state))
            }
            .keylineTint(statusTint(context.state))
        }
    }

    @ViewBuilder
    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(WidgetPalette.dim)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(WidgetPalette.white)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 锁屏 / 横幅视图

private struct LockScreenLiveView: View {

    let state: BatteryActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: statusIcon(state))
                        .font(.system(size: 12, weight: .bold))
                    Text(state.statusText)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(statusTint(state))

                Spacer()

                Text(levelText(state))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(WidgetPalette.white)
            }

            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(wattsText(state))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(statusTint(state))
                Text("W")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(WidgetPalette.dim)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("电池端功率")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(WidgetPalette.dim)
                    Text(clockText(state.updatedAt))
                        .font(.system(size: 10))
                        .foregroundColor(WidgetPalette.dim)
                }
            }

            HStack(spacing: 0) {
                metric(title: "电流", value: currentText(state))
                metric(title: "电压", value: voltageText(state))
                metric(title: "温度", value: temperatureText(state))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(WidgetPalette.dim)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(WidgetPalette.white)
        }
        .frame(maxWidth: .infinity)
    }
}
