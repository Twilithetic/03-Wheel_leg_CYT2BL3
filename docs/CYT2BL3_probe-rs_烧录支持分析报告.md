# probe-rs 对 CYT2BL3 烧录支持 — 源码级分析报告

> **分析日期**: 2026-05-05  
> **源码版本**: probe-rs (从 `docs/probe-rs-src/` 分析)  
> **调试探针**: WCH-Link (CMSIS-DAP)  
> **前序报告**: 
> - [CYT2BL3 调试接口 ADIv5 兼容性分析报告](./CYT2BL3_调试接口_ADIv5兼容性分析报告.md)
> - [CYT2BL3 probe-rs 探测实测分析报告](./CYT2BL3_probe-rs_探测实测分析报告.md)

---

## 1. 核心问题速答

| 问题 | 答案 |
|------|------|
| **probe-rs 能烧录 HEX 吗？** | ✅ **能！** 支持 `hex` / `ihex` / `intelhex` |
| **probe-rs 支持 CYT2BL3 吗？** | ⚠️ **不内置支持**，但可以通过 SWD 连接并手动操作 |
| **要怎么做才能烧录？** | 需要编写 Flash Algorithm 二进制 + YAML 芯片描述 |
| **不写代码能直接用吗？** | 可以调试/单步/RAM加载，但不能直接 Flash 烧录 |

---

## 2. probe-rs 支持的所有文件格式

通过分析源码 `probe-rs/src/flashing/loader.rs`（第62-74行），probe-rs 内建了 **4 种烧录格式**：

```rust
// 源码: docs/probe-rs-src/probe-rs/src/flashing/loader.rs:62-74
static LOADERS: LazyLock<RwLock<Vec<&'static dyn ImageFormat>>> = LazyLock::new(|| {
    let mut image_formats: Vec<&'static dyn ImageFormat> = vec![];

    #[cfg(feature = "builtin-formats")]
    {
        image_formats.extend_from_slice(&[
            &ElfLoaderFactory,     // ← ELF
            &BinLoaderFactory,     // ← 原始二进制
            &HexLoaderFactory,     // ← Intel HEX ← 你问的这个！
            &Uf2LoaderFactory,     // ← Microsoft UF2
        ]);
    }
    // ...
});
```

### 2.1 各格式详细说明

| 格式 | CLI 名称 | 别名 | 说明 |
|------|----------|------|------|
| **ELF** | `elf` | — | 可执行可链接格式，**首选格式**，含段地址信息 |
| **Binary** | `bin` | `binary` | 原始二进制，需手动指定 `--base-address` |
| **Intel HEX** | `hex` | `ihex`, `intelhex` | ✅ 支持标准 Intel HEX，自动解析地址 |
| **UF2** | `uf2` | — | Microsoft 的通用 Flash 格式 |
| **ESP-IDF** | `idf` | `esp-idf`, `espidf` | ESP32 专用，含 bootloader + 分区表 |

### 2.2 Intel HEX 烧录的实现细节

```rust
// 源码: docs/probe-rs-src/probe-rs/src/flashing/loader.rs:385-421
pub struct HexLoader;

impl ImageLoader for HexLoader {
    fn load(&self, flash_loader: &mut FlashLoader, _session: &mut Session,
            file: &mut dyn ImageReader) -> Result<(), FileDownloadError> {
        let mut base_address = 0;
        let mut data = String::new();
        file.read_to_string(&mut data)?;

        for record in ihex::Reader::new(&data) {
            match record? {
                Record::Data { offset, value } => {
                    let offset = base_address + offset as u64;
                    flash_loader.add_data(offset, &value)?;  // ← 写入 Flash Loader
                }
                Record::ExtendedSegmentAddress(address) => {
                    base_address = (address as u64) * 16;     // ← HEX 段地址
                }
                Record::ExtendedLinearAddress(address) => {
                    base_address = (address as u64) << 16;   // ← HEX 线性地址
                }
                // ... 其他记录类型
            }
        }
    }
}
```

**HEX 文件不需要额外参数**——地址信息直接从 HEX 记录中解析，包括 `Extended Linear Address` (类型 04) 和 `Extended Segment Address` (类型 02)。

### 2.3 命令行使用方式

```bash
# 默认按芯片偏好的格式（通常是 ELF）
probe-rs download --chip <芯片名> firmware.elf

# 显式指定 HEX 格式
probe-rs download --chip <芯片名> --binary-format hex firmware.hex

# 显式指定 Binary 格式（需手动给基地址）
probe-rs download --chip <芯片名> --binary-format bin --base-address 0x10000000 firmware.bin
```

---

## 3. CYT2BL3 在 probe-rs 中的支持状态

### 3.1 🔴 当前状态：**不支持**

在源码的 `probe-rs/targets/` 目录（217 个 YAML 文件）中搜索：

```bash
# 搜索结果
grep -ri "cyt2b\|traveo\|CYT2BL" probe-rs/targets/*.yaml
→ 0 matches ❌
```

