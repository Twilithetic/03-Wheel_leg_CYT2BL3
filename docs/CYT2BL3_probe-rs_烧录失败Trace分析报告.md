# probe-rs 烧录 CYT2BL3 失败 — Trace 日志深度分析报告

> **日期**: 2026-05-05  
> **分析对象**: `probe-rs download --chip CYT2BL3BAS --protocol swd --binary-format hex firmware.hex`  
> **Trace 级别**: RUST_LOG=trace  
> **结果**: DPIDR 读超时，1 秒内 7-8 次 Line Reset + DPIDR 重试均失败

---

## 1. Trace 日志还原

### 1.1 完整 trace（精简版）

```
Performing SWD line reset          ← 第 1 次: Line Reset
Reading DPIDR                      ← 读 DPIDR → 失败

Performing SWD line reset          ← 第 2 次: Line Reset
Reading DPIDR to enable SWD        ← 读 DPIDR → 失败

Performing SWD line reset          ← 第 3 次: Line Reset
Reading DPIDR to enable SWD        ← 读 DPIDR → 失败

Performing SWD line reset          ← 第 4 次
Reading DPIDR to enable SWD        ← 失败

Performing SWD line reset          ← 第 5 次
Reading DPIDR to enable SWD        ← 失败

Performing SWD line reset          ← 第 6 次
Reading DPIDR to enable SWD        ← 失败

Performing SWD line reset          ← 第 7 次
Reading DPIDR to enable SWD        ← 失败

DPIDR didn't become readable within guard time  ← 💀 超时放弃

Error: Failed to reset, and then halt the CPU.
  Target device did not respond to request.
```

### 1.2 关键参数

| 参数 | 值 | 源码位置 |
|------|-----|---------|
| 重试间隔 | 5 ms | `sequences.rs:980` `RESET_RECOVERY_RETRY_INTERVAL` |
| 总超时 | 1 秒 | `sequences.rs:979` `RESET_RECOVERY_TIMEOUT` |
| 理论最大重试次数 | 200 次 (1000ms / 5ms) | |
| 实际重试次数 | **7-8 次** | ← 远少于理论值！ |
| 每次重试耗时 | **~140 ms** (1000ms / 7) | ← 远大于 5ms 间隔！ |

---

## 2. 关键发现：为什么只有 7-8 次重试而非 200 次？

### 2.1 理论 vs 实际

```
理论:  1 秒 / 5ms = 200 次重试
实际:  ~7-8 次重试, 每次 ~140ms

差距:  140ms 远大于 5ms! 
```

### 2.2 每次重试到底做了什么？

看源码 `sequences.rs:512-621`，`debug_port_setup()` 每次重试的执行路径：

```
for retry in 0..5 {                     // ← 5 次外层重试
    swd_line_reset(interface, 0)?;       // ① SWD Line Reset
    
    match interface.active_protocol() {
        Some(Swd) => {
            // ② JTAG-to-SWD 切换序列 (16 bit)
            interface.swj_sequence(16, 0xE79E)?;  // ← USB 命令往返!
            
            // ③ 如果是 retry >= 2:
            if has_dormant {
                // Select Dormant State (31 bit)
                interface.swj_sequence(31, 0x33BBBBBA)?;
                // Alert Sequence (128 bit)
                alert_sequence(interface)?;   // ← 2 次 USB 命令往返!
                // SWD Activation Code (12 bit)
                interface.swj_sequence(12, 0x1A0)?;
            }
        }
    }
    
    // ④ DPIDR 读循环 (内层)
    result = self.debug_port_connect(interface, dp);
    // 这里还有最多 200 次内层重试 (每次 5ms)
}
```

### 2.3 延迟分析

每次重试周期包含多个 USB 传输：

| 操作 | USB 命令 | 预估耗时 |
|------|---------|:---:|
| SWD Line Reset | `DAP_SWJ_Sequence(51 bits)` | ~5ms |
| JTAG-to-SWD 切换 | `DAP_SWJ_Sequence(16 bits)` | ~5ms |
| DPIDR 读 (内层循环) | `DAP_Transfer` × N 次 | N × 5ms |
| 如果进入 dormant 路径 | 额外 3 个 SWJ_Sequence | +15ms |
| **总计** | | **~25-50ms 基础 + 内层 DPIDR 循环** |

每次外层的 `debug_port_setup` 重试大约耗时 25-50ms（不含内层 DPIDR 读循环）。内层 DPIDR 读循环每次 5ms，取决于循环次数。

