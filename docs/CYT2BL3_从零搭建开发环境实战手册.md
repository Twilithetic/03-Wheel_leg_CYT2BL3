# CYT2BL3 开发环境搭建实战手册

> *从零开始，一步步搭建 EIDE + GCC + Makefile + VSCode 编译环境*
> 芯片：Infineon CYT2BL3 (TRAVEO T2G, Cortex-M4F + M0+)
> 基于实际踩坑经验整理 — 2026-05-04

---

## 目录

1. [项目结构总览](#一项目结构总览)
2. [第一步：下载所有库](#二第一步下载所有库)
3. [第二步：编写启动文件](#三第二步编写启动文件)
4. [第三步：编写链接脚本](#四第三步编写链接脚本)
5. [第四步：编写 Makefile](#五第四步编写-makefile)
6. [第五步：安装 make 工具](#六第五步安装-make-工具)
7. [第六步：配置 VSCode Tasks](#七第六步配置-vscode-tasks)
8. [第七步：编译测试](#八第七步编译测试)
9. [常用命令速查](#九常用命令速查)
10. [常见问题排查](#十常见问题排查)

---

## 一、项目结构总览

```
Wheel_leg_CYT2BL3/
├── .vscode/
│   └── tasks.json           ← VSCode 构建任务 (Ctrl+Shift+B)
├── .eide/
│   └── eide.yml             ← EIDE 项目配置
├── src/
│   ├── main.c               ← 主程序
│   ├── startup_cyt2bl3_cm4.S    ← 启动文件 (汇编)
│   ├── cyt2bl3_flash.ld         ← 链接脚本
│   └── FreeRTOSConfig.h         ← FreeRTOS 配置 (以后用)
├── libs/
│   ├── CMSIS_5/             ← ARM CMSIS 标准头文件
│   ├── pdl/                 ← Infineon PDL 外设驱动库
│   ├── hal/                 ← Infineon HAL 硬件抽象层
│   ├── core-lib/            ← Infineon core-lib (cy_utils.h)
│   └── FreeRTOS/            ← FreeRTOS 内核
├── Makefile                 ← 构建脚本 (make 命令)
├── build.ps1                ← PowerShell 编译脚本 (备选)
└── docs/                    ← 各种分析报告
```

---

## 二、第一步：下载所有库

### 2.1 克隆命令（在项目根目录执行）

```powershell
# 创建 libs 目录
mkdir libs
cd libs

# 1. ARM CMSIS — 提供 core_cm4.h 等标准头文件
git clone --depth 1 https://github.com/ARM-software/CMSIS_5.git CMSIS_5

# 2. Infineon PDL — 外设驱动库 (Peripheral Driver Library)
git clone --depth 1 https://github.com/Infineon/mtb-pdl-cat1.git pdl

# 3. Infineon HAL — 硬件抽象层 (Hardware Abstraction Layer)
git clone --depth 1 https://github.com/Infineon/mtb-hal-cat1.git hal

# 4. Infineon core-lib — 提供 cy_utils.h 等工具函数
git clone --depth 1 https://github.com/Infineon/core-lib.git core-lib

# 5. FreeRTOS — 实时操作系统内核
git clone --depth 1 https://github.com/FreeRTOS/FreeRTOS-Kernel.git FreeRTOS

cd ..
```

### 2.2 库文件关键路径速查

| 需要的文件 | 路径 |
|-----------|------|
| `core_cm4.h` | `libs/CMSIS_5/CMSIS/Core/Include/` |
| `ARMCM4_FP.h` (设备模板) | `libs/CMSIS_5/Device/ARM/ARMCM4/Include/` |
| `cy_pdl.h` (以后用) | `libs/pdl/devices/COMPONENT_CAT1C/include/` |
| `cy_utils.h` | `libs/core-lib/include/` |
| `FreeRTOS.h` (以后用) | `libs/FreeRTOS/include/` |
| `port.c` (ARM_CM4F) | `libs/FreeRTOS/portable/GCC/ARM_CM4F/` |

---

## 三、第二步：编写启动文件

### 3.1 启动文件做什么？

```
芯片上电 → 启动文件 → 初始化 FPU → 复制 .data → 清零 .bss → main()
```

### 3.2 完整启动文件：`src/startup_cyt2bl3_cm4.S`

```assembly
/**************************************************************************//**
 * @file     startup_cyt2bl3_cm4.S
 * @brief    CYT2BL3 Cortex-M4F 启动文件 (GCC ARM)
 * 
 * 基于 CMSIS ARMCM4 模板修改
 ******************************************************************************/

                .syntax  unified
                .arch    armv7e-m
                .fpu     fpv4-sp-d16          /* 单精度 FPU */

/* ========== 中断向量表 ========== */
                .section .vectors
                .align   2
                .globl   __Vectors
__Vectors:
                .long    __StackTop           /*  0: 初始栈顶 */
                .long    Reset_Handler        /*  1: 复位 */
                .long    NMI_Handler          /*  2: NMI */
                .long    HardFault_Handler    /*  3: HardFault */
                .long    MemManage_Handler    /*  4: MemManage */
                .long    BusFault_Handler     /*  5: BusFault */
                .long    UsageFault_Handler   /*  6: UsageFault */
                .long    0                    /*  7 */
                .long    0                    /*  8 */
                .long    0                    /*  9 */
                .long    0                    /* 10 */
                .long    SVC_Handler          /* 11: SVCall */
                .long    DebugMon_Handler     /* 12: DebugMon */
                .long    0                    /* 13 */
                .long    PendSV_Handler       /* 14: PendSV */
                .long    SysTick_Handler      /* 15: SysTick */

                /* 外设中断 (简化: GPIO 0-9) */
                .long    ioss_interrupts_gpio_0_IRQHandler
                .long    ioss_interrupts_gpio_1_IRQHandler
                .long    ioss_interrupts_gpio_2_IRQHandler
                .long    ioss_interrupts_gpio_3_IRQHandler
                .long    ioss_interrupts_gpio_4_IRQHandler
                .long    ioss_interrupts_gpio_5_IRQHandler
                .long    ioss_interrupts_gpio_6_IRQHandler
                .long    ioss_interrupts_gpio_7_IRQHandler
                .long    ioss_interrupts_gpio_8_IRQHandler
                .long    ioss_interrupts_gpio_9_IRQHandler
                /* 其余中断留空 */
                .space   (214 * 4)

__Vectors_End:
                .equ     __Vectors_Size, __Vectors_End - __Vectors

/* ========== 复位处理 ========== */
                .thumb
                .section .text
                .align   2

                .thumb_func
                .type    Reset_Handler, %function
                .globl   Reset_Handler
                .fnstart
Reset_Handler:
                /* 1. 使能 FPU */
                ldr      r0, =0xE000ED88        /* CPACR 寄存器 */
                ldr      r1, [r0]
                orr      r1, r1, #(0xF << 20)   /* 使能 CP10, CP11 */
                str      r1, [r0]
                dsb
                isb

                /* 2. 调用 SystemInit */
                bl       Cy_SystemInit

                /* 3. 复制 .data 段 (FLASH → SRAM) */
                ldr      r4, =__copy_table_start__
                ldr      r5, =__copy_table_end__
.L_loop0:
                cmp      r4, r5
                bge      .L_loop0_done
                ldr      r1, [r4]
                ldr      r2, [r4, #4]
                ldr      r3, [r4, #8]
                lsls     r3, r3, #2
.L_loop0_0:
                subs     r3, #4
                ittt     ge
                ldrge    r0, [r1, r3]
                strge    r0, [r2, r3]
                bge      .L_loop0_0
                adds     r4, #12
                b        .L_loop0
.L_loop0_done:

                /* 4. 清零 .bss 段 */
                ldr      r3, =__zero_table_start__
                ldr      r4, =__zero_table_end__
.L_loop2:
                cmp      r3, r4
                bge      .L_loop2_done
                ldr      r1, [r3]
                ldr      r2, [r3, #4]
                lsls     r2, r2, #2
                movs     r0, 0
.L_loop2_0:
                subs     r2, #4
                itt      ge
                strge    r0, [r1, r2]
                bge      .L_loop2_0
                adds     r3, #8
                b        .L_loop2
.L_loop2_done:

                /* 5. 跳转 main() */
                bl       main
                b        .

                .fnend
                .size    Reset_Handler, . - Reset_Handler

/* ========== 默认中断处理 (死循环) ========== */
                .thumb_func
                .type    HardFault_Handler, %function
                .weak    HardFault_Handler
HardFault_Handler:
                b        .

                .thumb_func
                .type    Default_Handler, %function
                .weak    Default_Handler
Default_Handler:
                b        .

                .macro   Set_Default_Handler  Handler_Name
                .weak    \Handler_Name
                .set     \Handler_Name, Default_Handler
                .endm

                Set_Default_Handler  NMI_Handler
                Set_Default_Handler  MemManage_Handler
                Set_Default_Handler  BusFault_Handler
                Set_Default_Handler  UsageFault_Handler
                Set_Default_Handler  SVC_Handler
                Set_Default_Handler  DebugMon_Handler
                Set_Default_Handler  PendSV_Handler
                Set_Default_Handler  SysTick_Handler

                Set_Default_Handler  ioss_interrupts_gpio_0_IRQHandler
                Set_Default_Handler  ioss_interrupts_gpio_1_IRQHandler
                Set_Default_Handler  ioss_interrupts_gpio_2_IRQHandler
                Set_Default_Handler  ioss_interrupts_gpio_3_IRQHandler
                Set_Default_Handler  ioss_interrupts_gpio_4_IRQHandler
                Set_Default_Handler  ioss_interrupts_gpio_5_IRQHandler
                Set_Default_Handler  ioss_interrupts_gpio_6_IRQHandler
                Set_Default_Handler  ioss_interrupts_gpio_7_IRQHandler
                Set_Default_Handler  ioss_interrupts_gpio_8_IRQHandler
                Set_Default_Handler  ioss_interrupts_gpio_9_IRQHandler

                .end
```

---

## 四、第三步：编写链接脚本

### 4.1 CYT2BL3 内存布局

```
Code Flash: 0x10000000  4160 KB  ← 存代码
Work Flash: 0x14000000   128 KB  ← 存配置
SRAM:       0x08000000   512 KB  ← 运行时数据 (前 2KB 保留)
```

### 4.2 完整链接脚本：`src/cyt2bl3_flash.ld`

```ld
/*****************************************************************************
 * CYT2BL3 GCC 链接脚本
 * Flash: 0x10000000 (4160 KB)    SRAM: 0x08000000 (512 KB, 前 2KB 保留)
 *****************************************************************************/

__STACK_SIZE  =  0x00002000;    /* 8 KB 栈 */
__HEAP_SIZE   =  0x00001000;    /* 4 KB 堆 */

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x10000000, LENGTH = 4160K
    SRAM  (rwx) : ORIGIN = 0x08000800, LENGTH = 510K
}

ENTRY(Reset_Handler)

SECTIONS
{
    /* 中断向量表 */
    .vectors : {
        KEEP(*(.vectors))
        . = ALIGN(256);
    } > FLASH

    /* 代码和只读数据 */
    .text : {
        *(.text*)
        *(.rodata*)
        *(.glue_7) *(.glue_7t)
        KEEP(*(.init)) KEEP(*(.fini))
        . = ALIGN(4);
        _etext = .;
    } > FLASH

    /* ARM 异常表 */
    .ARM.extab : { *(.ARM.extab*) } > FLASH
    .ARM.exidx : { *(.ARM.exidx*) } > FLASH

    /* C++ 构造函数 */
    .preinit_array : { KEEP(*(.preinit_array*)) } > FLASH
    .init_array : { KEEP(*(.init_array*)) } > FLASH
    .fini_array : { KEEP(*(.fini_array*)) } > FLASH

    /* .data 段 (初始值在 FLASH, 运行时复制到 SRAM) */
    _sidata = LOADADDR(.data);
    .data : { *(.data*) . = ALIGN(4); } > SRAM AT > FLASH

    /* .bss 段 (运行时在 SRAM, 启动时清零) */
    .bss (NOLOAD) : { *(.bss*) *(COMMON) . = ALIGN(4); } > SRAM

    /* 堆 */
    .heap (NOLOAD) : {
        PROVIDE(__heap_start__ = .);
        . = . + __HEAP_SIZE;
        . = ALIGN(8);
        PROVIDE(__heap_end__ = .);
    } > SRAM

    /* 栈 */
    .stack (NOLOAD) : {
        . = ALIGN(8);
        . = . + __STACK_SIZE;
        . = ALIGN(8);
        PROVIDE(__StackTop = .);
    } > SRAM

    /* 复制表 (启动代码用) */
    .copy_table : {
        __copy_table_start__ = .;
        LONG(LOADADDR(.data))
        LONG(ADDR(.data))
        LONG(SIZEOF(.data) / 4)
        __copy_table_end__ = .;
    } > FLASH

    /* 清零表 (启动代码用) */
    .zero_table : {
        __zero_table_start__ = .;
        LONG(ADDR(.bss))
        LONG(SIZEOF(.bss) / 4)
        __zero_table_end__ = .;
    } > FLASH
}
```

### 4.3 ⚠️ 关键注意事项

- **copy_table 和 zero_table 必须放在 section 内部！** 不能裸放在 `SECTIONS { }` 中。
- `__StackTop` 必须在链接脚本中定义，启动文件引用它。
- SRAM 前 2KB 被 CYT2BL3 内部保留，所以要跳过：`ORIGIN = 0x08000800`

---

## 五、第四步：编写 Makefile

### 5.1 Makefile 核心概念

```
目标: 依赖
	命令

firmware.elf: main.o startup.o      ← "要生成 firmware.elf，需要 main.o 和 startup.o"
	arm-none-eabi-gcc main.o startup.o -o firmware.elf   ← "生成命令"

main.o: main.c                      ← "main.o 依赖 main.c"
	arm-none-eabi-gcc -c main.c -o main.o   ← "编译命令"
```

make 自动比较时间戳：文件没改就不重编！

### 5.2 完整 Makefile

```makefile
# ========== 工具链 ==========
GCC     = C:/Users/29344/.eide/tools/gcc_arm/bin/arm-none-eabi-gcc.exe
SIZE    = C:/Users/29344/.eide/tools/gcc_arm/bin/arm-none-eabi-size.exe
OBJCOPY = C:/Users/29344/.eide/tools/gcc_arm/bin/arm-none-eabi-objcopy.exe

# ========== 目标 ==========
TARGET    = firmware
BUILD_DIR = build

# ========== 编译标志 ==========
CPU_FLAGS  = -mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16
C_DEFS     = -D__CORTEX_M4 -D__FPU_PRESENT=1 -DCYT2BL3
C_FLAGS    = $(CPU_FLAGS) $(C_DEFS) -std=c11 -O0 -g3 -Wall -Wextra
C_FLAGS   += -ffunction-sections -fdata-sections -fno-common
AS_FLAGS   = $(CPU_FLAGS) -g
LD_FLAGS   = $(CPU_FLAGS) -T src/cyt2bl3_flash.ld -nostartfiles
LD_FLAGS  += --specs=nano.specs --specs=nosys.specs
LD_FLAGS  += -Wl,-Map=$(BUILD_DIR)/$(TARGET).map
LD_FLAGS  += -Wl,--gc-sections -Wl,--print-memory-usage

# ========== Include 路径 ==========
INCLUDES  = -Isrc
INCLUDES += -Ilibs/CMSIS_5/CMSIS/Core/Include
INCLUDES += -Ilibs/CMSIS_5/Device/ARM/ARMCM4/Include

# ========== 源文件 ==========
C_SRCS   = src/main.c
ASM_SRCS = src/startup_cyt2bl3_cm4.S

C_OBJS   = $(C_SRCS:%.c=$(BUILD_DIR)/%.o)
ASM_OBJS = $(ASM_SRCS:%.S=$(BUILD_DIR)/%.o)
OBJS     = $(C_OBJS) $(ASM_OBJS)

# ========== 目标 ==========
.PHONY: all clean flash

all: $(BUILD_DIR)/$(TARGET).elf $(BUILD_DIR)/$(TARGET).hex $(BUILD_DIR)/$(TARGET).bin

# 链接
$(BUILD_DIR)/$(TARGET).elf: $(OBJS)
	@echo "🔗 Linking..."
	$(GCC) $(LD_FLAGS) $(OBJS) -o $@
	@$(SIZE) $@

$(BUILD_DIR)/$(TARGET).hex: $(BUILD_DIR)/$(TARGET).elf
	@$(OBJCOPY) -O ihex $< $@

$(BUILD_DIR)/$(TARGET).bin: $(BUILD_DIR)/$(TARGET).elf
	@$(OBJCOPY) -O binary $< $@

# 编译 C
$(BUILD_DIR)/%.o: %.c
	@mkdir -p $(dir $@)
	@echo "🔧 Compiling $< ..."
	$(GCC) -c $(C_FLAGS) $(INCLUDES) $< -o $@

# 编译汇编
$(BUILD_DIR)/%.o: %.S
	@mkdir -p $(dir $@)
	@echo "🔧 Assembling $< ..."
	$(GCC) -c $(AS_FLAGS) -x assembler-with-cpp $(INCLUDES) $< -o $@

# 清理
clean:
	@echo "🧹 Cleaning..."
	rm -rf $(BUILD_DIR)
	@echo "✅ Done!"

# 烧录 (需要 J-Link 连接)
flash: $(BUILD_DIR)/$(TARGET).hex
	@echo "🔥 Flashing..."
	@echo "r" > $(BUILD_DIR)/flash.jlink
	@echo "h" >> $(BUILD_DIR)/flash.jlink
	@echo "loadfile $(BUILD_DIR)/$(TARGET).hex" >> $(BUILD_DIR)/flash.jlink
	@echo "r" >> $(BUILD_DIR)/flash.jlink
	@echo "g" >> $(BUILD_DIR)/flash.jlink
	@echo "qc" >> $(BUILD_DIR)/flash.jlink
	JLink.exe -device CYT2BL3 -if SWD -speed 4000 -autoconnect 1 \
		-CommanderScript $(BUILD_DIR)/flash.jlink
	@echo "✅ Flash done!"
```

### 5.3 如何加新文件？

```makefile
# 加 C 文件：
C_SRCS += src/led.c
C_SRCS += src/uart.c

# 加汇编文件：
ASM_SRCS += src/startup_cm0.S

# 加 include 路径：
INCLUDES += -Ilibs/FreeRTOS/include
INCLUDES += -Ilibs/pdl/drivers/include
```

---

## 六、第五步：安装 make 工具

### 6.1 make 在哪？

**EIDE 自带！** 不需要额外安装！

```
路径: C:\Users\29344\.eide\bin\builder\msys\bin\make.exe
```

### 6.2 永久添加到 PATH

```powershell
# 方法1: PowerShell (推荐)
$makePath = "C:\Users\29344\.eide\bin\builder\msys\bin"
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
[Environment]::SetEnvironmentVariable("Path", "$currentPath;$makePath", "User")
```

```cmd
# 方法2: CMD (管理员)
setx PATH "%PATH%;C:\Users\29344\.eide\bin\builder\msys\bin"
```

> ⚠️ 添加后需要**重启终端**才能生效！

### 6.3 验证安装

```bash
make --version
# 输出: GNU Make 3.81
```

### 6.4 如果 EIDE 没有 make（备选方案）

```powershell
# 方案A: winget
winget install GnuWin32.Make

# 方案B: Chocolatey
choco install make

# 方案C: 直接下载 make.exe
# https://sourceforge.net/projects/ezwinports/files/
# 下载 make-4.4.1-without-guile-w32-bin.zip
# 解压后把 make.exe 放到 C:\Windows\ 或项目目录
```

---

## 七、第六步：配置 VSCode Tasks

### 7.1 创建 `.vscode/tasks.json`

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "🔨 build",
            "type": "shell",
            "command": "make",
            "args": ["all"],
            "group": {"kind": "build", "isDefault": true},
            "options": {
                "env": {
                    "PATH": "C:\\Users\\29344\\.eide\\bin\\builder\\msys\\bin;${env:PATH}"
                }
            },
            "problemMatcher": ["$gcc"],
            "presentation": {"reveal": "always", "panel": "dedicated"}
        },
        {
            "label": "🧹 clean",
            "type": "shell",
            "command": "make",
            "args": ["clean"],
            "group": "build",
            "options": {
                "env": {
                    "PATH": "C:\\Users\\29344\\.eide\\bin\\builder\\msys\\bin;${env:PATH}"
                }
            }
        },
        {
            "label": "🔄 rebuild",
            "type": "shell",
            "command": "make",
            "args": ["clean", "all"],
            "group": "build",
            "options": {
                "env": {
                    "PATH": "C:\\Users\\29344\\.eide\\bin\\builder\\msys\\bin;${env:PATH}"
                }
            },
            "problemMatcher": ["$gcc"]
        },
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
    ]
}
```

### 7.2 用法

```
Ctrl+Shift+B → 弹出任务列表
  🔨 build    → 增量编译
  🔄 rebuild  → 清理 + 全量编译
  🧹 clean    → 清理
  🔥 flash    → 编译 + 烧录
```

---

## 八、第七步：编译测试

### 8.1 命令行测试

```bash
# 清理旧文件
make clean

# 编译
make all

# 期望输出:
#   🔧 Compiling src/main.c ...
#   🔧 Assembling src/startup_cyt2bl3_cm4.S ...
#   🔗 Linking...
#      text    data    bss     dec     hex
#      5628    100     12296   18024   4668   build/firmware.elf
#   FLASH: 0.13%    SRAM: 2.37%
```

### 8.2 VSCode 测试

```
1. Ctrl+Shift+B
2. 选 "🔄 rebuild"
3. 查看终端输出
```

### 8.3 min.c 示例（用于验证）

```c
/**
 * CYT2BL3 极简示例 — 纯 CMSIS，零依赖
 */
#include <stdint.h>
#include "ARMCM4_FP.h"   /* CMSIS 设备模板 */

/* CYT2BL3 GPIO 寄存器 */
#define GPIO_PRT0_BASE      0x40310000UL
#define GPIO_CFG_REG        0x20
#define GPIO_OUT_INV_REG    0x0C

uint32_t SystemCoreClock = 160000000UL;

/* SystemInit — 启动代码调用 */
void Cy_SystemInit(void)
{
    SCB->CPACR |= ((3UL << 10*2) | (3UL << 11*2));
    __DSB(); __ISB();
}

/* 简易延时 */
static void delay(uint32_t n) { while(n--) __NOP(); }

/* GPIO 推挽输出 */
static void gpio_output(uint32_t port, uint8_t pin)
{
    volatile uint32_t *cfg = (uint32_t*)(port + GPIO_CFG_REG);
    uint32_t shift = (pin % 8) * 4;
    uint32_t val = *cfg;
    val &= ~(0x0FUL << shift);
    val |=  (0x09UL << shift);
    *cfg = val;
}

/* 翻转引脚 */
static void gpio_toggle(uint32_t port, uint8_t pin)
{
    *(volatile uint32_t*)(port + GPIO_OUT_INV_REG) = (1UL << pin);
}

int main(void)
{
    gpio_output(GPIO_PRT0_BASE, 5);  /* LED 接 P0.5 */
    while (1) {
        gpio_toggle(GPIO_PRT0_BASE, 5);
        delay(80000000);  /* ~500ms */
    }
    return 0;
}
```

---

## 九、常用命令速查

```bash
# ===== 编译 =====
make                  # 增量编译 (只编改过的文件)
make all              # 同 make
make clean && make all # 全量编译

# ===== VSCode =====
Ctrl+Shift+B → 🔨 build   # 增量编译
Ctrl+Shift+B → 🔄 rebuild # 全量编译
Ctrl+Shift+B → 🧹 clean   # 清理
Ctrl+Shift+B → 🔥 flash   # 编译 + 烧录

# ===== 生成文件 =====
ls build/firmware.elf     # ELF (调试用)
ls build/firmware.hex     # HEX (烧录用)
ls build/firmware.bin     # BIN (原始二进制)
ls build/firmware.map     # MAP (内存布局)
```

---

## 十、常见问题排查

### 10.1 `make: command not found`

```bash
# 原因: make 不在 PATH 中
# 解决: 临时加到 PATH
set PATH=C:\Users\29344\.eide\bin\builder\msys\bin;%PATH%
```

### 10.2 `Nothing to be done for 'all'`

```
不是报错！说明所有文件都已是最新，不需要重新编译。
想强制重编: make clean && make all
```

### 10.3 `fatal error: core_cm4.h: No such file`

```
原因: CMSIS include 路径没配
检查 Makefile 中 INCLUDES 是否包含:
  -Ilibs/CMSIS_5/CMSIS/Core/Include
```

### 10.4 `fatal error: startup_cat1c.h: No such file`

```
原因: 用了 PDL 的 cy_pdl.h，但它依赖 startup_cat1c.h
解决: 暂时不用 PDL，用 ARMCM4_FP.h 替代
      (等 PDL 支持 CYT2BL 后再切换)
```

### 10.5 `syntax error in linker script`

```
原因: copy_table / zero_table 裸放在 SECTIONS 外面了
解决: 必须包裹在 .copy_table { } 和 .zero_table { } 段内
```

### 10.6 `undefined reference to '_exit'`

```
原因: Newlib 标准库需要系统调用桩
解决: 链接时加 --specs=nosys.specs
```

### 10.7 `__FPU_PRESENT redefined`

```
只是 warning，不影响！ARMCM4_FP.h 内部定义了 __FPU_PRESENT，
而 Makefile 也传了 -D__FPU_PRESENT=1，去掉 Makefile 里的即可。
```

---

## 附录：从零到编译的完整操作流程

```
1. 下载库
   cd Wheel_leg_CYT2BL3
   mkdir libs && cd libs
   git clone --depth 1 https://github.com/ARM-software/CMSIS_5.git CMSIS_5
   git clone --depth 1 https://github.com/Infineon/mtb-pdl-cat1.git pdl
   git clone --depth 1 https://github.com/Infineon/mtb-hal-cat1.git hal
   git clone --depth 1 https://github.com/Infineon/core-lib.git core-lib
   git clone --depth 1 https://github.com/FreeRTOS/FreeRTOS-Kernel.git FreeRTOS
   cd ..

2. 设置 make PATH
   [Environment]::SetEnvironmentVariable("Path",
     "$([Environment]::GetEnvironmentVariable('Path','User'));C:\Users\29344\.eide\bin\builder\msys\bin",
     "User")
   重启终端

3. 确认文件就位
   src/startup_cyt2bl3_cm4.S  ← 启动文件
   src/cyt2bl3_flash.ld       ← 链接脚本
   src/main.c                 ← 主程序
   Makefile                   ← 构建脚本

4. 编译
   make clean && make all

5. 输出
   build/firmware.elf  ← ✅ 成功了！
```

---

*手册版本：v1.0 | 2026-05-04 | 踩坑实录，亲测可用*
