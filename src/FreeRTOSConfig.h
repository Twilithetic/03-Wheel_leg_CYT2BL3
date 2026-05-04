/*
 * FreeRTOSConfig.h — CYT2BL3 定制配置
 * 
 * 根据 CYT2BL3 双核架构 (CM4 @ 160MHz + CM0+ @ 100MHz)
 * 使用 SysTick 作为 RTOS 滴答时钟
 */

#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

/* 硬件特性 */
#define configCPU_CLOCK_HZ                      (160000000UL)   /* CM4 主频 160MHz */
#define configTICK_RATE_HZ                      (1000)          /* 1kHz 滴答 */
#define configMAX_PRIORITIES                    (7)             /* 7 个优先级 */
#define configMINIMAL_STACK_SIZE                (128)           /* 最小任务栈 (字) */
#define configTOTAL_HEAP_SIZE                   (32 * 1024)     /* 32KB 堆 */
#define configMAX_TASK_NAME_LEN                 (16)            /* 任务名最大长度 */
#define configUSE_16_BIT_TICKS                  0               /* 使用 32 位滴答计数 */
#define configIDLE_SHOULD_YIELD                 1               /* 空闲任务让步 */
#define configUSE_PREEMPTION                    1               /* 抢占式调度 */
#define configUSE_TIME_SLICING                  1               /* 时间片调度 */

/* 内核功能开关 */
#define configUSE_MUTEXES                       1               /* 互斥量 */
#define configUSE_RECURSIVE_MUTEXES             1               /* 递归互斥量 */
#define configUSE_COUNTING_SEMAPHORES           1               /* 计数信号量 */
#define configUSE_TASK_NOTIFICATIONS            1               /* 任务通知 */
#define configUSE_TRACE_FACILITY                1               /* 跟踪功能 */
#define configUSE_STATS_FORMATTING_FUNCTIONS    1               /* 统计函数 */
#define configUSE_TICKLESS_IDLE                 0               /* 禁用 Tickless (先简单) */
#define configSUPPORT_STATIC_ALLOCATION         1               /* 静态内存分配 */
#define configSUPPORT_DYNAMIC_ALLOCATION        1               /* 动态内存分配 */

/* Hook 函数 */
#define configUSE_IDLE_HOOK                     0
#define configUSE_TICK_HOOK                     0
#define configCHECK_FOR_STACK_OVERFLOW          2               /* 栈溢出检测 */
#define configUSE_MALLOC_FAILED_HOOK            1

/* ARM Cortex-M 特定 */
#define configKERNEL_INTERRUPT_PRIORITY         (255 << 4)      /* 最低优先级 */
#define configMAX_SYSCALL_INTERRUPT_PRIORITY    (5 << 4)        /* 系统调用最高优先级 */

/* 中断处理 */
#define vPortSVCHandler                         SVC_Handler
#define xPortPendSVHandler                      PendSV_Handler
#define xPortSysTickHandler                     SysTick_Handler

/* 断言 */
#define configASSERT(x)                         if((x)==0) { taskDISABLE_INTERRUPTS(); for(;;); }

/* 包含 CMSIS / PDL */
#include "cy_pdl.h"

#endif /* FREERTOS_CONFIG_H */
