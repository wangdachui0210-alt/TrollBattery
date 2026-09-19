//
//  BatterySnapshot.swift
//  TrollBattery
//
//  一次电池采样的完整数据模型。
//
//  v2 修订（2026-09-19）：功率读数与充电器功率计 / 第三方软件不一致的根因是
//  只显示「电池端功率」，且该数据源（注册表 Voltage × InstantAmperage）在真机上
//  不可靠（可能是陈旧值）。本次引入三层功率：
//    1. 输入端功率（USB / 无线）—— HID 传感器 VQ0u × IQ0u，对标充电器功率计与主流第三方 App
//    2. 输入端功率回退 —— PowerTelemetryData.SystemPowerIn（注册表遥测，mW）
//    3. 电池端功率 —— 注册表 V × I（旧逻辑，降级为参考值）
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

struct BatterySnapshot {

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

    // 电池端电气参数（注册表，真机上可能不可靠）
    var cycleCount: Int?               // 循环次数
    var voltageMV: Int?                // 电压 mV
    var instantAmperageMA: Int?        // 瞬时电流 mA（充电为流入）
    var amperageMA: Int?               // 平均电流 mA
    var temperatureC: Double?          // 温度 ℃

    // 输入端电气参数（HID 传感器，真机可靠）
    var usbInputVoltage: Double?       // USB-C 输入电压 V
    var usbInputCurrent: Double?       // USB-C 输入电流 A
    var wirelessInputVoltage: Double?  // 无线输入电压 V
    var sensorBatteryVoltage: Double?  // 传感器读的电池端电压 V
    var sensorBatteryCurrent: Double?  // 传感器读的进入电池电流 A
    /// HID 传感器原始读数（诊断用）：名称 / usage / 数值
    var sensorReadings: [(name: String, usage: Int, value: Double)] = []

    // 充电器信息（powerd AdapterDetails）
    var adapterName: String?           // 充电器名称
    var adapterVoltageMV: Int?         // 协商电压 mV
    var adapterCurrentMA: Int?         // 协商电流 mA
    /// 充电器广播的全部 PD 档位 (index, mV, mA)
    var adapterProfiles: [(index: Int, voltageMV: Int, currentMA: Int)] = []
    var adapterIsWireless: Bool?

    // 注册表遥测（部分机型可用）
    var systemPowerInMW: Int?          // 系统输入功率 mW

    /// AppleSmartBattery 注册表原始键值（诊断用，排序后全量）
    var rawRegistryDump: [(key: String, value: String)] = []

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

    /// 输入端功率（W）：USB 输入 V × I —— 对标充电器功率计与主流第三方 App 的读数
    var usbInputWatts: Double? {
        guard let v = usbInputVoltage, let i = usbInputCurrent, v > 0.5, i > 0 else { return nil }
        return v * i
    }

    /// 是否无线输入：无线电压有效而 USB 电压无效
    var isWirelessInput: Bool {
        (wirelessInputVoltage ?? 0) > 1 && (usbInputVoltage ?? 0) < 1
    }

    /// 传感器读的电池端功率（W）
    var sensorBatteryWatts: Double? {
        guard let i = sensorBatteryCurrent, let v = sensorBatteryVoltage else { return nil }
        return i * v
    }

    /// 注册表读的电池端功率（W，绝对值）—— 真机上可能是陈旧值，仅作参考
    var registryBatteryWatts: Double? {
        guard let voltage = voltageMV, voltage > 0,
              let current = instantAmperageMA ?? amperageMA else { return nil }
        return abs(Double(voltage) * Double(current)) / 1_000_000.0
    }

    /// 电池端功率（W）：优先传感器，回退注册表
    var batteryWatts: Double? {
        sensorBatteryWatts ?? registryBatteryWatts
    }

    /// 输入端功率（W）：优先传感器，回退注册表遥测
    var inputWatts: Double? {
        if let w = usbInputWatts { return w }
        if let mw = systemPowerInMW, mw > 0 { return Double(mw) / 1000.0 }
        return nil
    }

    /// 主显示功率：插着电源看输入端（对标功率计），否则看电池端（放电功耗）
    var primaryWatts: Double? {
        if isPluggedIn == true, let w = inputWatts { return w }
        return batteryWatts
    }

    /// 主显示功率的标签
    var primaryWattsLabel: String {
        if isPluggedIn == true {
            return isWirelessInput ? "无线输入端" : "输入端"
        }
        return "电池端"
    }

    /// 实时功率（带方向，充电为正、放电为负）
    var signedPowerWatts: Double? {
        guard let power = batteryWatts else { return nil }
        return isCharging == true ? power : -power
    }

    /// 实时电流（安培，绝对值）—— 电池端
    var currentAmps: Double? {
        if let i = sensorBatteryCurrent { return abs(i) }
        if let current = instantAmperageMA ?? amperageMA { return abs(Double(current)) / 1000.0 }
        return nil
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

    /// 是否有任何可用功率数据
    var hasPowerData: Bool { primaryWatts != nil || batteryWatts != nil }

    /// 充电器协商摘要，如 "20.0 V × 2.25 A"
    var adapterNegotiatedText: String? {
        if let v = adapterVoltageMV, let c = adapterCurrentMA, v > 0, c > 0 {
            return String(format: "%.1f V × %.2f A", Double(v) / 1000, Double(c) / 1000)
        }
        return nil
    }

    // MARK: - 取值工具（静态，供 Reader 复用）

    /// IOKit 会把 32 位有符号值包装成 64 位无符号数返回
    /// （例如 -658 mA 显示为 18446744073709550958），此处统一拆包。
    static func signedValue(_ number: NSNumber) -> Int {
        let value = number.int64Value
        if value > Int64(Int32.max) || value < Int64(Int32.min) {
            return Int(Int32(truncatingIfNeeded: value))
        }
        return Int(value)
    }

    static func intValue(_ dict: [String: Any], _ keys: [String]) -> Int? {
        for key in keys {
            if let number = dict[key] as? NSNumber { return signedValue(number) }
        }
        return nil
    }

    static func boolValue(_ dict: [String: Any], _ keys: [String]) -> Bool? {
        for key in keys {
            if let flag = dict[key] as? Bool { return flag }
            if let number = dict[key] as? NSNumber { return number.boolValue }
        }
        return nil
    }
}
