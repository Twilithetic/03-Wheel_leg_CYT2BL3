# CYT2BL3 开发资源收藏夹

> *在线文档、工具、GitHub 仓库 — 一个页面全收录*

---

## 📚 外设驱动库

### Infineon PDL (Peripheral Driver Library)

| 资源 | 链接 |
|------|------|
| **API 文档总入口** | https://infineon.github.io/mtb-pdl-cat1/pdl_api_reference_manual/html/index.html |
| **模块列表** (GPIO/UART/SPI/CAN...) | https://infineon.github.io/mtb-pdl-cat1/pdl_api_reference_manual/html/modules.html |
| **快速入门** | https://infineon.github.io/mtb-pdl-cat1/pdl_api_reference_manual/html/page_getting_started.html |
| **GitHub 源码** | https://github.com/Infineon/mtb-pdl-cat1 |

### Infineon HAL (Hardware Abstraction Layer)

| 资源 | 链接 |
|------|------|
| **HAL 模块总览** | https://infineon.github.io/mtb-hal-cat1/html/modules.html |
| **GitHub 源码** | https://github.com/Infineon/mtb-hal-cat1 |

### Infineon core-lib

| 资源 | 链接 |
|------|------|
| **GitHub 源码** (cy_utils.h) | https://github.com/Infineon/core-lib |

---

## 🧵 RTOS

### FreeRTOS

| 资源 | 链接 |
|------|------|
| **官方文档入口** | https://www.freertos.org/Documentation/00-Overview |
| **API 参考手册 PDF** | https://www.freertos.org/media/2018/FreeRTOS_Reference_Manual_V10.0.0.pdf |
| **官网首页** | https://www.freertos.org/ |
| **GitHub 内核源码** | https://github.com/FreeRTOS/FreeRTOS-Kernel |

---

## 💻 ARM 标准库

### CMSIS

| 资源 | 链接 |
|------|------|
| **GitHub 源码** | https://github.com/ARM-software/CMSIS_5 |
| **CMSIS-Core 文档** | https://arm-software.github.io/CMSIS_5/Core/html/index.html |
| **CMSIS-DSP 文档** | https://arm-software.github.io/CMSIS_5/DSP/html/index.html |

---

## 🔧 工具与 IDE

| 资源 | 链接 |
|------|------|
| **ModusToolbox** (免费 IDE) | https://www.infineon.com/modustoolbox |
| **Infineon Auto Flash Utility** | https://www.infineon.com/auto-flash-utility |
| **SEGGER J-Link 软件** | https://www.segger.com/downloads/jlink/ |
| **EIDE 插件** (VS Code) | https://marketplace.visualstudio.com/items?itemName=CL.eide |
| **EIDE 文档** | https://em-ide.com/ |
| **Cortex-Debug 插件** | https://marketplace.visualstudio.com/items?itemName=marus25.cortex-debug |
| **GCC ARM 工具链** | https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain |

---

## 📖 Infineon 官方文档

| 文档 | 链接 |
|------|------|
| **CYT2BL 产品页** | https://www.infineon.com/products/microcontroller/32-bit-traveo-t2g-arm-cortex/for-body/t2g-cyt2bl |
| **TRAVEO T2G 文档中心** | https://documentation.infineon.com/traveo/ |
| **ModusToolbox 文档** | https://documentation.infineon.com/traveo/docs/fjr1650962894055 |
| **TRAVEO T2G 代码示例** | https://github.com/Infineon/TRAVEO_T2G_code_examples |
| **开发者社区论坛** | https://community.infineon.com/t5/TRAVEO-T2G/bd-p/TRAVEO-T2G |

### 关键应用笔记 (Application Notes)

| 编号 | 名称 | 说明 |
|------|------|------|
| AN220118 | Getting Started with TRAVEO T2G | 入门指南，工具链介绍 |
| AN235305 | TRAVEO T2G in ModusToolbox | ModusToolbox 开发流程 |
| AN220270 | Hardware Design Guide | JTAG/SWD 硬件设计 |
| AN227076 | Flash Bootloader | CAN/LIN 量产烧录 |
| AN220242 | Flash Accessing Procedure | Flash 编程流程 |

---

## 🔬 调试与烧录

| 资源 | 链接 |
|------|------|
| **OpenOCD 官网** | https://openocd.org/ |
| **OpenOCD 用户指南** | https://openocd.org/doc/html/ |
| **Infineon OpenOCD 配置** | ModusToolbox 内置 / Auto Flash Utility 内置 |

---

## 🦀 Rust 相关

| 资源 | 链接 |
|------|------|
| **TRAVEO T2G PAC 生成工具** | https://github.com/Infineon/traveo-t2g-pal |
| **TRAVEO T2G Rust 入门示例** | https://github.com/Infineon/gpio-access-t2g-bodyentry-starterkit |
| **Infineon Rust 博客** | https://community.infineon.com/t5/Blogs/Getting-started-with-Rust-on-TRAVEO-T2G-devices/ba-p/462206 |
| **Embassy (Rust 异步运行时)** | https://embassy.dev/ |
| **RTIC (Rust 实时框架)** | https://rtic.rs/ |
| **embedded-hal (Rust 嵌入式标准)** | https://docs.rs/embedded-hal |

---

## 📦 本项目 GitHub 仓库克隆命令

```bash
# 外设驱动
git clone --depth 1 https://github.com/Infineon/mtb-pdl-cat1.git         libs/pdl
git clone --depth 1 https://github.com/Infineon/mtb-hal-cat1.git         libs/hal
git clone --depth 1 https://github.com/Infineon/core-lib.git             libs/core-lib

# ARM 标准
git clone --depth 1 https://github.com/ARM-software/CMSIS_5.git          libs/CMSIS_5

# RTOS
git clone --depth 1 https://github.com/FreeRTOS/FreeRTOS-Kernel.git      libs/FreeRTOS
```

---

## 🎯 常用命令速查

```bash
# ===== 编译 =====
make                  # 增量编译
make clean && make all # 全量编译
make flash            # 编译 + 烧录

# ===== VSCode =====
Ctrl+Shift+B → 🔨 build    # 编译
Ctrl+Shift+B → 🔄 rebuild  # 清理 + 重编
Ctrl+Shift+B → 🧹 clean    # 清理
```

---

*收藏夹版本：v1.0 | 2026-05-04*
