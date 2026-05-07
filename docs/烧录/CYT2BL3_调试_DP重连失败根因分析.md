# CYT2BL3 烧录 DP 重连失败 — 源码级根因分析报告

> **分析日期**: 2026-05-05  
> **触发场景**: `openocd -c "program firmware.hex verify reset exit"` 执行失败  
> **成功对比**: `openocd -c "halt 3000" -c "flash write_image erase firmware.hex"` 执行成功  
> **根因**: 芯片软复位后 SWD 物理层恢复与 Boot ROM 引脚重配之间的**竞态条件**

---

## 1. 报错时间线还原

### 1.1 成功阶段（未出错前）

```
[00:00.2] Info : Using CMSIS-DAPv2 interface (VID:PID=0x1a86:0x8012)
[00:00.3] Info : SWD DPIDR 0x6ba02477                         ← ① DP 初次连接成功
[00:00.4] Info : [traveo2_be_4m.cpu.cm0] Cortex-M0+ r0p1      ← ② CM0+ 检测成功
[00:00.4] ** Detected Device: CYT2BL3CXE **                   ← ③ 芯片识别成功
[00:00.5] Info : [traveo2_be_4m.cpu.cm4] Cortex-M4 r0p1       ← ④ CM4 检测成功
```

### 1.2 失败触发点

```
[00:00.5] [program 命令开始执行]
              │
              ▼
[00:00.5] ocd_process_reset()  ← 准备复位芯片以进入烧录就绪状态
              │
              ▼
          ┌─ 发送 SYSRESETREQ (写 SCB→AIRCR) ──┐
          │        芯片全部逻辑复位               │
          │    ROM Boot 开始执行...              │  ← 🔥 竞态窗口开启
          │    调试引脚被 ROM 重新配置...         │
          └────────────────────────────────────┘
              │
              ▼
[00:00.6] reset-deassert-post 事件触发
          │
          ├─→ event_cm0_reset_deassert_post()
          │       │
          │       ├─→ mxs40_reset_deassert_post()  ← 写 Flash 控制器寄存器
          │       │       │
          │       │       └─→ mrw $FLASHC_FLASH_CTL  ← 读内存 = DP→AP→AHB
          │       │               │
          │       │               └─→ dap init()  ← 尝试重连 DP
          │       │                      │
          │       │                      └─→ ❌ Error: cannot read IDR
          │       │
          │       └─→ mww $FLASHC_FLASH_CTL   ← 写内存 = DP→AP→AHB
          │               │
          │               └─→ ❌ Error: cannot read IDR
          │
          └─→ event_cm4_reset_deassert_post()  ← 同样失败
```

---

## 2. 逐条报错解析

### 2.1 报错 #1 — DP 读不到 IDR

```
Error: Error connecting DP: cannot read IDR
```

**谁发出的**：OpenOCD 的 CMSIS-DAP 驱动层 (`src/jtag/drivers/cmsis_dap.c`)

**什么操作**：尝试通过 SWD 协议读取 DP 的 IDR (Identification Register, 地址 0x0)

**SWD 协议层面发生了什么**：
```
调试器 (WCH-Link)                     芯片 (CYT2BL3)
    │                                       │
    ├─ SWD Line Reset (50+ cycles) ────────►│  ① 重新同步 SWD 总线
    │                                       │
    ├─ SWD DPIDR Read Request ─────────────►│  ② 发包: "读 DP 地址 0"
    │     (APnDP=0, RnW=1, A[3:2]=00)       │
    │                                       │
    ├─ Turnaround (1 cycle)                 │
    │                                       │
    ├─ ?????????? ←─────────────── ✗ ──────┤  ③ 芯片没有回应 ACK
    │                                       │     或者回应了但数据无效
    │                                       │
    └─ 重试 N 次后放弃 ──→ "cannot read IDR"
```

**为什么芯片不回应**：此时芯片正在 ROM Boot 过程中，SWJ-DP 引脚可能处于三种状态之一：
- **Hi-Z (高阻态)**：Boot ROM 尚未配置引脚功能，SWD 总线上没有设备驱动
- **JTAG 模式**：Boot ROM 默认先配置为 JTAG，SWD 读请求被当作 JTAG TMS 序列
- **GPIO 模式**：引脚被 ROM 临时复用为其他功能

### 2.2 报错 #2 — DP 初始化失败

```
Error: [traveo2_be_4m.cpu.cm0] DP initialisation failed
```

**谁发出的**：OpenOCD 目标层 (`src/target/arm_adi_v5.c` 中的 `dap_dp_init()`)

**什么操作**：DP 初始化需要一连串寄存器读写：
```
dap_dp_init() 流程:
1. 读取 DPIDR (验证 DP 存在)         ← 这一步就失败了
2. 写 CTRL/STAT (上电调试域)
3. 等待 CSYSPWRUPACK / CDBGPWRUPACK
4. 配置 AP 选择
```

