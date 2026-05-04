# 双核（及多核）芯片启动流程对比

> *"其他双核芯片和 CYT2BL3 有什么不同？"*
> RP2040 vs STM32H7 vs LPC55 vs ESP32-S3 vs CYT2BL3

---

## 一、五款双核芯片速览

| 芯片 | 核 1 | 核 2 | ISA | 架构 | probe-rs |
|------|------|------|------|------|:---:|
| **RP2040** | M0+ | M0+ | ARMv6-M | 对称 | ✅ |
| **STM32H7** | M7 | M4 | ARMv7-M | 非对称 | ✅ |
| **LPC55** | M33 | M33 | ARMv8-M | 对称 | ✅ |
| **ESP32-S3** | Xtensa LX7 | Xtensa | Xtensa LX7 | 对称 | ✅ |
| **CYT2BL3** | M0+ | M4F | ARMv6-M/v7-M | **主从** | ❌ |

---

## 二、启动流程对比

### 2.1 RP2040 — 兄弟关系 🤝

```
上电
 │
 ▼
两个核同时上电
 │
 ├── Core 0: 从 Boot ROM 启动 → 跳转到 Flash → 开始执行
 │
 └── Core 1: 初始休眠（在 WFE 等待）
      │
      └── Core 0 写寄存器 → 给 Core 1 设置入口地址 → 发送 SEV
           │
           ▼
         Core 1 醒来 → 开始执行

SWD 调试:
  ✅ 两个核都可以独立 halt
  ✅ 不需要等 Core 0 释放 Core 1
  ✅ probe-rs 内置支持
```

```
特点:
  ✅ 完全对称 — 两个核是平等的
  ✅ Core 1 休眠而非复位 — SWD 随时可连
  ✅ Core 0 通过 "发信号" 方式启动 Core 1
```

---

### 2.2 STM32H7 — 父子关系（但没那么严）👨‍👦

```
上电
 │
 ▼
M7 先启动 (默认)
 │
 ├── M7 从 Flash 启动
 ├── M7 配置时钟、外设
 │
 └── M7 决定是否启动 M4:
      ├── 写 RCC 寄存器 → 释放 M4 复位
      └── 或通过 Option Bytes 预设为 "两个核都启动"

M4 随后从 Flash 启动

SWD 调试:
  ✅ 两个核有独立的 SWD 访问端口
  ✅ 可以独立 halt 任意核
  ✅ 可以通过 Option Bytes 让 M4 也自动启动
  ✅ probe-rs 内置支持
```

```
和 CYT2BL3 的相似点:
  ⚠️ 一个核控制另一个核的复位
  ⚠️ 主核需要"释放"辅核

和 CYT2BL3 的不同:
  ✅ Option Bytes 可配置 M4 自动启动
  ✅ 复位后可直接 SWD 访问 M4 (只是 halted 状态)
  ✅ 不需要等 M7 的 Boot ROM 验证签名
  ✅ M7 直接运行用户代码，无安全启动中间层
```

---

### 2.3 LPC55 — 双胞胎关系 👯

```
上电
 │
 ▼
Core 0 先启动
 │
 └── Core 1 默认也启动，可配置

两个核完全对称 (都是 M33)
共享同一个 Flash

SWD 调试:
  ✅ 对称设计，两个核的调试方式完全相同
  ✅ probe-rs 支持
```

---

### 2.4 ESP32-S3 — 双胞胎关系（但有一个赖床）👯‍♂️🛏️

```
上电
 │
 ▼
PRO CPU (CPU0) 立即从 Mask ROM 启动
APP CPU (CPU1) 保持复位状态

  PRO CPU ROM Bootloader (384KB 掩膜ROM，不可修改)
    ├── 检查 RTC_CNTL_STORE6_REG (Deep-sleep/WDT 检查复位原因)
    ├── 采样 Strapping 管脚 (GPIO0/3/45/46)
    ├── 确定 Boot 模式:
    │     ├── SPI Boot → 从 Flash 加载
    │     ├── Joint Download Boot → USB/UART 下载
    │     └── SPI Download Boot → SPI 下载
    ├── 配置 SPI Flash (基于 eFuse 值)
    └── → 加载 Second Stage Bootloader (Flash 0x0)
 │
 ▼
  Second Stage Bootloader
    ├── 读取分区表 (Flash 0x8000)
    ├── 选择 Factory / OTA 分区
    ├── 加载 App 段到 IRAM/DRAM
    └── → 跳转到 App 入口 call_start_cpu0
 │
 ▼
  call_start_cpu0 (PRO CPU)
    ├── 配置 CPU 异常 / 中断
    ├── 初始化 Cache (ICache 16/32KB + DCache 32/64KB)
    ├── 初始化 PSRAM (若配置)
    ├── 设置 CPU 时钟 (最高 240MHz)
    ├── 🔓 设置 APP CPU 入口地址
    ├── 🔓 释放 APP CPU 复位
    └── → 等待 APP CPU 就绪标志
 │
 ▼
  call_start_cpu1 (APP CPU)           ← APP CPU 醒来！
    ├── 轻量初始化 (时钟/中断)
    ├── 设置全局 "我准备好了" 标志
    └── → 进入 start_cpu_other_cores
 │
 ▼
  start_cpu0 (PRO CPU)
    ├── 堆分配器初始化
    ├── SPI Flash API 初始化
    ├── C++ 全局构造函数
    ├── 创建 main task
    └── → 启动 FreeRTOS 调度器
         │
         └── 触发中断启动 APP CPU 的 RTOS 调度器

SWD/JTAG 调试:
  ✅ USB Serial/JTAG 控制器 (内置)
  ✅ 两个核都可以独立 halt
  ✅ openocd / probe-rs 原生支持
  ✅ JTAG 信号源可通过 eFuse / GPIO3 配置
```

