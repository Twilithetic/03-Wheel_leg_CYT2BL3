# ST-LINK/V2 官方手册摘要

> 来源：STMicroelectronics UM1075 Rev 10 (April 2024)
> 官方下载：https://www.st.com/resource/en/user_manual/um1075-stlinkv2-incircuit-debuggerprogrammer-for-stm8-and-stm32-stmicroelectronics.pdf

---

## 一、硬件规格

| 参数 | 值 |
|------|-----|
| USB | 2.0 Full-Speed (12 Mbps) |
| SWD 速度 | 最高 4 MHz（默认 1.8 MHz） |
| JTAG 速度 | 最高 9 MHz（默认 1.125 MHz） |
| SWV 追踪 | 最高 2 MHz |
| 目标电压 | 1.65 - 3.6 V |
| 输入耐受 | 5 V |
| 供电 | USB 供电 |
| 状态灯 | 通信时闪烁 |
| DFU | 支持固件在线升级 |

---

## 二、接口引脚

### 20-pin JTAG 连接器（标准 2.54mm 间距）

```
Pin  信号      方向      说明
───  ────────  ────      ──────────────────
 1   VTref     IN        目标电压检测
 2   NC                  未连接
 3   nTRST     OUT       JTAG 复位
 4   GND                 地
 5   TDI       OUT       JTAG 数据输入
 6   GND                 地
 7   TMS/SWDIO IN/OUT    模式选择 / SWD 数据
 8   GND                 地
 9   TCK/SWCLK OUT       时钟
10   GND                 地
11   NC                  未连接
12   GND                 地
13   TDO/SWO   IN        JTAG 数据输出 / SWV 追踪
14   GND                 地
15   NRST      IN/OUT    目标复位
16   GND                 地
17   NC                  未连接
18   GND                 地
19   NC                  未连接
20   GND                 地
```

### SWD 模式只需 4 线

```
VTref  (Pin 1)  → 目标 VCC (电压检测)
GND    (Pin 4)  → 目标 GND
SWDIO  (Pin 7)  → 目标 SWDIO (CYT2BL3 P3-Pin4)
SWCLK  (Pin 9)  → 目标 SWCLK (CYT2BL3 P3-Pin5)
NRST   (Pin 15) → 目标 NRST (可选，CYT2BL3 P3-Pin3)
```

---

## 三、支持的协议

| 协议 | 目标芯片 | 接口 |
|------|---------|------|
| SWIM | STM8 | 单线 |
| SWD | STM32 (所有) | 2 线 |
| JTAG | STM32 | 4 线 |
| SWV | STM32 | 追踪输出 |

---

## 四、OpenOCD 中的 ST-Link

### 两种驱动模式

```
1. HLA 模式 (传统，默认)
   接口: interface/stlink.cfg
   传输: hla_swd
   特点: 
     ✅ 简单，开箱即用
     ❌ 不支持多 AP (ap-num 只能 = 0)
     ❌ 功能受限
     ⚠️ 已被 OpenOCD 标记为 deprecated

2. DAP API 模式 (新，需固件 >= V2.J21.S4)
   接口: interface/stlink-dap.cfg (或 stlink.cfg 新版自动检测)
   传输: swd (直接)
   特点:
     ✅ 支持多 AP
     ✅ 完整 DAP 功能
     ⚠️ 需要 ST-Link 固件 >= V2.J21.S4
     ⚠️ AP 数量受固件版本限制 (V2J29=3个, V2J32=8个)
```

### 我们遇到的问题

```
CYT2BL3 需要 AP1 (CM0+) + AP2 (CM4)
ST-Link V2 (克隆版) 只能 HLA 模式
HLA 模式不支持多 AP → Error: invalid parameter -ap-num (> 0)
```

---

## 五、和其他探针的对比

| 特性 | ST-Link V2 | J-Link EDU | MiniProg4 |
|------|:---:|:---:|:---:|
| 厂商 | ST | SEGGER | Infineon |
| 价格 | ¥15-30 | ¥200-400 | ¥150 |
| SWD 速度 | 4 MHz | 15 MHz | 2 MHz |
| 多 AP 支持 | ❌ (HLA) | ✅ | ✅ |
| CYT2BL3 | ❌ | ✅ | ✅ |
| RTT 日志 | ❌ | ✅ | ❌ |
| Flash 断点 | 有限 | 无限 | 有限 |
| 厂商锁 | STM32/STM8 | 无 | Infineon |

---

## 六、ST-Link 硬件版本

| 版本 | 说明 |
|------|------|
| ST-LINK/V1 | 最早版本，已淘汰 |
| ST-LINK/V2 | 当前常见，独立调试器 |
| ST-LINK/V2-A | V2 变体 |
| ST-LINK/V2-B | V2 变体 |
| ST-LINK/V2-1 | 板载版本（Nucleo/Discovery 板上） |
| STLINK-V3 | 最新版，USB 2.0 HS，速度大幅提升 |
| STLINK-V3PWR | V3 + 功耗测量 |

---

## 七、参考资料

| 文档 | 链接 |
|------|------|
| UM1075 用户手册 | https://www.st.com/resource/en/user_manual/um1075-stlinkv2-incircuit-debuggerprogrammer-for-stm8-and-stm32-stmicroelectronics.pdf |
| ST-LINK/V2 产品页 | https://www.st.com/en/development-tools/st-link-v2.html |
| ST-LINK USB 驱动 (STSW-LINK009) | https://www.st.com/en/development-tools/stsw-link009.html |
| ST-LINK 固件升级工具 | https://www.st.com/en/development-tools/stsw-link007.html |
| OpenOCD ST-Link 文档 | https://openocd.org/doc/html/Debug-Adapter-Configuration.html |

---

*摘要版本：v1.0 | 2026-05-04*