仅在以下 Infineon 芯片有支持：
| 芯片系列 | YAML 文件 |
|---------|----------|
| PSOC 6 (01/02/03/04) | `PSOC6_01.yaml` ~ `PSOC6_04.yaml` |
| PSOC E84 | `PSOC_E84.yaml` |
| PSOC C3 | `PSOC_C3.yaml` |
| XMC4000 | `XMC4000.yaml` |

**TRAVEO T2G (包括 CYT2BL3) 没有任何芯片描述文件。**

### 3.2 🟡 但是：SWD 连接已经通了！

虽然不能直接烧录 Flash，但 probe-rs 已经通过 SWD 成功识别了 CYT2BL3 的完整调试拓扑（见前序报告）。这意味着：
- ✅ **调试功能可用**：`probe-rs debug`、`probe-rs run`（仅 RAM）
- ✅ **内存读写可用**：`probe-rs read`、`probe-rs write`
- ✅ **寄存器查看可用**：`probe-rs info`（已验证）
- ❌ **Flash 烧录不可用**：需要 Flash Algorithm

---

## 4. 要让 probe-rs 支持 CYT2BL3 烧录，需要做什么？

### 4.1 probe-rs 烧录 Flash 的原理

```
probe-rs 烧录流程:
┌──────────┐     ┌──────────────┐     ┌──────────────┐
│ 固件文件  │────▶│ Flash Loader │────▶│ Flash Algo   │────▶ 芯片 Flash
│(elf/hex) │     │ (地址→数据)   │     │ (RAM 中执行)  │
└──────────┘     └──────────────┘     └──────────────┘
                                             │
                               ┌─────────────┴─────────────┐
                               │ Flash Algorithm 二进制     │
                               │ - Init()      初始化 Flash │
                               │ - EraseSector()  擦除扇区  │
                               │ - ProgramPage()  写入页    │
                               │ - Verify()      校验数据   │
                               │ - UnInit()      反初始化   │
                               └───────────────────────────┘
```

**关键组件：Flash Algorithm** —— 一个小段 ARM Thumb 代码，被 probe-rs 加载到芯片 RAM 中执行，负责实际的 Flash 擦写操作。

### 4.2 需要创建的文件

参考 PSOC6 的 YAML 示例（因为同是 Infineon 产品，且都用 Infineon 专有的 Flash 控制器），需要创建：

#### 文件 1: `CYT2BL_Series.yaml`（芯片家族描述）

```yaml
name: cyt2bl_series
manufacturer:
  id: 0x34          # JEP106: Cypress → Infineon 的 ID
  cc: 0x0
chip_detection:
- !ArmPart              # 通过 ARM Part Number 自动识别
  part: 0xea02          # ← probe-rs info 检测到的 Part Number!
variants:
- name: CYT2BL3BAS      # 具体芯片型号
  cores:
  - name: cm0p          # CM0+ 核心
    type: armv6m
    core_access_options: !Arm
      ap: !v1 1         # AP#1 = CM0+
  - name: cm4           # CM4F 核心
    type: armv7em
    core_access_options: !Arm
      ap: !v1 2         # AP#2 = CM4F
  memory_map:
  - !Ram
    name: SRAM
    range:
      start: 0x08000000      # CYT2BL3 SRAM 起始地址
      end: 0x08080000        # 512KB SRAM
    cores:
    - cm0p
    - cm4
  - !Nvm
    name: CodeFlash
    range:
      start: 0x10000000      # Code Flash 起始地址
      end: 0x10410000        # 4160KB + 128KB Work
    cores:
    - cm0p
    - cm4
    access:
      write: false
      boot: true
  flash_algorithms:
  - cyt2bl_main_flash         # ← 需要编写！
  - cyt2bl_work_flash
```

#### 文件 2: Flash Algorithm 二进制

这是**最难的部分**。需要：

1. 用 ARM GCC 编译一段**位置无关 (PIC)** 的 C/汇编代码
2. 实现标准 Flash Algorithm API：
   ```c
   int Init(uint32_t adr, uint32_t clk, uint32_t fnc);
   int UnInit(uint32_t fnc);
   int EraseSector(uint32_t adr);
   int ProgramPage(uint32_t adr, uint32_t sz, uint8_t *buf);
   int Verify(uint32_t adr, uint32_t sz, uint8_t *buf);    // 可选
   int EraseChip(void);                                      // 可选
   ```
3. 处理 Infineon TRAVEO T2G 的 Flash 控制器寄存器（不同于 STM32！）

**参考来源**：
- ✅ 项目已有 Infineon OpenOCD 的 Flash Loader 源码在 `tools/infineon-openocd/` 中
- ✅ CMSIS-Pack 中可能有 TRAVEO T2G 的 Flash 算法
- ✅ Infineon 官方 SDL（Sample Driver Library）包含 Flash 操作驱动

### 4.3 🚀 更简单的替代方案

