/**
 * @file     main.c
 * @brief    CYT2BL3 LED 闪烁 — SysTick 定时器 + P23.7 (低电平点亮)
 * 
 * 硬件:   LED 接 P23.7, 低电平点亮
 * 定时器: SysTick (Cortex-M4 内核定时器, CMSIS 标准 API)
 * 
 * 不需要 Infineon HAL/PDL ! 只用 ARM CMSIS 就能跑。
 */

#include <stdint.h>
#include <stdbool.h>
#include "ARMCM4_FP.h"       /* CMSIS 设备模板: IRQn_Type, SysTick, NVIC, SCB 等 */

/* ================================================================
 * CYT2BL3 GPIO 寄存器地址
 * TRAVEO T2G: 每个 GPIO Port 占 0x80 字节
 *   PRT0  = 0x40310000
 *   PRT23 = 0x40310000 + 23 * 0x80
 * ================================================================ */
#define GPIO_BASE             0x40310000UL
#define GPIO_PORT_OFFSET      0x00000080UL
#define GPIO_PRT23_BASE       (GPIO_BASE + 23 * GPIO_PORT_OFFSET)

/* GPIO 寄存器偏移 (TRAVEO T2G 通用) */
#define GPIO_OUT_REG          0x00    /* 输出数据 */
#define GPIO_OUT_SET_REG      0x08    /* 输出置位 (写1=置高) */
#define GPIO_OUT_CLR_REG      0x04    /* 输出清零 (写1=置低) */
#define GPIO_CFG_REG          0x20    /* 引脚配置 (每4位一个引脚) */

/* ================================================================
 * LED 定义
 * ================================================================ */
#define LED_PORT_BASE         GPIO_PRT23_BASE
#define LED_PIN               7
#define LED_ON()              (*(volatile uint32_t*)(LED_PORT_BASE + GPIO_OUT_CLR_REG) = (1U << LED_PIN))
#define LED_OFF()             (*(volatile uint32_t*)(LED_PORT_BASE + GPIO_OUT_SET_REG) = (1U << LED_PIN))
#define LED_TOGGLE()          (*(volatile uint32_t*)(LED_PORT_BASE + GPIO_OUT_CLR_REG) = (1U << LED_PIN))

/* ================================================================
 * 全局变量
 * ================================================================ */
uint32_t SystemCoreClock = 160000000UL;   /* CM4 主频 160MHz */
volatile uint32_t g_msTicks = 0;          /* 毫秒计数器 */

/* ================================================================
 * Cy_SystemInit — 由启动汇编调用
 * ================================================================ */
void Cy_SystemInit(void)
{
    /* 使能 FPU */
    SCB->CPACR |= ((3UL << 10*2) | (3UL << 11*2));
    __DSB();
    __ISB();
}

/* ================================================================
 * SysTick 中断服务函数 (每 1ms 触发一次)
 * ================================================================ */
void SysTick_Handler(void)
{
    g_msTicks++;
}

/* ================================================================
 * 毫秒级延时 (基于 SysTick 计数)
 * ================================================================ */
static void delay_ms(uint32_t ms)
{
    uint32_t target = g_msTicks + ms;
    while (g_msTicks < target) {
        __WFI();    /* 睡眠等待中断，省电 */
    }
}

/* ================================================================
 * 获取系统运行毫秒数
 * ================================================================ */
static uint32_t millis(void)
{
    return g_msTicks;
}

/* ================================================================
 * GPIO 驱动
 * ================================================================ */

/**
 * 配置 GPIO 引脚为推挽输出模式
 * TRAVEO T2G 引脚配置: 每 4 bit 控制一个引脚
 *   0x09 = Strong Drive, Output enabled, Input buffer off
 */
static void gpio_pin_output(uint32_t port_base, uint8_t pin)
{
    volatile uint32_t *cfg = (volatile uint32_t *)(port_base + GPIO_CFG_REG);
    uint32_t shift = (pin % 8) * 4;
    uint32_t val   = *cfg;

    val &= ~(0x0FUL << shift);   /* 清除旧配置 */
    val |=  (0x09UL << shift);   /* Strong Drive, Output */
    *cfg = val;
}

/* ================================================================
 * main()
 * ================================================================ */
int main(void)
{
    /* ---- 1. 配置 LED 引脚 ---- */
    gpio_pin_output(LED_PORT_BASE, LED_PIN);
    LED_OFF();  /* 初始熄灭 (P23.7 输出高电平) */

    /* ---- 2. 配置 SysTick: 1ms 中断 ---- */
    /* SysTick_Config() 是 CMSIS 标准 API:
     *   参数 = 两次中断之间的时钟周期数
     *   SystemCoreClock / 1000 = 160000000 / 1000 = 160000 周期 = 1ms */
    if (SysTick_Config(SystemCoreClock / 1000))
    {
        /* 配置失败 (参数太大) — 死循环 */
        while (1) {}
    }

    /* ---- 3. 主循环: 500ms 闪烁 ---- */
    while (1)
    {
        LED_ON();           /* 低电平 → LED 亮 */
        delay_ms(500);      /* 延时 500ms (SysTick 驱动, 不占 CPU) */

        LED_OFF();          /* 高电平 → LED 灭 */
        delay_ms(500);
    }

    return 0;
}
