# CYT2BL3 编译烧录工作流分析与替换方案报告

> **日期**: 2026-05-05  
> **当前调试器**: WCH-Link (CMSIS-DAP) — 已通过 SWD 验证可用  
> **已失效工具**: J-Link — 硬件不可用  
> **目标**: 将 J-Link 烧录流程替换为 OpenOCD + WCH-Link

---

## 1. 当前工作流全景

```
                    ┌─────────────────────────┐
                    │    VSCode (Ctrl+Shift+B) │
                    │    默认: 🔨 build        │
                    └───────────┬─────────────┘
                                │ 调用 make all
                                ▼
┌───────────────────────────────────────────────────────────┐
│                      Makefile                              │
│                                                            │
│  make all    ──→ 编译 C + 汇编 → 链接 → firmware.elf       │
│                    │                  → firmware.hex        │
│                    │                  → firmware.bin        │
│                    │                  → firmware.map        │
│                                                            │
│  make flash  ──→ ❌ JLink.exe (你没有这个硬件!)             │
│                    └─ 生成 flash.jlink 脚本                  │
│                    └─ JLink.exe -device CYT2BL3 -if SWD     │
│                                                            │
│  make clean  ──→ rm -rf build/                             │
│                                                            │
│  make debug  ──→ (未实现, 只是 .PHONY 占位)                 │
└───────────────────────────────────────────────────────────┘
                                ▲
                                │ Ctrl+Shift+P → Tasks: Run
                                │
┌───────────────────────────────────────────────────────────┐
│                   .vscode/tasks.json                       │
│                                                            │
│  🔨 build   ──→ make all              (Ctrl+Shift+B 默认)  │
│  🧹 clean   ──→ make clean                                 │
│  🔄 rebuild ──→ make clean all                             │
│  🔥 flash   ──→ make flash  ← ❌ 调用 J-Link, 失败!        │
│                    └─ dependsOn: 🔨 build (先编译再烧录)     │
└───────────────────────────────────────────────────────────┘
```

### 工作流关系图

```
用户操作                      VSCode tasks          Makefile
─────────                    ────────────          ────────

Ctrl+Shift+B                → 🔨 build            → make all
                              (默认构建任务)          编译源码
                                                    ↓
                                               build/
                                               ├── firmware.elf
                                               ├── firmware.hex  ← 烧录用
                                               ├── firmware.bin
                                               └── firmware.map

Ctrl+Shift+P → 🔥 flash     → 🔥 flash            → make flash
                              (先 dependsOn build)    ❌ JLink.exe
                                                     (J-Link硬件不存在)

Ctrl+Shift+P → 🔄 rebuild   → 🔄 rebuild           → make clean all

Ctrl+Shift+P → 🧹 clean     → 🧹 clean             → make clean
```

---

## 2. 失败点分析

### 2.1 `make flash` — 当前命令

```makefile
# Makefile:71-80
flash: $(BUILD_DIR)/$(TARGET).hex
	@echo "🔥 烧录中 (J-Link)..."
	@echo "r" > $(BUILD_DIR)/flash.jlink          # 复位
	@echo "h" >> $(BUILD_DIR)/flash.jlink         # 暂停
	@echo "loadfile $(BUILD_DIR)/$(TARGET).hex" >> $(BUILD_DIR)/flash.jlink  # 烧录HEX
	@echo "r" >> $(BUILD_DIR)/flash.jlink         # 复位
	@echo "g" >> $(BUILD_DIR)/flash.jlink         # 运行
	@echo "qc" >> $(BUILD_DIR)/flash.jlink        # 退出
	@JLink.exe -device CYT2BL3 -if SWD -speed 4000 -autoconnect 1 -CommanderScript $(BUILD_DIR)/flash.jlink
```

### 2.2 失败原因

| 步骤 | 状态 | 原因 |
|------|:--:|------|
| 生成 `flash.jlink` 脚本 | ✅ | 正常 |
| 调用 `JLink.exe` | ❌ | **J-Link 硬件不存在** — 用户用的是 WCH-Link |
| 编译 `firmware.hex` | ✅ | 正常 |

### 2.3 `${TARGET}.hex` 依赖

`make flash` 依赖 `build/firmware.hex`，如果 `.hex` 不存在会先触发 `make all`。所以 `make flash` 隐含了"先编译再烧录"的逻辑。

但当前 `make flash` 没有依赖 `.elf`/`.hex` 的自动检测——它用 `$(BUILD_DIR)/$(TARGET).hex` 作为依赖，只有文件不存在时才重新编译。如果源码改了但没重新 make，`flash` 会烧录旧固件。

---

## 3. 已验证可用的替换命令（OpenOCD + WCH-Link）

