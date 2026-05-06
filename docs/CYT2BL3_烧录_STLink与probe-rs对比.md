# ST-Link 烧录工具全景 & probe-rs 使用指南

> *"probe-rs 支持 ST-Link 吗？除了 OpenOCD 还有哪些工具？手上只有 ST-Link 怎么办？"*
> 基于 probe-rs 官方文档、pyOCD 文档及社区实践

---

## 一、核心结论

```
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║  ✅ probe-rs 完全支持 ST-Link v2 的 SWD 协议！                ║
║  ✅ 你的 ST-Link (VID:0483 PID:3748) 可以被 probe-rs 识别     ║
║  ✅ 除了 OpenOCD，还有 pyOCD、st-flash、probe-rs 等选择       ║
║                                                              ║
║  ⚠️ 关键限制：所有工具都需要 CYT2BL3 的 Flash 算法支持         ║
║     STM32 的算法 ≠ CYT2BL3 的算法                            ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

---

## 二、probe-rs 确认支持列表

### 2.1 支持的调试探针

| 探针 | 支持状态 | 接口 |
|------|:---:|------|
| **ST-Link v2** | ✅ | `probe-rs list` 可识别 |
| **ST-Link v3** | ✅ | 速度更快 |
| J-Link | ✅ | 行业标准 |
| CMSIS-DAP | ✅ | ARM 标准 |
| FTDI | ✅ | 通用 |
| Raspberry Pi Debug Probe | ✅ | 开源 |

### 2.2 支持的功能

```
probe-rs 能做什么：
  ✅ SWD / JTAG 协议
  ✅ Flash 编程（擦除+写入+校验）
  ✅ GDB 远程调试
  ✅ RTT (Real-Time Transfer) 日志
  ✅ VSCode 集成 (DAP 协议)
  ✅ 读取/写入内存
  ✅ 设置断点、单步
```

### 2.3 安装 probe-rs

```powershell
# 方法1: 下载预编译版本 (推荐)
# https://github.com/probe-rs/probe-rs/releases

# 方法2: cargo 安装 (需要 Rust)
cargo install probe-rs-tools

# 方法3: PowerShell 一键安装
irm https://github.com/probe-rs/probe-rs/releases/latest/download/probe-rs-tools-installer.ps1 | iex
```

### 2.4 验证 ST-Link 连接

```powershell
# 扫描所有调试探针
probe-rs list

# 期望输出:
# The following debug probes were found:
# 0: STLink V2 (VID: 0483, PID: 3748, Serial: ..., StLink)  ← 你的！
```

### 2.5 尝试连接 CYT2BL3

```powershell
# 看看 probe-rs 支持哪些芯片
probe-rs chip list | Select-String -Pattern "traveo|cyt|infineon"

# 如果没找到，可以用通用方式尝试连接
probe-rs info --probe 0483:3748

# 用 SWD 协议连接
probe-rs attach --chip <CHIP_NAME> --protocol swd
```

---

## 三、五大烧录工具对比

### 3.1 总览

```
烧录工具全家族：

┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  电脑 (host)                                                 │
│    │                                                         │
│    ├── OpenOCD ────── 最老牌、最全面、配置复杂               │
│    ├── probe-rs ───── 最新潮、Rust 生态、VSCode 完美         │
│    ├── pyOCD ──────── Python 实现、ARM 官方维护              │
│    ├── st-flash ───── 最轻量、仅 ST-Link、ST 官方部分支持    │
│    ├── J-Flash ────── 商业、最稳定 (需 J-Link 固件)         │
│    └── BlackMagic ─── 开源硬件、GDB 直连、把 ST-Link 刷成    │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 3.2 详细对比

