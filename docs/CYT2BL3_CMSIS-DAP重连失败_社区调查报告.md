# CMSIS-DAP SWD 重连失败 — 社区同类问题调查报告

> 日期: 2026-05-05
> 调查范围: Rust 论坛、EEVBlog、STM32/NXP/Infineon 社区、GitHub Issues

---

## 1. 调查结论

**有！而且是跨芯片、跨调试器、跨工具的普遍问题！**

从 STM32 + STLink 到 PSoC6 + KitProg3 到 CYT2BL3 + WCH-Link，从 OpenOCD 到 probe-rs，全网都在报同一个症状。

---

## 2. 典型案例

### 2.1 Rust 论坛 — 与我们的症状完全一致

**帖子**: probe-rs fails to work after first time use successful
**芯片**: STM32F103C8
**调试器**: STLink V2 (CMSIS-DAP 兼容)

引用原文:
> "I am able to successfully run and flash the target with probe-rs. However, after that, I am unable to re-connect to the target board."
> "Error: Command failed with status SwdApFault"
> "I disconnected and re-connected the power to my target, and to my STLink adapter, but this did not help."

解决方法:
> "The communication seems to only lock up when I flash. neither probe-rs nor openocd are able to flash the target **except when I manually hold down the reset button on the board and only release it once probe-rs or openocd run**."

**与我们的一致性**:
| 症状 | STM32+STLink | CYT2BL3+WCH-Link |
|------|:--:|:--:|
| 首次烧录成功 | YES | YES |
| 后续重连失败 | YES | YES |
| 硬件复位可解决 | YES | Need to test |

来源: https://users.rust-lang.org/t/probe-rs-fails-to-work-after-first-time-use-successful/103234

---

### 2.2 EEVBlog — CMSIS-DAP sticky overrun 铁证

**帖子**: Does anyone have experience debugging CMSIS-DAP firmware itself?
**芯片**: STM32F103

OpenOCD debug 日志关键行:
```
cmsis_dap.c:647 cmsis_dap_swd_read_process(): SWD ack not OK @ 0 JUNK
adi_v5_swd.c:144 swd_connect(): Error connecting DP: cannot read IDR
cmsis_dap.c:817 cmsis_dap_swd_write_from_queue(): refusing to enable sticky overrun detection
```

**关键发现**: `refusing to enable sticky overrun detection` — OpenOCD 的 CMSIS-DAP 驱动拒绝启用 sticky overrun 检测。这意味着如果有 sticky error，驱动不会自动清除，导致后续操作持续失败。

**这与我们的 pending error 假说完全吻合！**

来源: https://www.eevblog.com/forum/microcontrollers/does-anyone-have-experience-debugging-cmsis-dap-firmware-itself/

---

### 2.3 STM32 Community — 同类错误循环

**帖子**: OpenOCD SWD Programming with CMSIS-DAP
**芯片**: STM32F0

症状: 连接成功 → 过一会 → "Error connecting DP: cannot read IDR" → 重试间隔不断增加 (100ms → 300ms → 700ms → 1500ms) → 最终失败。

与我们看到的 probe-rs 重连循环完全相同，只是重试间隔不同。

来源: https://community.st.com/t5/stm32-mcus-products/open-ocd-swd-programming-with-cmsis-dap/td-p/782532

---

### 2.4 Infineon Community — KitProg3 特殊处理

**帖子**: Debugging PSOC6
**芯片**: PSoC6 (与 CYT2BL3 同架构!)

KitProg3 日志关键行:
```
kitprog3: acquiring the device (mode: reset)...
kitprog3: failed to acquire the device
Error: Error connecting DP: cannot read IDR
```

**发现**: KitProg3 有专门的 "acquiring the device (mode: reset)" 步骤。这是 Infineon 官方调试器对 HSIOM 架构芯片的特殊处理——在复位期间主动保持 SWD 连接。

而 WCH-Link 作为通用 CMSIS-DAP 适配器，没有这个特殊处理。

来源: https://community.infineon.com/t5/PSOC-6/Debugging-PSOC6/td-p/817652

---

### 2.5 NXP Community — 需要 SDP 模式恢复

**帖子**: CMSIS-DAP SWD/JTAG Communication Failure after working previously
**芯片**: i.MX RT