```powershell
# 在项目根目录 D:\03-Wheel_leg_CYT2BL3 执行 — 已验证烧录成功!
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

### 命令逐行功能

| 参数 | 功能 |
|------|------|
| `-s "tools/.../scripts"` | OpenOCD 脚本搜索路径 |
| `-f "interface/cmsis-dap.cfg"` | 使用 CMSIS-DAP 调试器 (WCH-Link) |
| `-f "target/infineon/cyt2bl.cfg"` | CYT2BL3 芯片配置 |
| `adapter speed 2000` | SWD 时钟 2MHz |
| `init` | 初始化调试链路 (连接芯片, 识别核心, 配置DAP) |
| `targets traveo2_be_4m.cpu.cm0` | 选择 CM0+ 核心 (Flash 烧录由 CM0+ 控制) |
| `halt 3000` | 🔑 暂停 CM0+ (不复位, 避免 DP 重连失败) |
| `flash write_image erase ...` | 擦除 + 烧录 HEX |
| `verify_image ...` | 校验写入内容 |
| `exit` | 完成后退出 |

---

## 4. 需要修改的文件

### 4.1 `Makefile` — 修改 `flash` 目标

**当前 (❌ 失败)**:
```makefile
flash: $(BUILD_DIR)/$(TARGET).hex
	@echo "🔥 烧录中 (J-Link)..."
	@echo "r" > $(BUILD_DIR)/flash.jlink
	@echo "h" >> $(BUILD_DIR)/flash.jlink
	@echo "loadfile $(BUILD_DIR)/$(TARGET).hex" >> $(BUILD_DIR)/flash.jlink
	@echo "r" >> $(BUILD_DIR)/flash.jlink
	@echo "g" >> $(BUILD_DIR)/flash.jlink
	@echo "qc" >> $(BUILD_DIR)/flash.jlink
	@JLink.exe -device CYT2BL3 -if SWD -speed 4000 -autoconnect 1 -CommanderScript $(BUILD_DIR)/flash.jlink
	@echo "✅ 烧录完成！"
```

**改为 (✅ 可用)**:
```makefile
# ========== 工具路径 ==========
OPENOCD = tools/infineon-openocd/bin/openocd.exe
OPENOCD_SCRIPTS = tools/infineon-openocd/scripts

# ========== 烧录 (OpenOCD + CMSIS-DAP) ==========
flash: $(BUILD_DIR)/$(TARGET).hex
	@echo "🔥 烧录中 (OpenOCD + WCH-Link)..."
	@$(OPENOCD) -s "$(OPENOCD_SCRIPTS)" \
		-f "interface/cmsis-dap.cfg" \
		-f "target/infineon/cyt2bl.cfg" \
		-c "adapter speed 2000" \
		-c "init" \
		-c "targets traveo2_be_4m.cpu.cm0" \
		-c "halt 3000" \
		-c "flash write_image erase $(BUILD_DIR)/$(TARGET).hex" \
		-c "verify_image $(BUILD_DIR)/$(TARGET).hex" \
		-c "exit"
	@echo "✅ 烧录完成！"
```

**改动点**:
- ✅ 删除 J-Link Commander 脚本生成逻辑
- ✅ 删除 `JLink.exe` 调用
- ✅ 添加 `OPENOCD` / `OPENOCD_SCRIPTS` 变量
- ✅ 替换为 OpenOCD + CMSIS-DAP 命令
- ✅ 反斜杠 `\` 续行（Makefile 语法）

### 4.2 `.vscode/tasks.json` — 修改 flash 任务

**当前 (❌)**:
```json
{
    "label": "🔥 flash",
    "type": "shell",
    "command": "make",
    "args": ["flash"],
    "group": "build",
    "options": {
        "env": {
            "PATH": "C:\\Users\\29344\\.eide\\bin\\builder\\msys\\bin;${env:PATH}"
        }
    },
    "dependsOn": ["🔨 build"]
}
```

**改为 (✅)**:
```json
{
    "label": "🔥 flash (OpenOCD)",
    "type": "shell",
    "command": "make",
    "args": ["flash"],
    "group": "build",
    "options": {
        "env": {
            "PATH": "C:\\Users\\29344\\.eide\\bin\\builder\\msys\\bin;${env:PATH}"
        }
    },
    "dependsOn": ["🔨 build"],
    "presentation": {"reveal": "always", "panel": "dedicated"}
}
```

**改动点**:
- ✅ Label 改为 `"🔥 flash (OpenOCD)"`（明确标注）
- ✅ 增加 `"presentation"` 配置（显示烧录输出面板）
- ✅ `command` 和 `args` 不变，仍然是 `make flash`（因为 Makefile 已改）
- ✅ `dependsOn` 不变（先 build 再 flash）

---

## 5. 修改后的完整工作流

```
                    ┌─────────────────────────┐
                    │    VSCode (Ctrl+Shift+B) │
                    │    默认: 🔨 build        │
                    └───────────┬─────────────┘
                                │ 调用 make all
                                ▼
