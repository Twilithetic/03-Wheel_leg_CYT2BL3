# SWD/JTAG 调试架构分析报告

> 写于 2026-05-05 | 知心姐姐的调试底层科普
> 核心问题：SWD/JTAG 到底能控制芯片的什么？为什么 CYT2BL3 的 CM4 用 SWD 连不上？

---

## 一、标准文档速查

### 1.1 协议标准

| 标准 | 全称 | 说明 |
|------|------|------|
| **IEEE 1149.1** | Standard Test Access Port and Boundary-Scan Architecture | JTAG 基础标准，定义 TAP 状态机 |
| **IEEE P1149.7** | Reduced-pin JTAG (cJTAG) | 两线 JTAG，SWD 的前身概念 |
| **ARM IHI 0031** | ARM Debug Interface v5 (ADIv5) | **最核心**：定义 DP/AP 架构、SWD 协议、MEM-AP |
| **ARM IHI 0074** | ARM Debug Interface v6 (ADIv6) | ADIv5 的升级版，支持更大地址空间 |

> 📎 ADIv5 是当前最广泛使用的版本。ADIv5 的核心创新是**解耦了外部调试接口（SWD/JTAG）和内部调试组件（CoreSight）**，使得调试器不需要知道 CPU 是什么型号就能通过标准协议访问。

### 1.2 获取方式

- **ARM IHI 0031 (ADIv5)**：https://developer.arm.com/documentation/ihi0031/latest/
- **IEEE 1149.1**：https://standards.ieee.org/standard/1149_1-2013.html
- **CMSIS-DAP 固件**：https://arm-software.github.io/CMSIS_5/DAP/html/index.html

---

## 二、SWD/JTAG 的物理层

### 2.1 管脚对比

```
┌────────────────────────────────────────────────────────┐
│                    SWD (2线) vs JTAG (4-5线)            │
│                                                        │
│  JTAG:  TDI ──→ 数据输入         SWD:  SWDIO ←→ 双向  │
│         TDO ←── 数据输出               SWCLK ──→ 时钟  │
│         TCK ──→ 时钟                                    │
│         TMS ──→ 模式选择                                │
│         TRST ─→ 复位(可选)                              │
│                                                        │
│  JTAG: 5线制，单向数据，菊花链可连多个芯片              │
│  SWD:  2线制，半双工，ARM 专属，只能连一个芯片          │
└────────────────────────────────────────────────────────┘
```

### 2.2 物理连接示意

```
  调试器(host)                        目标芯片(target)
  ┌──────────┐                       ┌──────────────┐
  │          │── SWDIO ────────────→ │              │
  │  PC      │── SWCLK ────────────→ │   SW-DP      │
  │  +       │                       │   (Debug     │
  │  probe-rs│── GND ──────────────→ │    Port)     │
  │          │                       │              │
  │          │  (可选)                │     ↓        │
  │          │── SWO ←────────────── │  trace输出   │
  └──────────┘                       └──────────────┘
```

---

## 三、ARM CoreSight DAP 调试架构（核心！）

### 3.1 架构总览

这是理解一切的基石——调试器不是直接跟 CPU 对话，而是通过一个叫 **DAP (Debug Access Port)** 的中间层：

