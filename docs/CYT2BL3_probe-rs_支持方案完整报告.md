# probe-rs 支持 CYT2BL3 的完整方案报告

> **日期**: 2026-05-05  
> **目标**: 列出让 probe-rs 支持 CYT2BL3 所需的所有文件和步骤  
> **核心发现**: Infineon 官方提供了 CMSIS-Pack (含 .FLM Flash 算法)，可直接用 `target-gen` 提取！

---

## 1. 好消息：Infineon 官方有 CMSIS-Pack！

在 Arm Keil 网站上找到了 Infineon 官方发布的 DFP (Device Family Pack)：

| Pack 名称 | 版本 | 说明 |
|-----------|------|------|
| **T2G-B-E_DFP** | 1.2.1 | **Infineon Traveo T2G Body Entry** ← CYT2BL 属于这个！ |
| T2G-B-H_DFP | 1.2.1 | Infineon Traveo T2G Body High |
| T2G-C-2D_DFP | 1.0.0 | Infineon Traveo T2G Cluster |

> 📎 来源: https://www.keil.arm.com/packs/ — 搜索 "Infineon"

### Pack 内容（CMSIS 标准）

```
T2G-B-E_DFP.pack (本质是 ZIP 文件)
├── *.pdsc              ← XML 包描述
├── Flash/
│   ├── CYT2BL3.FLM    ← Flash 烧录算法 (ELF 格式!)
│   ├── CYT2BL4.FLM
│   └── ...
├── SVD/
│   └── CYT2BL3.svd    ← 外设寄存器描述
└── Device/
    └── ...             ← 启动文件、头文件
```

---

## 2. 需要准备的文件和资料

### 2.1 必须的材料

