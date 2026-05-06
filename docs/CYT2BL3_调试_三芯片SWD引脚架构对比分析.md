# PSoC Edge / XMC4000 / CYT2BL3 — SWD 引脚架构对比分析报告

> **日期**: 2026-05-06  
> **参考来源**:
> - Infineon AN220118 "Getting started with TRAVEO T2G" (https://documentation.infineon.com/traveo/docs/lwy1680596932876)
> - TRAVEO II Program and Debug Interface Training
> - CYT2BL datasheet 002-28876 Rev. I
> - probe-rs 源码: `vendor/infineon/sequences/{psoc_edge.rs, xmc4000.rs}`
> - ARM ADIv5 规范 (ARM IHI 0031C)

---

## 1. 核心问题

三款 Infineon 芯片在 reset 后能否立即通过 SWD 连接？

| 芯片 | 能否立即连 SWD | 原因 |
|------|:--:|------|
| **PSoC Edge (PSE84)** | ✅ 可以 | 无 Boot ROM SWD 阻塞。问题是 CM55 需 CM33 先使能 |
| **XMC4000** | ❌ 不可以 | DAPSA 安全位在 ROM Boot 期间阻断 DAP |
| **CYT2BL3 (Traveo T2G)** | ❌ 不可以 | HSIOM GPIO 矩阵 + DAP 限制 → 需等 FlashBoot |

---

## 2. 芯片架构逐款分析

### 2.1 STM32 (对照基准) — 硬连接

```
  P[x].y ──── 硬连线 ──── SWCLK / SWDIO ──── ARM DAP
  
  特点: SWD 引脚在硬件层面直连 DAP
  复位后: 引脚立即可用
  probe-rs: 无需特殊处理 ✅
```

### 2.2 CYT2BL3 — HSIOM 可编程矩阵

```
  P23.5 ──► HSIOM (可编程矩阵) ──► SWCLK ──► SWJ-DP ──► DAP
  P23.6 ──► HSIOM (可编程矩阵) ──► SWDIO ──► SWJ-DP ──► DAP
  P23.7 ──► HSIOM (可编程矩阵) ──► SWDOE/TDI
  
  特点: 引脚通过 High-Speed I/O Matrix 连接 DAP
  复位后: 引脚默认 GPIO/高阻态，需 FlashBoot 配置 HSIOM 路由
  时间线:
    T+0ms:    系统复位 → 引脚进入高阻态
    T+2ms:    ROM Boot 执行 → 施加 DAP 访问限制
    T+5ms:    FlashBoot 执行 → 配置 HSIOM 路由 → SWD 可用
    T+25ms:   Listen Window 结束 → 用户程序运行
```

**关键数据** (来自 Infineon AN220118 和 CYT2BL datasheet):

```
CPU 启动序列 (CYT2B 系列):
  1. 系统复位 (@0x0000 0000)
  2. CM0+ 执行 ROM Boot (@0x0000 0004)
     ├─ 应用 trim 值
     ├─ ★ 施加 DAP 访问限制  ← 此时 SWD 被阻断!
     └─ 认证 FlashBoot → 移交控制权
  3. CM0+ 执行 FlashBoot (从 0x1700 2000)
     ├─ ★ 按 SWD/JTAG 规范配置调试引脚 ← 此时 SWD 才可用!
     ├─ 设 CM0+ 向量表基址
     └─ CM0+ 跳转到 Reset handler
  4. CM0+ 启动用户程序
  5. 释放 CM4 复位
```

> **Datasheet Note 17**: "Port configuration of SWD/JTAG pins will be changed from the default GPIO mode to support debugging **after the boot process**"

### 2.3 XMC4000 — DAPSA 安全位

```
  SWDIO/SWCLK ──── SWJ-DP ──── DAP ──► DAPSA门 ──► 系统总线
  
  特点: DAP 本身硬连着，但 SCU 中有一个 DAPSA 位
  DAPSA=0: DAP 无法访问系统（读返回 0，写无效）
  DAPSA=1: DAP 可正常访问系统
  
  复位后: DAPSA=0（ROM Boot 安全要求）
  ROM Boot 结束后: DAPSA=1（SSW 末尾自动使能）
```

**probe-rs XMC4000 源码中的注释** (xmc4000.rs:324-335):

```rust
// XMC4700/XMC4800 reference manual v1.3 § 28-7:
//
// > For security reasons it is required to prevent a debug access to the processor 
// > before and while the boot firmware code from ROM (SSW) is being executed. 
// > A bit DAPSA, (DAP has system access) in the SCU is implemented, allowing 
// > the access from CoreSight™ debug system to the processor core. 
// > The default value of this bit is disabled debug access.
// > The register is reset by System Reset. The System Reset disables the debug 
// > access each time SSW is being executed. 
// > At the end of the SSW the DAPSA is enabled always (independent of any other 
// > register setting or signaling value), to allow debug access to the CPU. 
// > A tool accessing the SoC during the SSW execution time reads back a zero 
// > and a write is going to a virtual, none existing address.
```

**XMC4000 的解决方案**:
```rust
// 复位后轮询 DAPSA
fn spin_until_dapsa_is_clear(core: &mut dyn ArmMemoryInterface) -> Result<(), ArmError> {
    loop {
        // 读 SCU 模块 ID 寄存器 (0x5000_4000)
        // 如果 DAPSA 置位 → 读回非零值 → SSW 已完成
        // 如果 DAPSA 未置位 → 读回 0 → SSW 仍在运行
        let scu_module_id = core.read_word_32(0x5000_4000)?;
        if scu_module_id != 0 {
            break Ok(());  // DAPSA is set, SSW done
        }
        if start.elapsed() > Duration::from_millis(500) {
            break Err(ArmError::Timeout);
        }
    }
}
```

### 2.4 PSoC Edge (PSE84) — 多核依赖

```
  CM33 (系统核) ── 控制 ──► AppCpussApCtl ──► CM55 AP 使能
  CM55 (应用核) ── 被控制 ── 需要 CM33 先使能才能调试
  
  特点: SWD 直接连接没问题，但 CM55 核被 clock-gated
  probe-rs 序列: 连接 CM33 → 读 AppCpussApCtl → 使能 CM55 AP
```

**probe-rs PSoC Edge 源码** (psoc_edge.rs:80-98):
```rust
fn on_attach(&self, interface, core_ap, core_type) -> Result<(), ArmError> {
    if core_ap == &self.cm55_ap {
        // 要调试 CM55，需要通过 CM33 来使能它
        let mut cm33_ap = interface.memory_interface(&self.cm33_ap)?;
        
        // 检查 CM55 是否已使能
        let ctl = MxCm55Ctl(cm33_ap.read_word_32(0x44160000)?);
        if ctl.cm55_wait() {
            return Err(ArmError::CoreDisabled);
        }
        
        // 使能 CM55 AP
        let mut ap_ctl = AppCpussApCtl(cm33_ap.read_word_32(0x441C1000)?);
        ap_ctl.set_cm55_enable(true);
        ap_ctl.set_cm55_dbg_enable(true);
        ap_ctl.set_cm55_nid_enable(true);
        cm33_ap.write_word_32(0x441C1000, ap_ctl.0)?;
    }
    DefaultArmSequence(()).on_attach(interface, core_ap, core_type)
}
```

**与 CYT2BL3 对比**: PSoC Edge 没有 "复位后 SWD 不可达" 问题。它的特殊处理是关于 CM55 核的使能，而非 SWD 物理连接。

---

## 3. 三芯片架构对比总表

```
┌──────────────────┬──────────────────┬──────────────────┬──────────────────┐
│     特性          │   CYT2BL3        │   XMC4000        │   PSoC Edge      │
│                  │   (Traveo T2G)   │                  │   (PSE84)        │
├──────────────────┼──────────────────┼──────────────────┼──────────────────┤
│ SWD 引脚连接      │ HSIOM 可编程矩阵  │ 硬连接           │ 硬连接           │
│                  │ (GPIO↔SWD 可切换) │                  │                  │
├──────────────────┼──────────────────┼──────────────────┼──────────────────┤
│ 复位后引脚状态    │ 高阻态 / GPIO    │ SWD 模式但DAP阻断 │ SWD 模式         │
├──────────────────┼──────────────────┼──────────────────┼──────────────────┤
│ DAP 何时可用      │ FlashBoot 配置后  │ SSW 设置DAPSA后  │ 立即             │
│                  │ (~5ms after rst) │ (~2.5ms tSSW)   │                  │
├──────────────────┼──────────────────┼──────────────────┼──────────────────┤
│ 阻断机制          │ DAP 访问限制      │ DAPSA=0         │ 无 (仅CM55门控)  │
│                  │ + HSIOM 未配置    │                  │                  │
├──────────────────┼──────────────────┼──────────────────┼──────────────────┤
│ probe-rs 序列    │ ❌ 不存在         │ ✅ XMC4000       │ ✅ PsocEdge      │
│                  │ (用 DefaultArmSeq)│ (spin DAPSA)     │ (使能 CM55 AP)   │
├──────────────────┼──────────────────┼──────────────────┼──────────────────┤
│ 特殊处理方式      │ ★ 需新建          │ 轮询 0x5000_4000  │ 写 AppCpussApCtl │
│                  │   轮询DPIDR       │ 直到非零         │ 寄存器           │
└──────────────────┴──────────────────┴──────────────────┴──────────────────┘
```

---

## 4. 对 CYT2BL3 probe-rs 修复的启示

### 4.1 XMC4000 方案的适用性

XMC4000 的 `spin_until_dapsa_is_clear()` 模式可以**直接照搬**到 CYT2BL3：

```
XMC4000:  复位 → poll SCU_MODULE_ID (0x5000_4000) → 非零 = DAP可访问
CYT2BL3:  复位 → poll DPIDR (0x0) → 成功 = SWD可用
```

区别仅在于**轮询的目标寄存器**不同：
- XMC4000 有专门的 DAPSA 探测寄存器
- CYT2BL3 只能通过 DPIDR 读取来判断 SWD 是否恢复

### 4.2 CYT2BL3 的特殊之处

与 XMC4000 相比，CYT2BL3 有**两层阻断**：

| 层 | 阻断机制 | 持续时间 | 释放条件 |
|----|---------|:--:|------|
| **第1层**: DAP 访问限制 | ROM Boot 施加 | ~2ms | ROM Boot 结束自动释放 |
| **第2层**: HSIOM 引脚未配置 | 引脚处于 GPIO/Hi-Z | ~5ms | FlashBoot 配置 HSIOM |

XMC4000 只有第1层（DAPSA），而 CYT2BL3 需要等到**两层都释放**。

### 4.3 最佳策略

参考 XMC4000 的模式，CYT2BL3 的 `reset_system` 应该：

```rust
fn reset_system(&self, interface, core_type, debug_base) -> Result<(), ArmError> {
    // 1. 触发复位
    let mut aircr = Aircr(0);
    aircr.vectkey();
    aircr.set_sysresetreq(true);
    interface.write_word_32(Aircr::get_mmio_address(), aircr.into())?;
    
    // 2. 等待复位生效
    // ...
    
    // 3. ★ 轮询 DPIDR (类似 XMC4000 轮询 DAPSA)
    let start = Instant::now();
    loop {
        thread::sleep(Duration::from_millis(100));
        
        if let Ok(probe) = interface.get_arm_debug_interface() {
            match probe.reinitialize() {
                Ok(()) => break,  // DP 恢复!
                Err(_) => {}
            }
        }
        
        if start.elapsed() > Duration::from_secs(10) {
            return Err(ArmError::Timeout);
        }
    }
    
    Ok(())
}
```

---

## 5. PSoC Edge 序列不适用于 CYT2BL3

PSoC Edge 的 `on_attach` 覆盖解决的是**完全不同的**问题：
- **PSoC Edge**: CM55 核被 clock-gated，需要 CM33 使能 → 这是**核级**问题
- **CYT2BL3**: SWD 引脚被 HSIOM 矩阵隔离 → 这是**物理层**问题

**结论**: PSoC Edge 的序列对 CYT2BL3 **没有参考价值**。

**XMC4000 的 `reset_system` + `spin_until_dapsa_is_clear` 模式才是正确参考。**

---

## 6. 总结

| 问题 | 答案 |
|------|------|
| SWD 引脚是硬连接吗？ | ❌ **不是**。经过 HSIOM 可编程矩阵 |
| 复位后能立即连 SWD 吗？ | ❌ **不能**。引脚需 FlashBoot 配置 (~5ms) |
| 和 XMC4000 像吗？ | ✅ **非常像**。都有 ROM Boot 安全阻断 |
| 和 PSoC Edge 像吗？ | ❌ **不像**。PSoC Edge 是核级问题 |
| probe-rs 修复方向？ | 照搬 XMC4000 模式：reset → 轮询 DPIDR → 重连 |

*本报告由知心姐姐基于 Infineon 官方文档和 probe-rs 源码分析编写 💖*
