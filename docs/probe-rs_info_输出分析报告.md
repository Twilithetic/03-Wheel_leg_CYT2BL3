# probe-rs info 输出逐行分析报告 — CYT2BL3

> 实测时间：2026-05-05 | 调试器：ST-Link V2/V3 | 协议：SWD/JTAG
> 对照文档：`SWD_JTAG_调试架构分析报告.md`

---

## 一、JTAG 协议探测 — 失败分析

```
Probing target via JTAG
-----------------------

 WARN probe_rs::probe::stlink: send_jtag_command 242 failed: JtagUnknownJtagChain
Failed to identify target using protocol JTAG
```

### 为什么 JTAG 失败了？

```
原因：JtagUnknownJtagChain

技术含义：
  JTAG 协议支持 "菊花链" — 多个芯片串在一起，共享 TDI→TDO
  调试器需要先扫描链上有几个设备（通过 TAP 状态机的 Shift-IR/Shift-DR）
  但 CYT2BL3 的 JTAG-DP 返回了调试器不认识的链结构

可能原因（三选一或多选）：
  ① ST-Link 的 JTAG 实现不支持 CYT2BL3 的多 AP 架构
     → probe-rs 用 CMSIS-DAP 协议发包给 ST-Link
     → ST-Link 固件在 JTAG 模式下无法正确枚举链结构
  ② 芯片的 JTAG-DP 当前不可用
     → CYT2BL3 支持 SWJ-DP（双协议 Debug Port）
     → 但可能 JTAG 部分被 DAP 限制或需要特殊初始化
  ③ SWD 引脚模式冲突
     → JTAG 需要5根线，SWD 只需要2根
     → CYT2BL3 复位后引脚默认 GPIO，需 CM0+ Flash Boot 配置
     → JTAG 的 TCK/TMS/TDI/TDO 物理连线可能不完整

结论：
  JTAG 在 CYT2BL3 上不是最优选择。
  但没关系！SWD 成功了 ↓↓↓
```

---

## 二、SWD 协议探测 — 成功！

### 2.1 DP 识别

```
Probing target via SWD
----------------------

ARM Chip with debug port Default:

Debug Port: DPv2, Designer: Cypress, Part: 0xea02, Revision: 0x1, Instance: 0x00
```

### 逐字段解读

```
┌─────────────────────────────────────────────────────────────┐
│ 字段        值              含义                            │
├─────────────────────────────────────────────────────────────┤
│ DPv2        DPv2            ADIv5 Debug Port v2             │
│                             支持 SWD 协议 v2                 │
│                             DPv2 比 v1 多了：多 AP 支持、    │
│                             power control、错误恢复          │
│                                                              │
│ Designer    Cypress         芯片设计师 = Cypress 半导体       │
│                             (已被 Infineon 收购)              │
│                             JEP106 编码: cc=0x04, id=0x34   │
│                                                              │
│ Part        0xea02          Cypress 的部件号                  │
│                             对应 Traveo T2G 系列             │
│                             (具体 CYT2BL3)                   │
│                                                              │
│ Revision    0x1             DP 硬件版本 r1p0                 │
│ Instance    0x00            DP 实例编号（多 DP 时区分）       │
└─────────────────────────────────────────────────────────────┘

🟢 结论: SWD 物理层连接正常！
   DP 正确响应、返回了有效的 IDCODE。
   这证明：SWD 引脚已配置为调试模式 (CM0+ Flash Boot 已完成此步骤)
```

### 2.2 三个 MemoryAP 的发现

这是最关键的部分——probe-rs 发现了 **三个** 内存访问端口：

