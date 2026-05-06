# probe-rs 自定义复位序列方案 — 可行性分析报告

> **日期**: 2026-05-06  
> **目标**: 为 CYT2BL3 实现自定义 `reset_system`：发送复位 → 每 100ms 读 DPIDR → 重试 100 次  
> **问题背景**: 标准 `reset_and_halt` 的 `cortex_m_wait_for_reset` (600ms 超时) 无法在 CYT2BL3 Boot ROM 窗口内成功重连 DP

---

## 1. probe-rs 的 Vendor Sequence 机制

### 1.1 架构概览

probe-rs 通过 **Vendor Support** 模块支持芯片特定的调试序列：

```
tools/probe-rs-src/probe-rs/src/vendor/
├── st/           ← STM32 系列
├── nxp/          ← NXP 系列
├── ti/           ← TI 系列
├── silabs/       ← Silicon Labs (EFM32)
├── raspberrypi/  ← RP2040/RP235x
├── infineon/     ← (不存在！需要新建)
└── ...
```

每个 Vendor 实现 `Vendor` trait，在 `try_create_debug_sequence()` 中返回一个 `DebugSequence`。

### 1.2 ArmDebugSequence trait — 可重写的方法

> 源码: `sequences.rs:444-1176`

| 方法 | 默认行为 | 你的方案需要修改? |
|------|---------|:--:|
| `debug_port_setup()` | SWD Line Reset + JTAG→SWD 切换 + DPIDR 读 | ❌ |
| `debug_port_connect()` | Line Reset + DPIDR 读 + CTRL/STAT 验证 | ❌ |
| `debug_port_start()` | DP 上电 + 错误清除 | ❌ |
| `debug_core_start()` | CSW 配置 + halt | ❌ |
| **`reset_system()`** | **SYSRESETREQ + 600ms 轮询** | **✅ 需重写!** |
| `reset_hardware_assert()` | 拉低 nRESET (如果可用) | ❌ |
| `recover_support_start()` | 从低功耗恢复 | 可选 |

---

## 2. 现有 Vendor 的实现范例

### 2.1 EFM32xG2 (Silicon Labs) — 最接近的参考

```rust
// tools/probe-rs-src/probe-rs/src/vendor/silabs/sequences/efm32xg2.rs
impl ArmDebugSequence for EFM32xG2 {
    fn reset_system(&self, interface: &mut dyn ArmMemoryInterface, ...) -> Result<(), ArmError> {
        let mut aircr = Aircr(0);
        aircr.vectkey();
        aircr.set_sysresetreq(true);
        
        // 写 AIRCR 触发系统复位
        interface.write_word_32(Aircr::get_mmio_address(), aircr.into())?;
        // 调用标准 wait_for_reset
        cortex_m_wait_for_reset(interface)?;
        // ...
    }
}
```

它也调用了标准 `cortex_m_wait_for_reset`，但可以做额外处理。

### 2.2 OL23D0 (NXP) — 自定义复位逻辑

```rust
// tools/probe-rs-src/probe-rs/src/vendor/nxp/sequences/nxp_armv8m/ol23d0.rs
impl ArmDebugSequence for OL23D0 {
    fn reset_system(&self, interface: &mut dyn ArmMemoryInterface, ...) -> Result<(), ArmError> {
        let mut core = OL23D0Core { memory: interface };
        if core.halt(Duration::from_millis(100)).is_err() {
            // Probable lockup, reset will fix it.
        }
        core.reset(Duration::from_millis(100))?;
        Ok(())
    }
}
```

**使用了完全自定义的 reset 逻辑**，不调用标准函数。

---

## 3. 你的方案的可行性分析

### 3.1 方案描述

```
reset_system() 重写:
  1. 写 AIRCR.SYSRESETREQ 触发芯片复位
  2. 等待 100ms
  3. 通过 SWD 读 DPIDR
  4. 如果失败(NACK) → 回到步骤 2
  5. 重试最多 100 次 (总计 10 秒)
  6. DPIDR 成功 → 恢复 DAP 状态(上电) → 返回 OK
```

