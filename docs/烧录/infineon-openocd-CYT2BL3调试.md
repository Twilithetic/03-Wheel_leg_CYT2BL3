# Infineon OpenOCD + WCH-Link 调试 CYT2BL3

## 问题

> infineon-openocd 可以用来调试 CYT2BL3 吗？怎么做？

## 原理

OpenOCD 作为 **GDB Server**，通过 SWD 接口连接芯片，提供 GDB 远程调试端口：

```
┌─────────────┐     ┌──────────────────┐     ┌──────────┐
│  VSCode/GDB  │ ←→ │  OpenOCD Server   │ ←→ │ CYT2BL3  │
│  (PC)        │ TCP │  GDB 3333(CM0+)   │ SWD │          │
│              │     │  GDB 3334(CM4)    │     │          │
└─────────────┘     └──────────────────┘     └──────────┘
```

CYT2BL3 双核：
- **CM0+** (cortex_m) → GDB port `3333` — 负责 Flash/SROM 操作，通常不需要调试
- **CM4** (cortex_m) → GDB port `3334` — 用户代码，**调试这个核心**

> 实测验证：OpenOCD 成功启动 GDB Server（见分析文档实测记录）

## 方法一：VSCode Cortex-Debug 扩展（推荐 ⭐）

### 1. 安装扩展

```powershell
code --install-extension marus25.cortex-debug
```

Cortex-Debug 原生支持 OpenOCD，会自动启动/停止 GDB Server。

### 2. launch.json 配置

已配好，直接用。`F5` 一键启动调试：

| 配置名 | 说明 |
|--------|------|
| `🐛 OpenOCD 调试 CM4 (WCH-Link)` | 调试用户代码（CM4 核心） |
| `🐛 OpenOCD 调试 CM0+ (WCH-Link)` | 调试 CM0+ 核心（特殊情况） |
| `🔥 OpenOCD 烧录并调试 (WCH-Link)` | 先烧录再进入调试 |

### 3. 使用方式

1. `Ctrl+Shift+B` 编译
2. `F5` 启动调试 → 自动烧录 + 停在 `main()` 入口
3. 设置断点 → `F10` 单步 → `F5` 继续运行
4. 左侧 `VARIABLES` 面板查看变量值

## 方法二：命令行 GDB 调试

### 1. 启动 GDB Server（终端 1）

```bash
make gdb-server
```

或手动：

```powershell
& "tools\infineon-openocd\bin\openocd.exe" `
    -s "tools\infineon-openocd\scripts" `
    -f interface/cmsis-dap.cfg `
    -c "adapter serial F3EE7D40070E" `
    -f target/infineon/cyt2bl.cfg
```

OpenOCD 会保持运行，打印：
```
Info : Listening on port 3333 for gdb connections
Info : Listening on port 3334 for gdb connections
```

### 2. 连接 GDB（终端 2）

```bash
make debug-cm4
```

或手动：

```powershell
C:/Users/29344/.eide/tools/gcc_arm/bin/arm-none-eabi-gdb.exe `
    -ex "target extended-remote localhost:3334" `
    -ex "monitor reset init" `
    -ex "load" `
    -ex "break main" `
    -ex "continue" `
    build/firmware.elf
```

### 3. GDB 常用命令

| 命令 | 说明 |
|------|------|
| `target extended-remote localhost:3334` | 连接 CM4 核心 |
| `monitor reset init` | 复位并初始化 |
| `monitor halt` | 暂停 CPU |
| `monitor reset run` | 复位并运行 |
| `load` | 下载固件到 Flash |
| `break main` | 在 main 设断点 |
| `continue` / `c` | 继续运行 |
| `step` / `s` | 单步进入 |
| `next` / `n` | 单步跳过 |
| `print var` / `p var` | 打印变量值 |
| `info registers` | 查看寄存器 |
| `bt` | 查看调用栈 |
| `quit` | 退出 GDB |
