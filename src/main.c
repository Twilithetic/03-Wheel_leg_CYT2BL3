/**
 * @file     main.c
 * @brief    CYT2BL3 PDL + FreeRTOS 示例
 * 
 * 这个示例展示：
 *   1. PDL 外设初始化 (GPIO LED 闪烁)
 *   2. FreeRTOS 多任务调度
 *   3. 任务间通信 (Queue)
 * 
 * 编译前需要配置：
 *   - CPU Type: Cortex-M4
 *   - FPU: fpv4-sp-d16 (hard float)
 *   - 链接脚本: cyt2bl3_flash.ld
 *   - Include: libs/pdl/devices/COMPONENT_CAT1C/include
 *              libs/pdl/drivers/include
 *              libs/FreeRTOS/include
 *              libs/CMSIS_5/CMSIS/Core/Include
 *              src/
 */

/* PDL 驱动库 */
#include "cy_pdl.h"

/* FreeRTOS */
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"

/* 你的 FreeRTOS 配置 */
#include "FreeRTOSConfig.h"

/* ================================================================
 * 全局定义
 * ================================================================ */

/* 假设用户 LED 在 P0.5 (根据你的核心板修改！) */
#define LED_PORT        GPIO_PRT0
#define LED_PIN         5
#define LED_DELAY_MS    500

/* UART 调试 (可选，假设 P5.0=TX, P5.1=RX) */
#define DEBUG_UART      SCB0

/* ================================================================
 * FreeRTOS 任务
 * ================================================================ */

/**
 * LED 闪烁任务
 * 用 PDL 的 Cy_GPIO 操作 GPIO
 */
void vLEDTask(void *pvParameters)
{
    (void)pvParameters;

    /* 配置 LED 引脚 */
    cy_stc_gpio_pin_config_t ledConfig = {
        .outVal    = 0,                              /* 初始低电平 */
        .driveMode = CY_GPIO_DM_STRONG_IN_OFF,       /* 推挽输出 */
        .hsiom     = CY_GPIO_HSIOM_SEL_GPIO,         /* GPIO 功能 */
    };
    Cy_GPIO_Pin_Init(LED_PORT, LED_PIN, &ledConfig);

    for (;;)
    {
        Cy_GPIO_Pin_Inv(LED_PORT, LED_PIN);          /* 翻转 LED */
        vTaskDelay(pdMS_TO_TICKS(LED_DELAY_MS));     /* 延时 500ms */
    }
}

/**
 * 简单计数器任务
 * 演示多任务并行
 */
void vCounterTask(void *pvParameters)
{
    (void)pvParameters;
    uint32_t count = 0;

    for (;;)
    {
        count++;
        vTaskDelay(pdMS_TO_TICKS(1000));             /* 每秒计数一次 */
    }
}

/* ================================================================
 * 系统初始化
 * ================================================================ */

/**
 * Cy_SystemInit — PDL 系统初始化
 * 由启动汇编调用
 */
void Cy_SystemInit(void)
{
    /* 使能 FPU */
    SCB->CPACR |= ((3UL << 10*2) | (3UL << 11*2));

    /* 配置系统时钟 (示例: 使用 IMO 8MHz → PLL → 160MHz) */
    /* TODO: 根据你的核心板时钟方案完善 */
}

/* ================================================================
 * main()
 * ================================================================ */

int main(void)
{
    /* PDL 设备初始化 */
    Cy_SysLib_Delay(10);  /* 短暂延时，等待电源稳定 */

    /* 创建 FreeRTOS 任务 */
    xTaskCreate(
        vLEDTask,           /* 任务函数 */
        "LED",              /* 任务名 */
        configMINIMAL_STACK_SIZE * 2,  /* 栈大小 */
        NULL,               /* 参数 */
        1,                  /* 优先级 */
        NULL                /* 任务句柄 */
    );

    xTaskCreate(
        vCounterTask,
        "Counter",
        configMINIMAL_STACK_SIZE,
        NULL,
        2,
        NULL
    );

    /* 启动 FreeRTOS 调度器 */
    vTaskStartScheduler();

    /* 永远不会执行到这里 */
    for (;;) {}
    return 0;
}

/* ================================================================
 * FreeRTOS 内存管理 (heap_4.c 需要)
 * ================================================================ */

/* 如果使用 heap_4.c，需要实现 vApplicationMallocFailedHook */
void vApplicationMallocFailedHook(void)
{
    /* 内存分配失败 — 进入死循环 */
    taskDISABLE_INTERRUPTS();
    for (;;) {}
}

/* 栈溢出钩子 */
void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName)
{
    (void)xTask;
    (void)pcTaskName;
    taskDISABLE_INTERRUPTS();
    for (;;) {}
}
