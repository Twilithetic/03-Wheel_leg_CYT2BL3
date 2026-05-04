# probe-rs 支持 CYT2BL3 技术路线图

> *"要让 probe-rs 支持 CYT2BL3，现在需要准备什么？"*
> 基于 probe-rs 官方文档、CMSIS-Pack 规范及 Infineon AN220242

---

## 一、probe-rs 官方资源

| 资源 | 链接 |
|------|------|
| 官网 | https://probe.rs/ |
| 文档总入口 | https://probe.rs/docs/ |
| CMSIS-Pack 指南 | https://probe.rs/docs/knowledge-base/cmsis-packs/ |
| API 文档 (Rust) | https://docs.rs/probe-rs/ |
| GitHub 仓库 | https://github.com/probe-rs/probe-rs |
| Flash 算法模板 | https://github.com/probe-rs/flash-algorithm-template |
| 社区讨论 | https://github.com/probe-rs/probe-rs/discussions |
| 安装指南 | https://probe.rs/docs/getting-started/installation/ |

---

## 二、probe-rs 如何添加新芯片

### 2.1 三种方式

```
方式1: CMSIS-Pack → target-gen → 自动生成 ✅ (最简单)
   └── 前提: 芯片厂商发布了 CMSIS-Pack
   └── CYT2BL3: ❌ Infineon 没有发布公开的 CMSIS-Pack

方式2: 手写 YAML + Flash 算法 → target-gen elf 提取 ✅ (推荐)
   └── 芯片信息手写 YAML
   └── Flash 算法用 Rust 模板写
   └── 编译后 target-gen 提取到 YAML

方式3: 已有 ELF loader → target-gen elf 转换
   └── 从 Infineon OpenOCD 提取 Flash Loader ELF
   └── target-gen elf -u flash.elf target.yaml
```

### 2.2 probe-rs 芯片描述文件结构

```yaml
# CYT2BL3.yaml — probe-rs 芯片描述 (目标格式)
---
name: CYT2BL3
manufacturer: Infineon

variants:
  - name: CYT2BL3BAAQ0AZSGS
    cores:
      - name: cm4
        type: armv7em          # Cortex-M4F
        core_access_options: !Arm {}
    memory_map:
      - !Ram
        range:
          start: 0x08000000
          end:   0x08080000    # 512 KB SRAM
        cores: [cm4]
      - !Nvm
        range:
          start: 0x10000000
          end:   0x10410000    # 4160 KB Code Flash
        cores: [cm4]
        is_boot_memory: true
    flash_algorithms:
      - cyt2bl3_code_flash

flash_algorithms:
  - name: cyt2bl3_code_flash
    description: CYT2BL3 Code Flash (4160 KB)
    default: true
    instructions: <BASE64_ENCODED_ELF_BLOB>
    load_address: 0x08001000     # 算法加载到 SRAM 的地址
    data_load_address: 0x08002000
    flash_properties:
      address: 0x10000000
      size: 4259840
      page_size: 512
      erased_byte_value: 0x00
      program_page_timeout: 100
      erase_sector_timeout: 3000
      sectors:
        - size: 32768
          address: 0x10000000
```

---

## 三、添加 CYT2BL3 需要准备什么

### 3.1 清单总览

```
┌─────────────────────────────────────────────────────────────┐
│  📋 需要的东西                  状态                         │
├─────────────────────────────────────────────────────────────┤
│  1. 芯片信息 (内存布局)         ✅ 已有 (Datasheet)          │
│  2. Flash 扇区信息              ✅ 已有                       │
│  3. CMSIS-Pack                  ❌ Infineon 未发布           │
│  4. Flash 算法 (ELF blob)       ⚠️ 需要编写                  │
│  5. YAML 描述文件               ⚠️ 需要编写                  │
│  6. Rust 开发环境               ⚠️ 需要安装                  │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 详细分析

#### ✅ 1. 芯片信息 (已有)

```
来源: Infineon CYT2BL Datasheet (002-28876 Rev. *H)

