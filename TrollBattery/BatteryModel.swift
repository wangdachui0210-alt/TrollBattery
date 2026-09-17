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

    /// 采样间隔（秒）
    private let interval: TimeInterval = 2.0
    /// 曲线最多保留的采样点（约 5 分钟）
    private let maxSamples = 150

    private var timer: Timer?

    init() {
        refresh()
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
