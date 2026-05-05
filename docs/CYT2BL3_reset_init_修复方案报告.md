# CYT2BL3 reset init 修复方案 — 精确定位与实施报告

> **日期**: 2026-05-05  
> **目标**: 修复 `reset init` 在 WCH-Link CMSIS-DAP 下 DP 重连失败的问题  
> **前序**: 已通过 TIMEOUT 变量修复了 `dap_handshake` 层面，但 `reset init` 的失败点不在那里

---

## 1. `reset init` 失败点精确定位

### 1.1 调用链全景

```
reset init
  └─ ocd_process_reset (embedded:startup.tcl)
       └─ ocd_process_reset_inner (embedded:startup.tcl:1225)
            └─ foreach target:
                 ├─ cortex_m_assert_reset()   ← C 代码: 写 AIRCR = SYSRESETREQ
                 │    └─ 芯片完全复位，Boot ROM 开始执行
                 │
                 ├─ cortex_m_deassert_reset()  ← C 代码: 尝试 halt @ 复位向量
                 │    ├─ 读 VTOR → DP 不可达 → ❌ 报错点 #1
                 │    │    "Vector Table not found, reset_halt skipped"
                 │    │
                 │    └─ 触发事件: reset-deassert-post
                 │
                 └─ reset-deassert-post 事件:
                      │
                      ├─ CM0+ 侧: event_cm0_reset_deassert_post()
                      │    │  base_cyt2xx.cfg:91-101
                      │    │
                      │    ├─ [1] mxs40_reset_deassert_post()
                      │    │       func_mxs40.cfg:550-605
                      │    │       ├─ catch {$target arp_examine}  ← DP不可达, catch吞掉
                      │    │       ├─ catch {$target arp_poll}      ← DP不可达, catch吞掉
                      │    │       └─ 对非kitprog3: 什么都不做, 直接返回
                      │    │
                      │    └─ [2] mrw $FLASHC_FLASH_CTL  ← DP不可达
                      │           └─ 被 catch {} 吞掉 (base_cyt2xx.cfg:94)
                      │
                      └─ CM4 侧: mxs40_reset_deassert_post()
                           │  func_mxs40.cfg:592-602 (非主核分支)
                           │
                           └─ ❌ 报错点 #2:
                                [$target curstate]  ← 不在 catch 里! 直接抛异常!
                                └─ DP 不可达 → Tcl 错误向上传播
```

### 1.2 两个确切的报错点

| # | 位置 | 代码 | 为何失败 |
|---|------|------|---------|
| **#1** | C 代码: `cortex_m_deassert_reset` | 读 VTOR via DP | Boot ROM 未完成引脚配置，DP 不响应 |
| **#2** | `func_mxs40.cfg:593/597` | `[$target curstate]` | CM4 的 reset-deassert-post 处理器，`curstate` 需要 DP 访问 |

---

## 2. 为何 TIMEOUT 变量未生效

### 2.1 TIMEOUT 变量的生效范围

```
TIMEOUT_RESET_HANDSHAKE ──→ 仅影响这些函数:
TIMEOUT_BOOT_COMPLETE       ├─ dap_handshake()       ← ✅ 生效
                            ├─ poll_cpu_ap_open()    ← ✅ 生效
                            ├─ poll_examine()        ← ✅ 生效
                            └─ poll_halted()         ← ✅ 生效

                            ❌ 不影响:
                            ├─ mxs40_reset_deassert_post()   ← 直接访问 DP
                            ├─ event_cm0_reset_deassert_post() ← 直接 mrw/mww
                            └─ cortex_m_deassert_reset()     ← C代码层, 不经过Tcl
```

### 2.2 关键代码

```tcl
# func_mxs40.cfg:550 — 这个函数不使用 dap_handshake!
proc mxs40_reset_deassert_post { target_type target } {
    # 直接调用 arp_examine, 没有等待 DP 重连
    catch { $target arp_examine }     # ← 失败, 被 catch 吞掉
    catch { $target arp_poll }        # ← 失败, 被 catch 吞掉

    # CM4 路径 — 这里没有 catch!
    if { [$target curstate] eq "reset" } {    # ← ❌ DP 不可达, 抛异常!
        $target arp_poll
    }
}
```

---

## 3. 修复方案

### 3.1 方案概述

在 `mxs40_reset_deassert_post` 函数的入口处，**在任何 DP 访问之前**，先调用 `dap_handshake` 等待 DP 重连。如果 DP 重连成功，后续操作正常执行。如果超时，优雅跳过。

### 3.2 具体修改

修改文件: `tools/infineon-openocd/scripts/target/infineon/cat1/func_mxs40.cfg`

**第 550-605 行，在 `arp_examine` 之前插入 DP 重连等待**：

```tcl
# 修改前:
proc mxs40_reset_deassert_post { target_type target } {
    log_proc_entry
    # ... type dispatch ...
    catch { $target arp_examine }    # ← DP 立刻访问, 必然失败
    catch { $target arp_poll }
    # ...

# 修改后:
proc mxs40_reset_deassert_post { target_type target } {
    log_proc_entry
    # ... type dispatch ...

    # 🔑 新增: 等待 DP 重连 (利用已设置的 TIMEOUT 变量)
    # dap_handshake 会循环调用 dap_init, 每次失败等 25ms
    # 因为有 TIMEOUT_BOOT_COMPLETE=2000ms, 最多重试约 80 次
    # Boot ROM 配置 SWD 引脚只需 2-5ms, 绰绰有余
    if {![dap_handshake]} {
        echo "Warn : DP handshake failed after reset, skipping post-reset init"
        log_proc_return
        return
    }

    catch { $target arp_examine }
    catch { $target arp_poll }
    # ... 其余代码不变 ...
```

