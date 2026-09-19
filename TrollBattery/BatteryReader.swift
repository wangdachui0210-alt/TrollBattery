//
//  BatteryReader.swift
//  TrollBattery
//
//  数据读取层 v2：四个数据源合并。
//    A. HID 电源传感器（IOHIDEventSystemClient）—— 输入端电压/电流，真机可靠
//    B. IOKit 电池注册表（AppleSmartBattery）    —— 容量/循环数/状态 + 电池端 V/I（真机可能陈旧）
//    C. powerd 充电器详情（IOPSCopyExternalPowerAdapterDetails）—— 协商档位/PD 菜单
//    D. IOPS / UIDevice 兜底                     —— 电量与充电状态
//
//  注意：HID client 每进程只能建一个（第二个起全部返回 NaN），
//  因此 HIDSensors 实例必须是进程级单例。
//

import Foundation
import UIKit

enum BatteryReader {

    /// 进程级 HID 传感器单例
    private static let hid = HIDSensors()

    static func read() -> BatterySnapshot {
        if let snapshot = readSmartBattery() {
            var merged = snapshot
            mergeExtras(into: &merged)
            return merged
        }
        if var snapshot = readPowerSources() {
            mergeExtras(into: &snapshot)
            return snapshot
        }
        var snapshot = readDeviceFallback()
        mergeExtras(into: &snapshot)
        return snapshot
    }

    // MARK: - B. 一级：IOKit 电池注册表

    private static func readSmartBattery() -> BatterySnapshot? {
        guard let hit = IOKitBridge.shared.batteryProperties() else { return nil }
        let raw = hit.properties

        // 部分机型把容量信息放在嵌套的 BatteryData 字典里
        let inner = raw["BatteryData"] as? [String: Any] ?? [:]

        var s = BatterySnapshot()
        s.timestamp = Date()
        s.source = .iokit
        s.serviceName = hit.service

        s.isCharging = BatterySnapshot.boolValue(raw, ["IsCharging"])
        s.isPluggedIn = BatterySnapshot.boolValue(raw, ["ExternalConnected", "AppleRawExternalConnected"])
        s.isFull = BatterySnapshot.boolValue(raw, ["FullyCharged"])
        if s.isPluggedIn == nil { s.isPluggedIn = (s.isCharging == true) }
        if s.isPluggedIn == false { s.isFull = false }

        s.designCapacity = BatterySnapshot.intValue(raw, ["DesignCapacity"]) ?? BatterySnapshot.intValue(inner, ["DesignCapacity"])
        s.currentMaxCapacity = BatterySnapshot.intValue(raw, ["AppleRawMaxCapacity", "NominalChargeCapacity", "MaxCapacity"])
        s.rawCurrentCapacity = BatterySnapshot.intValue(raw, ["AppleRawCurrentCapacity"])
        s.cycleCount = BatterySnapshot.intValue(raw, ["CycleCount"]) ?? BatterySnapshot.intValue(inner, ["CycleCount"])

        s.voltageMV = BatterySnapshot.intValue(raw, ["Voltage"])
        s.instantAmperageMA = BatterySnapshot.intValue(raw, ["InstantAmperage"]) ?? BatterySnapshot.intValue(inner, ["InstantAmperage"])
        s.amperageMA = BatterySnapshot.intValue(raw, ["Amperage"]) ?? BatterySnapshot.intValue(inner, ["Amperage"])
        s.temperatureC = temperatureValue(raw["Temperature"])

        // 注册表遥测：部分机型给出系统输入功率（mW）
        if let telemetry = raw["PowerTelemetryData"] as? [String: Any] {
            s.systemPowerInMW = BatterySnapshot.intValue(telemetry, ["SystemPowerIn"])
        }

        s.timeToFullMinutes = saneMinutes(BatterySnapshot.intValue(raw, ["AvgTimeToFull", "TimeToFull"]))
        s.timeToEmptyMinutes = saneMinutes(BatterySnapshot.intValue(raw, ["TimeRemaining", "AvgTimeToEmpty"]))

        s.levelPercent = levelPercent(raw: raw, snapshot: s)

        // 关键字段全空说明注册表读取被拦截，交给下一级
        guard s.designCapacity != nil || s.currentMaxCapacity != nil || s.voltageMV != nil else {
            return nil
        }

        // 原始键值转储（诊断用）
        s.rawRegistryDump = raw.sorted { $0.key < $1.key }.map { key, value in
            (key: key, value: String(describing: value).prefix(120).description)
        }
        return s
    }

    /// CurrentCapacity 在有的机型是百分比、有的是 mAh，这里做启发式判断。
    private static func levelPercent(raw: [String: Any], snapshot: BatterySnapshot) -> Double? {
        if let cur = BatterySnapshot.intValue(raw, ["CurrentCapacity"]), cur > 0, cur <= 100 {
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

    // MARK: - D. 二级：IOPS 系统电源接口

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

    // MARK: - D. 三级：UIDevice 兜底

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

    // MARK: - A+C. 合并：HID 传感器 + 充电器详情

    /// 把传感器与充电器详情并入快照（就地修改）。
    private static func mergeExtras(into snapshot: inout BatterySnapshot) {
        // --- HID 传感器 ---
        let readings = hid.read()
        snapshot.sensorReadings = readings.map { ($0.name, $0.usage, $0.value) }

        // 传感器集合为空时尝试重扫（插拔后集合可能变化）
        if readings.isEmpty {
            hid.rescan()
        }

        func sensor(_ name: String) -> Double? {
            readings.first { $0.name == name }?.value
        }

        snapshot.usbInputVoltage = sensor("Charger VQ0u")
        snapshot.usbInputCurrent = sensor("Charger IQ0u")
        snapshot.wirelessInputVoltage = sensor("Charger VQ1u")
        snapshot.sensorBatteryCurrent = sensor("Charger IQ0B")
        snapshot.sensorBatteryVoltage = sensor("Charger VQ0l") ?? sensor("PMU VP0u")

        // 传感器看到输入而注册表没说插电：以传感器为准（注册表状态可能滞后）
        let usbLive = (snapshot.usbInputVoltage ?? 0) > 0.5
        let wirelessLive = (snapshot.wirelessInputVoltage ?? 0) > 1
        if (usbLive || wirelessLive) && snapshot.isPluggedIn != true {
            snapshot.isPluggedIn = true
            if snapshot.isFull != true {
                snapshot.isCharging = snapshot.isCharging ?? true
            }
        }

        // --- 充电器详情（powerd）---
        if let adapter = IOKitBridge.shared.adapterDetails() {
            snapshot.adapterName = adapter["Name"] as? String ?? adapter["Description"] as? String
            snapshot.adapterVoltageMV = BatterySnapshot.intValue(adapter, ["Voltage", "AdapterVoltage"])
            snapshot.adapterCurrentMA = BatterySnapshot.intValue(adapter, ["Current"])
            snapshot.adapterIsWireless = BatterySnapshot.boolValue(adapter, ["IsWireless"])
            if let menu = adapter["UsbHvcMenu"] as? [[String: Any]] {
                snapshot.adapterProfiles = menu.compactMap { entry in
                    guard let v = BatterySnapshot.intValue(entry, ["MaxVoltage"]),
                          let c = BatterySnapshot.intValue(entry, ["MaxCurrent"]) else { return nil }
                    return (BatterySnapshot.intValue(entry, ["Index"]) ?? 0, v, c)
                }
            }
            // 充电器自报无线（MagSafe）时补无线状态
            if snapshot.adapterIsWireless == true && wirelessLive {
                snapshot.isPluggedIn = true
            }
        }
    }

    // MARK: - 取值工具

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