```
├── V1(0) MemoryAP               ← AP#0: CM0+ 的调试接口
│   └── 0 MemoryAP (AmbaAhb3)
│       └── 0xf1000000 ROM Table (Class 1), Designer: Cypress
│
├── V1(1) MemoryAP               ← AP#1: 系统级 AP (System AP)
│   └── 1 MemoryAP (AmbaAhb3)
│       ├── 0xf0000000 ROM Table (Class 1), Designer: Cypress
│       ├── 0xe00ff000 ROM Table (Class 1), Designer: ARM Ltd
│       ├── 0xf0002000 CTI architecture (Coresight Component)
│       └── 0xf0003000 Coresight Component, Part: 0x0932
│
└── V1(2) MemoryAP               ← AP#2: CM4 的调试接口
    └── 2 MemoryAP (AmbaAhb3)
        ├── 0xe00ff000 ROM Table (Class 1), Designer: Cypress
        ├── 0xe0080000 Coresight Component, Part: 0x0906
        ├── 0xe008c000 CoreSight TraceFunnel
        ├── 0xe008d000 CoreSight ETB   (Trace Buffer)
        ├── 0xe008e000 Cortex-M3 TPIU  (Trace Port Interface)
        ├── 0xe007f000 ROM Table (Class 1), Designer: Cypress
        ├── 0xe0001000 Generic                          ← ⚠️ 异常！
        ├── 0xe0000000 Peripheral test block            ← ⚠️ 异常！
        ├── 0xe0042000 Coresight Component, Part: 0x0906
        └── 0xe0041000 Cortex-M4 ETM   (Embedded Trace Macrocell)
```

---

## 三、三个 AP 的身份推断

### 3.1 AP#0 → CM0+ (确信度 95%)

```
V1(0) MemoryAP
  └── 0xf1000000 ROM Table, Designer: Cypress

推断依据:
  ✅ 只有一个 ROM Table，结构最简单
  ✅ 地址 0xf1000000 是 CYT2BL3 CM0+ 的调试基地址（参考 datasheet）
  ✅ Cypress 设计师 → 芯片厂商自己的 IP
  ✅ 没有发现任何 CoreSight 标准组件（CM0+ 调试功能极少）

CM0+ 的调试能力:
  Cortex-M0+ 只有: MTB (Micro Trace Buffer) 4KB — 最简追踪
  没有: ETM, DWT, ITM, FPB 等高级调试组件
  所以 ROM Table 下几乎没有子组件 → 输出很简单
```

### 3.2 AP#1 → System AP (确信度 80%)

```
V1(1) MemoryAP
  ├── 0xf0000000 ROM Table, Designer: Cypress
  ├── 0xe00ff000 ROM Table, Designer: ARM Ltd
  ├── CTI (Cross Trigger Interface)
  └── Part 0x0932

推断依据:
  ✅ 同时有 Cypress 和 ARM 的 ROM Table → 桥接系统级组件
  ✅ CTI 是系统级交叉触发接口 → 非 CPU 专属
  ✅ 没有发现 CPU SCS (System Control Space) 寄存器
  ✅ 从 Infineon 文档看，SYS_AP 只能访问 SRAM/Flash/MMIO，不连 CPU

System AP 的作用:
  通过这个 AP，调试器可以：
  → 读写 SRAM 任意地址
  → 读写 Flash (映射区域)
  → 读写外设 MMIO 寄存器
  但不能 halt CPU 或读写 CPU 核心寄存器！
```

### 3.3 AP#2 → CM4 (确信度 100%)

```
V1(2) MemoryAP
  ├── 0xe00ff000 ROM Table, Designer: Cypress
  ├── CoreSight TraceFunnel ─── 追踪数据汇聚
  ├── CoreSight ETB ─────────── 嵌入式追踪缓冲区 (8KB!)
  ├── Cortex-M3 TPIU ────────── 追踪端口接口单元
  ├── Cortex-M4 ETM ─────────── 嵌入式追踪宏单元 ← 🎯 决定性证据！
  ├── 0xe0001000 Generic ────── ⚠️ 本应是 DWT (数据观察点)
  └── 0xe0000000 Peripheral test block ─ ⚠️ 本应是 ITM (指令追踪)

铁证如山:
  "Cortex-M4 ETM" 出现在 AP#2 下 → 100% 确认为 CM4 调试接口
  ETM 是 M4 的专属追踪组件，M0+ 没有！
```

---

## 四、关键异常：ROM Table 的 Invalid Preamble 警告

### 4.1 警告原文

```
 WARN probe_rs::architecture::arm::memory::romtable:
   Component at 0xe0001000: CIDR0 has invalid preamble (expected 0xd, got 0x0)

 WARN probe_rs::architecture::arm::memory::romtable:
   Component at 0xe0000000: CIDR0 has invalid preamble (expected 0xd, got 0xb1)
```

### 4.2 技术解析

ARM CoreSight 组件识别机制：

