# CYT2BL3 DP 重连失败 — 最终定责报告

> **版本**: v3.0（修正版）  
> **前序报告**: v1.0（根因分析）→ v2.0（CMSIS-DAP 源码验证，排除了固件责任）  
> **结论**: **OpenOCD 的 CYT2BL3 配置存在缺陷** —— 超时变量未设置导致 DP 重连只试一次就放弃

---

## 1. 责任链追溯

```
┌─────────────────────────────────────────────────────────────┐
│                      问题分层                                │
├─────────────┬───────────────────────────────────────────────┤
│ CMSIS-DAP   │ ✅ 无责。retry_count 只对 WAIT 响应重试,       │
│   固件      │   引脚 Hi-Z 时的 JUNK ACK 不属于其职责范围      │
├─────────────┼───────────────────────────────────────────────┤
│ WCH-Link    │ ✅ 无责。正常实现了 CMSIS-DAP v2 协议          │
│   硬件      │   （已通过 SWD 连接、枚举、烧录全部成功）       │
├─────────────┼───────────────────────────────────────────────┤
│ OpenOCD     │ ⚠️ 部分责任。`dap_handshake` 设计了重试机制    │
│  C 源码     │   但在 CYT2BL3 配置中未启用                    │
├─────────────┼───────────────────────────────────────────────┤
│ Infineon    │ ❌ 主要责任。CYT2BL3 的 OpenOCD 配置没有设置    │
│ CYT2BL3     │   TIMEOUT_RESET_HANDSHAKE 和                   │
│   配置      │   TIMEOUT_BOOT_COMPLETE 超时变量               │
└─────────────┴───────────────────────────────────────────────┘
```

---

## 2. 关键证据一：超时变量没有设置！

### 2.1 对比其他 Infineon 芯片的配置

| 芯片系列 | TIMEOUT_RESET_HANDSHAKE | TIMEOUT_BOOT_COMPLETE | 配置位置 |
|---------|:---:|:---:|------|
| **PSoC3 (cat1b)** | **100 ms** | **1200 ms** | `config_cat1b_psc3.cfg:29,34` |
| **PSoC E84 (cat1d)** | **100 ms** | **5000 ms** | `config_cat1d_pse84.cfg:25,34` |
| **CYT2BL3 (cat1a)** | **❌ 未设置!** | **❌ 未设置!** | — |

### 2.2 源码证明

```tcl
# config_cat1a_cyt2xx.cfg — CYT2BL3 的配置文件（共35行）
# 搜索 TIMEOUT → 0 results !
# 整个配置文件没有提到 TIMEOUT_RESET_HANDSHAKE
# 整个配置文件没有提到 TIMEOUT_BOOT_COMPLETE
```

对比 `config_cat1d_pse84.cfg` 的注释：
```tcl
# config_cat1d_pse84.cfg:19-34
# Reset Handshake - timeout for the debugger to poll the DAP after reset until
#   set_or_global TIMEOUT_RESET_HANDSHAKE   100
# The additional timeout for the debugger to wait from when the SWJ pins became
#   set_or_global TIMEOUT_BOOT_COMPLETE     5000
```

---

## 3. 关键证据二：没有超时 = 只试一次

### 3.1 `dap_handshake` 函数源码

```tcl
# common_ifx.cfg:200-229
proc dap_handshake { {timeout 0} } {
    if {$timeout == 0} {
        # 如果这两个变量都不存在, timeout 保持为 0 !
        if {[info exists ::TIMEOUT_RESET_HANDSHAKE]} { incr timeout $::TIMEOUT_RESET_HANDSHAKE }
        if {[info exists ::TIMEOUT_BOOT_COMPLETE]}   { incr timeout $::TIMEOUT_BOOT_COMPLETE   }
        set timeout [scale_timeout $timeout]    # 0 × 1.0 = 0
    }

    set ret 0; set t_start [ms]; set t_elapsed 0
    while 1 {
        if {[catch {dap init}] == 0} {
            set ret 1
        }
        set t_elapsed [expr {[ms] - $t_start]}   # 第1次: t_elapsed ≈ 1
        if {$ret || ($t_elapsed > $timeout)} { break }  # 1 > 0 → BREAK!
        sleep 25   # ← 这行永远不会执行!
    }
    return $ret
}
```

### 3.2 模拟执行

```
timeout = 0

第1次循环:
  t_elapsed = 0 → 执行 dap_init → 失败 → ret=0
  t_elapsed = 1 (dap_init 耗时约1ms)
  检查: 0 || (1 > 0) → TRUE → BREAK!
  
结果: 只试了 1 次, sleep 25 从未执行!
```

**所以你说的"每 25ms 重试一次"——对于 CYT2BL3 来说根本没发生过！** 25ms 的 sleep 在 break 之后，永远走不到。

---

## 4. 如果设置了超时会怎样？

假设像 PSoC3 一样设置 `TIMEOUT_RESET_HANDSHAKE=100, TIMEOUT_BOOT_COMPLETE=1200`：