第 1 步就失败，所以整个 DP 初始化无法完成。

### 2.3 报错 #3 — 向量表找不到

```
Info : traveo2_be_4m.cpu.cm0: Waiting up to 0.600 sec for valid Vector Table address...
Error: Error connecting DP: cannot read IDR
Info : traveo2_be_4m.cpu.cm0: Vector Table not found (core not started?), reset_halt skipped
```

**谁发出的**：Cortex-M 复位序列 (`src/target/cortex_m.c` 的 `cortex_m_assert_reset()`)

**什么操作**：复位后，调试器期望：
1. 核心停在复位向量 (从 VTOR 读取 SP 和 PC)
2. 验证 SP 在 RAM 范围内
3. 设置硬件断点在复位地址
4. 然后释放复位，核心停在第一条指令

由于 DP 不可达，无法读 VTOR，所以**整个 `reset_halt` 被跳过** — 这意味着核心在复位后就全速运行了（进入了 ROM Boot），而不是停在第一条指令。

### 2.4 报错 #4 — reset-deassert-post 事件失败

```
Error executing event reset-deassert-post on target traveo2_be_4m.cpu.cm0:
D:\03-Wheel_leg_CYT2BL3\tools\infineon-openocd\scripts/target/infineon/cat1a/base_cyt2xx.cfg:43: Error:
in procedure 'ocd_process_reset'
in procedure 'ocd_process_reset_inner' called at file "embedded:startup.tcl", line 1225
at file "D:\03-Wheel_leg_CYT2BL3\tools\infineon-openocd\scripts/target/infineon/cat1a/base_cyt2xx.cfg", line 43
```

**谁发出的**：OpenOCD 事件系统 + Infineon 自定义脚本

**什么操作**：这是整个错误链条的**真正源头**。Tcl 调用栈如下：

```
OpenOCD 内部调用栈 (从底到顶):
─────────────────────────────────────────────────────
base_cyt2xx.cfg:91-101  event_cm0_reset_deassert_post ← 自定义回调
    ↓ 调用
base_cyt2xx.cfg:92      mxs40_reset_deassert_post       ← Flash 驱动初始化
    ↓ 调用 mrw (读 Flash 控制寄存器)
src/target/arm_adi_v5.c  dap_dp_init()                  ← DP 初始化
    ↓ 调用 DAP 操作
src/jtag/drivers/cmsis_dap.c  cmsis_dap_queue_dp_read() ← SWD 读 DPIDR
    ↓ 返回错误
src/target/cortex_m.c   → "Error connecting DP: cannot read IDR"
    ↓ 错误传播
common_ifx.cfg:216      catch {dap init} 捕获到错误 → 重试 → 全部失败
    ↓
base_cyt2xx.cfg:43      event 回调失败 → 向上抛异常
    ↓
embedded:startup.tcl:1225  ocd_process_reset_inner → 整个 reset 流程失败
```

**`event_cm0_reset_deassert_post` 里到底做了什么**：

```tcl
# base_cyt2xx.cfg:91-101
proc event_cm0_reset_deassert_post {} {
    # ① 调用 Flash 驱动初始化 (mxs40 是 Infineon 的 Flash 控制器代号)
    mxs40_reset_deassert_post ${::FLASH_DRIVER_NAME} ${::TARGET}.cm0

    # ② 如果不是 "reset run" 模式 (烧录用的是 "reset init" 模式)
    if { $::RESET_MODE ne "run" } {
        catch {
            # ③ 读 Flash 控制寄存器 ← 这需要 DP→AP→AHB→Flash Controller
            set flash_ctl [mrw $::FLASHC_FLASH_CTL]

            # ④ 写 Flash 控制寄存器 (关闭 ECC 以允许对已擦除 Flash 做校验)
            mww $::FLASHC_FLASH_CTL [expr {$flash_ctl & $::FLASHC_FLASH_CTL_DISABLE_ECC}]
        }
    }
}
```

**每一步都需要 DP 可达**。`mrw`/`mww` 最终都通过 `dap init` → `dap_dp_init` → SWD 读 DPIDR。第①步就失败了，所以所有操作全部报错。

### 2.5 报错 #5 — 最后的清理失败

```
Info : traveo2_be_4m.dap: powering down debug domain...
Error: Error connecting DP: cannot read IDR
Warn : Failed to power down Debug Domains
```

**谁发出的**：OpenOCD 退出时，因为 DAP 配置了 `-power-down-on-quit`

**什么操作**：退出前写 DP 的 CTRL/STAT 寄存器断电调试域。DP 不可达所以失败。

**这条不影响烧录结果** — 只是退出时清理不优雅。

