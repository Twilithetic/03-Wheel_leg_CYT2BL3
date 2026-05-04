# CYT2BL3 USB 与调试接口说明手册

> 基于 Infineon CYT2BL Datasheet (002-28876 Rev. *H) 及 TRAVEO T2G 系列技术文档
> 项目：Wheel_leg_CYT2BL3 | 核心芯片：CYT2BL3

---

## 一、核心结论（TL;DR）

| 问题 | 答案 |
|------|------|
| CYT2BL3 有 USB 外设吗？ | ❌ **没有** |
| 有 D+/D- 引脚吗？ | ❌ **没有** |
| 能直接用 USB 线调试吗？ | ❌ **芯片不支持直连 USB** |
| 能用 USB 调试器调试吗？ | ✅ **可以！用 J-Link 等通过 SWD 接口** |

> 🔑 **关键理解**：芯片不需要有 USB，也能用 USB 调试器！调试器（J-Link）一头接电脑 USB，另一头接芯片的 SWD/JTAG，充当"翻译官"的角色。

---

## 二、CYT2BL3 的通信接口全貌

从官方 Datasheet Table 1-1（Features list）可以确认，CYT2BL3 支持的通信外设如下：

| 外设 | 通道数 (64-LQFP) | 说明 |
|------|:---:|------|
| **CAN FD** (CAN0) | 3 ch | 高达 8 Mbps，汽车总线 |
| **CAN FD** (CAN1) | 2 ch | 同上 |
| **LIN** | 7 ch | 车身控制网络 |
| **CXPI** | 2 ch | 时钟扩展外设接口 |
| **SCB/UART** | 7 ch | 串口 |
| **SCB/I²C** | 6 ch | I²C 总线 |
| **SCB/SPI** | 3 ch | SPI 总线 |
| **USB** | ❌ **0** | **不支持！** |

> CYT2BL 系列定位为 **汽车车身控制器 (Body Controller)**，典型应用场景是 CAN/LIN 网络通信，不需要 USB。TRAVEO T2G 家族中 **CYT3/CYT4 系列**（仪表盘、信息娱乐等）才有 USB 外设。

---

## 三、那怎么用 USB 调试？——调试器架构

### 3.1 调试链路拓扑

```
┌──────────┐     USB 线      ┌──────────────┐   SWD 2线   ┌──────────────┐
│  你的电脑  │◄──────────────►│   USB 调试器   │◄───────────►│  CYT2BL3 芯片 │
│  (Win/Linux)│                │  (J-Link /    │  SWDIO+SWCLK │  核心板 P3     │
│             │               │   DAPLink 等)  │               │              │
└──────────┘                  └──────────────┘               └──────────────┘
     ▲                              ▲                            ▲
     │                              │                            │
  运行 IDE/烧录软件           USB→SWD协议转换               SWD外设在芯片内部
  (IAR/J-Flash/OpenOCD)       "翻译官"角色                  (硬件支持)
```

### 3.2 调试器就是"翻译官"

调试器（如 J-Link）内部做的事：

```
电脑端 (USB)                    调试器内部                      芯片端 (SWD)
─────────────────────────────────────────────────────────────────────
"擦除 Flash 扇区 5"  ──►  USB 数据包  ──►  转换为 SWD 协议  ──►  发送给 CM0+ 系统调用
                                                                     │
"写入 256 字节到              ◄──  USB 应答  ◄──  转换 SWD 应答  ◄──  返回状态码 0xA
 0x10002000"                                                       (成功)
```

**所以芯片不需要 USB！** 它只需要 SWD/JTAG 接口（这也是 ARM Cortex-M 芯片的标准调试接口）。

---

## 四、本项目核心板的调试方案

### 4.1 P3 SWD 接口回顾

```
P3 插座 (10-pin Cortex Debug, 2×5, 1.27mm 间距)

      ┌─────────────────┐
      │ 1  VCC3V3   GND  2 │  ← 目标电压检测 + 地
      │ 3  NRST     SWDIO 4 │  ← 复位线 + 数据
      │ 5  SWCLK    (NC)  6 │  ← 时钟
      │ 7  (NC)     (NC)  8 │
      │ 9  (NC)     (NC) 10 │
      └─────────────────┘
      
      SWDIO ──[22Ω J2]── P3-4
      SWCLK ──[22Ω J1]── P3-5
      NRST  ──[10KΩ R2 上拉至 VCC3V3]── P3-3
```

### 4.2 推荐调试器

| 调试器 | 价格 | 特点 | 连接 P3 方式 |
|--------|------|------|-------------|
| **SEGGER J-Link EDU** | ~¥400 | 行业标准，速度最快 | J-Link 20-pin → 杜邦线 → P3 |
| **SEGGER J-Link OB** | ~¥100 | 精简版，够用 | 直接杜邦线 |
| **DAPLink (CMSIS-DAP)** | ~¥30 | 开源，便宜 | 杜邦线接 4 线 |
| **ST-Link v2** | ~¥20 | 需要重刷固件 | 不推荐（兼容性差） |