```
┌─────────────────────────────────────────────────────────────────┐
│                      ARM CoreSight DAP 架构                      │
│                                                                  │
│  外部调试器                                                        │
│  ┌──────────┐                                                    │
│  │ probe-rs │                                                    │
│  │ openocd  │                                                    │
│  │ J-Link   │                                                    │
│  └────┬─────┘                                                    │
│       │ SWD 或 JTAG                                               │
│       ▼                                                          │
│  ┌─────────────────────────────────────────────┐                 │
│  │              Debug Port (DP)                │  ← 物理接口      │
│  │  ┌──────────┐  ┌──────────┐  ┌───────────┐ │                 │
│  │  │  SW-DP   │  │ JTAG-DP  │  │  SWJ-DP   │ │  三选一         │
│  │  │ (仅SWD)  │  │ (仅JTAG) │  │ (双协议)  │ │                 │
│  │  └──────────┘  └──────────┘  └───────────┘ │                 │
│  │                                            │                 │
│  │  DP 寄存器：(CTRL/STAT, SELECT, IDCODE...)  │                 │
│  └──────────────────┬──────────────────────────┘                 │
│                     │ 内部总线 (DAP Bus)                          │
│        ┌────────────┼────────────┐                               │
│        ▼            ▼            ▼                               │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                         │
│  │ MEM-AP 0 │ │ MEM-AP 1 │ │ MEM-AP 2 │  ← Access Ports         │
│  │ (AHB-AP) │ │ (AHB-AP) │ │ (APB-AP) │                         │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘                         │
│       │            │            │                                 │
│       ▼            ▼            ▼                                 │
│  ┌────────┐  ┌────────┐  ┌──────────┐                           │
│  │ CM0+   │  │ CM4    │  │ 调试组件  │   ← 最终目标              │
│  │ 内核   │  │ 内核   │  │ 寄存器等  │                           │
│  └────────┘  └────────┘  └──────────┘                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 关键概念：DP → AP → 目标

```
调试器能控制的一切，都遵循这个三层访问链：

  第1步: 调试器 → DP   (通过 SWD/JTAG 物理协议)
         读 DP IDCODE 确认芯片身份
         写 DP CTRL/STAT 上电调试域
         写 DP SELECT 选择目标 AP

  第2步: DP → AP        (通过 DAP 内部总线)
         写 AP CSW 配置访问参数 (数据宽度、地址自增等)
         写 AP TAR 设置目标地址
         读/写 AP DRW 实际传输数据

  第3步: AP → 目标       (通过 AHB/APB 系统总线)
         MEM-AP 把 TAR 中的地址发到系统总线上
         就像 CPU 做了一次内存访问一样！
```

### 3.3 DP 核心寄存器

| 寄存器 | 地址 (A[3:2]) | 作用 |
|--------|:---:|------|
| **IDCODE** | — | 芯片识别码（DPv0/v1/v2，设计师ID） |
| **CTRL/STAT** | 01 | 控制/状态：上电请求、复位请求、错误标志 |
| **SELECT** | 10 | 选择哪个 AP + 该 AP 的哪个寄存器组 |

**CTRL/STAT 关键位：**

```
位[28] CDBGPWRUPREQ  — 请求上电调试域（必须置1才能调试！）
位[30] CSYSPWRUPREQ  — 请求上电系统域
位[26] CDBGRSTREQ    — 请求复位调试域
位[5]  STICKYERR     — 粘性错误标志（AP 访问出错时置1）
                  ↑ 这个位是报错的关键！
```

### 3.4 AP (MEM-AP) 核心寄存器

| 寄存器 | 偏移 | 作用 |
|--------|:---:|------|
| **CSW** | 0x00 | 控制/状态字：数据宽度(8/16/32bit)、地址自增 |
| **TAR** | 0x04 | 传输地址寄存器：设置要读写的内存地址 |
| **DRW** | 0x0C | 数据读写寄存器：实际读/写的数据 |
| **BASE** | 0xF8 | 调试基地址：指向 ROM Table 或调试寄存器 |
| **IDR** | 0xFC | AP 识别寄存器：AP 类型、设计师 |

### 3.5 MEM-AP 读写内存的完整流程

```
【写内存】 把 0xAA55AA55 写到地址 0x20000000

  DP: 写 SELECT 选 AP#0
  AP: 写 CSW = 0x02 (32-bit, 不自动加地址)
  AP: 写 TAR = 0x20000000
  AP: 写 DRW = 0xAA55AA55    ← 数据通过 AHB 总线写入目标地址！
       ↑ 这一步，MEM-AP 代替 CPU 发起了一次 AHB 总线写事务

【读内存】 从地址 0x08000000 读数据

  DP: 写 SELECT 选 AP#0
  AP: 写 CSW = 0x02
  AP: 写 TAR = 0x08000000
  AP: 读 DRW                 ← MEM-AP 发起 AHB 总线读事务
       ↑ 读到的就是目标地址的内容

【发现 CPU】 通过 ROM Table

  AP: 读 BASE 寄存器 → 得到 ROM Table 基地址 (如 0xE00FF000)
  AP: 写 TAR = ROM_Table_addr
  AP: 读 DRW → 得到组件信息 (SCS, DWT, FPB, ITM...)
  每个组件有 CLASS/PIDR/CIDR 标识它是 Cortex-M几