CPU:        Cortex-M4F (armv7em) @ 160 MHz
            Cortex-M0+ (cortex-m0plus) @ 100 MHz

Code Flash: 0x10000000, 4160 KB
Work Flash: 0x14000000, 128 KB
SRAM:       0x08000000, 512 KB (前 2KB 保留)
ROM:        32 KB
```

#### ✅ 2. Flash 扇区信息 (已有)

```
Code Flash 扇区 (Single Bank):
  Sector 0:  0x10000000, 32 KB (Small)
  Sector 1:  0x10008000, 32 KB (Small)
  Sector 2:  0x10010000, 256 KB (Large)
  Sector 3:  0x10050000, 256 KB (Large)
  ... (共计约 16 个大扇区)

Work Flash 扇区:
  Sector 0:  0x14000000, 32 KB
  ...
  来源: CYT2BL Datasheet Table 5-1, 5-2
```

#### ❌ 3. CMSIS-Pack (不存在)

```
Infineon 没有为 CYT2BL3 发布独立的 CMSIS-Pack。
TRAVEO T2G 的支持是通过 ModusToolbox 内部机制实现。
→ 跳过此方式，用手写方案。
```

#### ⚠️ 4. Flash 算法 (需要编写)

这是最核心、最需要工作量的一步。

**需要实现 4 个函数：**

```c
// CMSIS-Pack Flash Algorithm 标准接口
int  flash_init(void);                          // 初始化 (时钟、IPC)
int  flash_erase_sector(uint32_t address);      // 擦除扇区
int  flash_program_page(uint32_t address,       // 编程一页
                        const uint8_t *data, 
                        uint32_t size);
int  flash_verify(uint32_t address,             // 校验 (可选)
                  const uint8_t *data,
                  uint32_t size);
```

**CYT2BL3 的实现基础（来自 AN220242 公开文档）：**

```
擦除扇区:
  1. IPC1 获取锁
  2. 写 SramScratch = opcode + 扇区地址
  3. 写 SRAM_SCRATCH_ADDR 到 IPC1_DATA0
  4. 发 NOTIFY → CM0+ IRQ0
  5. 等待状态返回

编程页:
  1. IPC1 获取锁
  2. 把数据写入 SRAM 缓冲区
  3. 写 SramScratch = 0x06 (ProgramRow opcode) + 参数
  4. 写缓冲区地址到 IPC1_DATA0
  5. 发 NOTIFY → CM0+ IRQ0
  6. 等待状态返回
```

**可以用 probe-rs 的 Rust 模板：**

```bash
# 安装 cargo-generate
cargo install cargo-generate

# 从模板创建 Flash 算法项目
cargo generate gh:probe-rs/flash-algorithm-template

# 填写参数:
#   Architecture: thumbv7em-none-eabihf
#   RAM start:    0x08001000
#   RAM size:     0x1000
#   Flash start:  0x10000000
#   Flash size:   0x410000
#   Page size:    512
#   Sector size:  32768
```

#### ⚠️ 5. YAML 描述文件 (需要编写)

格式已在 2.2 节给出。需要填充 CYT2BL3 的具体参数。

#### ⚠️ 6. Rust 开发环境 (需要安装)

```powershell
# 安装 Rust (如果没有)
# https://rustup.rs/

# 安装 probe-rs
cargo install probe-rs-tools

# 添加 ARM 交叉编译目标
rustup target add thumbv7em-none-eabihf
```

---

## 四、完整操作步骤

### Step 1: 安装环境

```powershell
cargo install probe-rs-tools
cargo install cargo-generate
rustup target add thumbv7em-none-eabihf
```

### Step 2: 创建 Flash 算法项目

```powershell
cargo generate gh:probe-rs/flash-algorithm-template
# 回答:
#   Project Name: cyt2bl3-flash-algo
#   Architecture: thumbv7em-none-eabihf
#   RAM start: 0x08001000
#   RAM size: 0x1000
#   Flash start: 0x10000000
#   Flash size: 0x410000
#   Page size: 512
#   Sector size: 32768
```

### Step 3: 编写 Flash 算法

在生成的 `src/main.rs` 中实现 4 个函数，调用 CYT2BL3 的 SROM API：

```rust
// 基于 AN220242 文档
const IPC1_ACQUIRE: u32 = 0x08010008;
const IPC1_DATA0:   u32 = 0x08010010;
const IPC1_NOTIFY:  u32 = 0x08010018;
const SRAM_SCRATCH: u32 = 0x0800F000;  // 临时缓冲区