### 4.3 J-Link 连接 CYT2BL3 核心板

```
J-Link (20-pin 牛角座)               CYT2BL3 P3 (2×5 排针)
═══════════════════════              ══════════════════
Pin 1  VTref (目标电压检测)  ──────  Pin 1  VCC3V3
Pin 4  GND                  ──────  Pin 2  GND
Pin 7  SWDIO (TMS)          ──────  Pin 4  SWDIO
Pin 9  SWCLK (TCK)          ──────  Pin 5  SWCLK
Pin 15 nRESET               ──────  Pin 3  NRST (可选)
```

### 4.4 调试/烧录软件配置

#### J-Flash（SEGGER 官方）
```
1. File → New Project
2. Target Device: Infineon → TRAVEO T2G → CYT2BL3
3. Target Interface: SWD
4. Speed: 4000 kHz (初始), 可上调至 15000 kHz
5. Target → Connect      → 验证连接
6. Target → Erase Chip    → 全片擦除
7. File → Open Data File  → 加载 .hex / .bin
8. Target → Production Programming → 烧录！
```

#### OpenOCD (开源方案)
```bash
# 启动 OpenOCD 服务器 (使用 J-Link 作为探针)
openocd -f interface/jlink.cfg \
        -c "transport select swd" \
        -c "adapter speed 4000" \
        -f target/traveo2_c2d_4m.cfg

# 另一个终端用 telnet 连接
telnet localhost 4444
> reset halt
> traveo2 flash erase_sector 0 0 100
> flash write_image erase firmware.hex
> reset
```

#### IAR EWARM（一站式开发）
```
1. Project → Options → Debugger → Driver: J-Link/J-Trace
2. Project → Options → J-Link/J-Trace → Connection: SWD
3. 点击 "Download and Debug" (Ctrl+D)
   → 自动编译 → 连接 → 擦除 → 烧录 → 开始调试 ✓
```

---

## 五、常见问题 FAQ

### Q1: 为什么不用 USB 直接连芯片？
**A:** CYT2BL3 是汽车级 MCU，设计场景不需要 USB。CAN/LIN 才是汽车通信的标准。USB 会增加芯片成本和功耗。

### Q2: JTAG 和 SWD 有什么区别？我该用哪个？

| 特性 | JTAG | SWD |
|------|------|-----|
| 引脚数 | 4 线 (TMS/TCK/TDI/TDO) | **2 线** (SWDIO/SWCLK) |
| 速度 | 较慢 | **更快** |
| 额外功能 | 边界扫描 | - |
| 推荐 | 保留给产线测试 | ✅ **日常开发首选** |

> 本项目核心板 P3 用的是 **SWD 模式**，只需要 SWDIO + SWCLK + GND 三根线就能调试！

### Q3: 可以用 ST-Link 吗？
**A:** 理论上 ST-Link 支持 SWD 协议，但 TRAVEO T2G 不是 STM32，ST-Link 的固件可能不完全兼容。**强烈建议使用 J-Link**——Infineon 官方支持的调试器。

### Q4: 需要外接电源吗？
**A:** **需要！** 核心板通过 LDO (RT9013) 从 5V 产生 3.3V 供电。J-Link 的 VTref 只用于检测目标电压，**不能给核心板供电**。接线时：
- ✅ 核心板接 5V 电源
- ✅ J-Link VTref 接 P3-VCC3V3（检测）
- ❌ 不要用 J-Link 供电

### Q5: SWD 连接不上怎么办？
1. 确认核心板供电正常（测 VCC3V3 = 3.3V ± 0.1V）
2. 确认 J-Link VTref 测到 3.3V
3. 检查 SWDIO/SWCLK 接线（两线不要反）
4. 上电后等待 >200ms（Boot 完成 SWD 引脚才激活）
5. 在 J-Flash 中降低 SWD 速度到 100 kHz 试试

---

## 六、总结

```
┌──────────────────────────────────────────────────────┐
│                                                      │
│   CYT2BL3 没有 USB，但有 SWD/JTAG ——                 │
│   这正是 ARM Cortex-M 芯片调试的标准姿势！             │
│                                                      │
│   🎯 你需要的就是：                                   │
│   一台 J-Link 调试器 + 几根杜邦线 =                   │
│   完整调试 & 烧录体验                                  │
│                                                      │
│   电脑 ──[USB]──► J-Link ──[SWD]──► CYT2BL3          │
│                                              │       │
│                                        P3 接口        │
│                                                      │
└──────────────────────────────────────────────────────┘
```

---

*手册版本：v1.0 | 2026-05-04 | 基于 Infineon 官方 Datasheet*
