# CYT2BL3 OpenOCD 烧录实操成功报告

> **日期**: 2026-05-05  
> **芯片**: Infineon TRAVEO™ T2G CYT2BL3CXE (Silicon 0xEA02, Rev A0)  
> **调试探针**: WCH-Link (CMSIS-DAP v2, VID:PID=0x1a86:0x8012, FW 2.0.0)  
> **OpenOCD**: Infineon 定制版 0.12.0+dev-5.16.1.4486  
> **固件**: LED 闪烁 (P23.7, SysTick 1ms, 500ms 翻转)

---

## 1. 固件文件说明

### 1.1 编译产物位置

```
build/
├── firmware.elf    ← ELF (调试符号，80.7 KB)
├── firmware.hex    ← Intel HEX (烧录用，16.4 KB)
├── firmware.bin    ← 原始二进制 (5.8 KB)
├── firmware.map    ← 内存映射
└── src/
    ├── main.o
    └── startup_cyt2bl3_cm4.o
```

### 1.2 固件内容

| 项目 | 详情 |
|------|------|
| 源文件 | `src/main.c` + `src/startup_cyt2bl3_cm4.S` |
| 核心 | Cortex-M4F @ 160MHz |
| 功能 | P23.7 LED 闪烁 (500ms 亮 / 500ms 灭) |
| 定时器 | SysTick (CMSIS 标准 API, 1ms 中断) |
| GPIO | 直接寄存器操作 (TRAVEO T2G GPIO Port 23) |
| 依赖 | 仅 ARM CMSIS，无 Infineon HAL/PDL |

### 1.3 编译方式 (Makefile)

```makefile
# 工具链: arm-none-eabi-gcc (eide)
# 编译命令:
make all          # 编译 → 生成 .elf + .hex + .bin
make clean        # 清理 build/
make flash        # J-Link 烧录 (需 J-Link 硬件)
```

编译参数：
```
-mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16
-O0 -g3                          # 调试优化
-T src/cyt2bl3_flash.ld          # Flash 链接脚本
--specs=nano.specs               # newlib-nano
```

---

## 2. OpenOCD 烧录命令

### 2.1 ✅ 成功命令（推荐）

```powershell
# 在项目根目录 D:\03-Wheel_leg_CYT2BL3 下执行：
& "tools/infineon-openocd/bin/openocd.exe" `
  -s "tools/infineon-openocd/scripts" `
  -f "interface/cmsis-dap.cfg" `
  -f "target/infineon/cyt2bl.cfg" `
  -c "adapter speed 2000" `
  -c "init" `
  -c "targets traveo2_be_4m.cpu.cm0" `
  -c "halt 3000" `
  -c "flash write_image erase build/firmware.hex" `
  -c "verify_image build/firmware.hex" `
  -c "exit"
```

### 2.2 命令逐行解析

| 参数 | 作用 |
|------|------|
| `-s "tools/.../scripts"` | 设置脚本搜索路径 |
| `-f "interface/cmsis-dap.cfg"` | 使用 CMSIS-DAP 调试器（WCH-Link 兼容） |
| `-f "target/infineon/cyt2bl.cfg"` | 加载 CYT2BL 芯片配置 |
| `-c "adapter speed 2000"` | SWD 时钟 2000 kHz（稳定速度） |
| `-c "init"` | 初始化调试链路 |
| `-c "targets traveo2_be_4m.cpu.cm0"` | 选择 CM0+ 核心（Flash 烧录由 CM0+ 控制） |
| `-c "halt 3000"` | 🔑 **关键技巧** — 暂停 CM0+ 而非 reset |
| `-c "flash write_image erase build/firmware.hex"` | 擦除 + 烧录 HEX |
| `-c "verify_image build/firmware.hex"` | 校验写入内容 |
| `-c "exit"` | 完成后退出 |

### 2.3 🔑 核心技巧：用 `halt` 替代 `reset init`

这是这次烧录成功的关键发现！

| 方式 | 结果 | 原因 |
|------|:--:|------|
| `-c "program ..."` 或 `-c "reset init"` | ❌ 失败 | `reset` 后 WCH-Link 重连 DP 太慢，触发 `reset-deassert-post` 事件时 DP 不可达 |
| `-c "halt 3000"` | ✅ 成功 | 不触发芯片复位，直接在当前运行状态下暂停 CM0+，DP 连接保持稳定 |

**原理**：CYT2BL3 的 OpenOCD 配置 (`base_cyt2xx.cfg`) 中注册了 `reset-deassert-post` 事件回调，在芯片复位解除后会尝试通过 DAP 配置 Flash 控制器。WCH-Link 在芯片复位期间 SWD 物理层会暂时断开，重连速度不够快，导致事件回调中的 DAP 访问失败。跳过复位阶段就避开了这个时序问题。

> 💡 如果你的调试器支持硬件复位引脚 (nRESET/SRST)，也可以用 `reset_config srst_only` 来使用 XRES 硬件复位。

---

## 3. 烧录过程时间线

