//
//  BatterySnapshot.swift
//  TrollBattery
//
//  一次电池采样的完整数据模型。
//

import Foundation

/// 数据来源，用于在界面上标明当前是否拿到了完整数据。
enum BatteryDataSource: String {
    case iokit        = "IOKit 完整数据"
    case powerSources = "系统电源接口"
    case device       = "基础接口"
    case unavailable  = "不可用"

    /// 是否包含容量 / 功率等完整字段
    var isFull: Bool { self == .iokit }
}

struct BatterySnapshot: Equatable {

    var timestamp = Date()
    var source: BatteryDataSource = .unavailable
    /// 实际命中的 IOKit 服务名（诊断用）
    var serviceName: String?

    // 状态
    var levelPercent: Double?          // 当前电量 0...100
    var isCharging: Bool?
    var isPluggedIn: Bool?
    var isFull: Bool?

    // 容量
    var designCapacity: Int?           // 设计容量 mAh
    var currentMaxCapacity: Int?       // 当前最大容量 mAh
    var rawCurrentCapacity: Int?       // 当前剩余容量 mAh

    // 电气参数
    var cycleCount: Int?               // 循环次数
    var voltageMV: Int?                // 电压 mV
    var instantAmperageMA: Int?        // 瞬时电流 mA（充电为流入）
    var amperageMA: Int?               // 平均电流 mA
    var temperatureC: Double?          // 温度 ℃

    // 时间预估
    var timeToFullMinutes: Int?
    var timeToEmptyMinutes: Int?

    // MARK: - 派生值

    /// 电池健康度 = 当前最大容量 / 设计容量
    var healthPercent: Double? {
        guard let design = designCapacity, let maxCap = currentMaxCapacity,
              design > 0, maxCap > 0 else { return nil }
        return Double(maxCap) / Double(design) * 100.0
    }

    /// 实时功率（绝对值，单位 W）
    var powerWatts: Double? {
        guard let voltage = voltageMV, voltage > 0,
              let current = instantAmperageMA ?? amperageMA else { return nil }
        return abs(Double(voltage) * Double(current)) / 1_000_000.0
    }

    /// 实时功率（带方向，充电为正、放电为负）
    var signedPowerWatts: Double? {
        guard let power = powerWatts else { return nil }
        return isCharging == true ? power : -power
    }

    /// 实时电流（安培，绝对值）
    var currentAmps: Double? {
        guard let current = instantAmperageMA ?? amperageMA else { return nil }
        return abs(Double(current)) / 1000.0
    }

    /// 充电方向描述
    var powerDirection: String {
        if isCharging == true { return "流入" }
        if isPluggedIn == true && isFull == true { return "已充满" }
        if isPluggedIn == true { return "待机" }
        return "流出"
    }

    /// 状态文案
    var statusText: String {
        if isCharging == true { return "充电中" }
        if isPluggedIn == true && isFull == true { return "已充满" }
        if isPluggedIn == true { return "已接电源" }
        if isPluggedIn == false { return "放电中" }
        return "未知"
    }

    /// 是否有完整的功率数据
    var hasPowerData: Bool { powerWatts != nil }
}
