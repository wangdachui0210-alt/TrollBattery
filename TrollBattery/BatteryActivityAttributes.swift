//
//  BatteryActivityAttributes.swift
//  TrollBattery
//
//  Live Activity（灵动岛 / 锁屏实时活动）的数据契约。
//  本文件同时编译进主 App 与 Widget Extension 两个 target，
//  是两者之间唯一的共享定义，改动时必须保持双 target 一致。
//

import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// 静态属性：在整个活动生命周期内不变。
@available(iOS 16.1, *)
struct BatteryActivityAttributes: ActivityAttributes {

    /// 动态内容：每次采样都会整体替换。
    struct ContentState: Codable, Hashable {
        /// 电池端功率绝对值，单位 W
        var watts: Double
        /// 电池端功率，带方向（充电为正、放电为负）
        var signedWatts: Double
        /// 当前电量 0...100
        var levelPercent: Double
        var isCharging: Bool
        var isPluggedIn: Bool
        var isFull: Bool
        /// 状态文案，如「充电中」
        var statusText: String
        /// 电池电压 mV
        var voltageMV: Int
        /// 电池电流 mA（绝对值）
        var currentMA: Int
        /// 电池温度 ℃
        var temperatureC: Double
        /// 本次采样时刻，用于在界面上标注数据新鲜度
        var updatedAt: Date
    }

    /// 设备标识（机型名），保持稳定
    var deviceModel: String
}

#endif