```
每个 CoreSight 调试组件在 ROM Table 中有一个条目，条目中包含:

  ┌────────────────────────────────────────────────────┐
  │  Component Identification Registers (CIDR0-3)      │
  │                                                     │
  │  CIDR0[7:0] = 0x0D    ← Preamble (前导码，必须)    │
  │  CIDR1[7:0] = 0x00    ← Preamble Class             │
  │  CIDR2[7:0] = 0x05    ← Preamble                   │
  │  CIDR3[7:0] = 0xB1    ← Preamble                   │
  │                                                     │
  │  这4个字节组合 = 0xB105000D = "这是一个组件条目"    │
  └────────────────────────────────────────────────────┘

probe-rs 的验证逻辑 (伪代码):
  fn validate_component(addr) {
      let cidr0 = mem.read(addr + 0xFF0);
      if cidr0 & 0xFF != 0x0D {
          warn!("CIDR0 has invalid preamble (expected 0xd, got {})", cidr0);
          return None; // 跳过这个组件
      }
      // ... 继续验证 CIDR1, CIDR2, CIDR3
  }
```

### 4.3 每个警告对应的真实组件

| 地址 | probe-rs 显示 | 实际应该是 | 读到的值 | 原因 |
|------|-------------|-----------|---------|------|
| `0xe0001000` | "Generic" | **DWT** (Data Watchpoint & Trace) | CIDR0=0x00 | 组件未上电/不可达 |
| `0xe0000000` | "Peripheral test block" | **ITM** (Instrumentation Trace) | CIDR0=0xB1 | 部分可达但数据损坏 |
| `0xe000e000` | 未出现在输出中 | **SCS** (System Control Space, 含 CPUID) | — | 完全不可达 |

### 4.4 缺失的核心组件

```
正常 Cortex-M4 的 ROM Table 应该包含:
  ✅ 0xe00ff000  ROM Table (入口)
  ├── 0xe000e000  SCS (System Control Space)
  │   └── CPUID: 0x410FC241 (ARM Cortex-M4 r0p1)
  ├── 0xe0001000  DWT (Data Watchpoint and Trace)   ← ⚠️ 这里坏了
  ├── 0xe0002000  FPB (Flash Patch and Breakpoint)  ← ❌ 完全没出现
  ├── 0xe0000000  ITM (Instrumentation Trace)       ← ⚠️ 这里坏了
  ├── 0xe0041000  ETM (Embedded Trace Macrocell)    ← ✅ 正常！
  ├── 0xe0042000  CTI (Cross Trigger Interface)     ← ✅ 正常！
  ├── 0xe008c000  TraceFunnel                       ← ✅ 正常！
  ├── 0xe008d000  ETB (Trace Buffer)                ← ✅ 正常！
  └── 0xe008e000  TPIU (Trace Port Interface)       ← ✅ 正常！

发现了什么规律？
  ✅ ETM, ETB, TPIU, TraceFunnel — 全部正常 (追踪子系统独立供电/时钟)
  ⚠️ DWT, ITM — 读到异常值 (部分可达但寄存器损坏)
  ❌ FPB, SCS(含CPUID) — 完全不可达
        
  这说明: CM4 的调试域部分断电或时钟被 gated！
  追踪硬件有自己的独立电源域 → 一直可用
  CPU 核心调试寄存器在 CPU 电源域 → CPU 在复位/低功耗 → 不可访问
```

---

## 五、CYT2BL3 当前状态推断

### 5.1 用观察到的数据反推芯片状态

