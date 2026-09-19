//
//  BatteryModel.swift
//  TrollBattery
//

import Foundation
import Combine

struct PowerSample: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let watts: Double
}

final class BatteryModel: ObservableObject {

    @Published private(set) var snapshot = BatterySnapshot()
    @Published private(set) var history: [PowerSample] = []
    @Published var autoRefresh: Bool = true

    /// 灵动岛 / 锁屏实时活动开关
    @Published private(set) var liveActivityOn: Bool = false
    /// 开启失败时的提示文案
    @Published private(set) var liveActivityMessage: String?

    /// 采样间隔（秒）
    private let interval: TimeInterval = 2.0
    /// 曲线最多保留的采样点（约 5 分钟）
    private let maxSamples = 150

    private let liveActivityKey = "com.david.trollbattery.liveactivity"
    private var timer: Timer?

    init() {
        refresh()
        // 恢复上次的开关状态
        if UserDefaults.standard.bool(forKey: liveActivityKey) {
            setLiveActivity(true)
        }
    }

    func refresh() {
        let current = BatteryReader.read()
        snapshot = current
        if let watts = current.powerWatts {
            history.append(PowerSample(date: current.timestamp, watts: watts))
            if history.count > maxSamples {
                history.removeFirst(history.count - maxSamples)
            }
        }
        // 同步推送到灵动岛（内部有节流）
        if liveActivityOn {
            LiveActivityController.shared.push(current)
        }
    }

    // MARK: - 实时活动

    /// 系统是否支持实时活动（iOS 16.1+）
    var liveActivitySupported: Bool { LiveActivityController.isSupported }

    /// 打开 / 关闭灵动岛实时功率
    func setLiveActivity(_ enabled: Bool) {
        guard enabled else {
            LiveActivityController.shared.stop()
            liveActivityOn = false
            liveActivityMessage = nil
            UserDefaults.standard.set(false, forKey: liveActivityKey)
            return
        }

        if let reason = LiveActivityController.shared.unavailableReason {
            liveActivityOn = false
            liveActivityMessage = reason
            UserDefaults.standard.set(false, forKey: liveActivityKey)
            return
        }

        let ok = LiveActivityController.shared.start(with: snapshot)
        liveActivityOn = ok
        liveActivityMessage = ok ? nil : "实时活动启动失败，请稍后重试"
        UserDefaults.standard.set(ok, forKey: liveActivityKey)
    }

    func setAutoRefresh(_ enabled: Bool) {
        autoRefresh = enabled
        enabled ? start() : stop()
    }

    func start() {
        stop()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.current.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}