```
特点:
  ✅ 对称双核 — 两个 Xtensa LX7 完全对等
  ✅ PRO CPU 先启动，APP CPU 复位中等待（类似 CYT2BL3）
  ✅ ROM Bootloader 根据 Strapping 管脚决定启动模式
  ✅ 支持安全启动 (Secure Boot) 和 Flash 加密 (可选，eFuse 控制)
  ✅ 双核共享 ICache 和 DCache
  ✅ Mask ROM 不可修改（384KB ROM，存放底层启动代码）
```

```
和 RP2040 的相似点:
  ✅ 对称双核，两个核完全对等
  ✅ 一个核先启动，另一个核等待释放
  ✅ SWD/JTAG 原生可调试

和 CYT2BL3 的相似点:
  ⚠️ ROM 引导加载程序存在 (Mask ROM)
  ⚠️ eFuse 参与启动配置 (Boot 模式控制)
  ⚠️ 安全启动功能可用 (Secure Boot V2)

和 CYT2BL3 的不同:
  ✅ 安全启动可选 — eFuse 烧写后启用，默认不强制
  ✅ APP CPU 复位释放后直接可用 — 无需等复杂认证
  ✅ ROM Bootloader 不强制验证签名 (非 Secure Boot 模式)
  ✅ 双核对称架构 — 两个核都能做主核
  ✅ JTAG 随时可用 — USB Serial/JTAG 控制器独立
  ✅ 通用 MCU 定位，非汽车安全 MCU
  ✅ probe-rs / openocd 完全支持
```

---

### 2.5 CYT2BL3 — 严格安保关系 🔐🔫

```
上电
 │
 ▼
只有 CM0+ 能启动！CM4 在复位中！

  CM0+ Boot ROM (掩膜ROM，不可修改)
    ├── 加载校准参数
    ├── 配置 DAP 访问限制
    ├── 🔐 验证 Flash Boot 签名 (SECURE 模式下必须)
    └── → 签名不对？→ 芯片拒绝启动 CM4！
 │
 ▼
  CM0+ Flash Boot (Supervisory Flash)
    ├── 配置 SWD 引脚 (GPIO → Debug)
    ├── 设置 CM4_VECTOR_TABLE_BASE
    └── 🔓 释放 CM4 复位
 │
 ▼
  CM4 开始执行用户程序

SWD 调试:
  ❌ 复位后 CM4 不可访问 (还没被释放！)
  ❌ 不能直接 halt CM4 (CM0+ 控制着)
  ❌ CM0+ 必须先跑完安全验证
  ❌ probe-rs 不支持
```

---

## 三、核心差异总结

### 3.1 一张图看懂

```
          RP2040           STM32H7        ESP32-S3          CYT2BL3
          ──────           ───────        ────────          ───────

上电后:   两个核都活着      M7活着 M4可配  PRO活着 APP复位    只有M0+活着！
                                        
Core 1:   休眠(等信号)     被复位(等释放)  被复位(等释放)     被复位(等M0+放)
          SWD可连 ✅       SWD可连 ✅      JTAG可连 ✅        SWD不可连 ❌

启动方式: Core0发信号      M7写RCC        PRO CPU跑ROM       M0+跑完Boot ROM
          轻量级           寄存器操作      →Flash Boot       →Flash Boot
          ~1μs             ~10μs          →App Startup      →验证签名
                                          ~数ms             ~10ms！

安全层:   无               无              🔐 可选安全启动    🔐 强制安全启动
                                          🔐 eFuse 控制      🔐 SROM API
                                          🔐 Flash 加密      🔐 eFuse + DAP限制
```

