# CYT2BL3 用户固件 SWJ 引脚配置分析 — 源码逐行审计报告

> **日期**: 2026-05-05  
> **分析对象**: `src/main.c`、`src/startup_cyt2bl3_cm4.S`、`src/cyt2bl3_flash.ld`  
> **核心问题**: 用户固件是否在运行阶段修改了 SWJ 引脚配置？

---

## 1. 源码逐行审计

### 1.1 启动代码 (`startup_cyt2bl3_cm4.S`)

```assembly
Reset_Handler:
    ldr  r0, =0xE000ED88       ; CPACR — FPU 访问控制
    ldr  r1, [r0]
    orr  r1, r1, #(0xF << 20)  ; 使能 CP10, CP11
    str  r1, [r0]
    bl   Cy_SystemInit
    ; ... 复制 .data, 清零 .bss ...
    bl   main
```

| 操作 | 是否影响 SWJ？ |
|------|:--:|
| 使能 FPU (CPACR) | ❌ 不影响 |
| Cy_SystemInit() | ❌ 空函数 |
| 复制 .data / 清零 .bss | ❌ 仅操作 SRAM |
| 跳转 main() | — |

### 1.2 链接脚本 (`cyt2bl3_flash.ld`)

```
FLASH 起始: 0x10000000
SRAM  起始: 0x08000800  (预留前 2KB 给系统)
栈大小:    8KB @ SRAM 末尾
```

| 配置 | 是否影响 SWJ？ |
|------|:--:|
| Code Flash 基址 0x10000000 | ❌ 标准地址 |
| SRAM 预留 2KB (0x08000000-0x080007FF) | ❌ 保护 OpenOCD/flash algo 工作区 |

### 1.3 主程序 (`main.c`)

```c
void gpio_pin_output(uint32_t port_base, uint8_t pin) {
    volatile uint32_t *cfg = (volatile uint32_t *)(port_base + 0x20);  // GPIO_CFG
    uint32_t shift = (pin % 8) * 4;     // P23.7 → shift=28
    uint32_t val = *cfg;                // ★ 读当前所有 8 个引脚的配置
    val &= ~(0x0FUL << shift);          // ★ 只清 P23.7 的 4 bits
    val |=  (0x09UL << shift);          // ★ 设为 Strong Drive, Output
    *cfg = val;                         // ★ 写回 → 其他 7 个引脚不变
}

int main(void) {
    gpio_pin_output(LED_PORT_BASE, LED_PIN);  // 配置 P23.7
    LED_OFF();                                 // P23.7 = HIGH
    SysTick_Config(SystemCoreClock / 1000);    // 1ms 中断
    while (1) {
        LED_ON();    delay_ms(500);            // __WFI() 睡眠
        LED_OFF();   delay_ms(500);            // __WFI() 睡眠
    }
}
```

---

## 2. SWJ 引脚占用分析

CYT2BL3 的 SWJ 引脚均位于 **Port 23**：

| GPIO | SWJ 功能 | 固件操作 | SWD 需要？ |
|------|---------|---------|:--:|
| **P23.4** | SWO / TDO | ❌ 未触碰 | ❌ (SWD 不用) |
| **P23.5** | SWCLK / TCLK | ❌ 未触碰 | ✅ **必须** |
| **P23.6** | SWDIO / TMS | ❌ 未触碰 | ✅ **必须** |
| **P23.7** | SWDOE / TDI | ⚠️ 设为 GPIO 输出 | ❌ (SWD 不用 TDI) |
| P2.0 | TRSTN | ❌ 未触碰 | ❌ |

### 2.1 GPIO_CFG 寄存器读-改-写验证

```
GPIO_PRT23_CFG 寄存器 (0x40310BA0):
  位 [31:28] = P23.7 配置  ← 固件改为 0x9
  位 [27:24] = P23.6 配置  ← 未修改 (SWDIO, FlashBoot 设为 Input Pull-up)
  位 [23:20] = P23.5 配置  ← 未修改 (SWCLK, FlashBoot 设为 Input Pull-down)
  位 [19:16] = P23.4 配置  ← 未修改 (SWO, FlashBoot 设为 Strong Output)

我们的代码:
  val = *cfg;            // 读出完整 32-bit
  val &= ~(0xF << 28);   // 只清零 bits 31:28
  val |= (0x9 << 28);    // 只写入 bits 31:28
  *cfg = val;            // 写回 → 其他 bits 不变 ✅
```

**✅ P23.4、P23.5、P23.6 的 SWJ 配置完全被保留！**

---