### 3.3 同步修改 CM4 路径

CM4 的非主核分支 (`func_mxs40.cfg:592-602`) 中，`[$target curstate]` 也需要 DP。但因为我们在函数入口已经做了 `dap_handshake`，CM0+ 和 CM4 的 handler 都会走到同一个 `mxs40_reset_deassert_post`，所以入口处的修复同时保护了两个核心。

### 3.4 额外保险：CM4 分支加 catch

即使入口处做了 dap_handshake，CM4 路径的 `curstate` 调用也值得加一层 catch 保护：

```tcl
# 修改前:
} else {
    if { [$target curstate] eq "reset" } {
        $target arp_poll
    }
    if { [$target curstate] eq "running" } {
        echo "** $target: Ran after reset and before halt..."
        $target arp_halt
        $target arp_waitstate halted 100
    }
}

# 修改后:
} else {
    catch {
        if { [$target curstate] eq "reset" } {
            $target arp_poll
        }
        if { [$target curstate] eq "running" } {
            echo "** $target: Ran after reset and before halt..."
            $target arp_halt
            $target arp_waitstate halted 100
        }
    }
}
```

---

## 4. 修改影响范围

| 文件 | 改动 | 影响 |
|------|------|------|
| `cat1/func_mxs40.cfg` | 第 552 行后插入 `dap_handshake` | 所有 TRAVEO T2G / PSoC6 / XMC 芯片 |
| `cat1/func_mxs40.cfg` | CM4 分支加 `catch` | 同上 |

**安全性**: `dap_handshake` 是 Infineon 自己的工具函数，本身就是为"复位后 DP 重连"设计的。加在 `mxs40_reset_deassert_post` 入口处只是让它在这个特定场景下被调用——这正是它设计的目的。

对 KitProg3/J-Link 用户无影响——这些调试器 DP 重连极快，`dap_handshake` 第一次就会成功，几乎零开销。

---

## 5. 实施步骤

```
步骤 1: 备份原文件
  copy func_mxs40.cfg func_mxs40.cfg.bak

步骤 2: 在 func_mxs40.cfg 第 552 行后添加 dap_handshake 调用

步骤 3: 测试
  openocd -f interface/cmsis-dap.cfg -f target/infineon/cyt2bl.cfg
    -c "init" -c "reset init" -c "exit"
  预期: 不再报 "cannot read IDR"

步骤 4: 测试烧录
  make flash
  或在 OpenOCD 中: -c "program build/firmware.hex verify reset exit"
```

---

## 6. 预期效果

```
修改前:
  reset init
    → 芯片复位
    → DP 断开 (Boot ROM 未完成)
    → 立即尝试 arp_examine → ❌ DP 不可达
    → 事件处理器报错 → reset init 失败

修改后:
  reset init
    → 芯片复位
    → DP 断开 (Boot ROM 未完成)
    → dap_handshake 等待 (最多 2100ms, 每 25ms 重试)
    → ~50ms 后 Boot ROM 完成 → DP 重连成功 ✅
    → arp_examine 正常执行
    → Flash 烧录正常
    → reset init 成功 ✅
```

---

## 7. 如果还不行？

如果 `dap_handshake` 在 `mxs40_reset_deassert_post` 中仍然失败（可能性低，因为 TIMEOUT=2100ms >> Boot ROM 的 2-5ms），可以进一步增加：

```tcl
# 在 config_cat1a_cyt2xx.cfg 中增大超时:
set_or_global TIMEOUT_BOOT_COMPLETE     5000   # 5秒
```

或者在 `dap_handshake` 之前加一个固定延时：

```tcl
sleep 100   # 等 100ms 让 Boot ROM 一定跑完
if {![dap_handshake]} { ... }
```

---

## 8. 总结

```
╔═════════════════════════════════════════════════════════════╗
║                                                             ║
║  失败点: mxs40_reset_deassert_post() 第 568 行              ║
║          catch {$target arp_examine}                        ║
║          在 DP 还没恢复时就访问了 DP                        ║
║                                                             ║
║  TIMEOUT 为什么没用:                                        ║
║          dap_handshake 管不到 mxs40_reset_deassert_post     ║
║          后者直接调 arp_examine, 不经过任何轮询函数          ║
║                                                             ║
║  修复: 在 mxs40_reset_deassert_post 入口加 dap_handshake    ║
║        让 DP 在访问前有充分时间恢复                          ║
║                                                             ║
║  风险: 极低 — dap_handshake 就是这个场景设计的               ║
║        对 KitProg3/J-Link 无影响 (第一次就成功)              ║
║                                                             ║
╚═════════════════════════════════════════════════════════════╝
```

---

> 📎 **关联文档**:
> - [DP 重连失败根因分析 v1.0](./CYT2BL3_DP重连失败根因分析报告.md)
> - [CMSIS-DAP 源码验证 v2.0](./CYT2BL3_CMSIS-DAP源码验证_DP重连失败报告.md)
> - [OpenOCD 配置缺陷定责 v3.0](./CYT2BL3_OpenOCD配置缺陷_最终定责报告.md)
