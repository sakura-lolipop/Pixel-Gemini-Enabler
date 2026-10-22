# Pixel-Gemini-Enabler

一键修复并防止 Pixel 上 **Gemini 应用反复被系统自动禁用（桌面图标消失）** 的脚本。
纯 `pm` 配置层操作，**无需 root、无需 Xposed/LSPosed/Magisk 任何框架**，秒级可逆。

## 问题现象

在部分国家/地区，系统组件 **Google Partner Setup**（`com.google.android.partnersetup`）
会按服务端下发的地区可用性策略，把 Gemini（`com.google.android.apps.bard`）连同
Google TV、Maps 等应用一起 `pm disable`。你手动启用后，它会在下一个触发点
（开机 / Gservices 配置同步 / SIM 变化 / 应用更新）重新禁用——图标就这样反复消失。

自证方法（一条命令看到真凶）：

```sh
adb shell "dumpsys package com.google.android.apps.bard | grep -E 'enabled=|lastDisabledCaller'"
# enabled=2 (DISABLED) + lastDisabledCaller: com.google.android.partnersetup
```

## 方案

反编译 PartnerSetup 并做全量调用链交叉引用，触达禁用 API
（`setApplicationEnabledSetting` / `setComponentEnabledSetting`）的路径**只有 8 个组件**：

| 类型 | 组件 | 触发 |
|---|---|---|
| 广播接收器 | `.BootReceiver` | BOOT_COMPLETED / 自身更新 |
| 广播接收器 | `.GservicesChangedReceiver` | 服务端配置同步 |
| 广播接收器 | `.PhoneStateReceiver` | SIM / 地区变化 |
| 广播接收器 | `.PhenotypeBroadcastReceiver` | Phenotype 配置推送 |
| 广播接收器 | `…stable.PhenotypeUpdateBackgroundBroadcastReceiver` | 同上 |
| JobService | `.InstalledAppJobService` | 周期任务 |
| JobService | `.AppHidingJobService` | 周期任务（名字即职能） |
| JobService | `.PhenotypeJobService` | 配置推送任务 |

只禁这 8 个执行入口，**其余功能原样保留**：RLZ provider（`rlzappprovider` 等，
代码证实与隐藏无关，属纯遥测管线）、phenotype 元数据服务、clientId 配置、
通话自修复等全部不受影响。组件级状态存于系统的 package-restrictions，
重启不丢，`pm enable` 随时还原。

## 使用

```sh
./gemini_guard.sh on       # 一键恢复: 启用所有被策略禁用的 Google 应用 + 禁用 8 个入口
./gemini_guard.sh off      # 一键还原: 8 个入口全部恢复原状（应用保持启用）
./gemini_guard.sh status   # 查看当前状态（Gemini 状态 + 逐组件清单）
```

- 依赖：手机开启 **USB 调试**，电脑有 `adb`（默认取 PATH 中的 adb；
  或用环境变量指定：`ADB=/path/to/adb ./gemini_guard.sh on`）。
  `pm disable/enable` 是系统授予 shell 的常规命令，**不需要 root**。
- 多台设备时用 `SERIAL=设备序列号` 指定目标。
- `on` 会自动扫描全机 `lastDisabledCaller` 记录，把所有被 PartnerSetup
  禁过的应用（Gemini / Google TV / Maps / YouTube 等）一并恢复。

## 恢复 / 卸载

```sh
./gemini_guard.sh off      # 脚本还原
# 或手动全量还原：
adb shell "pm enable com.google.android.partnersetup; pm enable com.google.android.apps.bard"
```

系统 OTA 大版本更新后建议跑一次 `status` 复核组件状态。

## 已知边界

- 触达禁用 API 的入口由反编译确认（PartnerSetup v100.740061114 / Pixel Android 17 实测）。
  Google 未来改版若新增执行路径，重跑 `status` 观察 + `lastDisabledCaller` 仍可定位；
  极端情况下可用 LSPosed 钩 `PackageManager.setApplicationEnabledSetting` 兜底。
- 禁用入口后，PartnerSetup 的"地区策略"不再自动执行：换卡/跨地区时 Google 应用
  的可用性不会自动切换（`off` 后即恢复自动）。
- 部分应用（如 Google TV 的影视租赁）在服务端仍有地区门控，图标恢复 ≠ 内容可用。

## License

MIT