### 3.2 为什么 CYT2BL3 最"重"？

```
RP2040:
  上电 → Core0 跑 → 发信号 → Core1 跑
  "打个招呼就行了"

STM32H7:
  上电 → M7 跑 → 写个寄存器 → M4 跑
  "填个表格就行了"

ESP32-S3:
  上电 → PRO CPU 跑 ROM → 读 Strapping 管脚
  → 判断 Boot 模式 → 从 Flash 加载 2nd Bootloader
  → 加载分区表 → 加载 App → 释放 APP CPU
  → 两个核一起跑 FreeRTOS
  "刷卡进门 + 上楼 + 开电脑"

CYT2BL3:
  上电 → CM0+ 跑 ROM → 验证签名 → 跑 Flash Boot
  → 配置安全策略 → 检查 eFuse → 配置 DAP
  → 设置 CM4 向量表 → 释放 CM4 → CM4 跑
  "经过安检 + 身份验证 + 权限审批 + 工位安排"
```

### 3.3 安全层次对比

```
ESP32-S3 的安全是可选的：
  ✅ Secure Boot V2 — eFuse 烧写后启用，默认关闭
  ✅ Flash 加密 — eFuse 控制，默认关闭
  ✅ 下载模式禁用 — eFuse 可永久禁用 USB/UART 下载
  ✅ ROM 日志控制 — eFuse 可永久关闭启动日志
  ⚠️ 安全功能启用后不可逆 (eFuse 一次性烧写)
  
  定位: 通用 IoT/Wi-Fi MCU，安全是"可选功能"
        量产时可烧 eFuse 锁死 → 变成"安全的 IoT MCU"

CYT2BL3 的安全是强制的：
  ✅ 验证签名 → 防止恶意固件 (ISO 21434 网络安全)
  ✅ 配置 DAP → 防止调试器偷看安全数据
  ✅ eFuse 配置 → 芯片生命周期管理
  ✅ SROM API → Flash 操作必须经过安全核
  ✅ 独立电压域 → CM0+ 可以在 CM4 崩溃时继续运行
  ⚠️ 安全启动从芯片出厂即生效
  
  定位: 汽车安全 MCU，安全是"基础设施"
        从一开始就不能绕过
```

---

## 四、对调试工具的影响

```
RP2040 / STM32H7 / LPC55 / ESP32-S3:
  → probe-rs 的标准复位序列就能工作
  → halt → 等待 → 成功
  → 原因: 复位后所有核的 SWD/JTAG 都可达

ESP32-S3 特别注意:
  ✅ 内置 USB Serial/JTAG 控制器
  ✅ 复位后 PRO CPU 先跑，但 APP CPU 也可通过 JTAG 访问
  ✅ openocd/probe-rs 原生支持 (esp32s3 target)
  ✅ JTAG 可用 GPIO3 + eFuse 配置信号源

CYT2BL3:
  → probe-rs 的标准复位序列必然失败
  → halt → 超时 → SwdDpError
  → 原因: 复位后 CM4 不存在于总线上！
  → 需要: 先连 CM0+ → 等它完成认证 → 确认 CM4 释放 → 再连 CM4
  → probe-rs 需要特殊适配 (我们的 YAML + Flash 算法)
```

---

## 五、总结

```
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║  CYT2BL3 不是"怪"，是"汽车级"：                              ║
║                                                              ║
║  RP2040   = 共享单车的锁 (踢开就走)                          ║
║  STM32H7  = 家用门锁 (拧一下钥匙)                            ║
║  ESP32-S3 = 小区门禁刷卡 (刷卡进门，可选加指纹锁)            ║
║  CYT2BL3  = 银行金库门 (指纹+密码+钥匙+保安确认)             ║
║                                                              ║
║  关键差异:                                                    ║
║  ESP32-S3 的安全功能是"add-on" — 默认关闭，量产时锁定        ║
║  CYT2BL3 的安全功能是"built-in" — 从芯片设计就内置           ║
║                                                              ║
║  probe-rs 目前只会开 RP2040/STM32H7/ESP32-S3/LPC55 的锁，   ║
║  还没学会开金库门。                                          ║
║  但我们的 YAML + Flash 算法已经准备好了，                     ║
║  等它学会开金库门那天，直接就能用。                           ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

---

*报告版本：v1.1 | 2026-05-04 | 基于各芯片 Datasheet 及社区文档*
*新增：ESP32-S3 启动流程 | 参考资料：ESP32-S3 技术参考手册 v1.8 + ESP-IDF v6.0.1 官方文档*