| 方案 | 难度 | 说明 |
|------|:--:|------|
| **方案 A: 先用 OpenOCD 烧录** | ⭐ | 项目已有 Infineon OpenOCD，直接可用 |
| **方案 B: 用 pyOCD 烧录** | ⭐⭐ | pyOCD 对 CMSIS-Pack 支持好 |
| **方案 C: 写 probe-rs YAML** | ⭐⭐⭐ | 需要 Flash Algorithm 二进制 |
| **方案 D: 给 probe-rs 提 PR** | ⭐⭐⭐⭐ | 完整贡献，长期收益 |

> 💡 **姐姐建议**：当前阶段用 **Infineon OpenOCD**（项目里已经有了！）烧录和调试，probe-rs 用来做快速探测和验证（`probe-rs info` 已经证明了调试链路畅通）。

---

## 5. 当前可行的 probe-rs 操作

虽然不能烧录 Flash，但以下操作**立即可用**（已验证 SWD 连接正常）：

### 5.1 探测芯片信息

```bash
# 列出可用调试器
probe-rs list

# 扫描芯片调试拓扑（已验证成功！）
probe-rs info
```

### 5.2 读取内存/寄存器

```bash
# 读取 32 位寄存器（通过调试器直接访问）
# 例如读 CPUID 寄存器 (0xE000ED00)
# （需要先 attach）

# 读 Flash 内容到文件
# （需要指定芯片，但由于 CYT2BL3 未被识别，可能需要通用方式）
```

### 5.3 使用 OpenOCD 替代烧录

```bash
# 项目已有的 OpenOCD 配置
openocd -f tools/infineon-openocd/scripts/interface/kitprog3.cfg \
        -f tools/infineon-openocd/scripts/target/infineon/cyt2bl.cfg

# 然后用 telnet/GDB 烧录
telnet localhost 4444
> program firmware.hex verify
> reset run
```

### 5.4 probe-rs 作为 GDB Server 调试

```bash
# 启动 GDB 服务器（仅调试，不烧录 Flash）
probe-rs gdb-server --chip <generic_arm_chip>
```

---

## 6. HEX 文件烧录的其他方式

### 6.1 用 Infineon OpenOCD（推荐）

```bash
# 启动 OpenOCD
openocd -f scripts/interface/kitprog3.cfg \
        -f scripts/target/infineon/cyt2bl.cfg

# 另一个终端，用 telnet 连接
telnet localhost 4444
> halt                    # 暂停 CPU
> flash write_image erase firmware.hex ihex  # 烧录 HEX！
> reset run               # 复位运行
```

### 6.2 用 IAR / GHS MULTI

商用 IDE 原生支持 TRAVEO T2G，可以直接烧录 HEX/ELF。

### 6.3 用 J-Link Commander

```bash
JLinkExe -device CYT2BL3 -if SWD -speed 4000
> loadfile firmware.hex
> r
> g
```

---

## 7. 源码关键发现总结

| 文件 | 关键信息 |
|------|---------|
| `probe-rs/src/flashing/loader.rs:62-74` | 内建 4 种格式：ELF, BIN, HEX, UF2 |
| `probe-rs/src/flashing/loader.rs:385-421` | Intel HEX 完整解析实现，支持扩展地址 |
| `probe-rs-tools/src/bin/probe-rs/main.rs:383-426` | CLI `--binary-format` 参数定义 |
| `probe-rs/targets/PSOC6_01.yaml` | Infineon 芯片 YAML 参考模板（同厂！） |
| `probe-rs/src/plugin.rs:29-42` | 插件系统可按需注册芯片和 Flash 算法 |
| `probe-rs-target/src/flash_algorithm.rs:28-112` | Flash Algorithm 结构定义 |
| `probe-rs/targets/` (217 files) | ❌ 无 CYT2BL/TRAVEO 定义 |

---

## 8. 结论

```
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   probe-rs 能烧录 HEX 吗？                                 ║
║   ✅ 能！支持 Intel HEX (含扩展线性/段地址)                  ║
║                                                           ║
║   probe-rs 能直接烧录 CYT2BL3 吗？                          ║
║   ❌ 不能。需要编写 Flash Algorithm + YAML 芯片描述           ║
║                                                           ║
║   当前最佳方案？                                            ║
║   用项目已有的 Infineon OpenOCD 烧录 HEX/ELF               ║
║   用 probe-rs 做快速探测和验证（已验证 SWD 链路畅通）        ║
║                                                           ║
║   长期方案？                                                ║
║   从 Infineon CMSIS-Pack 提取 Flash Algorithm，            ║
║   编写 YAML，给 probe-rs 贡献 CYT2BL 支持                   ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
```

> 📎 **本报告基于以下来源的交叉验证**：
> - `docs/probe-rs-src/` 完整源码（Rust 代码 + YAML 芯片描述）
> - `probe-rs info` 实测输出（DPv2, Part 0xea02, 3个AP 已验证）
> - Infineon OpenOCD 项目配置（`cyt2bl.cfg`, `base_cyt2xx.cfg`）
> - PSOC6 YAML 模板（同厂 Infineon，架构参考）
> - probe-rs 官方文档及 API
