# probe-rs reinitialize 重连失败 — 源码级根因分析

> **日期**: 2026-05-05  
> **核心问题**: 断电→芯片重启→DAP 恢复→但 probe-rs 重试了 200+ 次为什么还是读不到 DPIDR？

---

## 1. `reinitialize()` 做了什么

源码 `communication_interface.rs:243-259`：

```rust
fn reinitialize(&mut self) -> Result<(), ArmError> {
    let current_dp = self.current_dp;

    // Step ①: 断开连接 — 调用 debug_port_stop() 给 DAP 断电!
    self.disconnect();    // ← 🔥 先断电!

    // Step ②: 重新连接
    if let Some(dp) = current_dp {
        self.select_dp(dp)?;  // → debug_port_setup() → Line Reset → DPIDR Read
    }
    Ok(())
}
```

### Step ① `disconnect()` 干什么了

```rust
fn disconnect(&mut self) {
    // 调用 debug_port_stop → 写 CTRL/STAT = 0 → DAP 调试域断电!
    self.sequence.debug_port_stop(probe, current_dp).ok();
    self.dps.clear();
    probe.raw_flush().ok();
}
```

### Step ② `select_dp()` 干什么了

```rust
fn select_dp(&mut self, dp: DpAddress) -> ... {
    if self.current_dp.is_none() {
        // debug_port_setup: Line Reset → JTAG-to-SWD → debug_port_connect
        sequence.debug_port_setup(&mut *self.probe_mut(), dp)?; // ← 这里失败!
    }
    // 如果 debug_port_setup 成功, 接下来:
    sequence.debug_port_start(self, dp)?;  // ← 永远走不到这里!
}
```

---

## 2. 死锁分析

```
正常流程 (初始连接):
  芯片已上电 → DAP 已上电
  → debug_port_setup() → Line Reset → DPIDR Read ✅
  → debug_port_start() → 写 CTRL/STAT 上电 (已是上电状态, no-op)
  
  成功! ✅


reinitialize 流程 (复位后重连):
  SYSRESETREQ → DAP 复位, 调试域断电
  → disconnect() → debug_port_stop() → 尝试写 CTRL/STAT=0 (断电)
     ↑ ↑ ↑
     │ │ └─ DAP 已经断电了, 这个写操作可能失败!
     │ └─── 但错误被 .ok() 吞掉了!
     └───── CMSIS-DAP 适配器可能留下 pending error!
  
  → select_dp() → debug_port_setup()
     ├─ Line Reset → ✅ (无状态操作, 总是成功)
     ├─ JTAG-to-SWD → ⚠️ (可能受 pending error 影响)
     └─ debug_port_connect()
          └─ 内层循环:
               Line Reset → DPIDR Read → ❌ FAIL
               Line Reset → DPIDR Read → ❌ FAIL
               ... 200 次 ...
               Line Reset → DPIDR Read → ❌ FAIL
               → "DPIDR didn't become readable within guard time"
  
  失败! ❌
```

---

## 3. 为什么 DPIDR 读不到？

### 3.1 不是因为芯片 SWD 不可用

| 证据 | 结论 |
|------|------|
| probe-rs info 成功 | 芯片运行用户程序时 SWD 可用 ✅ |
| TOC2_FLAGS 确认 | SWJ 已启用, Listen Window 20ms ✅ |
| 源码审计 | 固件没有关闭 SWJ ✅ |

**芯片端 SWD 在重试期间是正常的！**

### 3.2 真正的原因：CMSIS-DAP 适配器状态污染

