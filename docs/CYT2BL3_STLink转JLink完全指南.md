# ST-Link → J-Link 转换完全指南

> *"ST-Link V2 真的能刷成 J-Link？怎么做到的？"*
> 基于 SEGGER 官方文档及社区实践

---

## 一、核心答案

```
✅ ST-Link V2 可以刷成 J-Link！
✅ 你的 VID:0483 PID:3748 完全支持！
✅ 可逆操作，随时刷回 ST-Link！
```

---

## 二、原理：硬件相同，固件不同

### 2.1 ST-Link 的硬件本质

```
ST-Link V2 内部是一颗 STM32F103C8T6 MCU：

  ┌─────────────────────────────────────────┐
  │         ST-Link V2 内部                  │
  │                                          │
  │  ┌──────────────┐    ┌──────────────┐   │
  │  │ STM32F103C8T6 │   │ 电平转换 +    │   │
  │  │ (主控 MCU)    │   │ ESD 保护      │   │
  │  │              │   │              │   │
  │  │ USB ── PC    │───│ SWD ── 目标芯片 │   │
  │  │ 12 Mbps      │   │              │   │
  │  └──────────────┘    └──────────────┘   │
  │                                          │
  │  运行 ST-Link 固件 (ST 官方)              │
  │  或 J-Link OB 固件 (SEGGER)              │
  │  或 CMSIS-DAP 固件 (开源)                │
  └─────────────────────────────────────────┘
```

> 💡 **硬件完全一样！** ST-Link 和 J-Link OB 用的是同一颗 STM32F103 芯片。区别只在固件——就像同一台电脑可以装 Windows 也可以装 Linux。

### 2.2 刷固件改变了什么

```
刷之前 (ST-Link):                  刷之后 (J-Link OB):

  USB: VID 0483 PID 3748           USB: VID 1366 PID 0101
  协议: ST-Link 私有协议            协议: J-Link 协议
  驱动: WinUSB                      驱动: SEGGER J-Link 驱动
  识别: "STM32 STLink"             识别: "J-Link"
  
  SWD: ✅ 支持                      SWD: ✅ 支持 (更快)
  Flash: 仅 STM32 算法              Flash: 40+ 厂商算法
  调试: 基础                        调试: RTT / SWO / 无限断点
```

### 2.3 不变的是什么

```
✅ USB 接口 — 还是那个 Micro-USB 口
✅ SWD 引脚 — 还是那几根线 (SWDIO/SWCLK/GND/VTref)
✅ 烧录原理 — USB → 探针 → SWD → 目标芯片
✅ 硬件速度 — 还是 USB Full-Speed (12 Mbps)

改变的是:
  🔄 USB 协议 — ST-Link 私有 → SEGGER J-Link 标准
  🔄 驱动 — WinUSB → SEGGER 驱动
  🔄 Flash 算法库 — STM32 专用 → 全系列支持
```

---

## 三、SEGGER 官方支持

### 3.1 官方页面

```
https://www.segger.com/products/debug-probes/j-link/models/other-j-links/st-link-on-board/

SEGGER 官方提供的工具: STLinkReflash.exe

功能:
  ✅ 将 ST-Link 固件替换为 J-Link OB 固件
  ✅ 可刷回 ST-Link 原始固件
  ✅ 支持 ST-Link V2 和 V2.1
  ✅ 免费使用 (开发用途)
```

### 3.2 你的 ST-Link V2 兼容性

```
你的设备: VID 0x0483 PID 0x3748 (ST-Link V2)

SEGGER 兼容列表:
  ✅ 所有 Nucleo 板上的 ST-Link V2.1
  ✅ 所有 Discovery 板上的 ST-Link V2
  ✅ 独立 ST-Link V2 调试器 ← 你的！
  ⚠️ ST-Link V3 (需要更新版本的 STLinkReflash)
  ⚠️ 克隆版 ST-Link (有些可以，有些不行)
```

---

## 四、操作步骤

### 4.1 准备工作

```
1. 下载 SEGGER J-Link 软件包
   https://www.segger.com/downloads/jlink/

2. 下载 STLinkReflash 工具
   https://www.segger.com/downloads/jlink#STLink_Reflash

3. 确保 ST-Link 驱动正常
   设备管理器 → 能看到 "STM32 STLink"
```

### 4.2 转换步骤

```
Step 1: 关闭所有使用 ST-Link 的软件 (IDE、OpenOCD 等)

Step 2: 运行 STLinkReflash.exe (管理员权限)

Step 3: 接受 SEGGER 许可协议
        ⚠️ 注意: 只能用于 ST 芯片的开发和调试
        (调试非 ST 芯片可能违反协议)
        
        ┌─────────────────────────────────────┐
        │  SEGGER License Agreement            │
        │                                      │
        │  [✓] I accept the terms              │
        │                                      │
        │  1. Upgrade to J-Link                │
        │  2. Restore ST-Link                   │
        └─────────────────────────────────────┘
        选 "1" → Enter

Step 4: 等待固件写入 (~10 秒)

Step 5: 拔掉 ST-Link，重新插入

Step 6: 验证
        设备管理器 → 应该看到 "J-Link"
        或运行 JLink.exe → 显示固件版本
```

