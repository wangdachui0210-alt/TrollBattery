//
//  HIDSensors.swift
//  TrollBattery
//
//  通过 IOHIDEventSystemClient 私有接口读取 Apple 电源传感器。
//  本实现参考 ChargeSpeed（github.com/gregsramblings/ios-charging-monitor，MIT License）
//  在 iPhone 17 Pro Max / iOS 26 真机上验证过的方案。
//
//  关键事实：
//  1. 该通道即使普通沙盒 App 也可用（每进程只能创建一个 client，多了返回 NaN）；
//     TrollStore 应用带 no-sandbox 特权，同样适用。
//  2. 传感器命名（iPhone 17 Pro Max 实测）：
//     Charger VQ0u / IQ0u  → USB-C 输入电压 / 电流   ← 这是「线缆传过来的功率」，对标充电器功率计
//     Charger VQ1u         → 无线（MagSafe）输入电压
//     Charger IQ0B         → 进入电池的电流
//     Charger VQ0l, PMU VP0u → 电池端电压
//     gas gauge battery    → 电池温度（usage page 0xff00, usage 5）
//  3. 传感器名称随机型 / 系统版本而异，所以必须把发现的传感器全部列出，
//     由 BatteryReader 按名称匹配，读不到的字段自然降级。
//

import Foundation
import Darwin

final class HIDSensors {

    struct Reading {
        let name: String
        /// HID usage：2 = 电流(A)，3 = 电压(V)，5 = 温度(℃)
        let usage: Int
        let value: Double
    }

    // MARK: - 符号签名

    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatchingFn = @convention(c) (CFTypeRef, CFDictionary) -> Void
    private typealias CopyServicesFn = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias GetFloatFn = @convention(c) (CFTypeRef, Int32) -> Double

    private static let powerEventType: Int64 = 25        // kIOHIDEventTypePower
    private static let temperatureEventType: Int64 = 15  // kIOHIDEventTypeTemperature

    private struct Service {
        let ref: CFTypeRef
        let name: String
        let usage: Int
        let eventType: Int64
    }

    private let client: CFTypeRef
    private let setMatching: SetMatchingFn
    private let copyServices: CopyServicesFn
    private let copyProperty: CopyPropertyFn
    private let copyEvent: CopyEventFn
    private let getFloat: GetFloatFn
    private var services: [Service] = []

    /// 是否成功初始化（失败则整体降级，不影响 App 其它功能）
    private(set) var isAvailable: Bool

    // MARK: - 初始化

    init() {
        let path = "/System/Library/Frameworks/IOKit.framework/IOKit"
        let h = dlopen(path, RTLD_NOW)

        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let h, let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: type)
        }

        guard let create = sym("IOHIDEventSystemClientCreate", CreateFn.self),
              let setMatching = sym("IOHIDEventSystemClientSetMatching", SetMatchingFn.self),
              let copyServices = sym("IOHIDEventSystemClientCopyServices", CopyServicesFn.self),
              let copyProperty = sym("IOHIDServiceClientCopyProperty", CopyPropertyFn.self),
              let copyEvent = sym("IOHIDServiceClientCopyEvent", CopyEventFn.self),
              let getFloat = sym("IOHIDEventGetFloatValue", GetFloatFn.self),
              let clientBox = create(kCFAllocatorDefault)
        else {
            self.client = "" as CFTypeRef
            self.setMatching = { _, _ in }
            self.copyServices = { _ in nil }
            self.copyProperty = { _, _ in nil }
            self.copyEvent = { _, _, _, _ in nil }
            self.getFloat = { _, _ in 0 }
            self.isAvailable = false
            return
        }
        let client = clientBox.takeRetainedValue()

        self.client = client
        self.setMatching = setMatching
        self.copyServices = copyServices
        self.copyProperty = copyProperty
        self.copyEvent = copyEvent
        self.getFloat = getFloat
        self.isAvailable = true
        rescan()
    }

    /// 重新枚举传感器服务。插拔充电器后传感器集合可能变化，需要重扫。
    func rescan() {
        guard isAvailable else { return }
        var found: [Service] = []
        // Apple 厂商电源传感器（usage page 0xff08）：usage 2 = 电流，3 = 电压
        found += discover(matching: ["PrimaryUsagePage": 0xff08], eventType: Self.powerEventType)
        // 温度传感器：usage page 0xff00, usage 5
        found += discover(matching: ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5], eventType: Self.temperatureEventType)
        services = found
    }

    var sensorCount: Int { services.count }

    private func discover(matching: [String: Any], eventType: Int64) -> [Service] {
        setMatching(client, matching as CFDictionary)
        let refs = copyServices(client)?.takeRetainedValue() as? [CFTypeRef] ?? []
        return refs.map { ref in
            let name = copyProperty(ref, "Product" as CFString)?.takeRetainedValue() as? String ?? "?"
            let usage = (copyProperty(ref, "PrimaryUsage" as CFString)?.takeRetainedValue() as? NSNumber)?.intValue ?? 0
            return Service(ref: ref, name: name, usage: usage, eventType: eventType)
        }
    }

    /// 读取全部传感器当前值（返回 NaN 的跳过）。
    func read() -> [Reading] {
        guard isAvailable else { return [] }
        return services.compactMap { service in
            guard let event = copyEvent(service.ref, service.eventType, 0, 0)?.takeRetainedValue() else { return nil }
            let value = getFloat(event, Int32(service.eventType << 16))
            guard value.isFinite else { return nil }
            return Reading(name: service.name, usage: service.usage, value: value)
        }
    }
}
