//
//  IOKitBridge.swift
//  TrollBattery
//
//  通过 dlopen / dlsym 直接调用 IOKit 私有接口读取 AppleSmartBattery 注册表。
//  这样编译期完全不依赖 IOKit 头文件，普通 iOS SDK 也能构建通过。
//

import Foundation
import Darwin

final class IOKitBridge {

    static let shared = IOKitBridge()

    // MARK: - 符号签名

    private typealias IOServiceMatchingFn =
        @convention(c) (UnsafePointer<CChar>) -> CFMutableDictionary?

    private typealias IOServiceGetMatchingServiceFn =
        @convention(c) (UInt32, CFDictionary?) -> UInt32

    private typealias IORegistryEntryCreateCFPropertiesFn =
        @convention(c) (UInt32,
                        UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>,
                        CFAllocator?,
                        UInt32) -> kern_return_t

    private typealias IOObjectReleaseFn =
        @convention(c) (UInt32) -> kern_return_t

    private typealias IOPSCopyPowerSourcesInfoFn =
        @convention(c) () -> Unmanaged<CFTypeRef>?

    private typealias IOPSCopyPowerSourcesListFn =
        @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?

    private typealias IOPSGetPowerSourceDescriptionFn =
        @convention(c) (CFTypeRef, CFTypeRef) -> Unmanaged<CFDictionary>?

    // MARK: - 已解析符号

    private let serviceMatching: IOServiceMatchingFn?
    private let getMatchingService: IOServiceGetMatchingServiceFn?
    private let registryCreateProperties: IORegistryEntryCreateCFPropertiesFn?
    private let objectRelease: IOObjectReleaseFn?

    private let copyPowerSourcesInfo: IOPSCopyPowerSourcesInfoFn?
    private let copyPowerSourcesList: IOPSCopyPowerSourcesListFn?
    private let getPowerSourceDescription: IOPSGetPowerSourceDescriptionFn?

    private let handle: UnsafeMutableRawPointer?

    /// IOKit 核心符号是否可用（决定能否读到完整电池数据）
    var isIOKitAvailable: Bool {
        serviceMatching != nil
            && getMatchingService != nil
            && registryCreateProperties != nil
            && objectRelease != nil
    }

    /// 公开电源接口是否可用（回退方案）
    var isPowerSourcesAvailable: Bool {
        copyPowerSourcesInfo != nil && copyPowerSourcesList != nil && getPowerSourceDescription != nil
    }

    // MARK: - 初始化

    private init() {
        // IOKit 在 iOS 上是私有框架，路径固定；先按路径打开，失败再退回全局符号表。
        let path = "/System/Library/Frameworks/IOKit.framework/IOKit"
        var h = dlopen(path, RTLD_LAZY | RTLD_GLOBAL)
        if h == nil {
            h = dlopen(nil, RTLD_LAZY | RTLD_GLOBAL)
        }
        handle = h

        serviceMatching = Self.symbol(h, "IOServiceMatching", as: IOServiceMatchingFn.self)
        getMatchingService = Self.symbol(h, "IOServiceGetMatchingService", as: IOServiceGetMatchingServiceFn.self)
        registryCreateProperties = Self.symbol(h, "IORegistryEntryCreateCFProperties", as: IORegistryEntryCreateCFPropertiesFn.self)
        objectRelease = Self.symbol(h, "IOObjectRelease", as: IOObjectReleaseFn.self)

        copyPowerSourcesInfo = Self.symbol(h, "IOPSCopyPowerSourcesInfo", as: IOPSCopyPowerSourcesInfoFn.self)
        copyPowerSourcesList = Self.symbol(h, "IOPSCopyPowerSourcesList", as: IOPSCopyPowerSourcesListFn.self)
        getPowerSourceDescription = Self.symbol(h, "IOPSGetPowerSourceDescription", as: IOPSGetPowerSourceDescriptionFn.self)
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
        guard let handle = handle, let ptr = dlsym(handle, name) else { return nil }
        return unsafeBitCast(ptr, to: T.self)
    }

    // MARK: - 电池注册表属性

    /// 依次尝试的电池服务名。
    /// AppleSmartBattery 属性最全；IOPMPowerSource 是更底层的备用通道，部分机型只放开后者。
    private let candidateServices = ["AppleSmartBattery", "IOPMPowerSource"]

    /// 按候选顺序读取电池注册表属性，返回首个成功的结果。
    func batteryProperties() -> (service: String, properties: [String: Any])? {
        for name in candidateServices {
            if let props = properties(forService: name) {
                return (name, props)
            }
        }
        return nil
    }

    /// 读取指定 IOKit 服务的全部注册表属性。
    /// 需要平台级 entitlement（TrollStore 安装的应用通常自带），普通沙盒 App 会返回 nil。
    func properties(forService name: String) -> [String: Any]? {
        guard isIOKitAvailable,
              let matching = serviceMatching?(name),
              let service = getMatchingService?(0 /* kIOMasterPortDefault == MACH_PORT_NULL */, matching),
              service != 0
        else { return nil }

        defer { _ = objectRelease?(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        let kr = registryCreateProperties?(service, &properties, nil, 0)
        guard kr == KERN_SUCCESS, let unmanaged = properties else { return nil }

        let dict = unmanaged.takeRetainedValue()
        return dict as? [String: Any]
    }

    // MARK: - 公开电源接口（回退）

    /// 通过 IOPS 拿到当前电源描述（电量百分比 / 充电状态 / 预计时间）。
    /// 该接口在系统内是公开行为，即使没有 IOKit 权限也通常可用。
    func powerSourceDescription() -> [String: Any]? {
        guard isPowerSourcesAvailable,
              let infoRef = copyPowerSourcesInfo?().takeRetainedValue(),
              let listRef = copyPowerSourcesList?(infoRef).takeRetainedValue()
        else { return nil }

        let list = listRef as NSArray
        for item in list {
            let itemRef: CFTypeRef = item as AnyObject
            if let desc = getPowerSourceDescription?(infoRef, itemRef) {
                // 按 CoreFoundation 命名规则，"Get" 系列返回 +0 引用，此处不可 release。
                let dict = desc.takeUnretainedValue()
                return dict as? [String: Any]
            }
        }
        return nil
    }
}