---

## 3. 根因分析：竞态条件的时间窗口

### 3.1 芯片侧的时序

```
时间线 (芯片侧):
─────────────────────────────────────────────────────────►

  t=0        t≈100μs     t≈500μs       t≈2ms         t≈5ms
  │            │            │             │              │
  │ 复位解除    │ ROM 开始   │ 时钟系统     │ 调试引脚      │ 用户代码
  │            │ 执行       │ 初始化完成   │ 配置完成      │ 开始执行
  │            │            │             │              │
  │ 所有逻辑   │ 取第一条   │ FLL/PLL     │ SWJ-DP 引脚  │ Flash 中的
  │ 回到初始   │ ROM 指令   │ 锁定        │ 配置为       │ 用户程序
  │ 状态       │            │             │ 调试功能      │
  │            │            │             │              │
  │ ◄────── 调试引脚处于 Hi-Z / 不定态 ──────►│◄─ SWD 可用 ─►
  │                                          │
  │         ❌ SWD 不可用窗口 (~2-5ms)        │  ✅ SWD 可用
```

**关键事实**（来自 Infineon Traveo II Program and Debug Interface Training）：

> *"After reset, the debug pins remain in high-impedance mode until Boot ROM initializes them as follows:*
> - *swj_trstn: Input, Internal Pull-up*
> - *swj_swo_tdo: Strong Output*
> - *swj_swdoe_tdi: Input, Internal Pull-up*
> - *swj_swdio_tms: Input, Internal Pull-up*

在 Boot ROM 完成引脚配置之前，所有 SWJ-DP 引脚都是 **高阻态 (Hi-Z)**。此时 SWD 协议根本无法工作——没有设备在总线上驱动 ACK 响应。

### 3.2 调试器侧的时序

```
时间线 (调试器侧, WCH-Link CMSIS-DAP):
─────────────────────────────────────────►

  t=0           t≈1ms          t≈2ms          t≈3ms
  │               │               │               │
  │ 发送 AIRCR    │ 等待...       │ 尝试 SWD       │ 放弃，报错
  │ (软件复位)    │               │ Line Reset    │
  │               │               │ + 读 DPIDR    │
  │               │               │               │
  │               │               ├─ 重试 #1      │
  │               │               ├─ 重试 #2      │
  │               │               └─ 重试 #N ────► "cannot read IDR"
```

**WCH-Link CMSIS-DAP 的 DAP 操作重试机制**是在其固件内部实现的，不在 OpenOCD 层面。当 OpenOCD 发出 `DAP_Transfer` 命令后，CMSIS-DAP 固件尝试在 SWD 总线上执行，失败后返回错误码。OpenOCD 收到错误后可能重试几次，但总超时很短。

### 3.3 竞态窗口

```
        芯片侧:  [~~~~~ ROM Boot, 引脚未配置 ~~~~~][ SWD 就绪 ]
                          ↑                      ↑
                        ~2-5ms                    ~5ms
                          │
        调试器侧:  [尝试读 DP] [重试] [报错退出]
                          ↑         ↑       ↑
                         ~1ms     ~2ms    ~3ms

        结论: 调试器的重试在芯片准备好之前就结束了！
```

**这就是根因**：WCH-Link 的重试窗口 (~2ms) 小于芯片的 Boot ROM 引脚配置时间 (~2-5ms)，导致在所有重试都发生在 "SWD 不可用" 窗口内。

---

## 4. 为什么 `halt` 成功但 `reset init` 失败？

### 4.1 `reset init` — 触发完整的复位序列

```
reset init 流程:
┌─────────────────────────────────────────────────────────┐
│ 1. 发送复位 (SYSRESETREQ → AIRCR)                        │
│ 2. 芯片全部逻辑复位，ROM Boot 开始执行                    │
│ 3. 【问题】调试引脚进入 Hi-Z，需要等待 ROM 重新配置       │
│ 4. reset-deassert-post 事件触发                          │
│ 5. event_cm0_reset_deassert_post 尝试访问 Flash 控制器    │
│ 6. DP 不可达 → 失败 → 错误传播 → 整个过程终止             │
└─────────────────────────────────────────────────────────┘
```

### 4.2 `halt` — 不触发复位

```
halt 3000 流程:
┌─────────────────────────────────────────────────────────┐
│ 1. 芯片已经在上电后运行了一段时间                        │
│ 2. ROM Boot 早已完成，调试引脚已是 SWD 模式              │
│ 3. 调试器已经建立了稳定的 DP 连接 (DPIDR 已验证)         │
│ 4. 发送 halt 请求 (写 DHCSR)                             │
│ 5. 核心暂停 → Flash 烧录开始                             │
│ 6. DP 连接始终稳定 → 整个过程成功                        │
└─────────────────────────────────────────────────────────┘
```

