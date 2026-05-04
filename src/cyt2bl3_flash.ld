/*****************************************************************************
 * @file     cyt2bl3_flash.ld
 * @brief    CYT2BL3 GCC 链接脚本
 * 
 * 内存布局 (参考 Infineon Datasheet 002-28876 Rev. *H):
 *   Code Flash:  0x10000000  Size: 4160 KB
 *   Work Flash:  0x14000000  Size:  128 KB
 *   SRAM:        0x08000000  Size:  512 KB (前 2 KB 保留)
 *****************************************************************************/

/* 栈大小 (可根据实际需求调整) */
__STACK_SIZE  =  0x00002000;    /* 8 KB */
__HEAP_SIZE   =  0x00001000;    /* 4 KB */

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x10000000, LENGTH = 4160K
    SRAM  (rwx) : ORIGIN = 0x08000800, LENGTH = 512K - 2K   /* 前 2KB 保留 */
}

ENTRY(Reset_Handler)

SECTIONS
{
    /* ========== 中断向量表 ========== */
    .vectors :
    {
        KEEP(*(.vectors))
        . = ALIGN(256);
    } > FLASH

    /* ========== 代码段 ========== */
    .text :
    {
        *(.text*)
        *(.rodata*)
        *(.glue_7)
        *(.glue_7t)
        KEEP(*(.init))
        KEEP(*(.fini))
        . = ALIGN(4);
        _etext = .;
    } > FLASH

    /* ========== ARM 异常表 ========== */
    .ARM.extab :
    {
        *(.ARM.extab* .gnu.linkonce.armextab.*)
    } > FLASH

    .ARM.exidx :
    {
        __exidx_start = .;
        *(.ARM.exidx* .gnu.linkonce.armexidx.*)
        __exidx_end = .;
    } > FLASH

    /* ========== 预初始化数组 ========== */
    .preinit_array :
    {
        PROVIDE_HIDDEN(__preinit_array_start = .);
        KEEP(*(.preinit_array*))
        PROVIDE_HIDDEN(__preinit_array_end = .);
    } > FLASH

    .init_array :
    {
        PROVIDE_HIDDEN(__init_array_start = .);
        KEEP(*(SORT(.init_array.*)))
        KEEP(*(.init_array*))
        PROVIDE_HIDDEN(__init_array_end = .);
    } > FLASH

    .fini_array :
    {
        PROVIDE_HIDDEN(__fini_array_start = .);
        KEEP(*(SORT(.fini_array.*)))
        KEEP(*(.fini_array*))
        PROVIDE_HIDDEN(__fini_array_end = .);
    } > FLASH

    /* ========== .data 段 (初始值在 FLASH, 运行时在 SRAM) ========== */
    _sidata = LOADADDR(.data);
    .data :
    {
        _sdata = .;
        *(.data*)
        . = ALIGN(4);
        _edata = .;
    } > SRAM AT > FLASH

    /* ========== .bss 段 (运行时在 SRAM) ========== */
    .bss (NOLOAD) :
    {
        _sbss = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > SRAM

    /* ========== 堆 (Heap) ========== */
    .heap (NOLOAD) :
    {
        PROVIDE(__heap_start__ = .);
        . = . + __HEAP_SIZE;
        . = ALIGN(8);
        PROVIDE(__heap_end__ = .);
    } > SRAM

    /* ========== 栈 (Stack) ========== */
    .stack (NOLOAD) :
    {
        . = ALIGN(8);
        PROVIDE(__stack_start__ = .);
        . = . + __STACK_SIZE;
        . = ALIGN(8);
        PROVIDE(__stack_end__ = .);
        PROVIDE(__StackTop = __stack_end__);
    } > SRAM

    /* ========== 段复制/清零表 (放在 FLASH 中) ========== */
    .copy_table :
    {
        __copy_table_start__ = .;
        LONG(LOADADDR(.data))
        LONG(ADDR(.data))
        LONG(SIZEOF(.data) / 4)
        __copy_table_end__ = .;
    } > FLASH

    .zero_table :
    {
        __zero_table_start__ = .;
        LONG(ADDR(.bss))
        LONG(SIZEOF(.bss) / 4)
        __zero_table_end__ = .;
    } > FLASH

    /* ========== 调试符号 ========== */
    PROVIDE(end = __heap_end__);
    PROVIDE(_end = __heap_end__);
}
