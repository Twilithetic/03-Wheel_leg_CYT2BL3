/**
 * @file     main.c
 * @brief    CYT2BL3 极简示例 — 使用 ARMCM4_FP 设备模板
 * 
 * 包含:
 *   - ARMCM4_FP.h → 提供 IRQn_Type, SystemCoreClock 等 CMSIS 设备定义
 *   - core_cm4.h   → 自动被 ARMCM4_FP.h 引入
 *   - CYT2BL3 GPIO 寄存器 → 手动定义
 * 
 * 后续可替换为正式的 CYT2BL 设备头文件
 */

#include <stdint.h>

/* ================================================================
 * ARM CMSIS 设备模板 — 提供 IRQn_Type, __NVIC_PRIO_BITS 等
 * 未来替换为: #include "cyt2bl3.h"
 * ================================================================ */
#include "ARMCM4_FP.h"

/* ================================================================
 * CYT2BL3 / TRAVEO T2G 外设寄存器地址
 * (摘自 Infineon Datasheet 002-28876 Rev. *H)
 * ================================================================ */

/* --- GPIO Port 基地址 --- */
#define GPIO_PRT0_BASE      0x40310000UL

/* --- GPIO 寄存器偏移 (TRAVEO T2G 通用) --- */
#define GPIO_OUT_INV_REG    0x0C    /* 输出翻转 */
#define GPIO_CFG_REG        0x20    /* 引脚配置 (每4位一个引脚) */

/* ================================================================
 * 全局变量
 * ================================================================ */
uint32_t SystemCoreClock = 160000000UL;  /* CM4 主频 160MHz */

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
 * 简易忙等延时 (~160MHz)
 * ================================================================ */
static void simple_delay(uint32_t count)
{
    while (count--) {
        __NOP();
    }
}

/* ================================================================
 * GPIO 驱动 (寄存器级)
 * ================================================================ */

/* 配置 GPIO 引脚为推挽输出 */
static void gpio_pin_output(uint32_t port_base, uint8_t pin)
{
    volatile uint32_t *cfg = (volatile uint32_t *)(port_base + GPIO_CFG_REG);
    uint32_t shift = (pin % 8) * 4;
    uint32_t val = *cfg;
    val &= ~(0x0FUL << shift);   /* 清除旧配置 */
    val |=  (0x09UL << shift);   /* 0x09: strong drive, output enable */
    *cfg = val;
}

/* 翻转 GPIO 引脚 */
static void gpio_pin_toggle(uint32_t port_base, uint8_t pin)
{
    volatile uint32_t *inv = (volatile uint32_t *)(port_base + GPIO_OUT_INV_REG);
    *inv = (1UL << pin);
}

/* ================================================================
 * main()
 * ================================================================ */
int main(void)
{
    /*
     * 配置 P0.5 为推挽输出
     * (根据你的核心板原理图修改引脚号！
     *  核心板原理图: P23.7 接 LED)
     */
    gpio_pin_output(GPIO_PRT0_BASE, 5);

    /* 主循环 — LED 闪烁 */
    while (1)
    {
        gpio_pin_toggle(GPIO_PRT0_BASE, 5);  /* 翻转 LED */
        simple_delay(80000000);              /* 大约 500ms @ 160MHz */
    }

    return 0;
}