```

---

## 四、SWD/JTAG 到底能控制芯片的什么？

### 4.1 全能清单

```
┌─────────────────────────────────────────────────────────────┐
│              SWD/JTAG 通过 DAP 能做到的事情                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ 🔌 连接与识别                                                │
│   ✅ 读取 DP IDCODE → 识别芯片型号、DP 版本                  │
│   ✅ 扫描所有 AP → 发现系统中有几个调试接口                   │
│   ✅ 读取 ROM Table → 发现所有 CoreSight 调试组件             │
│   ✅ 读取 CPUID → 识别 Cortex-M0/M4/M7/...                   │
│                                                             │
│ ⚡ 电源与复位                                                 │
│   ✅ 上电调试域 (CDBGPWRUPREQ)                                │
│   ✅ 上电系统域 (CSYSPWRUPREQ)                                │
│   ✅ 复位调试域 (CDBGRSTREQ)                                  │
│   ✅ 系统复位 (通过 AIRCR 寄存器)                             │
│                                                             │
│ 🧠 CPU 控制                                                   │
│   ✅ Halt (暂停 CPU) — 通过 DHCSR 寄存器                      │
│   ✅ Resume (恢复运行)                                        │
│   ✅ Single Step (单步执行)                                   │
│   ✅ 读/写 CPU 核心寄存器 (R0-R15, MSP, PSP, CONTROL...)     │
│   ✅ 设置硬件断点 (FPB 单元，通常 4-8 个)                     │
│   ✅ 设置 watchpoint (DWT 单元)                               │
│                                                             │
│ 💾 内存访问                                                   │
│   ✅ 读/写任意 SRAM 地址                                      │
│   ✅ 读 Flash (映射到地址空间后)                              │
│   ✅ 写 Flash (需要先擦除 + 编程算法)                         │
│   ✅ 读/写外设寄存器 (GPIO, UART, SPI...)                    │
│   ✅ 批量数据传输 (TRNCNT 计数器加速)                         │
│                                                             │
│ 🔍 追踪 (可选，需 Trace 硬件)                                 │
│   ✅ SWO 串行输出 (printf 重定向)                             │
│   ✅ ETM/ETB 指令追踪                                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 一句话总结

> **调试器通过 SWD/JTAG → DP → MEM-AP → AHB 总线，获得了和 CPU 完全一样的 "内存视角"。CPU 能访问的任何地址，调试器都能访问。CPU 能被暂停、单步、设断点——这些都是通过 CoreSight 调试寄存器实现的。**

---

## 五、为什么 CYT2BL3 的 CM4 SWD 控制不了？

### 5.1 正常情况（RP2040 / STM32H7）

```
正常芯片：SWD 复位后立即可用

  probe-rs 发出连接序列
       │
       ▼
  SW-DP 响应: "我是 DPv2, ID=0x2BA01477"
       │
       ▼
  扫描 AP: 发现 MEM-AP#0 (AHB-AP)
       │
       ▼
  读 AP#0 的 BASE → ROM Table @ 0xE00FF000
       │
       ▼
  遍历 ROM Table → 发现 Cortex-M4 SCS
       │
       ▼
  ✅ Halt CPU, 读写内存, 一切正常！

  为什么能行？
  → 复位后，所有 AP 都上电，所有总线都连接
  → DAP 访问限制 = 无
  → CPU 在复位释放后立即能被调试器捕获
```

### 5.2 CYT2BL3 的情况：CM0+ 是守门人

```
CYT2BL3: CM4 被 CM0+ "藏起来了"

  芯片上电
       │
       ▼
  CM0+ ROM Boot 启动
       │
       ├── 步骤 1: 加载校准参数
       │
       ├── 步骤 2: 🔐 配置 DAP 访问限制
       │           (从 eFuse + Supervisory Flash 读取策略)
       │           │
       │           ├── CM0_AP:  可能允许或限制
       │           ├── CM4_AP:  可以设为 "禁止访问"❌
       │           └── SYS_AP:  可以设为 "禁止访问"
       │
       ├── 步骤 3: 验证 Flash Boot 签名 (SECURE 阶段)
       │
       └── 步骤 4: Flash Boot 运行
                   │
                   └── 配置 SWD 引脚 (GPIO → Debug 模式)
                   └── 设置 CM4 向量表
                   └── 🔓 释放 CM4 复位
                   └── 配置 CM4_AP 为 "允许访问"

  在步骤 2-3 之间，probe-rs 尝试连接：

  probe-rs 发出连接序列
       │
       ▼
  SW-DP 响应: "我是 DPv2"  ✅ (DP 在 always-on 域，始终可用)
       │
       ▼
  扫描 AP: 发现 MEM-AP#0 (可能是 CM0_AP)
       │   发现 MEM-AP#1 (可能是 CM4_AP)
       │
       ▼
  尝试读 CM4_AP 的 IDR 寄存器
       │
       ▼
  ❌ STICKYERR! (CTRL/STAT[5] = 1)
     或者: ❌ No Response (AP 根本没挂到总线上)
     或者: ❌ WAIT 超时 (AP 没上电/没时钟)
```