### 3.2 可行性: ✅ 完全可行

**理由**:

1. **`ArmDebugSequence` trait 的 `reset_system()` 可以被完全重写**
   - 源码: `sequences.rs:842-857`
   - 无需调用默认实现，可以实现任意逻辑

2. **`ArmMemoryInterface` 提供了获取 probe 的方法**
   - `interface.get_arm_debug_interface()` → 返回 `&mut dyn ArmDebugInterface`
   - `ArmDebugInterface` 上有 `reinitialize()` 方法（源码: `communication_interface.rs:243`）

3. **可以直接操作 probe 底层 SWD**
   - `probe.swj_sequence()` — 发送 Line Reset
   - `probe.raw_read_register()` — 读 DPIDR
   - `probe.raw_write_register()` — 写 ABORT/SELECT/CTRL

4. **已有 vendor 实现了完全自定义的 reset_system**
   - NXP OL23D0: 完全自定义
   - STM32H7: `debug_port_setup` + 额外初始化
   - 这些都是可以照搬的模式

### 3.3 关键接口清单

```rust
trait ArmMemoryInterface {
    // 获取底层 probe 接口 ★ 最关键的方法
    fn get_arm_debug_interface(&mut self) 
        -> Result<&mut dyn ArmDebugInterface, ArmError>;
    
    fn read_word_32(&mut self, addr: u64) -> Result<u32, ArmError>;
    fn write_word_32(&mut self, addr: u64, data: u32) -> Result<(), ArmError>;
}

trait ArmDebugInterface {
    // 重连 DP ★ 
    fn reinitialize(&mut self) -> Result<(), ArmError>;
    
    fn memory_interface(...) -> ...;
}
```

### 3.4 伪代码实现

```rust
use std::time::{Duration, Instant};

impl ArmDebugSequence for Cyt2blSequence {
    fn reset_system(
        &self,
        interface: &mut dyn ArmMemoryInterface,
        _core_type: CoreType,
        _debug_base: Option<u64>,
    ) -> Result<(), ArmError> {
        // 1. 触发系统复位 (写 AIRCR)
        let mut aircr = Aircr(0);
        aircr.vectkey();
        aircr.set_sysresetreq(true);
        interface.write_word_32(Aircr::get_mmio_address(), aircr.into())?;
        
        // 2. 轮询 DPIDR (每 100ms, 最多 100 次 = 10 秒)
        const POLL_INTERVAL: Duration = Duration::from_millis(100);
        const MAX_RETRIES: usize = 100;
        
        for attempt in 0..MAX_RETRIES {
            thread::sleep(POLL_INTERVAL);
            
            // 获取 probe 接口
            if let Ok(probe) = interface.get_arm_debug_interface() {
                // 尝试重新初始化 DP
                match probe.reinitialize() {
                    Ok(()) => {
                        tracing::info!("DP reconnected after {}ms", 
                            (attempt + 1) * 100);
                        return Ok(());
                    }
                    Err(_) => {
                        tracing::debug!("DP not ready, retry {}/{}", 
                            attempt + 1, MAX_RETRIES);
                    }
                }
            }
        }
        
        Err(ArmError::Timeout)
    }
}
```

---

## 4. 风险与限制

| 风险 | 严重度 | 缓解方案 |
|------|:--:|------|
| `get_arm_debug_interface()` 在 reset 后可能返回旧状态 | 中 | 每次调用前先 drop 旧接口 |
| `reinitialize()` 内部调用 `debug_port_connect` 也会重试 5 秒 | 低 | 这正是我们需要的！外层每 100ms 触发一次内层 5 秒重试 |
| 10 秒超时太长 | 低 | 实测芯片 Boot ROM ~几十 ms，大概率前几次就成功 |
| 双核复位可能需分别处理 | 中 | CM0+ 先复位，Flask 算法在 CM0+ 上运行 |

### 4.1 关于 `reinitialize()` 的内部行为