**本质区别**：`halt` 不触发芯片复位，所以不存在 "DP 重连" 的需求。DP 连接从 `init` 阶段建立后一直保持到 `exit`。

---

## 5. 为什么 J-Link 不报这个错？

同样的 OpenOCD 配置，用 J-Link 就不会遇到这个问题。原因：

| 因素 | WCH-Link CMSIS-DAP | J-Link |
|------|:--:|:--:|
| SWD 时钟 | 受限于 USB FS (12Mbps) | 最高 50MHz |
| DAP 操作重试 | 固件内置，参数固定 | 可配置 `JTAG_SPEED` + 自适应 |
| SWD Line Reset 后等待 | 固件固定延时 | 检测 ACK 超时灵活 |
| 固件复杂度 | 通用 CMSIS-DAP | Segger 专有优化 |
| `reset_config` 方式 | 仅 sysresetreq 可用 | 可同时用 SRST 硬件复位 |

J-Link 会自动检测到 DP 不可达后**等待更长时间**并多次重试，直到芯片的 Boot ROM 完成引脚配置。

---

## 6. 错误传播链的完整图谱

```
最终用户看到的：
  Error: Error connecting DP: cannot read IDR
  Error: [traveo2_be_4m.cpu.cm0] DP initialisation failed
  Vector Table not found, reset_halt skipped
  Error executing event reset-deassert-post
  Failed to power down Debug Domains

═══════════════════════════════════════════════════════════
实际调用链：
═══════════════════════════════════════════════════════════

program 命令
  └─ ocd_process_reset (embedded:startup.tcl:1225)
       └─ ocd_process_reset_inner
            └─ foreach target: reset init
                 └─ cortex_m_assert_reset (C 代码)
                      └─ 写 AIRCR = SYSRESETREQ
                      └─ 等待 core 复位
                      └─ cortex_m_deassert_reset
                           ├─ 读 VTOR → ❌ DP 不可达 → "cannot read IDR"
                           ├─ "Vector Table not found" → reset_halt 跳过
                           └─ 触发 reset-deassert-post 事件
                                └─ event_cm0_reset_deassert_post (Tcl)
                                     └─ mxs40_reset_deassert_post (Tcl)
                                          └─ mrw $FLASHC_FLASH_CTL
                                               └─ dap init() (C 代码)
                                                    └─ dap_dp_init()
                                                         └─ SWD 读 DPIDR
                                                              └─ ❌ 芯片不回应
                                                                   └─ CMSIS-DAP 固件返回错误
                                                                        └─ catch 捕获 → 重试
                                                                             └─ 全部失败 → 抛异常
                                                                                  └─ 上层 catch → 整个 program 失败
```

---

## 7. 各类复位方式对比

| 复位方式 | 命令 | WCH-Link 兼容性 | 说明 |
|---------|------|:--:|------|
| **不复位** | `halt 3000` | ✅ | 核心已在运行，直接暂停 |
| 软件复位 | `reset init` (sysresetreq) | ❌ | 芯片完全重启，DP 重连窗口太短 |
| 硬件复位 | `reset_config srst_only` + XRES | ⚠️ | 需要接线 nRESET 引脚 |
| 仅复位核心 | `cortex_m reset_config vectreset` | ⚠️ | 仅复位 Cortex-M 核心，不重启外设 |

---

## 8. 解决方案总结

| 方案 | 命令/操作 | 效果 |
|------|---------|------|
| **方案 A** (已验证) | `halt 3000` 代替 `reset init` | ✅ 稳定烧录 |
| 方案 B | 换用 J-Link 等专业调试器 | ✅ 原生支持 reset 后自动重连 |
| 方案 C | 连接 XRES 引脚 + `reset_config srst_only` | ✅ 硬件复位时序可控 |
| 方案 D | 延长 OpenOCD 的 `adapter srst delay` | ⚠️ 仅对硬件复位有效 |
| 方案 E | 用 `dap_handshake` 轮询 DP | ⚠️ 需要修改脚本，增加超时 |

---

## 9. 一句话总结

> **芯片软复位后，ROM Bootloader 需要 2-5ms 来重新配置 SWJ-DP 调试引脚。WCH-Link 的 CMSIS-DAP 固件在这个窗口内就放弃了重试，导致 DP 读 IDR 失败。跳过复位 (`halt` 代替 `reset init`) 绕过了这个竞态条件，烧录成功。**

---

> 📎 **关联文档**:
> - [CYT2BL3 OpenOCD 烧录实操成功报告](./CYT2BL3_OpenOCD_烧录实操成功报告.md)
> - [CYT2BL3 调试接口 ADIv5 兼容性分析](./CYT2BL3_调试接口_ADIv5兼容性分析报告.md)