┌───────────────────────────────────────────────────────────┐
│                      Makefile (修改后)                     │
│                                                            │
│  make all    ──→ GCC ARM 编译 → firmware.elf               │
│                    │              → firmware.hex (ihex)     │
│                    │              → firmware.bin (binary)   │
│                    │              → firmware.map            │
│                                                            │
│  make flash  ──→ ✅ OpenOCD + CMSIS-DAP                    │
│                    └─ adapter speed 2000 (SWD)              │
│                    └─ init → halt CM0+                      │
│                    └─ flash write_image erase firmware.hex │
│                    └─ verify_image firmware.hex             │
│                    └─ exit                                  │
│                                                            │
│  make clean  ──→ rm -rf build/                             │
└───────────────────────────────────────────────────────────┘
                                ▲
                                │
┌───────────────────────────────────────────────────────────┐
│               .vscode/tasks.json (修改后)                  │
│                                                            │
│  🔨 build        ──→ make all        (Ctrl+Shift+B 默认)  │
│  🧹 clean        ──→ make clean                           │
│  🔄 rebuild      ──→ make clean all                       │
│  🔥 flash(OCD)   ──→ make flash ← ✅ 用 OpenOCD + WCH-Link│
│                       └─ dependsOn: 🔨 build              │
└───────────────────────────────────────────────────────────┘
```

---

## 6. 各文件修改汇总

| 文件 | 改动性质 | 改动量 |
|------|---------|:---:|
| **Makefile** | 修改 `flash` 目标，删除 J-Link 逻辑，替换为 OpenOCD 命令 | ~15 行改 |
| **.vscode/tasks.json** | 修改 `🔥 flash` 任务，更新标签和显示配置 | ~3 行改 |

**不需要改的文件**:
- `src/` — 源码不变
- `libs/` — 库不变
- `config_cat1a_cyt2xx.cfg` — TIMEOUT 变量已加，保持不变
- `cyt2bl.cfg` — OpenOCD 目标配置，保持不变
- 其他 `.vscode/` 配置 — 不变

---

## 7. 构建烧录全流程（修改后）

```
完整工作流:
────────────────────────────────────────────────────────────

开发阶段:
  $ make all               ← 编译 (Ctrl+Shift+B)

烧录阶段:
  $ make flash             ← 编译+烧录 (one-shot)
  或
  Ctrl+Shift+P → 🔥 flash  ← 在 VSCode 里一键编译+烧录

清理:
  $ make clean             ← 删除编译产物

从零构建:
  $ make clean all flash   ← 清理→编译→烧录

仅重新烧录 (源码没变):
  $ make flash             ← 已编译则跳过编译, 直接烧录
```

---

## 8. Makefile 是否是"管理一切"？

**是的，Makefile 是整个项目的构建中心。**

```
工作流层次:
──────────────────────────────────────────

  用户层        VSCode tasks.json
                 ↓ 封装为任务
  调度层        make (通过 MSYS2/MinGW)
                 ↓ 解析 Makefile
  构建层        arm-none-eabi-gcc (编译)
                arm-none-eabi-objcopy (格式转换)
                openocd.exe (烧录)
```

| 层 | 职责 | 何时修改 |
|----|------|---------|
| `tasks.json` | VSCode 用户界面封装 | 加任务/改快捷键/改显示方式 |
| `Makefile` | 构建逻辑 (编译规则 + 烧录命令) | 改编译参数、换工具链、替换烧录器 |
| 源码 | 功能代码 | 改功能 |

---

## 9. 快速参考卡片（修改后）

```
╔══════════════════════════════════════════════════════════╗
║          CYT2BL3 编译烧录速查卡 (修改后)                  ║
╠══════════════════════════════════════════════════════════╣
║                                                          ║
║  VSCode:                                                 ║
║    Ctrl+Shift+B    → 编译 (默认)                         ║
║    Ctrl+Shift+P → 🔥 flash(OCD) → 编译+烧录              ║
║                                                          ║
║  终端:                                                   ║
║    make all        → 编译                                ║
║    make flash      → 编译+烧录                           ║
║    make clean      → 清理                                ║
║                                                          ║
║  调试器: WCH-Link (CMSIS-DAP, SWD)                      ║
║  烧录器: OpenOCD (Infineon 定制版)                       ║
║  文件:   build/firmware.hex (Intel HEX)                  ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
```

---

> 📎 **关联文档**:
> - [OpenOCD 烧录实操成功报告](./CYT2BL3_OpenOCD_烧录实操成功报告.md)
> - [OpenOCD 配置缺陷最终定责报告](./CYT2BL3_OpenOCD配置缺陷_最终定责报告.md)