```rust
// communication_interface.rs:243
fn reinitialize(&mut self) -> Result<(), ArmError> {
    self.disconnect();                       // 断开现有 DP 连接
    if let Some(dp) = current_dp {
        self.select_dp(dp)?;                 // 重新连接
        //    → debug_port_setup()          // Line Reset + JTAG→SWD
        //       → debug_port_connect()     // DPIDR 读 (1秒超时, 5ms 间隔)
        //          → 成功 → break
        //          → 失败 → 重试 × 5 次 (含 Dormant 路径)
    }
    Ok(())
}
```

**注意**: `reinitialize()` 内部已经有**自己的重试循环**（5轮 × 200次 = 5秒）。你的 100ms 外层轮询 + 内层 5 秒重试 = **嵌套重试**，但这没关系——一旦 DP 恢复，第一次内层重试就会成功并立即返回。

### 4.2 优化建议

可以改为先做轻量级的 DPIDR 尝探（1 次 Line Reset + 1 次 DPIDR 读），确认 DP 恢复了再做完整的 `reinitialize()`：

```rust
fn try_read_dpidr(probe: &mut dyn ArmDebugInterface) -> bool {
    // 做一次 SWD Line Reset
    probe.swj_sequence(54, 0x0007_FFFF_FFFF_FFFF).ok()?;
    // 读一发 DPIDR
    probe.raw_read_register(DPIDR::ADDRESS.into()).is_ok()
}
```

---

## 5. 实施步骤

### 5.1 新增 Infineon Vendor 模块

```
tools/probe-rs-src/probe-rs/src/vendor/infineon/
├── mod.rs              ← 注册 Vendor
└── sequences/
    ├── mod.rs
    └── cyt2bl.rs       ← CYT2BL 专用序列
```

### 5.2 注册 Vendor

在 `vendor/mod.rs` 中（或其他 vendor 注册处）添加 Infineon 的注册。

### 5.3 实现 cyt2bl.rs

```rust
// 基本结构
#[derive(Debug)]
pub struct Cyt2blSequence;

impl Cyt2blSequence {
    pub fn create() -> Arc<dyn ArmDebugSequence> {
        Arc::new(Self)
    }
}

impl ArmDebugSequence for Cyt2blSequence {
    fn reset_system(&self, interface: &mut dyn ArmMemoryInterface, 
        core_type: CoreType, debug_base: Option<u64>) -> Result<(), ArmError> 
    {
        // 自定义复位 + 轮询 DPIDR 逻辑
    }
}
```

### 5.4 编译测试

在项目根目录（即 probe-rs 工作区）编译：
```bash
cargo build --release -p probe-rs-tools
```

---

## 6. 更简单的替代方案

如果你不想新增一个 vendor 模块，可以直接修改 `cortex_m_wait_for_reset`：

```rust
// sequences.rs:409
while start.elapsed() < Duration::from_millis(600) {  // 改为 10000
```

把 600ms 改成 10000ms (10秒)，虽然不够优雅但最快。

或者修改 `debug_port_connect` 的超时：

```rust
// sequences.rs:979
const RESET_RECOVERY_TIMEOUT: Duration = Duration::from_millis(10000);  // 1s → 10s
```

---

## 7. 总结

| 问题 | 答案 |
|------|------|
| probe-rs 能发自定义序列吗？ | **✅ 能** — `swj_sequence()` 可发任意 bit 序列 |
| 能重写 reset 流程吗？ | **✅ 能** — `ArmDebugSequence::reset_system()` 可完全重写 |
| 能每 100ms 读 DPIDR 吗？ | **✅ 能** — `raw_read_register()` + `thread::sleep()` |
| 能重试 100 次吗？ | **✅ 能** — 标准 Rust 循环，随便循环多少次 |
| 有现成的 vendor 范例吗？ | **✅ 有** — EFM32xG2, OL23D0, STM32H7 等 |
| 最简实现是什么？ | 改一行：`Duration::from_millis(600)` → `10000` |

*本报告由知心姐姐基于 probe-rs 官方文档和源码分析编写 💖*