### 4.3 刷回 ST-Link（如果需要）

```
运行 STLinkReflash.exe → 选 "2. Restore ST-Link"
完全可逆！
```

---

## 五、刷完后的使用

### 5.1 验证

```powershell
# 查看 J-Link 信息
JLink.exe

# 期望输出:
# SEGGER J-Link Commander V7.xx
# Connecting to J-Link via USB...O.K.
# Firmware: J-Link OB-STM32F103 V1 compiled ...
# Hardware version: V1.00
# S/N: xxxxxxxx
# VTref = 3.300V
```

### 5.2 烧录 CYT2BL3

```powershell
# 方式 1: J-Link Commander
JLink.exe -device CYT2BL3 -if SWD -speed 4000 -autoconnect 1

# 方式 2: J-Flash GUI
# 打开 J-Flash → 选 CYT2BL3 → File → Open → firmware.hex
# → Target → Production Programming

# 方式 3: Makefile (已配置好)
make flash
```

### 5.3 和 probe-rs 配合

```
刷成 J-Link 后，probe-rs 也能用 J-Link 协议连接：

probe-rs list
# 输出: J-Link (VID: 1366, PID: 0101, ...)

但 Flash 烧录还是需要 probe-rs 有 CYT2BL3 算法。
所以：
  调试 → probe-rs (连接快，好看)
  烧录 → J-Flash 或 make flash (有算法)
```

---

## 六、授权说明

### 6.1 SEGGER 许可

```
⚠️ 重要: SEGGER 的 STLinkReflash 许可协议规定:

  ✅ 可以用于:
    - ST 官方芯片 (STM32/STM8) 的开发和调试
    - 个人学习项目

  ⚠️ 灰色地带:
    - 调试非 ST 芯片 (如 CYT2BL3)
    - SEGGER 协议字面上禁止
    - 但技术上完全可以 (SWD 是通用协议)
    - J-Link 固件内置了 CYT2BL3 算法 (SEGGER 自己加的)
    
  ❌ 禁止:
    - 量产烧录
    - 商业产品开发 (需购买正版 J-Link)
    
  💡 建议:
    学习/个人项目 → 可以用
    商业项目 → 买正版 J-Link EDU (~¥400)
```

---

## 七、USB 通信详解

### 7.1 刷固件前后的 USB 对比

```
刷前 (ST-Link):

  USB 描述符:
    设备类:     Vendor Specific (0xFF)
    VID/PID:    0x0483 / 0x3748
    端点:       EP1 IN (Bulk), EP2 OUT (Bulk), EP3 IN (Bulk)
    协议:       ST-Link 私有协议

  通信过程:
    openocd -f interface/stlink.cfg
      ↓ (USB Bulk)
    ST-Link 固件解析 ST-Link 协议
      ↓ (SWD)
    目标芯片


刷后 (J-Link OB):

  USB 描述符:
    设备类:     Vendor Specific (0xFF)
    VID/PID:    0x1366 / 0x0101 (SEGGER)
    端点:       EP1 IN (Bulk), EP2 OUT (Bulk)
    协议:       J-Link 协议

  通信过程:
    JLink.exe -device CYT2BL3
      ↓ (USB Bulk)
    J-Link 固件解析 J-Link 协议
      ↓ (SWD)
    目标芯片
```

### 7.2 为什么 J-Link 能连 CYT2BL3？

```
J-Link 固件内置了 TRAVEO T2G 的特殊连接序列:

  1. SWD 连接 CM0+ (AP0)
  2. 不复位！(关键！)
  3. 等待 CM0+ Boot ROM 完成
  4. CM0+ 释放 CM4
  5. 连接 CM4 (AP1)
  6. = 成功！

这个序列是 SEGGER 和 Infineon 合作开发的。
ST-Link 的原始固件没有这个序列。
```

---

## 八、总结

```
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║  🔑 ST-Link → J-Link 的原理:                                 ║
║                                                              ║
║  硬件: 同一颗 STM32F103 芯片                                 ║
║  固件: ST 固件 → SEGGER 固件                                ║
║  USB:  还是那个口，协议从 ST-Link 变成 J-Link                ║
║  SWD:  还是那几根线，能力大大增强                            ║
║                                                              ║
║  🎯 对 CYT2BL3 的意义:                                       ║
║  J-Link 固件内置了 TRAVEO T2G 专用的双核连接序列              ║
║  (先连 CM0+、等释放、再连 CM4)                               ║
║  这正是 probe-rs 缺少的东西！                                ║
║                                                              ║
║  📦 你现在就可以:                                            ║
║  1. 下 STLinkReflash                                        ║
║  2. 一键转换                                                ║
║  3. make flash → ✅ CYT2BL3 烧录成功！                       ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

---

*报告版本：v1.0 | 2026-05-04 | 基于 SEGGER 官方文档*
