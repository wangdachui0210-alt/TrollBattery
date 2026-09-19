//
//  LiveActivityController.swift
//  TrollBattery
//
//  Live Activity 的启动 / 刷新 / 结束。
//
//  设计约束（务必留意）：
//  1. 全部 ActivityKit 调用都在 @available(iOS 16.1, *) 保护下，
//     低版本系统静默跳过，不会影响 App 其它功能。
//  2. iOS 会在 App 进入后台 / 锁屏后对 Live Activity 更新做限流，
//     实测后台约 30 秒后更新会被系统静默丢弃（不报错）。
//     因此后台期间灵动岛会停在最后一次成功推送的数值。
//  3. 推送做了节流，避免高频 refresh 触发系统熔断。
//

import Foundation
import UIKit

#if canImport(ActivityKit)
import ActivityKit
#endif

final class LiveActivityController {

    static let shared = LiveActivityController()
    private init() {}

    // MARK: - 状态

    @available(iOS 16.1, *)
    private var activity: Activity<BatteryActivityAttributes>?

    /// 最近一次成功推送时刻，用于节流
    private var lastPushAt: Date = .distantPast

    /// 最小推送间隔（秒）。低于系统建议阈值会被限流丢弃。
    private let minPushInterval: TimeInterval = 2.0

    /// 系统层面是否开放实时活动（用户可在「设置 › 巨魔电池」中单独关闭）
    static var isSupported: Bool {
        if #available(iOS 16.1, *) { return true }
        return false
    }

    var isSystemEnabled: Bool {
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
    }

    /// 当前是否有活跃的实时活动
    var isRunning: Bool {
        if #available(iOS 16.1, *) {
            guard let activity = activity else { return false }
            return activity.activityState == .active
        }
        return false
    }

    /// 无法启动时给出的原因，用于界面提示
    var unavailableReason: String? {
        guard Self.isSupported else { return "当前系统低于 iOS 16.1，不支持实时活动" }
        guard isSystemEnabled else { return "实时活动已被系统关闭，请在「设置 › 巨魔电池」中开启" }
        return nil
    }

    // MARK: - 启动

    @discardableResult
    func start(with snapshot: BatterySnapshot) -> Bool {
        guard #available(iOS 16.1, *) else { return false }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }

        // 已有活跃活动：直接刷新并复用
        if let existing = activity, existing.activityState == .active {
            push(snapshot, force: true)
            return true
        }

        let attributes = BatteryActivityAttributes(deviceModel: UIDevice.current.model)
        let state = makeState(from: snapshot)

        do {
            if #available(iOS 16.2, *) {
                activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
            } else {
                activity = try Activity.request(
                    attributes: attributes,
                    contentState: state,
                    pushType: nil
                )
            }
            lastPushAt = Date()
            return true
        } catch {
            activity = nil
            return false
        }
    }

    // MARK: - 刷新

    /// 把最新采样推给灵动岛。force 为 true 时跳过节流。
    func push(_ snapshot: BatterySnapshot, force: Bool = false) {
        guard #available(iOS 16.1, *) else { return }
        guard let activity = activity, activity.activityState == .active else { return }

        let now = Date()
        if !force && now.timeIntervalSince(lastPushAt) < minPushInterval { return }
        lastPushAt = now

        let state = makeState(from: snapshot)
        let target = activity
        // staleDate 设为 2 分钟后：若期间无新数据，系统会自行把内容标记为过期
        let stale = Date().addingTimeInterval(120)

        Task {
            if #available(iOS 16.2, *) {
                await target.update(ActivityContent(state: state, staleDate: stale))
            } else {
                await target.update(using: state)
            }
        }
    }

    // MARK: - 结束

    func stop() {
        guard #available(iOS 16.1, *) else { return }
        guard let activity = activity else { return }
        self.activity = nil

        Task {
            if #available(iOS 16.2, *) {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else {
                await activity.end(using: nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - 组装 ContentState

    @available(iOS 16.1, *)
    private func makeState(from snapshot: BatterySnapshot) -> BatteryActivityAttributes.ContentState {
        BatteryActivityAttributes.ContentState(
            watts: snapshot.powerWatts ?? 0,
            signedWatts: snapshot.signedPowerWatts ?? 0,
            levelPercent: snapshot.levelPercent ?? 0,
            isCharging: snapshot.isCharging == true,
            isPluggedIn: snapshot.isPluggedIn == true,
            isFull: snapshot.isFull == true,
            statusText: snapshot.statusText,
            voltageMV: snapshot.voltageMV ?? 0,
            currentMA: abs(snapshot.instantAmperageMA ?? snapshot.amperageMA ?? 0),
            temperatureC: snapshot.temperatureC ?? 0,
            updatedAt: snapshot.timestamp
        )
    }
}
