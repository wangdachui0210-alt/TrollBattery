# 巨魔电池 · TrollBattery

TrollStore 专用的 iOS 电池工具：**电池容量**（设计容量 / 当前最大容量 / 健康度 / 循环次数）＋ **充电实时功率**（W / 电流 / 电压 / 温度 / 功率曲线）。

- 部署目标：iOS 14.0+
- 无第三方依赖，纯 SwiftUI
- 无需开发者账号、无需配置描述文件，产出未签名 IPA 直接交给 TrollStore

---

## 一、为什么没有现成的 IPA

当前你的电脑是 Windows。iOS 应用必须用 **macOS + Xcode（iPhoneOS SDK）** 编译，Windows 上无法产出 IPA。

因此这里交付的是**完整可编译工程**，下面三条路线任选一条出包：

| 路线 | 需要什么 | 耗时 | 说明 |
|---|---|---|---|
| **A. GitHub Actions（推荐）** | 一个 GitHub 账号 | 约 5 分钟 | 不占用本地资源，推代码即自动出 IPA |
| **B. 本地脚本** | 一台 Mac + Xcode | 约 2 分钟 | 跑 `./build_ipa.sh` |
| **C. Xcode 图形界面** | 一台 Mac + Xcode | 约 3 分钟 | 适合后续改代码调试 |

---

## 二、路线 A：GitHub Actions 自动出包（无需 Mac）

```bash
# 1. 在本目录初始化仓库
git init
git add .
git commit -m "feat: TrollBattery initial"

# 2. 推到你的 GitHub（换成自己的仓库地址）
git remote add origin https://github.com/<你的用户名>/TrollBattery.git
git branch -M main
git push -u origin main
```

推送完成后打开仓库的 **Actions** 页面：

1. 等 `Build TrollBattery IPA` 跑完（约 3–5 分钟）
2. 页面底部 **Artifacts** → 下载 `TrollBattery-unsigned-ipa`
3. **下载到的是个 zip，先解压一次**，里面就是 `TrollBattery.ipa`

> 若想让 CI 直接产出可下载的 IPA 文件（不再套一层 zip），打一个 tag 即可：
> ```bash
> git tag v1.0.0 && git push origin v1.0.0
> ```
> 之后在仓库 **Releases** 里直接下载 `TrollBattery.ipa`。

---

## 三、路线 B：Mac 本地一条命令

```bash
brew install ldid          # 可选，用于注入 entitlements
bash build_ipa.sh
```

产出 `TrollBattery.ipa` 于当前目录。

## 四、路线 C：Xcode 图形界面

1. 双击 `TrollBattery.xcodeproj`
2. 顶部 Scheme 选 `TrollBattery`，设备选 **Any iOS Device (arm64)**
3. `Product` → `Build`（工程已设 `CODE_SIGNING_ALLOWED=NO`，不会要求证书）
4. 产物在 `~/Library/Developer/Xcode/DerivedData/TrollBattery-*/Build/Products/Release-iphoneos/TrollBattery.app`
5. 建一个 `Payload` 文件夹，把 `.app` 拖进去，压缩成 `TrollBattery.ipa`

---

## 五、安装到 iPhone

1. 把 `TrollBattery.ipa` 传到手机（AirDrop / 微信文件传输 / 爱思助手）
2. 用 **TrollStore** 打开该 IPA（分享菜单 → TrollStore，或在 TrollStore 里点右上角 `+`）
3. 点 `Install`，回桌面即可看到「巨魔电池」

---

## 六、权限与排查

应用采用三级读取策略，界面右上角会显示当前数据来源：

| 徽标 | 含义 | 能读到什么 |
|---|---|---|
| IOKit 完整数据 | 权限正常 | 容量、健康度、循环、功率、温度全量 |
| 系统电源接口 | IOKit 被拦截 | 仅电量百分比、充电状态、预计时间 |
| 基础接口 | 兜底 | 仅电量百分比 |

**如果只显示「系统电源接口」或「基础接口」**，说明 AppleSmartBattery 注册表被拦截，处理顺序：

1. 确认应用是**用 TrollStore 安装**的（普通签名安装绝无可能读到 IOKit）
2. 确认 `TrollBattery.entitlements` 已通过 `ldid` 注入（路线 A / B 的脚本已自动处理）
3. 仍不行就点界面底部「查看诊断信息」，把 `source` 与各字段值发我，据此调整权限组合

> 说明：TrollStore 安装时默认会给应用 `platform-application` 等特权，多数设备不加任何额外配置即可直读 IOKit。entitlements 注入属于保险措施。

---

## 七、工程结构

```
TrollBattery/
├── TrollBattery/
│   ├── TrollBatteryApp.swift      App 入口
│   ├── ContentView.swift          界面（健康度环 / 功率卡 / 明细 / 曲线）
│   ├── BatteryModel.swift         采样与状态管理（2 秒一采）
│   ├── BatterySnapshot.swift      数据模型与派生值（健康度、功率）
│   ├── BatteryReader.swift        三级读取策略
│   ├── IOKitBridge.swift          dlopen/dlsym 调用 IOKit 私有接口
│   ├── HistoryChart.swift         纯 Path 功率曲线（兼容 iOS 14）
│   ├── Info.plist
│   └── TrollBattery.entitlements  私有权限声明
├── TrollBattery.xcodeproj
├── .github/workflows/build.yml    CI 自动出包
├── build_ipa.sh                   Mac 本地出包（bash build_ipa.sh）
└── README.md
```

## 八、可以自己改的地方

| 想改什么 | 改哪里 |
|---|---|
| 应用名 / Bundle ID | `Info.plist` 的 `CFBundleDisplayName`；`project.pbxproj` 的 `PRODUCT_BUNDLE_IDENTIFIER` |
| 采样间隔 | `BatteryModel.swift` 的 `interval`（默认 2 秒） |
| 曲线保留点数 | `BatteryModel.swift` 的 `maxSamples`（默认 150） |
| 支持的最低系统 | `project.pbxproj` 的 `IPHONEOS_DEPLOYMENT_TARGET` |

## 九、已知限制

- 部分机型 `InstantAmperage` 键不存在，此时功率会回落到 `Amperage`（平均电流），数值波动更平滑但不够瞬时。
- 电池温度键 `Temperature` 在各机型单位不一致（0.01℃ / 0.1℃），代码已做区间启发式判断，若显示异常请在诊断信息中核对原始值。
- 应用未申请后台常驻权限，退出后停止采样；曲线数据不落盘，重启即清零。