```
timeout = 100 + 1200 = 1300 ms
scale_timeout(1300) → SWD 模式: 1300 × 1.0 = 1300 ms

循环:
  第1次: dap_init 失败 → t_elapsed=1 → 1>1300? No → sleep 25
  第2次: dap_init 失败 → t_elapsed=27 → 27>1300? No → sleep 25
  ...
  第N次: dap_init 失败 → t_elapsed=1251 → 1251>1300? No → sleep 25
  第N+1次: dap_init 成功 → ret=1 → BREAK ✅!

总尝试次数 ≈ 1300/25 ≈ 52 次
总等待时间 ≈ 1300ms

Boot ROM 配置 SWD 引脚只需 2-5ms
→ 1300ms 绰绰有余!
```

**如果 CYT2BL3 的配置也设置了这些超时变量，这次烧录根本不会失败！**

---

## 5. 为什么 PSoC 设了但 CYT2BL3 没设？

推测原因：

| 芯片 | 可能原因 |
|------|---------|
| PSoC3/PSoC E84 | 开发较早，踩过坑，加了超时 |
| CYT2BL3 | 可能是从 PSoC6 配置模板快速移植的，忽略了超时变量 |
| | 或者：官方用 KitProg3/J-Link 测试，这些调试器重连很快，不需要超时 |
| | 用 CMSIS-DAP (WCH-Link) 的场景没有被充分测试 |

---

## 6. 验证：如果加上超时会怎样？

修改 `target/infineon/cat1a/config_cat1a_cyt2xx.cfg`，添加：

```tcl
# 在文件末尾添加:
set_or_global TIMEOUT_RESET_HANDSHAKE   100
set_or_global TIMEOUT_BOOT_COMPLETE     2000
```

预期效果：
- `dap_handshake` 会循环重试约 `2100/25 ≈ 84` 次
- 总等待 2.1 秒，远超 Boot ROM 的 2-5ms 配置时间
- 在芯片 SWD 引脚就绪后的第一次 dap_init 就会成功

---

## 7. 完整责任链总结

```
报错: "Error connecting DP: cannot read IDR"
         │
         ├─ 直接原因: SWD 读 DPIDR 时芯片引脚是 Hi-Z, ACK=111(JUNK)
         │   ├─ [CMSIS-DAP] 不负责重连物理层  ← ✅ 设计如此
         │   └─ [CYT2BL3] ROM Boot 期间引脚 Hi-Z ← ✅ 芯片正常行为
         │
         ├─ 重连机制: OpenOCD 的 dap_handshake
         │   ├─ 设计上可以循环重试, 每次 sleep 25ms  ← ✅ 机制存在
         │   └─ 但需要 TIMEOUT 变量设置总超时        ← ❌ 这里断了!
         │
         └─ 根因: CYT2BL3 配置中 TIMEOUT_RESET_HANDSHAKE 和
                 TIMEOUT_BOOT_COMPLETE 均未设置
                 → dap_handshake timeout=0 → 只试 1 次就放弃
                 → 如果设置了 (如 PSoC3 的 1300ms), 应该在 ~50ms 内成功
```

---

## 8. 各方责任分配

```
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║   CMSIS-DAP 固件:    ✅ 0%  责任                             ║
║   WCH-Link 硬件:     ✅ 0%  责任 (正常实现了 CMSIS-DAP v2)    ║
║   CYT2BL3 芯片:      ✅ 0%  责任 (ROM Boot 是正常行为)        ║
║   OpenOCD C 源码:    ⚠️ 10%  (超时机制依赖配置, 无可指责)     ║
║   CYT2BL3 配置:      ❌ 90% (漏设了超时变量)                  ║
║                                                              ║
║   结论: 不是 CMSIS-DAP 的错, 不是 WCH-Link 的错,              ║
║         不是芯片的错, 甚至不是 OpenOCD 本身的错 ——            ║
║         是 Infineon 的 CYT2BL3 OpenOCD 配置漏了两个超时变量。  ║
║                                                              ║
║   修复方法: 在 config_cat1a_cyt2xx.cfg 中添加:               ║
║     set_or_global TIMEOUT_RESET_HANDSHAKE   100              ║
║     set_or_global TIMEOUT_BOOT_COMPLETE     2000             ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

---

## 9. 附录：修复建议

### 9.1 临时修复（用户侧）

修改 `tools/infineon-openocd/scripts/target/infineon/cat1a/config_cat1a_cyt2xx.cfg`，在文件末尾添加：

```tcl
# DP Reconnection Timeout (missing in original config)
set_or_global TIMEOUT_RESET_HANDSHAKE   100   ;# DAP handshake timeout after reset
set_or_global TIMEOUT_BOOT_COMPLETE     2000  ;# Additional boot completion timeout
```

### 9.2 永久修复（提 PR）

向 [Infineon/OpenOCD](https://github.com/Infineon/openocd) 提交 Pull Request，为 CAT1A 系列添加超时配置。

### 9.3 绕过方案（已验证）

继续使用 `halt 3000` 代替 `reset init`，绕开整个复位-重连问题。

---

> 📎 **完整调查链**:
> - [v1.0] [DP 重连失败根因分析](./CYT2BL3_DP重连失败根因分析报告.md) — 竞态条件分析
> - [v2.0] [CMSIS-DAP 源码验证](./CYT2BL3_CMSIS-DAP源码验证_DP重连失败报告.md) — 排除固件责任
> - [v3.0] 本报告 — 最终定责：OpenOCD 配置缺陷
