# Cortex-M HardFault 诊断笔记

> 适用于 Cortex-M0/M0+/M3/M4/M7/M23/M33 全系列  
> 工具：OpenOCD / GDB / J-Link Commander

---

## 一、三步判断是否进入 HardFault

```tcl
# OpenOCD 命令（用你的 CYT2BL3 CM0+ 核心）
targets traveo2_be_4m.cpu.cm0    # 选 CM0+
halt 5000                          # 暂停 CPU
reg xpsr                           # ★ 关键寄存器
```

```gdb
# GDB 等效命令
monitor halt
monitor reg xpsr
```

### 判断标准

```
xPSR & 0x1FF == 3  →  HardFault
```

**核心就这一句话：`reg xpsr`，看低 9 位是不是 3。**

---

## 二、xPSR 寄存器完全拆解

xPSR = **APSR** + **EPSR** + **IPSR** 三位一体：

```
 31   30   29   28   27   26..25   24   23..20   19..9   8..0
┌────┬────┬────┬────┬────┬───────┬────┬────────┬───────┬───────┐
│ N  │ Z  │ C  │ V  │ Q  │ 保留  │ T  │ ICI/IT │ 保留  │ IPSR  │
└────┴────┴────┴────┴────┴───────┴────┴────────┴───────┴───────┘
└──────── APSR (5bit) ────────┘└EPSR┘└─ EPSR ──┘       └─IPSR(9b)─┘
```

### IPSR：Exception Number（bits [8:0]）

| Number | 名称 | M0/M0+ | M3/M4/M7 |
|--------|------|--------|----------|
| 0 | Thread mode | ✅ | ✅ |
| 1 | 保留 | — | — |
| 2 | NMI | ✅ | ✅ |
| **3** | **HardFault** | ✅ | ✅ |
| 4 | MemManage | → 升级为 HardFault | ✅ |
| 5 | BusFault | → 升级为 HardFault | ✅ |
| 6 | UsageFault | → 升级为 HardFault | ✅ |
| 11 | SVCall | ✅ | ✅ |
| 14 | PendSV | ✅ | ✅ |
| 15 | SysTick | ✅ | ✅ |
| 16+ | IRQ0, IRQ1, ... | ✅ | ✅ |

> ⚠️ M0/M0+ 没有 MemManage/BusFault/UsageFault  
> → 所有内存/总线/指令错误一律升级为 **HardFault (3)**

### APSR：条件码标志（bits [31:27]）

| Bit | 名称 | 含义 |
|-----|------|------|
| 31 | **N** | Negative：结果为负 |
| 30 | **Z** | Zero：结果为零 |
| 29 | **C** | Carry：进位/借位 |
| 28 | **V** | Overflow：溢出 |
| 27 | **Q** | 饱和标志（仅 M3/M4/M7 有 DSP） |

### EPSR（bits [26:24], [15:10]）

| Bit | 名称 | 含义 |
|-----|------|------|
| 24 | **T** | Thumb 状态，Cortex-M 永远为 1 |

---

## 三、实战案例：姐姐的诊断过程

### 命令

```tcl
targets traveo2_be_4m.cpu.cm0
halt 5000
reg pc
reg sp
reg xpsr
mdw 0xE000E100 8        # NVIC ISER（看哪些 IRQ 被使能了）
mdw 0xE000E280 8        # NVIC ICPR（看哪些 IRQ 在挂起）
mdw 0x10000000 8        # 向量表（SP + Reset + NMI + HardFault 入口）
```

### 输出

```
pc   = 0x00006B5C
sp   = 0x08003824
xpsr = 0x81000003          ← ★
NVIC ISER: 全是 0
NVIC ICPR: 全是 0
```

### 解读

```
xpsr = 0x81000003

bit31 N = 1     → 上一条指令结果为负
bit24 T = 1     → Thumb 模式（正常）
bit[8:0] = 0x03 → Exception #3 → HardFault ✅ 确诊！
```

---

## 四、进阶：定位 HardFault 原因

