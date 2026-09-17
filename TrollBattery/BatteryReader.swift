//
//  BatteryReader.swift
//  TrollBattery
//
//  三级读取策略：IOKit 完整数据 → 系统电源接口 → UIDevice 基础接口。
//  任一层拿到有效数据即返回，保证在权限不足的设备上界面依然可用。
//

import Foundation
import UIKit

enum BatteryReader {

    static func read() -> BatterySnapshot {
        if let snapshot = readSmartBattery() { return snapshot }
        if let snapshot = readPowerSources() { return snapshot }
        return readDeviceFallback()
    }

    // MARK: - 一级：IOKit 电池注册表

    private static func readSmartBattery() -> BatterySnapshot? {
        guard let hit = IOKitBridge.shared.batteryProperties() else { return nil }
        let raw = hit.properties

        // 部分机型把容量信息放在嵌套的 BatteryData 字典里
        let inner = raw["BatteryData"] as? [String: Any] ?? [:]

        var s = BatterySnapshot()
        s.timestamp = Date()
        s.source = .iokit
        s.serviceName = hit.service

        s.isCharging = boolValue(raw, ["IsCharging"])
        s.isPluggedIn = boolValue(raw, ["ExternalConnected", "AppleRawExternalConnected"])
        s.isFull = boolValue(raw, ["FullyCharged"])
        if s.isPluggedIn == nil { s.isPluggedIn = (s.isCharging == true) }
        if s.isPluggedIn == false { s.isFull = false }

        s.designCapacity = intValue(raw, ["DesignCapacity"]) ?? intValue(inner, ["DesignCapacity"])
        s.currentMaxCapacity = intValue(raw, ["AppleRawMaxCapacity", "NominalChargeCapacity", "MaxCapacity"])
        s.rawCurrentCapacity = intValue(raw, ["AppleRawCurrentCapacity"])
        s.cycleCount = intValue(raw, ["CycleCount"]) ?? intValue(inner, ["CycleCount"])

        s.voltageMV = intValue(raw, ["Voltage"])
        s.instantAmperageMA = intValue(raw, ["InstantAmperage"]) ?? intValue(raw, ["Amperage"])
        s.amperageMA = intValue(raw, ["Amperage"])
        s.temperatureC = temperatureValue(raw["Temperature"])

        s.timeToFullMinutes = saneMinutes(intValue(raw, ["AvgTimeToFull", "TimeToFull"]))
        s.timeToEmptyMinutes = saneMinutes(intValue(raw, ["TimeRemaining", "AvgTimeToEmpty"]))

        s.levelPercent = levelPercent(raw: raw, snapshot: s)

        // 关键字段全空说明注册表读取被拦截，交给下一级
        guard s.designCapacity != nil || s.currentMaxCapacity != nil || s.voltageMV != nil else {
            return nil
        }
        return s
    }

    /// CurrentCapacity 在有的机型是百分比、有的是 mAh，这里做启发式判断。
    private static func levelPercent(raw: [String: Any], snapshot: BatterySnapshot) -> Double? {
        if let cur = intValue(raw, ["CurrentCapacity"]), cur > 0, cur <= 100 {
            return Double(cur)
        }
        if let rawCur = snapshot.rawCurrentCapacity {
            if let maxCap = snapshot.currentMaxCapacity, maxCap > 0 {
                return min(100, Double(rawCur) / Double(maxCap) * 100)
            }
            if let design = snapshot.designCapacity, design > 0 {
                return min(100, Double(rawCur) / Double(design) * 100)
            }
        }
        return nil
    }

    // MARK: - 二级：IOPS 系统电源接口

    private static func readPowerSources() -> BatterySnapshot? {
        guard let desc = IOKitBridge.shared.powerSourceDescription() else { return nil }

        var s = BatterySnapshot()
        s.timestamp = Date()
        s.source = .powerSources

        s.levelPercent = (desc["Current Capacity"] as? NSNumber)?.doubleValue

        let charging = (desc["Is Charging"] as? NSNumber)?.boolValue
        s.isCharging = charging
        s.isPluggedIn = (desc["Power Source State"] as? String) == "AC Power" || charging == true
        if let level = s.levelPercent, level >= 100, s.isPluggedIn == true { s.isFull = true }

        s.timeToFullMinutes = saneMinutes((desc["Time to Full Charge"] as? NSNumber)?.intValue)
        s.timeToEmptyMinutes = saneMinutes((desc["Time to Empty"] as? NSNumber)?.intValue)

        guard s.levelPercent != nil else { return nil }
        return s
    }

    // MARK: - 三级：UIDevice 兜底

    private static func readDeviceFallback() -> BatterySnapshot {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        var s = BatterySnapshot()
        s.timestamp = Date()

        if device.batteryLevel >= 0 {
            s.levelPercent = Double(device.batteryLevel) * 100.0
            s.source = .device
        } else {
            s.source = .unavailable
        }

        switch device.batteryState {
        case .charging:
            s.isCharging = true
            s.isPluggedIn = true
        case .full:
            s.isCharging = false
            s.isPluggedIn = true
            s.isFull = true
        case .unplugged:
            s.isCharging = false
            s.isPluggedIn = false
        default:
            break
        }
        return s
    }

    // MARK: - 取值工具

    private static func intValue(_ dict: [String: Any], _ keys: [String]) -> Int? {
        for key in keys {
            if let number = dict[key] as? NSNumber { return number.intValue }
        }
        return nil
    }

    private static func boolValue(_ dict: [String: Any], _ keys: [String]) -> Bool? {
        for key in keys {
            if let flag = dict[key] as? Bool { return flag }
            if let number = dict[key] as? NSNumber { return number.boolValue }
        }
        return nil
    }

    /// IORegistry 中温度单位在不同机型上为 0.01℃ 或 0.1℃，做区间判断。
    private static func temperatureValue(_ any: Any?) -> Double? {
        guard let number = any as? NSNumber else { return nil }
        let value = number.doubleValue
        guard value > 0 else { return nil }
        if value > 1000 { return value / 100.0 }
        if value > 200 { return value / 10.0 }
        return value
    }

    /// 65535 是 IOKit 表示"未知"的哨兵值
    private static func saneMinutes(_ value: Int?) -> Int? {
        guard let value = value, value > 0, value < 65535 else { return nil }
        return value
    }
}