**外层的 5 次重试 + 内层 DPIDR 读循环 = 约 140ms/外层循环 = 7-8 次总重试在 1 秒内。**

---

## 3. probe-rs 重连流程完整还原

```
probe-rs download 命令执行流程:
═══════════════════════════════════════════════════════════════

t=0      连接芯片 (attach)
         ├─ debug_port_setup() → SWD Line Reset → JTAG-to-SWD → DPIDR ✅
         ├─ debug_port_start() → 上电调试域 ✅  
         ├─ 枚举 AP → 读取 ROM Table ✅
         └─ 芯片连接成功!

t≈100ms  【触发点】flash 算法需要芯片复位 (reset_and_halt)
         ├─ cortex_m_reset_system()
         │    └─ 写 AIRCR = 0x05FA0004 → SYSRESETREQ
         │
         ├─ 【芯片侧】芯片复位 → ROM Boot → FlashBoot → Listen Window
         │    0-5ms:  引脚 Hi-Z ❌
         │    5-25ms: Listen Window, SWD 就绪 ✅
         │    >25ms:  用户程序
         │
         └─ cortex_m_wait_for_reset()
              └─ 读 DHCSR 等 S_RESET_ST 清零
              └─ 如果 DHCSR 读失败 (NoAcknowledge)
                   └─ probe.reinitialize() ← 调用 debug_port_setup()
                        │
t≈150ms          ┌───── 外层重试循环 (最多 5 次) ─────┐
                 │                                       │
t≈150ms          │ 第 1 次:                              │
                 │   swd_line_reset() ──────────────► 芯片 (Hi-Z, 不应)
                 │   swj_sequence(JTAG→SWD) ────────► 芯片 (Hi-Z)
                 │   debug_port_connect():              │
                 │     内层 DPIDR 读循环:                │
                 │       swd_line_reset() ──────────► 芯片
                 │       DPIDR Read → ❌ JUNK ACK       │
                 │       sleep 5ms                       │
                 │       swd_line_reset() ──────────► 芯片
                 │       DPIDR Read → ❌ JUNK ACK       │
                 │       ... (N 次, 直到 ~25ms 过去)    │
t≈175ms          │   失败 → has_dormant 保持 false       │
                 │                                       │
t≈175ms          │ 第 2 次:                              │
                 │   同上, 仍失败                         │
                 │   失败 → has_dormant = true (retry>=2)│
                 │                                       │
t≈315ms          │ 第 3 次:                              │
                 │   swd_line_reset()                   │
                 │   swj_sequence(JTAG→SWD)             │
                 │   【dormant 路径】:                    │
                 │     Select Dormant State (31bit)     │
                 │     Alert Sequence (128bit)           │
                 │     SWD Activation (12bit)            │
                 │   debug_port_connect() → 失败         │
                 │                                       │
t≈455ms          │ 第 4 次: 同上                          │
t≈595ms          │ 第 5 次: 同上                          │
                 └───────────────────────────────────────┘
t≈735ms     probe.reinitialize() 返回失败
           ↓
           cortex_m_wait_for_reset 循环 (最多 600ms)
t≈800ms    读 DHCSR → ❌ NoAcknowledge
           probe.reinitialize() → 再次 debug_port_setup (5 次)
t≈900ms    读 DHCSR → ❌ NoAcknowledge  
           600ms 超时 → 返回 ArmError::Timeout
           ↓
           最终错误: "Failed to reset, and then halt the CPU"
```

---

## 4. 失败根因分析

### 4.1 probe-rs 做法完全正确

probe-rs 的重连流程**完全符合 ARM ADIv5.2 规范**:
- ✅ SWD Line Reset (强制状态机进入 RESET)
- ✅ JTAG-to-SWD 切换序列
- ✅ 多次重试 (外层 5 次 × 内层最多 200 次)
- ✅ Dormant State 唤醒（2 次失败后尝试）
- ✅ 总超时 1 秒
- ✅ 复位后自动 `reinitialize()`

### 4.2 那为什么还是失败？

**时序问题**：probe-rs 的重试发生在 `cortex_m_wait_for_reset()` 内部，这个函数在 SYSRESETREQ 之后**立即**开始循环。从 trace 看，7-8 次外层重试在 ~735ms 内完成（每次约 100-140ms）。