进异常时，硬件自动压栈 8 个寄存器（从 SP 往上）：

```
栈地址      内容
SP + 0x00 → R0       # 当时的寄存器值
SP + 0x04 → R1
SP + 0x08 → R2
SP + 0x0C → R3
SP + 0x10 → R12
SP + 0x14 → LR       # 链接寄存器（判断异常发生时的模式）
SP + 0x18 → PC_fault # ← 这就是触发 HardFault 的指令地址！
SP + 0x1C → xPSR_fault
```

### OpenOCD 命令

```tcl
mdw 0x08003824 8       # 读 8 个 32-bit 值（栈帧）
```

拿第 7 个值去反查 `.map` 文件，就能定位到源代码！

### 栈帧 LR 判断异常前状态

| LR 值（进异常时） | 含义 |
|------------------|------|
| 0xFFFFFFF1 | 异常前在 Handler 模式，用 MSP |
| 0xFFFFFFF9 | 异常前在 Thread 模式，用 MSP |
| 0xFFFFFFFD | 异常前在 Thread 模式，用 PSP |

---

## 五、ARM 核心兼容性

### ✅ 完全通用（Cortex-M 全系列）

- `xPSR` 寄存器格式：**M0 / M0+ / M3 / M4 / M7 / M23 / M33 / M55 / M85 完全一致**
- Exception Number 0~15 含义统一
- NVIC 寄存器（ISER/ICPR/ISPR 等）地址和格式统一
- 异常压栈顺序统一

### ❌ 不通用（Cortex-A / Cortex-R）

- Cortex-A 用的是 **CPSR / SPSR**，格式完全不同
- Cortex-A 异常模型是 ARM 架构参考手册定义的，不是 NVIC

### ✅ 其他 ARM 调试器也适用

| 工具 | 等效命令 |
|------|---------|
| OpenOCD | `reg xpsr` |
| GDB | `monitor reg xpsr` 或 `info registers` |
| J-Link Commander | `reg xPSR` |
| SEGGER Ozone | 寄存器窗口直接看 |
| Keil MDK | Peripherals → Core Peripherals → Fault Reports |

---

## 六、常用 NVIC 寄存器速查

```
0xE000E100  ISER    中断使能寄存器（读：哪些 IRQ 被使能）
0xE000E180  ICER    中断除能寄存器（写 1 清除使能）
0xE000E200  ISPR    中断挂起设置（写 1 强制挂起）
0xE000E280  ICPR    中断挂起清除（写 1 清除挂起）
0xE000E300  IABR    中断活跃位（读：哪些 IRQ 正在执行）
0xE000E400  IPR0..7 中断优先级（每 8 bit 一个 IRQ）
```

## 七、Cortex-M 系统控制寄存器速查

```
0xE000ED00  CPUID    内核 ID
0xE000ED04  ICSR     中断控制状态
0xE000ED08  VTOR     向量表偏移（当前向量表基址）
0xE000ED0C  AIRCR    复位控制（写 0x05FA0004 触发 SYSRESETREQ）
0xE000ED10  SCR      系统控制
0xE000ED14  CCR      配置与控制
0xE000ED1C  SHPR2    系统异常优先级（SVCall）
0xE000ED20  SHPR3    系统异常优先级（PendSV, SysTick）
0xE000ED24  SHCSR    系统 Handler 控制与状态
0xE000ED28  CFSR     可配置 Fault 状态（M3/M4/M7）
0xE000ED2C  HFSR     HardFault 状态（具体原因）
0xE000ED34  MMFAR     MemManage 错误地址
0xE000ED38  BFAR      BusFault 错误地址
0xE000EDF0  DHCSR    调试暂停控制
0xE000EDF4  DCRSR    调试核心寄存器选择
0xE000EDF8  DCRDR    调试核心寄存器数据
0xE000EDFC  DEMCR    调试异常与监控控制
```

---

> 记不住没关系，姐姐帮你存档好了~ 随时回来看就行！💖
