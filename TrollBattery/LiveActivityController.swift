//
//  LiveActivityController.swift
//  TrollBattery
//
//  Live Activity 的启动 / 刷新 / 结束。
//
//  设计约束（务必留意）：
//  1. 主 App 的 deployment target 是 14.0，而 ActivityKit 需要 16.1。
//     这里把所有 ActivityKit 调用收进 @available(iOS 16.1, *) 的私有方法，
//     公开方法只做一次 #available 判断后转发 —— 这样方法体（含 Task 闭包）
//     整体处于可用性上下文中，不会踩「转义闭包不继承 if #available」的坑。
//  2. 存储属性不能标注 @available，故用 Any 存储 + 计算属性转发。
//  3. iOS 会在 App 进入后台 / 锁屏约 30 秒后对 Live Activity 更新做静默限流，
//     因此后台期间灵动岛会停在最后一次成功推送的数值。
//  4. 推送做了节流，避免高频 refresh 触发系统熔断。
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

    /// 存储层：用 Any 持有真实活动对象
    private var activityStorage: Any?

    @available(iOS 16.1, *)
    private var activity: Activity<BatteryActivityAttributes>? {
        get { activityStorage as? Activity<BatteryActivityAttributes> }
        set { activityStorage = newValue }
    }

    /// 最近一次成功推送时刻，用于节流
    private var lastPushAt: Date = .distantPast

    /// 最小推送间隔（秒）。低于系统建议阈值会被限流丢弃。
    private let minPushInterval: TimeInterval = 2.0

    /// 系统是否支持实时活动
    static var isSupported: Bool {
        if #available(iOS 16.1, *) { return true }
        return false
    }

    /// 系统层面是否开放实时活动（用户可在「设置 › 充电助手」中单独关闭）
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

    /// 无法启动时的原因，用于界面提示
    var unavailableReason: String? {
        guard Self.isSupported else { return "当前系统低于 iOS 16.1，不支持实时活动" }
        guard isSystemEnabled else { return "实时活动已被系统关闭，请在「设置 › 充电助手」中开启" }
        return nil
    }

    // MARK: - 公开接口

    @discardableResult
    func start(with snapshot: BatterySnapshot) -> Bool {
        guard #available(iOS 16.1, *) else { return false }
        return startAvailable(snapshot)
    }

    func push(_ snapshot: BatterySnapshot, force: Bool = false) {
        guard #available(iOS 16.1, *) else { return }
        pushAvailable(snapshot, force: force)
    }

    func stop() {
        guard #available(iOS 16.1, *) else { return }
        stopAvailable()
    }

    // MARK: - 实现（iOS 16.1+）

    @available(iOS 16.1, *)
    @discardableResult
    private func startAvailable(_ snapshot: BatterySnapshot) -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }

        // 已有活动的处理
        if let existing = activity {
            if existing.activityState == .active {
                pushAvailable(snapshot, force: true)
                return true
            }
            activity = nil
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

    @available(iOS 16.1, *)
    private func pushAvailable(_ snapshot: BatterySnapshot, force: Bool = false) {
        guard let target = activity, target.activityState == .active else { return }

        let now = Date()
        if !force && now.timeIntervalSince(lastPushAt) < minPushInterval { return }
        lastPushAt = now

        let state = makeState(from: snapshot)
        // staleDate：若 2 分钟内无新数据，系统会把内容标记为过期
        let stale = Date().addingTimeInterval(120)

        Task {
            if #available(iOS 16.2, *) {
                await target.update(ActivityContent(state: state, staleDate: stale))
            } else {
                await target.update(using: state)
            }
        }
    }

    @available(iOS 16.1, *)
    private func stopAvailable() {
        guard let target = activity else { return }
        activity = nil

        Task {
            if #available(iOS 16.2, *) {
                await target.end(nil, dismissalPolicy: .immediate)
            } else {
                await target.end(using: nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - 组装 ContentState

    @available(iOS 16.1, *)
    private func makeState(from snapshot: BatterySnapshot) -> BatteryActivityAttributes.ContentState {
        BatteryActivityAttributes.ContentState(
            watts: snapshot.primaryWatts ?? 0,
            wattsLabel: snapshot.primaryWattsLabel,
            batteryWatts: snapshot.batteryWatts ?? 0,
            signedWatts: snapshot.signedPowerWatts ?? 0,
            levelPercent: snapshot.levelPercent ?? 0,
            isCharging: snapshot.isCharging == true,
            isPluggedIn: snapshot.isPluggedIn == true,
            isFull: snapshot.isFull == true,
            statusText: snapshot.statusText,
            voltageMV: snapshot.voltageMV ?? 0,
            currentMA: Int(((snapshot.currentAmps ?? 0) * 1000)),
            inputVoltage: snapshot.usbInputVoltage ?? 0,
            inputCurrent: snapshot.usbInputCurrent ?? 0,
            temperatureC: snapshot.temperatureC ?? 0,
            updatedAt: snapshot.timestamp
        )
    }
}