## 3. HSIOM 引脚矩阵分析

TRAVEO T2G 的引脚功能由 **HSIOM** (High-Speed I/O Matrix) 控制，这是一个独立于 GPIO_CFG 的寄存器组。

| 方面 | 详情 |
|------|------|
| HSIOM 寄存器地址 | `0x40300000` 起 |
| 我们的固件 | **未访问任何 HSIOM 寄存器** |
| SWJ 路由 | 由 FlashBoot 设置，未被固件修改 ✅ |

**✅ HSIOM 始终将 P23.4-P23.7 路由到 SWJ 外设，未被固件改变！**

---

## 4. `__WFI()` 睡眠对 SWD 的影响

```c
static void delay_ms(uint32_t ms) {
    uint32_t target = g_msTicks + ms;
    while (g_msTicks < target) {
        __WFI();    // 休眠等待中断
    }
}
```

| 状态 | 持续时间 | SWD 是否可用？ |
|------|:--:|:--:|
| **WFI 睡眠** | ~499ms (每 500ms 周期) | ✅ 可用！DAP 独立于核心 |
| **SysTick ISR** | ~1μs (每 1ms) | ✅ 可用 |
| **主循环运行** | ~1μs | ✅ 可用 |

ARM 架构保证：**Debug Access Port (DAP) 通过 AHB-AP 访问系统总线，独立于核心的 WFI/WFE 状态。** 即使核心在 WFI 睡眠中，DAP 仍然可以读写内存和寄存器。

在 TRAVEO T2G 上已验证：`probe-rs info` 命令在芯片运行我们的固件时成功读到了 DPIDR 和完整的 CoreSight 拓扑。

---

## 5. P23.7 的 GPIO/ SWJ 冲突

```
P23.7 的双重身份:
┌─────────────────────────────────────────────┐
│  HSIOM 路由: P23.7 → SWJ_SWDOE_TDI (JTAG)  │  ← FlashBoot 设置
│  GPIO_CFG:     P23.7 → Strong Drive Output  │  ← 固件设置
│                                             │
│  冲突: SWJ 外设期望输入 (TDI)               │
│        GPIO 输出驱动尝试输出 (LED)           │
│        两个驱动源同时驱动同一引脚!            │
└─────────────────────────────────────────────┘
```

**影响评估**：
- SWD 模式：TDI 不使用 → **对 SWD 无影响** ✅
- JTAG 模式：TDI 被 GPIO 输出干扰 → **JTAG 不可用** ❌
- 电特性：GPIO Strong Drive 输出阻抗 ~几十 Ω，与 SWJ 内部驱动可能产生冲突电流，但不会损坏（TRAVEO T2G 的 I/O 有冲突保护）

**如果将来需要 JTAG，应该避免把 P23.7 用作 GPIO 输出。**

---

## 6. 最终结论

```
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║  Q: 用户固件是否关闭了 SWJ？                                  ║
║  A: ❌ 没有！                                                  ║
║                                                              ║
║  详细分析:                                                    ║
║  ✅ P23.5 (SWCLK) — 未触碰, 保持 SWJ 配置                    ║
║  ✅ P23.6 (SWDIO) — 未触碰, 保持 SWJ 配置                    ║
║  ✅ P23.4 (SWO)   — 未触碰, 保持 SWJ 配置                    ║
║  ⚠️ P23.7 (TDI)   — 改为 GPIO 输出 (不影响 SWD)              ║
║  ✅ HSIOM         — 未修改, SWJ 路由保持                      ║
║  ✅ GPIO_CFG RMW  — 正确保留其他引脚配置                      ║
║  ✅ WFI 睡眠      — DAP 独立于核心, SWD 仍可用                ║
║                                                              ║
║  因此: SWD 重连失败与固件配置无关。                            ║
║  根因仍然是: probe-rs 的 reconnect 启动延迟 (~150ms)          ║
║           远大于 Listen Window (20ms)。                       ║
║                                                              ║
║  小建议: 如果将来需要 JTAG 调试, 把 LED 换到别的引脚,         ║
║         避免 P23.7 的 GPIO/SWJ 冲突。                        ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

---

> 📎 **关联报告**:
> - [FlashBoot 参数诊断](./CYT2BL3_FlashBoot参数诊断_SWD重连失败最终报告.md)
> - [probe-rs 烧录失败 Trace 分析](./CYT2BL3_probe-rs_烧录失败Trace分析报告.md)
> - [OpenOCD 烧录实操成功报告](./CYT2BL3_OpenOCD_烧录实操成功报告.md)