| 序号 | 材料 | 来源 | 用途 |
|:--:|------|------|------|
| 1 | **T2G-B-E_DFP CMSIS-Pack** | [Arm Keil Packs](https://www.keil.arm.com/packs/) → 搜 "Infineon" | 含 Flash 算法 (.FLM)、SVD、设备描述 |
| 2 | **probe-rs 源码** | 已有 (`tools/probe-rs-src/`) | 构建工具和目标目录 |
| 3 | **Rust 工具链** | `rustup` | 编译 probe-rs 和 `target-gen` |
| 4 | **CYT2BL3 Datasheet** | 已有 (`docs/CYT2BL3核心板资料...`) | 验证内存映射 |
| 5 | **ARM CMSIS Pack spec** | 在线 | Flash 算法 API 参考 |

### 2.2 可选的辅助材料

| 序号 | 材料 | 用途 |
|:--:|------|------|
| 6 | CYT2BL3 TRM | 验证外设基址 |
| 7 | Infineon SDL (Sample Driver Library) | Flash 驱动参考 |
| 8 | PSOC6 YAML (已有) | 同架构 Infineon 芯片的 YAML 模板参考 |

---

## 3. 实施步骤（三选一）

### 🥇 方案 A：自动提取（最简单，推荐！）

```bash
# Step 1: 下载 CMSIS-Pack
# 从 https://www.keil.arm.com/packs/ 下载 T2G-B-E_DFP

# Step 2: 用 target-gen 自动提取
cd tools/probe-rs-src
cargo run --release --bin target-gen -- \
    pack extract T2G-B-E_DFP.1.2.1.pack \
    --output probe-rs/targets/CYT2BL_Series.yaml

# Step 3: 构建 probe-rs (包含新 target)
cargo build --release

# Step 4: 验证
./target/release/probe-rs chip list | grep CYT2BL
./target/release/probe-rs chip info CYT2BL3BAS
```

**`target-gen` 会自动**:
- ✅ 解析 `.pdsc` XML → 提取设备列表
- ✅ 解析 `.FLM` ELF 文件 → 提取 Flash 算法代码 (base64 编码)
- ✅ 解析 SVD → 提取内存映射
- ✅ 生成完整的 YAML 芯片描述

### 🥈 方案 B：手动编写 YAML（备选）

如果自动提取失败，参考 PSOC6 模板手动编写：

```yaml
# CYT2BL_Series.yaml
name: cyt2bl_series
manufacturer:
  id: 0x34          # JEP106: Infineon (原 Cypress)
  cc: 0x0

# === 芯片检测 ===
chip_detection:
- !ArmPart
  part: 0xea02       # ← probe-rs info 检测到的 Part Number!
  # 或使用 Infineon 专用检测方式:
  # - !InfineonT2gSiliconId ...

# === Flash 算法 ===
flash_algorithms:
- name: cyt2bl_main_flash
  description: CYT2BL3 Code Flash (4160KB)
  default: true
  instructions: <base64 from .FLM>  # target-gen 自动填充
  load_address: 0x08000800
  pc_init: 0x08000001
  pc_program_page: 0x080000xx
  pc_erase_sector: 0x080000xx
  pc_erase_all: 0x080000xx
  data_section_offset: 0x400
  flash_properties:
    address_range:
      start: 0x10000000
      end: 0x10410000
    page_size: 512
    erased_byte_value: 0x00
    program_page_timeout: 100
    erase_sector_timeout: 3000
    sectors:
    - size: 512
      address: 0x10000000
    # ... 更多扇区

# === 芯片变体 ===
variants:
- name: CYT2BL3BAS
  cores:
  - name: cm0p
    type: armv6m
    core_access_options: !Arm
      ap: !v1 1          # AP#1 = CM0+
  - name: cm4
    type: armv7em
    core_access_options: !Arm
      ap: !v1 2          # AP#2 = CM4F
  memory_map:
  - !Ram
    name: SRAM
    range:
      start: 0x08000000
      end: 0x08080000    # 512KB
    cores: [cm0p, cm4]
  - !Nvm
    name: CodeFlash
    range:
      start: 0x10000000
      end: 0x10410000    # 4160KB + 128KB Work
    cores: [cm0p, cm4]
    access:
      write: false
      boot: true
  flash_algorithms:
  - cyt2bl_main_flash
```

### 🥉 方案 C：编写 Rust Flash Algorithm（最可控）

```bash
# 使用 probe-rs 的 flash-algorithm 模板
git clone https://github.com/probe-rs/flash-algorithm
cd flash-algorithm

# 修改 src/main.rs 实现 TRAVEO T2G 的 Flash 操作
# (通过 SROM API 调用: IP通信 CM0+ IRQ0)

# 编译
cargo build --release

# 提取为 YAML
target-gen elf target/thumbv6m-none-eabi/release/flash-algo CYT2BL.yaml
```

---

## 4. 关键技术细节

### 4.1 Flash 算法 API (CMSIS 标准)

probe-rs 需要的 Flash 算法函数：

```c
// 标准 CMSIS Flash Algorithm API
int Init(uint32_t adr, uint32_t clk, uint32_t fnc);
int UnInit(uint32_t fnc);
int EraseSector(uint32_t adr);
int ProgramPage(uint32_t adr, uint32_t sz, uint8_t *buf);
int Verify(uint32_t adr, uint32_t sz, uint8_t *buf);   // 可选
int EraseChip(void);                                      // 可选
int BlankCheck(uint32_t adr, uint32_t sz, uint8_t pat);  // 可选
```

### 4.2 TRAVEO T2G Flash 操作特殊性

> 来自 Infineon AN220242:
> *"In TRAVEO™ T2G family, flash operations are implemented as system calls. System calls are executed inside CM0+ IRQ0. The CM4/CM7 user code requests the system call by acquiring the IPC and writing the SROM function opcode and parameters to the IPC DATA register."*

这意味着 Flash 算法必须：
1. 运行在 CM0+ 上
2. 通过 IPC 调用 SROM API
3. 处理 IRQ0 中断

**CMSIS-Pack 中的 .FLM 文件已经处理了这些！**

### 4.3 CYT2BL3 内存映射

| 区域 | 起始地址 | 大小 | 说明 |
|------|----------|------|------|
| Code Flash | `0x10000000` | 4160 KB | 主代码存储 |
| Work Flash | `0x14000000` | 128 KB | 频繁擦写区 |
| SRAM | `0x08000000` | 512 KB | 系统 RAM |
| SFlash | `0x17000000` | — | 系统配置 Flash |

### 4.4 chip_detection 方式选择

probe-rs 支持多种芯片检测方式：

```yaml
# 方式 1: ARM Part Number (probe-rs info 已经读到了)
- !ArmPart
  part: 0xea02

# 方式 2: Infineon PSoC Siid (PSOC6 使用)
- !InfineonPsocSiid
  family_id: 0x108
  silicon_ids:
    0xea02: CYT2BL3CXE

# 方式 3: 通用 (无自动检测，手动指定芯片名)
```

---

## 5. 需要的工具链

| 工具 | 用途 | 安装方式 |
|------|------|---------|
| `rustup` | Rust 工具链 | `winget install Rustlang.Rustup` |
| `cargo` | Rust 包管理 | 随 rustup 安装 |
| `target-gen` | CMSIS-Pack → YAML 转换 | `cargo install probe-rs-tools` 或源码编译 |
| `probe-rs` | 调试/烧录 | `cargo install probe-rs-tools` 或源码编译 |

---

## 6. 快速上手流程

```
┌─────────────────────────────────────────────────────────┐
│ 完整流程 (从零到能用)                                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. 下载 T2G-B-E_DFP CMSIS-Pack                        │
│     ↓                                                    │
│  2. target-gen pack extract → CYT2BL_Series.yaml        │
│     ↓                                                    │
│  3. 放入 probe-rs/targets/ 目录                         │
│     ↓                                                    │
│  4. cargo build --release                               │
│     ↓                                                    │
│  5. probe-rs chip list | grep CYT2BL ← 验证             │
│     ↓                                                    │
│  6. probe-rs download --chip CYT2BL3BAS firmware.hex    │
│     ↓                                                    │
│  7. ✅ 烧录成功!                                         │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 7. 与 OpenOCD 方案对比

| | OpenOCD (Infineon 版) | probe-rs |
|--|:--:|:--:|
| SWD 重连 | ❌ 有缺陷 | ✅ 架构级鲁棒 |
| HSIOM/PSoC6 经验 | ❌ 无 | ✅ 已针对优化 |
| 添加新芯片 | 手工 Tcl 脚本 | `target-gen` 自动 |
| Flash 算法 | 已有 .FLM | 复用同一 .FLM |
| 语言 | C + Tcl | Rust |
| 命令行 | 长命令 | 简洁 (`probe-rs download`) |

---

## 8. 总结

```
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║  需要什么文件？                                              ║
║  1. T2G-B-E_DFP CMSIS-Pack (Infineon 官方, 免费下载)        ║
║  2. probe-rs 源码 (已有)                                     ║
║  3. Rust 工具链                                              ║
║                                                              ║
║  难度有多高？                                                ║
║  方案 A (自动提取): ⭐    最简单, 一条命令                    ║
║  方案 B (手动 YAML): ⭐⭐   需要查 datasheet                  ║
║  方案 C (写 Flash Algo): ⭐⭐⭐⭐ 最可控但工作量大              ║
║                                                              ║
║  推荐: 方案 A — CMSIS-Pack 中已经有 .FLM 文件,               ║
║        target-gen 一条命令即可生成完整 YAML                   ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

---

> 📎 **关键链接**:
> - [Arm Keil Packs](https://www.keil.arm.com/packs/) — 下载 T2G-B-E_DFP
> - [probe-rs CMSIS Packs Doc](https://probe.rs/docs/knowledge-base/cmsis-packs/)
> - [probe-rs flash-algorithm template](https://github.com/probe-rs/flash-algorithm)
> - [Infineon AN220242 Flash Accessing](https://documentation.infineon.com/traveo/docs/grn1680597195267_2)
> - [CMSIS Flash Algorithm Spec](https://open-cmsis-pack.github.io/Open-CMSIS-Pack-Spec/main/html/flashAlgorithm.html)