```
时间线:
────────────────────────────────────────────────────────────►
[芯片]  SYSRESETREQ → ROM→FlashBoot→用户程序 (SWD就绪)
[适配器] 保持连接中, 不知道芯片复位了
[probe-rs] 
  → cortex_m_wait_for_reset()
    → 读 DHCSR → ❌ NoAcknowledge (芯片在ROM Boot)
    → probe.reinitialize()
      → disconnect()
        → debug_port_stop() → 往已复位的芯片写 CTRL/STAT=0
        → CMSIS-DAP 适配器: 发送 SWD 写请求
        → 芯片 SW-DP: 状态机在 UNKNOWN → 不响应
        → 适配器: 收到错误 → pending error flag! 🔴
      
      → select_dp() → debug_port_setup()
        → Line Reset → 适配器发送 SWJ_Sequence
        → 这应该清除 SWD 状态... 但适配器的 pending error 可能还在!
        → DPIDR Read → 适配器: 还有 pending error → 不发送/返回错误
        → ❌ 重试循环全部失败!
```

**CMSIS-DAP 适配器有一个 `pending_error` 状态**。当之前的操作失败时（比如往已复位的芯片写断电命令），适配器记住了这个错误。后续操作检测到 pending error，可能跳过实际发送。

这正是我们在 `SW_DP.c` 和 `DAP.c` 中没有看到的——这是 **CMSIS-DAP 适配器固件层面的状态管理**，不是 CMSIS-DAP 协议的问题。

---

## 4. 验证假设

### 4.1 如果绕过 `disconnect()` 会怎样？

如果 `reinitialize()` 不调用 `disconnect()`，而是直接调用 `debug_port_setup()`：

```rust
fn reinitialize_fixed(&mut self) -> Result<(), ArmError> {
    let current_dp = self.current_dp;
    
    // 不清除 DP 状态, 不尝试操作已复位的芯片
    self.current_dp = None;
    self.dps.clear();
    
    // 直接重连
    if let Some(dp) = current_dp {
        self.select_dp(dp)?;  // → debug_port_setup → ✅
    }
    Ok(())
}
```

这应该能工作——因为我们知道芯片端的 SWD 在用户程序运行期间是可用的。`debug_port_setup()` 的 Line Reset + DPIDR 读应该能成功。

### 4.2 为什么初始连接不受影响？

初始连接时，没有"前序失败操作"污染适配器状态。所有操作从干净状态开始。

---

## 5. 总结

```
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║  Q: 断电后芯片恢复, 为什么重试 200+ 次还是连不上?             ║
║                                                              ║
║  A: 不是重试次数不够, 是"第一次操作就搞坏了适配器"!           ║
║                                                              ║
║  reinitialize() 流程:                                         ║
║    ① disconnect() → debug_port_stop() → 往已复位芯片写断电    ║
║       → 适配器记录 pending error 🔴                            ║
║    ② select_dp() → debug_port_setup() → Line Reset + DPIDR   ║
║       → 适配器因 pending error 拒绝发送/返回错误               ║
║       → 无论重试多少次, 只要 pending error 不清除就会一直失败  ║
║                                                              ║
║  类比: 就像你先拔了网线 (disconnect),                         ║
║        然后一直重试 ping 百度 (DPIDR Read),                   ║
║        但网卡驱动已经崩了 (pending error),                    ║
║        ping 多少次都没用——需要先重启网卡。                     ║
║                                                              ║
║  OpenOCD halt 方式为什么能行:                                  ║
║    不复位 → 没有"往已复位芯片操作" → 没有 pending error       ║
║    → 适配器状态干净 → 一切正常                                 ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

---

> 📎 **源码证据**:
> - `communication_interface.rs:243-259` — `reinitialize()` 先 `disconnect()` 再 `select_dp()`
> - `communication_interface.rs:209-233` — `disconnect()` 调用 `debug_port_stop()` 写 CTRL/STAT=0
> - `communication_interface.rs:340-364` — `select_dp()` 调用 `debug_port_setup()`
> - `sequences.rs:957-1023` — `debug_port_connect()` 内层 DPIDR 读循环
> - `sequences.rs:512-621` — `debug_port_setup()` 外层 5 次重试

> 📎 **关联报告**:
> - [SWD 可用条件分析](./CYT2BL3_SWD可用条件完整分析报告.md)
> - [probe-rs 烧录失败 Trace 分析](./CYT2BL3_probe-rs_烧录失败Trace分析报告.md)