### 5.3 报错的三种技术原因

```
原因 A: AP 被 DAP 访问限制屏蔽

  CYT2BL3 ROM Boot 在步骤 2 做了这件事:
    "Applies Debug Access Port (DAP) access restrictions"
    
  具体机制:
    芯片有一个 AP_CTL (Access Port Control) 寄存器组
    ROM Boot 根据 eFuse 写入限制策略:
      CM4_AP_CTL.ENABLE = 0  ← CM4 的调试端口被禁用！
    
  结果: probe-rs 向 CM4_AP 发请求 → 总线不响应 → STICKYERR

原因 B: CM4 在复位中，AP 时钟未使能

  CM4 处于复位状态 → CM4 的 AHB 总线从设备不响应
  CM4_AP 虽然物理存在，但它的时钟可能被 gated
  结果: probe-rs 读 AP IDR → WAIT → 超时

原因 C: SWD 引脚还未配置为 Debug 模式

  CYT2BL3 复位后，SWD 引脚默认是 GPIO 模式
  CM0+ Flash Boot 在步骤 4 才配置引脚
  如果 probe-rs 在 Flash Boot 之前尝试连接:
    结果: 物理层 SWD 序列都没有应答 → SwdDpError
```

### 5.4 时序图：probe-rs vs CYT2BL3

```
时间轴 →

上电 ─── ROM Boot ─── Flash Boot ─── CM4 释放 ─── App 运行
         (CM0+)         (CM0+)                    (CM4)
         
         │              │            │
DAP 状态:│              │            │
  DP:    可用          可用         可用
  CM0_AP: 受限         允许         允许
  CM4_AP: ❌ 禁止       ❌ 禁止      ✅ 允许
  SYS_AP: ❌ 禁止       受限         允许

probe-rs 如果在这里 ─┐
  尝试 halt CM4:     │  在 ROM Boot 期间
  ① SWD 物理连接     │  ① ❌ 引脚还是 GPIO，SWD序列无应答
  ② 读 DP IDCODE     │  ② ❌ 同上
  ③ 扫描 AP          │  ③ ❌ 同上
  ④ 读 CM4_AP IDR    │  ④ ❌ 同上
  
probe-rs 如果在这里 ─┐
  尝试 halt CM4:     │  在 Flash Boot 期间
  ① SWD 物理连接     │  ① ✅ 引脚已配置为 SWD
  ② 读 DP IDCODE     │  ② ✅ DP 始终可用
  ③ 扫描 AP          │  ③ ✅ 能发现 AP
  ④ 读 CM4_AP IDR    │  ④ ❌ CM4_AP 被 DAP 限制禁用
                     │     → STICKYERR / No Response
  
probe-rs 如果在这里 ─┐
  尝试 halt CM4:     │  CM4 已释放
  ①~④                │  全部 ✅！正常调试！
```

### 5.5 一句话总结

> **probe-rs 连不上 CYT2BL3 的 CM4，不是因为 probe-rs 有 bug，而是因为 CM0+ ROM Boot 在启动过程中主动关闭了 CM4 的调试接口（DAP Access Restriction）。这就像银行金库的门——不是锁坏了，是安保系统故意锁着的，必须要经过正确的认证流程才能打开。**

---

## 六、与 probe-rs 代码层面的对应

### 6.1 probe-rs 的 DAP 操作序列

probe-rs 源码中的标准连接流程（简化）：

```rust
// 1. 连接 DP，读 IDCODE
let dp = Dp::new(probe);
let idcode = dp.read_idcode()?;  
// → 如果芯片 SWD 引脚还是 GPIO，这一步就失败了

// 2. 上电调试域
dp.write_register(DP_CTRL_STAT, CDBGPWRUPREQ | CSYSPWRUPREQ)?;

// 3. 扫描 AP
for ap_num in 0..256 {
    dp.select_ap(ap_num);
    match dp.read_ap_idr() {
        Ok(idr) => { /* 发现了一个 AP */ }
        Err(ArmError::NoAcknowledge) => break,  // AP 扫描结束
        Err(ArmError::AccessPort { .. }) => {
            // ← CYT2BL3 CM4_AP 在这里报错！
            // STICKYERR 或超时
        }
    }
}

// 4. 对找到的 MEM-AP，读 ROM Table
let base = ap.read_base()?;
let rom_table = discover_rom_table(&mut ap, base)?;

// 5. 从 ROM Table 发现 CPU 核心
for component in rom_table {
    if component.is_cortex_m() {
        let core = Core::new(ap, component);
        core.halt()?;  // ← 如果 CM4 未释放，这里也会失败
    }
}
```