| 特性 | OpenOCD | probe-rs | pyOCD | st-flash | J-Flash |
|------|:---:|:---:|:---:|:---:|:---:|
| **ST-Link 支持** | ✅ | ✅ | ✅ | ✅ 专用 | ⚠️ 需刷固件 |
| **免费开源** | ✅ | ✅ | ✅ | ✅ | ❌ 商业 |
| **SWD 协议** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **CYT2BL3 支持** | ⚠️ 需配置 | ⚠️ 需算法 | ⚠️ 需算法 | ❌ STM32 专用 | ✅ |
| **GDB 调试** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **VSCode 集成** | ✅ | ✅ 最佳 | ✅ | ❌ | ✅ |
| **烧录速度** | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| **学习曲线** | 陡峭 | 平缓 | 中等 | 简单 | 中等 |
| **安装方式** | 下载/编译 | cargo/下载 | pip install | apt/git | 下载安装 |
| **非 STM32 芯片** | ✅ | ✅ | ✅ | ❌ | ✅ |

---

## 四、各工具实战

### 4.1 pyOCD — Python 实现，ARM 官方维护

```powershell
# 安装
pip install pyocd

# 查看连接的探针
pyocd list --probes
# 期望: STLink V2 出现在列表中

# 查看支持的芯片
pyocd list --targets | Select-String traveo

# 尝试烧录 (如果有 CYT2BL3 支持)
pyocd flash -t cyt2bl3 build/firmware.hex

# 如果 CYT2BL3 不在支持列表中，用通用 Cortex-M 方式
pyocd commander
> connect
> load build/firmware.hex
> reset
```

### 4.2 st-flash / st-util (texane/stlink)

> ⚠️ **仅支持 STM32 芯片！** 不要用于 CYT2BL3。

```bash
# st-flash 是 ST-Link 专用工具
# 如果你在开发 STM32，它是很好的选择
# 但不适用于 CYT2BL3
```

### 4.3 Black Magic Probe (BMP)

```bash
# 把 ST-Link 刷成 Black Magic Probe 固件
# https://github.com/blackmagic-debug/blackmagic

# 刷完后，ST-Link 变成 BMP
# BMP 自带 GDB 服务器，不需要 OpenOCD！
arm-none-eabi-gdb build/firmware.elf
(gdb) target extended-remote /dev/ttyACM0
(gdb) monitor swdp_scan
(gdb) attach 1
(gdb) load
(gdb) run
```

### 4.4 probe-rs 完整用法

```powershell
# === 基本用法 ===

# 查看所有连接的探针
probe-rs list

# 查看支持的芯片列表
probe-rs chip list

# 查看芯片详细信息
probe-rs chip info STM32F407VG

# === 烧录 (需要芯片在支持列表中) ===

# 烧录 hex/elf
probe-rs download --chip <CHIP> build/firmware.hex
probe-rs run --chip <CHIP> build/firmware.elf

# === 调试 ===

# 启动 GDB 服务器
probe-rs gdb --chip <CHIP>

# 然后在另一个终端
arm-none-eabi-gdb build/firmware.elf
(gdb) target remote localhost:1337
(gdb) load
(gdb) continue

# === VSCode 集成 ===

# 安装 probe-rs VSCode 扩展
# 在 launch.json 中配置:
{
    "type": "probe-rs-debug",
    "request": "launch",
    "chip": "<CHIP_NAME>",
    "protocol": "swd",
    "programBinary": "build/firmware.elf"
}
```

---

## 五、CYT2BL3 的核心问题：Flash 算法

### 5.1 为什么工具不能直接用？

```
所有烧录工具的流程：

  1. 通过 SWD 建立连接        ← ✅ 所有工具都能做到
  2. 通过 DAP 访问内存        ← ✅ 所有工具都能做到
  3. 加载 Flash 算法到 RAM    ← ⚠️ 需要芯片特定的算法！
  4. 执行 Flash 编程命令      ← ⚠️ CYT2BL3 通过 CM0+ 系统调用
  5. 校验写入结果             ← ✅

瓶颈在第 3、4 步！
```

### 5.2 CYT2BL3 Flash 编程的特殊性

CYT2BL3 的 Flash 编程不是简单写寄存器，而是通过 **CM0+ 系统调用**：

```
外部 SWD → DAP → IPC 通知 → CM0+ 执行系统调用 → Flash 控制器 → 编程完成
```