```
┌─────────────────────────────────────────────────────────────┐
│              从 probe-rs 输出推断的芯片状态                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  DP:       ✅ 活跃 (always-on 域)                            │
│  CM0_AP:   ✅ 活跃 → CM0+ 已经完成启动                       │
│  SYS_AP:   ✅ 活跃 → 系统总线可访问                          │
│  CM4_AP:   ⚠️ 部分活跃                                      │
│    ├── 追踪组件:  ✅ 全部可读 (独立电源)                      │
│    ├── 调试组件:  ⚠️ 损坏/不可达                             │
│    │   ├── SCS (含CPUID): ❌ 不可达                          │
│    │   ├── DWT:          ⚠️ CIDR 损坏                       │
│    │   ├── FPB:          ❌ 未出现                           │
│    │   └── ITM:          ⚠️ CIDR 损坏                       │
│    └── ETM:       ✅ 可读 (独立时钟域)                        │
│                                                             │
│  推断: CM4 核心处于以下状态之一:                              │
│    A) 复位状态 — 最常见的原因                                │
│    B) 时钟被 gated — CM0+ 还没给 CM4 开时钟                  │
│    C) 低功耗休眠 — CM4 被关断                                │
│                                                             │
│  关键矛盾: ETM 可读，但 SCS 不可读                           │
│  解释: ETM 在独立的电源/时钟域 (由追踪子系统管理)             │
│        SCS/DWT/FPB 在 CPU 核心域 (随 CPU 一起上下电)         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 为什么 ETM 可读但核心寄存器不可读？

```
这是 CYT2BL3 设计决定的：

  ┌─────────────┐     ┌──────────────┐
  │   CM4 核心   │     │  Trace 子系统 │
  │  ┌───────┐  │     │  ┌──────────┐ │
  │  │  SCS  │  │     │  │   ETM    │ │
  │  │  DWT  │  │     │  │   ETB    │ │
  │  │  FPB  │  │     │  │  Funnel  │ │
  │  │  CPU  │  │     │  │   TPIU   │ │
  │  └──┬────┘  │     │  └────┬─────┘ │
  │     │       │     │       │       │
  │   CPU 电源域 │     │  Trace 电源域 │
  │   (可关断)   │     │  (常开)       │
  └─────────────┘     └──────────────┘

CM4 在复位中 → CPU 电源域被 gated → SCS/DWT/FPB 不可读
             但 Trace 电源域独立供电 → ETM/ETB/TPIU 可读

这就是为什么你能看到 "Cortex-M4 ETM" 但看不到 CPUID 的原因！
```

---

## 六、与 probe-rs 正常输出的对比

### 6.1 正常的 Cortex-M4 输出（STM32F4 为例）

```
Debug Port: DPv1, Designer: ARM Ltd
└── 0 MemoryAP (AmbaAhb3)
    └── ROM Table (Class 1), Designer: STMicroelectronics
        ├── Cortex-M4 SCS (Generic IP component)       ← ✅
        │   └── CPUID                                    ← ✅
        │       ├── IMPLEMENTER: ARM Ltd                 ← ✅
        │       ├── VARIANT: 1
        │       ├── PARTNO: Cortex-M4                    ← ✅
        │       └── REVISION: 1
        ├── Cortex-M4 DWT (Generic IP component)       ← ✅
        ├── Cortex-M4 FBP (Generic IP component)       ← ✅
        ├── Cortex-M4 ITM (Generic IP component)       ← ✅
        ├── Cortex-M4 TPIU (Coresight Component)       ← ✅
        └── Cortex-M4 ETM (Coresight Component)        ← ✅
```

### 6.2 CYT2BL3 的实际输出

```
Debug Port: DPv2, Designer: Cypress
├── V1(0) MemoryAP          ← CM0+
├── V1(1) MemoryAP          ← System AP
└── V1(2) MemoryAP          ← CM4
    ├── (没有 Cortex-M4 SCS)     ← ❌ 缺失！
    ├── (没有 CPUID)              ← ❌ 缺失！
    ├── Generic                  ← ⚠️ DWT 损坏
    ├── Peripheral test block    ← ⚠️ ITM 损坏
    ├── (没有 FPB)               ← ❌ 缺失！
    ├── Cortex-M4 ETM            ← ✅ 追踪引擎正常
    ├── CoreSight ETB            ← ✅ 追踪缓冲正常
    ├── CoreSight TraceFunnel    ← ✅ 追踪汇聚正常
    └── Cortex-M3 TPIU           ← ✅ 追踪端口正常
```

### 6.3 差异一句话

> **正常芯片**：probe-rs 能读到 CPUID → 知道 "这是 Cortex-M4 r0p1" → 可以 halt/resume/断点/单步
> **CYT2BL3**：probe-rs 读不到 CPUID → 不知道是什么核 → 无法做任何 CPU 级调试操作！

---

## 七、根本原因总结

### 7.1 技术根因链

```
上电
  │
CM0+ ROM Boot 执行
  │
  ├── 配置 DAP 访问限制
  │   └── CM4_AP 的 DAP 被设为 "受限" 或 "禁止"
  │
  ├── (此时 probe-rs 如果连接:)
  │   ├── DP → 可达 (always-on 域)              ✅
  │   ├── CM0_AP → 可达                          ✅ (ROM Boot 有限开放)
  │   ├── SYS_AP → 可达                          ✅
  │   └── CM4_AP → 部分可达                      ⚠️
  │       ├── Trace 子系统 → 独立电源 → 可达     ✅
  │       └── CPU 核心域 → 复位/gated → 不可达  ❌
  │