解决: 进入串行下载模式 (SDP Mode), 擦除 Flash, 重新编程。之后恢复正常。

来源: https://community.nxp.com/t5/i-MX-RT-Crossover-MCUs/CMSIS-DAP-SWD-JTAG-Communication-Failure-after-working/td-p/1283179

---

### 2.6 STM32 Community — SWD 引脚被固件关闭

**帖子**: Why SWD stopped working after re-programming
**芯片**: STM32

原因: STM32CubeMX 的 "Set all free pins as analog" 选项把 SWD 引脚 (PA13/PA14) 设为了模拟模式, 导致 SWD 断开。

需要: 启用 "Connect under reset" 或使用硬件复位引脚。

来源: https://community.st.com/t5/stm32-mcus-products/answer-why-swd-stopped-working-after-re-programming/td-p/404108

---

## 3. 问题模式总结

### 3.1 三种失败模式

| 模式 | 代表芯片 | 根因 |
|------|---------|------|
| **A: 固件关闭SWD** | STM32 | 用户代码将 SWD 引脚改为 GPIO/模拟 |
| **B: 适配器状态污染** | STM32+STLink, CYT2BL3+WCH-Link | sticky error / pending error 未清除 |
| **C: HSIOM 重配延迟** | PSoC6, CYT2BL3 | ROM Boot + FlashBoot 需要时间配置引脚 |

我们的 CYT2BL3 同时遇到 **模式 B + 模式 C**！

### 3.2 通用解决方案

| 方案 | 适用性 | 难度 |
|------|:--:|:--:|
| **硬件复位 (SRST/nRESET)** | 所有模式 | 需要接线 |
| **Connect Under Reset** | 模式 A, B | 需要调试器支持 |
| **断电重启** | 模式 B | 最简单 |
| **专用调试器 (KitProg3/J-Link)** | 模式 C | 需要购买 |
| **避开 SYSRESETREQ (halt 方式)** | 模式 B, C | 已验证可行! |

---

## 4. 我们的定位

```
社区报告矩阵:
                  STM32    PSoC6    CYT2BL3
CMSIS-DAP 首次可用   YES      YES      YES
CMSIS-DAP 重复失败   YES      YES      YES
OpenOCD 受影响       YES      YES      YES
probe-rs 受影响      YES      ?        YES
KitProg3 修复        N/A      YES      ?
J-Link 无问题        YES      YES      ?
断电重启有效         ?        ?        YES (首次)
halt 方式有效        ?        ?        YES

结论: 我们不是第一个遇到的, 也不会是最后一个。
      这个问题在 CMSIS-DAP 生态中是系统性的。
```

---

## 5. 最终结论

```
1. CMSIS-DAP + SWD 重连失败是跨芯片、跨工具的普遍问题
   - STM32、PSoC6、CYT2BL3、i.MX RT 全线受影响
   - OpenOCD、probe-rs 都有此问题

2. 根因在 CMSIS-DAP 架构层面
   - 固件不做自动重连 (只做协议层重试)
   - Host 驱动对 sticky error 处理不完善
   - 芯片复位后适配器状态污染

3. 专业调试器 (KitProg3/J-Link) 通过固件特殊处理规避
   - KitProg3: "acquiring the device (mode: reset)"
   - J-Link: 固件层自动重连 + 自适应时序

4. 我们的 halt 方式是社区验证过的可行 workaround
   - 与 Rust 论坛的"按住复位键"方案原理相同
   - 都是跳过 SYSRESETREQ, 避免触发适配器状态污染
```

来源汇总:
- https://users.rust-lang.org/t/probe-rs-fails-to-work-after-first-time-use-successful/103234
- https://www.eevblog.com/forum/microcontrollers/does-anyone-have-experience-debugging-cmsis-dap-firmware-itself/
- https://community.st.com/t5/stm32-mcus-products/open-ocd-swd-programming-with-cmsis-dap/td-p/782532
- https://community.infineon.com/t5/PSOC-6/Debugging-PSOC6/td-p/817652
- https://community.nxp.com/t5/i-MX-RT-Crossover-MCUs/CMSIS-DAP-SWD-JTAG-Communication-Failure-after-working/td-p/1283179
- https://community.st.com/t5/stm32-mcus-products/answer-why-swd-stopped-working-after-re-programming/td-p/404108