### 6.2 错误传播链

```
用户看到:
  Error: Failed to attach to target
  Caused by: SwdDpError

实际链路:
  probe-rs::architecture::arm::ap  ← 读 AP IDR 失败
        ↓
  probe_rs::probe::stlink (或 cmsisdap)
        ↓  SWD 线路上
  SW-DP → 转发给 AP → AP 无应答 → STICKYERR
        ↓
  调试器读 CTRL/STAT → 发现 STICKYERR=1
        ↓
  向上报告: "目标设备未响应" / "无法连接 DAP"
```

---

## 七、解决方案思路

### 7.1 为什么 CYT2BL3 需要特殊处理

```
其他芯片 (RP2040/STM32H7/ESP32-S3):
  ✅ 复位后 DAP 完全开放
  ✅ probe-rs 标准序列开箱即用

CYT2BL3:
  ❌ 复位后 CM4_AP 被锁定
  ❌ 需要 CM0+ 完成安全启动流程后手动释放
  
需要的特殊步骤:
  1. 先连接 CM0+ (如果 CM0_AP 可用)
  2. 让 CM0+ 跑完 ROM Boot + Flash Boot
  3. CM0+ 代码释放 CM4 + 配置 CM4_AP 访问
  4. 然后才能连 CM4
```

### 7.2 probe-rs 需要的适配

```
probe-rs 当前假设:
  "复位后，所有核都可以通过 DAP 访问"

CYT2BL3 需要的是:
  "复位后，等待 CM0+ 完成启动 → 轮询 CM4_AP 是否可用 → 再连"

具体技术方案 (我们的 YAML + Flash 算法):
  ① 连接 DP (始终可用)
  ② 发现 CM0_AP
  ③ 在 SRAM 中注入一段小代码给 CM0+
  ④ 让 CM0+ 执行注入代码：
     - 配置 CM4_AP 为允许
     - 释放 CM4 复位
  ⑤ probe-rs 重新扫描 AP → 发现 CM4_AP
  ⑥ 正常连接 CM4，开始调试！
```

---

## 八、参考资料汇总

| 文档 | 链接 | 关键内容 |
|------|------|---------|
| ARM ADIv5 规范 (IHI 0031) | [ARM Developer](https://developer.arm.com/documentation/ihi0031/) | DP/AP 架构、SWD 协议、寄存器定义 |
| ARM ADIv6 规范 (IHI 0074) | [ARM Developer](https://developer.arm.com/documentation/ihi0074/) | ADIv6 新特性 |
| IEEE 1149.1 (JTAG) | [IEEE](https://standards.ieee.org/standard/1149_1-2013.html) | TAP 状态机、JTAG 协议 |
| CoreSight DAP 教程 | [ARM Dev](https://developer.arm.com/documentation/102585/) | DAP 架构入门、自动检测 |
| CMSIS-DAP 固件 | [GitHub](https://arm-software.github.io/CMSIS_5/DAP/) | 调试器固件参考实现 |
| DAP 深入分析 | [PlatformIO Labs](https://piolabs.com/blog/engineering/diving-into-arm-debug-access-port.html) | DP/AP 寄存器操作详解 |
| CYT2BL3 Datasheet | [Infineon](https://www.infineon.com/assets/row/public/documents/10/49/infineon-cyt2bl-traveo-tm-t2g-32-bit-automotive-mcu-based-on-arm-r-cortex-r--m4f-single-datasheet-en.pdf) | DAP 访问限制、启动序列 |
| AN228680 安全配置 | [Infineon Traveo Docs](https://documentation.infineon.com/traveo/docs/ykc1680597580020_2) | DAP 限制、AP 控制详解 |
| AN220118 入门指南 | [Infineon](https://www.infineon.com/dgdl/Infineon-AN220118_GETTING_STARTED_WITH_TRAVEO_II_FAMILY_MCUS-ApplicationNotes-v06_00-EN.pdf) | 启动流程步骤 |

---

*报告完成 | 知心姐姐 | 2026-05-05*
*这份报告解释了从 SWD 物理层到 CYT2BL3 DAP 限制的全链路，希望能帮宝贝彻底搞懂调试底层！💖*