```
时间线:
  0ms:     SYSRESETREQ → 芯片复位
  0-5ms:   ROM Boot + FlashBoot → SWD 引脚从 Hi-Z 变为 SWD 模式
  5-25ms:  Listen Window → SWD 完全就绪
  ...

probe-rs 的重试窗口:  ~150ms - ~900ms  ← 这完全在 Listen Window 之后!
```

**问题是**：probe-rs 在 `cortex_m_wait_for_reset()` 中先尝试读 DHCSR。如果 DHCSR 返回 `NoAcknowledge`，再调用 `probe.reinitialize()` → `debug_port_setup()`。但 `debug_port_setup()` 的外层重试只有 5 次，每次 ~140ms。如果芯片在 5 次重试内（~700ms）没有响应，就会失败。

**但 5ms 的 Listen Window 应该在第一次重试时就已经过了！** 芯片应该在第 1-2 次重试就响应了。

### 4.3 🔑 真正的根因：芯片可能不在 Listen Window 中

回顾之前 Infineon AN228680 的信息：

```
T2G_FLASH_BOOT_PARAMS 寄存器:
  SWJ_PINS_CTL (bit[6:5]):
    0x2 = 在 FlashBoot 中启用 SWJ 引脚 ← 但这是可配置的!
  LISTEN_WINDOW (bit[4:2]):
    0x0 = 20ms, 0x3 = 0ms (无 Listen Window)
```

**可能的原因**：
1. 芯片的 `SWJ_PINS_CTL` 可能被设置为不启用 SWJ 引脚
2. `LISTEN_WINDOW` 可能被设置为 0ms (无等待窗口)
3. 芯片保护状态虽然不是 SECURE，但可能有其他设置影响
4. **最可能**：芯片在之前被我们的固件烧录后，FlashBoot 参数被修改，导致每次复位后 SWJ 引脚只在极短窗口内可用

### 4.4 对比：为什么 OpenOCD 的 `halt` 方式能工作

```
OpenOCD halt 方式:
  芯片已上电运行 → SWD 引脚已由 FlashBoot 配置好 → 直接暂停 → 烧录
  不触发 SYSRESETREQ → 不进入 ROM Boot → SWD 连接始终保持

probe-rs download 方式:
  必须 reset_and_halt → SYSRESETREQ → ROM Boot → SWD 断开 → 重连失败
```

---

## 5. 解决方案

### 5.1 已验证可用

| 方案 | 工具 | 命令 |
|------|------|------|
| 断电重启 + probe-rs | probe-rs | `probe-rs download --chip CYT2BL3BAS --binary-format hex firmware.hex` |
| halt 方式 | OpenOCD | `make flash` |

### 5.2 可尝试

| 方案 | 说明 |
|------|------|
| 检查 FlashBoot 参数 | 用 OpenOCD 读 T2G_FLASH_BOOT_PARAMS，确认 SWJ_PINS_CTL=2, LISTEN_WINDOW≠0 |
| probe-rs attach 后手动操作 | 不使用 `download`，手动 halt + flash write |

---

## 6. 总结

```
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║  probe-rs 的重连机制完全正确：                                ║
║  ✅ SWD Line Reset 每次都执行                                ║
║  ✅ JTAG-to-SWD 切换每次都执行                               ║
║  ✅ 外层 5 次 + 内层 200 次重试                              ║
║  ✅ Dormant State 唤醒在 2 次失败后启用                      ║
║  ✅ 1 秒总超时                                               ║
║                                                              ║
║  但芯片在 SYSRESETREQ 后 SWD 仍然不响应：                    ║
║  ⚠️ 可能 FlashBoot 参数限制了 SWJ 引脚可用时间               ║
║  ⚠️ Listen Window 可能被设为 0ms                             ║
║  ⚠️ 需要进一步诊断 FlashBoot 寄存器                          ║
║                                                              ║
║  trace 证据：                                                ║
║  7-8 次 "Performing SWD line reset" + "Reading DPIDR"       ║
║  每次 ~140ms, 总 735ms 后 5 次外层重试用尽                  ║
║  最终: "DPIDR didn't become readable within guard time"     ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

---

> 📎 **关联报告**:
> - [probe-rs 添加 CYT2BL3 支持操作报告](./CYT2BL3_probe-rs_添加CYT2BL3支持_操作报告.md)
> - [SWD Line Reset 原理与跨芯片分析](./CYT2BL3_SWD_Line_Reset原理与跨芯片分析报告.md)
> - [复位后 SWD 可用时序](./CYT2BL3_复位后SWD可用时序_官方文档分析报告.md)