这需要特殊的 Flash 算法（通常由 Infineon 在 Auto Flash Utility 的 OpenOCD 脚本中提供）。

### 5.3 当前各工具的支持状态

| 工具 | CYT2BL3 Flash 算法 | 来源 |
|------|:---:|------|
| **Infineon OpenOCD** (Auto Flash Utility) | ✅ 内置 | Infineon 官方 |
| **Infineon OpenOCD** (ModusToolbox) | ✅ 内置 | Infineon 官方 |
| **J-Flash** (SEGGER) | ✅ 内置 | SEGGER + Infineon |
| **probe-rs** | ❌ 待添加 | 需要贡献 Flash 算法 |
| **pyOCD** | ❌ 待添加 | 需要贡献 Flash 算法 |
| **通用 OpenOCD** | ❌ 无 | 需复制 Infineon 脚本 |

---

## 六、实操推荐路线

### 🥇 方案 A：Infineon OpenOCD + 任意 SWD 探针

```powershell
# 下载 Infineon Auto Flash Utility
# https://www.infineon.com/auto-flash-utility
# 它自带 OpenOCD + CYT2BL3 Flash 算法！

# 用 ST-Link 作为 SWD 探针
C:\...\Auto Flash Utility\bin\openocd.exe `
  -f interface/stlink.cfg `
  -c "transport select hla_swd" `
  -f target/traveo2_be_4m.cfg `
  -c "program build/firmware.hex verify reset exit"
```

> ⚠️ ST-Link + Infineon OpenOCD 可能因为 `hla_swd` 接口限制无法使用 `traveo2_be_4m.cfg`。需要测试。

### 🥈 方案 B：ST-Link → 刷 J-Link 固件 → J-Flash

```bash
# 1. 下载 SEGGER STLinkReflash
#    https://www.segger.com/downloads/jlink#STLink_Reflash
# 2. 运行，ST-Link 变 J-Link
# 3. 用 J-Flash / JLink.exe 烧录
JLink.exe -device CYT2BL3 -if SWD -speed 4000 -autoconnect 1
```

> ✅ 最稳定！J-Link 固件 + J-Flash 原生支持 CYT2BL3。

### 🥉 方案 C：用 prob-rs 做 SWD 调试 + 手动内存读写

```powershell
# probe-rs 至少可以做：
# 1. SWD 连接验证
# 2. 内存读写
# 3. 寄存器查看
# Flash 编程暂不支持，但可以先做连接测试

probe-rs list                    # 确认 ST-Link 识别
probe-rs info --probe 0483:3748  # 获取探针信息
```

---

## 七、总结

```
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║  📌 probe-rs 完全支持 ST-Link v2 ✅                          ║
║  📌 除了 OpenOCD，可选：                                      ║
║      probe-rs / pyOCD / st-flash / J-Flash / BlackMagic     ║
║                                                              ║
║  📌 CYT2BL3 的瓶颈不在探针，在 Flash 算法：                   ║
║      只有 Infineon 自带 OpenOCD 和 J-Link 有算法支持          ║
║                                                              ║
║  🥇 最推荐：ST-Link → 刷 J-Link → 完美支持 CYT2BL3           ║
║  🥈 备选：   Infineon OpenOCD + ST-Link (试试看)              ║
║  🥉 学习：   probe-rs 做 SWD 连接测试                         ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

---

## 附录：一键安装命令

```powershell
# ===== probe-rs =====
irm https://github.com/probe-rs/probe-rs/releases/latest/download/probe-rs-tools-installer.ps1 | iex

# ===== pyOCD =====
pip install pyocd

# ===== OpenOCD =====
# 推荐用 Infineon Auto Flash Utility 自带的版本
# 或 xpack: https://github.com/xpack-dev-tools/openocd-xpack

# ===== J-Link 固件 (从 ST-Link 转换) =====
# https://www.segger.com/downloads/jlink#STLink_Reflash
```

---

*报告版本：v1.0 | 2026-05-04*
