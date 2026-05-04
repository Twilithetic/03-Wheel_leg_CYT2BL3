/**************************************************************************//**
 * @file     startup_cyt2bl3_cm4.S
 * @brief    CYT2BL3 Cortex-M4F Startup File for GCC ARM
 * @based_on CMSIS ARMCM4 startup template
 * 
 * CYT2BL3 内存布局:
 *   Code Flash: 0x10000000 (4160 KB)
 *   Work Flash: 0x14000000 (128 KB)
 *   SRAM:       0x08000000 (512 KB, 前 2KB 保留)
 ******************************************************************************/

                .syntax  unified
                .arch    armv7e-m
                .fpu     fpv4-sp-d16          /* 单精度 FPU */

                .section .vectors
                .align   2
                .globl   __Vectors
                .globl   __Vectors_End
                .globl   __Vectors_Size
__Vectors:
                .long    __StackTop                         /*  0: 初始栈顶 */
                .long    Reset_Handler                      /*  1: 复位 */
                .long    NMI_Handler                        /*  2: NMI */
                .long    HardFault_Handler                  /*  3: HardFault */
                .long    MemManage_Handler                  /*  4: MemManage */
                .long    BusFault_Handler                   /*  5: BusFault */
                .long    UsageFault_Handler                 /*  6: UsageFault */
                .long    0                                  /*  7: 保留 */
                .long    0                                  /*  8: 保留 */
                .long    0                                  /*  9: 保留 */
                .long    0                                  /* 10: 保留 */
                .long    SVC_Handler                        /* 11: SVCall */
                .long    DebugMon_Handler                   /* 12: DebugMon */
                .long    0                                  /* 13: 保留 */
                .long    PendSV_Handler                     /* 14: PendSV */
                .long    SysTick_Handler                    /* 15: SysTick */

                /* 外设中断向量 — CYT2BL3 有多达 240 个中断 */
                .long    ioss_interrupts_gpio_0_IRQHandler       /* 16: GPIO Port 0 */
                .long    ioss_interrupts_gpio_1_IRQHandler       /* 17: GPIO Port 1 */
                .long    ioss_interrupts_gpio_2_IRQHandler       /* 18: GPIO Port 2 */
                .long    ioss_interrupts_gpio_3_IRQHandler       /* 19: GPIO Port 3 */
                .long    ioss_interrupts_gpio_4_IRQHandler       /* 20: GPIO Port 4 */
                .long    ioss_interrupts_gpio_5_IRQHandler       /* 21: GPIO Port 5 */
                .long    ioss_interrupts_gpio_6_IRQHandler       /* 22: GPIO Port 6 */
                .long    ioss_interrupts_gpio_7_IRQHandler       /* 23: GPIO Port 7 */
                .long    ioss_interrupts_gpio_8_IRQHandler       /* 24: GPIO Port 8 */
                .long    ioss_interrupts_gpio_9_IRQHandler       /* 25: GPIO Port 9 */
                /* 其余中断向量由 PDL 框架动态管理 */
                .space   (214 * 4)                               /* 补足到 240 个中断 */

__Vectors_End:
                .equ     __Vectors_Size, __Vectors_End - __Vectors
                .size    __Vectors, . - __Vectors


                .thumb
                .section .text
                .align   2

                .thumb_func
                .type    Reset_Handler, %function
                .globl   Reset_Handler
                .fnstart
Reset_Handler:
                /* 初始化 FPU（CYT2BL3 有硬件 FPU） */
                ldr      r0, =0xE000ED88           /* CPACR 寄存器 */
                ldr      r1, [r0]
                orr      r1, r1, #(0xF << 20)      /* 使能 CP10, CP11 (FPU) */
                str      r1, [r0]
                dsb
                isb

                /* 调用 PDL 系统初始化 */
                bl       Cy_SystemInit

                /* 复制 .data 段 (Flash → SRAM) */
                ldr      r4, =__copy_table_start__
                ldr      r5, =__copy_table_end__

.L_loop0:
                cmp      r4, r5
                bge      .L_loop0_done
                ldr      r1, [r4]                /* 源地址 */
                ldr      r2, [r4, #4]            /* 目标地址 */
                ldr      r3, [r4, #8]            /* 字数 */
                lsls     r3, r3, #2              /* 转为字节数 */

.L_loop0_0:
                subs     r3, #4
                ittt     ge
                ldrge    r0, [r1, r3]
                strge    r0, [r2, r3]
                bge      .L_loop0_0

                adds     r4, #12
                b        .L_loop0
.L_loop0_done:

                /* 清零 .bss 段 */
                ldr      r3, =__zero_table_start__
                ldr      r4, =__zero_table_end__

.L_loop2:
                cmp      r3, r4
                bge      .L_loop2_done
                ldr      r1, [r3]                /* 目标地址 */
                ldr      r2, [r3, #4]            /* 字数 */
                lsls     r2, r2, #2              /* 转为字节数 */
                movs     r0, 0

.L_loop2_0:
                subs     r2, #4
                itt      ge
                strge    r0, [r1, r2]
                bge      .L_loop2_0

                adds     r3, #8
                b        .L_loop2
.L_loop2_done:

                /* 跳转到 main() */
                bl       main

                /* 如果 main 返回，死循环 */
                b        .

                .fnend
                .size    Reset_Handler, . - Reset_Handler


/* HardFault — 捕获硬件错误 */
                .thumb_func
                .type    HardFault_Handler, %function
                .weak    HardFault_Handler
                .fnstart
HardFault_Handler:
                b        .
                .fnend
                .size    HardFault_Handler, . - HardFault_Handler

/* 默认中断处理函数 — 死循环 */
                .thumb_func
                .type    Default_Handler, %function
                .weak    Default_Handler
                .fnstart
Default_Handler:
                b        .
                .fnend
                .size    Default_Handler, . - Default_Handler

/* 定义默认弱符号 */
                .macro   Set_Default_Handler  Handler_Name
                .weak    \Handler_Name
                .set     \Handler_Name, Default_Handler
                .endm

/* 系统异常 */
                Set_Default_Handler  NMI_Handler
                Set_Default_Handler  MemManage_Handler
                Set_Default_Handler  BusFault_Handler
                Set_Default_Handler  UsageFault_Handler
                Set_Default_Handler  SVC_Handler
                Set_Default_Handler  DebugMon_Handler
                Set_Default_Handler  PendSV_Handler
                Set_Default_Handler  SysTick_Handler

/* GPIO 中断 */
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