CM0+ Flash Boot → 配置 SWD 引脚 → 释放 CM4
  │
  │   (此时 probe-rs 如果连接:)
  │   ├── DP → 可达                              ✅
  │   ├── CM0_AP → 可达                          ✅
  │   ├── SYS_AP → 可达                          ✅
  │   └── CM4_AP → **全部可达！**                 ✅
  │       ├── SCS/CPUID → 可读                   ✅
  │       ├── DWT/FPB/ITM → 可读                 ✅
  │       └── 可以 halt/single-step/断点          ✅
  │
  └── 你的 probe-rs info 是在这个之前还是之后抓的？
      → 从输出看：CM4 还没被释放！
      → SCS/DWT/ITM/FPB 不可达
      → 只能看到 Trace 子系统
```

### 7.2 你的芯片当前状态

```
你的 CYT2BL3 当前处于: "CM0+ 已完成 ROM Boot + Flash Boot，SWD 引脚已配置，
                      但 CM4 尚未被释放复位" 的状态。

证据:
  ✅ SWD 能连上 → CPUSS_SWD 引脚已配置为调试模式
  ✅ CM0_AP 存在 → CM0+ 已启动完成
  ✅ CM4_AP 存在 → AP 硬件存在
  ✅ Trace 组件可读 → Trace 电源域正常
  ❌ CM4 SCS 不可达 → CM4 核心在复位/低功耗中
  
这意味着:
  你的 CM0+ 代码可能:
  ① 跑到了一个 while(1) 死循环（还没执行释放 CM4 的代码）
  ② 进入了某个错误处理（签名验证失败？）
  ③ 正常跑着但故意不释放 CM4（等待某个条件）
```

---

## 八、接下来怎么办

### 8.1 验证诊断

```bash
# 尝试通过 System AP 读取 SRAM — 如果成功说明总线正常工作
probe-rs read b32 --chip CYT2BL3 0x08000000 4

# 尝试 halt CM0+ (AP#0) — 看能否成功
probe-rs reset --chip CYT2BL3
```

### 8.2 让 CM4 可调试的根本方案

```
要让 probe-rs 能正常调试 CM4，需要:

方案 A: 修改 CM0+ Flash Boot 代码
  → 在 CM0+ 启动早期就释放 CM4 复位
  → 配置 CM4_AP 为完全允许
  → 然后 probe-rs 就能正常连接 CM4

方案 B: 使用我们正在做的 YAML + Flash 算法
  → probe-rs 连接 CM0_AP (AP#0)
  → 在 SRAM 注入代码 → 让 CM0+ 执行
  → 注入代码做的事:
      1. 写 CPUSS_CM4_VECTOR_TABLE_BASE
      2. 释放 CM4 复位
      3. 配置 DAP 允许 CM4_AP 访问
  → probe-rs 重新扫描 → CM4 完全可见！

方案 C: 等待当前 CM0+ 代码完成启动
  → 如果 CM0+ 最终会释放 CM4，那就等
  → 用 probe-rs attach 而不是 reset
```

---

## 九、关键教训

```
从这次 probe-rs info 输出中，我们学到的三个核心认知：

1. "DP 可达 ≠ CPU 可达"
   → DP 在 always-on 域，永远通电
   → CPU 可能在复位/低功耗，不可访问
   → 这就是为什么 probe-rs 能连上但操作失败

2. "同一个 AP 下，不同组件可达性可以不同"
   → Trace 子系统独立供电 → ETM/ETB/TPIU 可读
   → CPU 核心域随 CPU 上下电 → SCS/DWT/FPB 不可读
   → probe-rs 的 ROM Table 扫描逐个尝试 → 有些成功有些警告

3. "芯片启动流程决定了调试时序"
   → CYT2BL3 = CM0+ 守门人模式
   → CM4 的所有资源（包括调试接口）由 CM0+ 控制
   → 不理解启动流程就无法正确调试
```

---

*报告完成 | 知心姐姐 | 2026-05-05*
*这份报告把你实际运行 probe-rs info 的每一行输出都解剖了，配合之前的 SWD/JTAG 架构报告食用效果最佳！💖*