```
[00:00.0] OpenOCD 启动，加载配置
[00:00.2] CMSIS-DAP 初始化成功
          - VID:PID = 0x1a86:0x8012
          - SWD 模式，FW v2.0.0
[00:00.3] SWD DPIDR = 0x6ba02477 ✅
[00:00.4] CM0+ 检测到 (r0p1)
[00:00.5] Flash 信息:
          - Silicon:  0xEA02
          - Family:   0x108
          - Revision: 0x11 (A0)
          - 型号:     CYT2BL3CXE
          - Main Flash: 4160 KB
          - Work Flash: 128 KB
          - 保护状态: NORMAL ✅
[00:00.6] CM4 检测到 (r0p1)
[00:00.8] halt CM0+ → 成功暂停
[00:01.0] Erasing 扇区...     [################################] 100%
[00:01.3] Programming 6144 bytes @ 20.8 KiB/s   [################################] 100%
[00:01.4] Verify 5944 bytes @ 193.1 KiB/s       ✅ 全部正确
[00:01.5] 完成！芯片断电重上即可运行
```

**总耗时**: 约 1.5 秒（不含 OpenOCD 启动时间）

---

## 4. WCH-Link 使用注意事项

### 4.1 已验证

| 功能 | 状态 |
|------|:--:|
| SWD 连接/识别 | ✅ |
| DP/AP 枚举 | ✅ |
| Flash 烧录 | ✅ |
| Flash 校验 | ✅ |
| JTAG 连接 | ❌ (WCH-Link 普通版硬件限制) |
| 芯片复位 | ⚠️ (DP 重连慢) |

### 4.2 推荐配置

```
SWD 时钟: 1000-2000 kHz (稳定)
接线: SWCLK + SWDIO + GND (最少 3 根线)
      nRESET 可选 (如需要硬件复位)
```

### 4.3 已知问题与解决

| 问题 | 解决方案 |
|------|---------|
| reset 后 DP 读不到 | 用 `halt` 代替 `reset init` |
| 烧录后芯片不运行 | 重新上电或按复位键 |
| OpenOCD 退出时报 DP error | 正常现象，烧录已完成 |

---

## 5. 其他烧录方式速查

### 5.1 J-Link（Makefile 自带）

```bash
make flash
# 等价于:
JLink.exe -device CYT2BL3 -if SWD -speed 4000 -autoconnect 1
> loadfile build/firmware.hex
> r
> g
```

### 5.2 probe-rs（仅探测/调试，不支持烧录）

```bash
# 探测芯片信息
probe-rs info

# GDB 调试（仅 RAM）
probe-rs gdb-server
```

### 5.3 IAR EWARM

直接在 IDE 中 Download and Debug，原生支持 TRAVEO T2G。

---

## 6. Makefile 构建系统速查

```bash
# 编译（生成 .elf + .hex + .bin）
make all

# 清理编译产物
make clean

# J-Link 烧录
make flash

# GDB 调试
make debug
```

---

## 7. 成功烧录的完整输出

```
Open On-Chip Debugger 0.12.0+dev-5.16.1.4486 (2026-04-14-18:10)

Info : Using CMSIS-DAPv2 interface with VID:PID=0x1a86:0x8012, serial=F3EE7D40070E
Info : CMSIS-DAP: SWD supported
Info : CMSIS-DAP: FW Version = 2.0.0
Info : CMSIS-DAP: Interface Initialised (SWD)
Info : clock speed 2000 kHz

Info : SWD DPIDR 0x6ba02477                              ← DP 识别成功
Info : [traveo2_be_4m.cpu.cm0] Cortex-M0+ r0p1 processor detected
Info : [traveo2_be_4m.cpu.cm0] target has 4 breakpoints, 2 watchpoints

***************************************
** Silicon: 0xEA02, Family: 0x108, Rev.: 0x11 (A0)
** Detected Device: CYT2BL3CXE                      ← 芯片型号识别
** Flash Boot version: 3.1.0.556
** Chip Protection: NORMAL                           ← 未锁定，可烧录
***************************************

Info : [traveo2_be_4m.cpu.cm4] Cortex-M4 r0p1 processor detected

Warn : [traveo2_be_4m.cpu.cm0] target was in unknown state when halt was requested
auto erase enabled

[100%] [################################] [ Erasing     ]
[100%] [################################] [ Programming ]
wrote 6144 bytes from file firmware.hex in 0.289s (20.788 KiB/s)

verified 5944 bytes in 0.030s (193.123 KiB/s)        ← ✅ 校验通过！
```

---

## 8. 快速参考卡片

```
╔═══════════════════════════════════════════════════════════╗
║           CYT2BL3 OpenOCD 烧录速查卡                      ║
╠═══════════════════════════════════════════════════════════╣
║                                                           ║
║  编译:  make all          (生成 build/firmware.hex)       ║
║  烧录:  openocd -f interface/cmsis-dap.cfg                ║
║                 -f target/infineon/cyt2bl.cfg             ║
║                 -c "init"                                 ║
║                 -c "targets traveo2_be_4m.cpu.cm0"        ║
║                 -c "halt 3000"           ← 关键！         ║
║                 -c "flash write_image erase firmware.hex" ║
║                 -c "verify_image firmware.hex"            ║
║                 -c "exit"                                 ║
║                                                           ║
║  运行:  重新上电 / 按复位键                               ║
║                                                           ║
║  调试器: WCH-Link (CMSIS-DAP, SWD)                       ║
║  时钟:   adapter speed 2000                               ║
║  接线:   SWCLK + SWDIO + GND                             ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
```

> 📎 **关联文档**:
> - [CYT2BL3 调试接口 ADIv5 兼容性分析](./CYT2BL3_调试接口_ADIv5兼容性分析报告.md)
> - [CYT2BL3 probe-rs 探测分析](./CYT2BL3_probe-rs_探测实测分析报告.md)
> - [CYT2BL3 probe-rs 烧录支持分析](./CYT2BL3_probe-rs_烧录支持分析报告.md)