fn call_srom_api(opcode: u32, addr: u32, data: *const u8, size: u32) -> bool {
    unsafe {
        // 1. 获取 IPC 锁
        while core::ptr::read_volatile(IPC1_ACQUIRE as *const u32) != 0 {}
        
        // 2. 复制数据到 SRAM
        // ...
        
        // 3. 写 opcode + 参数到 IPC
        core::ptr::write_volatile(IPC1_DATA0 as *mut u32, SRAM_SCRATCH);
        
        // 4. 通知 CM0+
        core::ptr::write_volatile(IPC1_NOTIFY as *mut u32, 1);
        
        // 5. 等待完成
        // ...
    }
}

#[no_mangle]
pub extern "C" fn flash_erase_sector(addr: u32) -> i32 {
    call_srom_api(0x14, addr, ptr::null(), 0);  // EraseSector opcode
    0
}
```

### Step 4: 编译并提取

```powershell
cd cyt2bl3-flash-algo
cargo build --release

# 提取 Flash 算法到 YAML
target-gen elf -u target/thumbv7em-none-eabihf/release/cyt2bl3-flash-algo cyt2bl3.yaml
```

### Step 5: 补全 YAML（手动添加芯片信息）

在自动生成的 `cyt2bl3.yaml` 基础上，手动添加：
- variants（芯片型号列表）
- memory_map（SRAM 区域）
- 多核信息（CM4 + CM0+）

### Step 6: 测试

```powershell
# 用自定义 YAML 烧录
probe-rs download --chip-description-path cyt2bl3.yaml build/firmware.hex

# 验证
probe-rs info --chip-description-path cyt2bl3.yaml
```

---

## 五、工作量预估

| 步骤 | 难度 | 预计时间 | 依赖 |
|------|:---:|:---:|------|
| 安装环境 | ⭐ | 10 分钟 | Rust 工具链 |
| 创建模板项目 | ⭐ | 5 分钟 | cargo-generate |
| 编写 Flash 算法 | ⭐⭐⭐ | 2-4 小时 | AN220242 文档理解 |
| 调试 Flash 算法 | ⭐⭐⭐⭐ | 2-6 小时 | 需要测试板 |
| 编写 YAML | ⭐⭐ | 30 分钟 | 芯片信息 |
| 测试验证 | ⭐⭐ | 30 分钟 | 测试板 + hex |
| **总计** | | **半天到一天** | |

---

## 六、备选方案对比

| 方案 | 时间 | 效果 |
|------|:---:|------|
| 🥇 **手写 probe-rs Flash 算法** | 半天 | probe-rs 全功能支持 |
| 🥈 **下载 Infineon OpenOCD** | 30 分钟 | 传统但稳定 |
| 🥉 **刷 J-Link + J-Flash** | 10 分钟 | 最快上手 |

---

## 七、参考文档链接

| 文档 | 链接 |
|------|------|
| probe-rs 文档 | https://probe.rs/docs/ |
| probe-rs CMSIS-Pack 指南 | https://probe.rs/docs/knowledge-base/cmsis-packs/ |
| Flash 算法模板 | https://github.com/probe-rs/flash-algorithm-template |
| probe-rs YAML 格式 | https://docs.rs/probe-rs-target |
| Infineon AN220242 | Flash 操作流程 (SROM API) |
| Infineon OpenOCD (开源) | https://github.com/Infineon/openocd |
| SEGGER J-Link 转换 | https://www.segger.com/downloads/jlink#STLink_Reflash |

---

*报告版本：v1.0 | 2026-05-04 | 基于 probe-rs v0.31 文档*
