# CYT2BL3 Makefile — GCC ARM 编译
# 用 VSCode tasks.json 调用: Ctrl+Shift+B → "build"

# ========== 工具链 ==========
GCC     = C:/Users/29344/.eide/tools/gcc_arm/bin/arm-none-eabi-gcc.exe
SIZE    = C:/Users/29344/.eide/tools/gcc_arm/bin/arm-none-eabi-size.exe
OBJCOPY = C:/Users/29344/.eide/tools/gcc_arm/bin/arm-none-eabi-objcopy.exe
GDB     = C:/Users/29344/.eide/tools/gcc_arm/bin/arm-none-eabi-gdb.exe

# ========== 烧录工具 ==========
OPENOCD         = tools/infineon-openocd/bin/openocd.exe
OPENOCD_SCRIPTS = tools/infineon-openocd/scripts

# ========== 目标 ==========
TARGET = firmware
BUILD_DIR = build

# ========== Cortex-M4F 编译标志 ==========
CPU_FLAGS   = -mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16
C_DEFS     = -D__CORTEX_M4 -DCYT2BL3
C_FLAGS     = $(CPU_FLAGS) $(C_DEFS) -std=c11 -O0 -g3 -Wall -Wextra
C_FLAGS    += -ffunction-sections -fdata-sections -fno-common
AS_FLAGS    = $(CPU_FLAGS) -g
LD_FLAGS    = $(CPU_FLAGS) -T src/cyt2bl3_flash.ld -nostartfiles
LD_FLAGS   += --specs=nano.specs --specs=nosys.specs
LD_FLAGS   += -Wl,-Map=$(BUILD_DIR)/$(TARGET).map
LD_FLAGS   += -Wl,--gc-sections -Wl,--print-memory-usage

# ========== Include 路径 ==========
INCLUDES  = -Isrc
INCLUDES += -Ilibs/CMSIS_5/CMSIS/Core/Include
INCLUDES += -Ilibs/CMSIS_5/Device/ARM/ARMCM4/Include

# ========== 源文件 ==========
C_SRCS   = src/main.c
ASM_SRCS = src/startup_cyt2bl3_cm4.S

# ========== 目标文件 ==========
C_OBJS   = $(C_SRCS:%.c=$(BUILD_DIR)/%.o)
ASM_OBJS = $(ASM_SRCS:%.S=$(BUILD_DIR)/%.o)
OBJS     = $(C_OBJS) $(ASM_OBJS)

# ========== 默认目标 ==========
.PHONY: all clean flash debug

all: $(BUILD_DIR)/$(TARGET).elf $(BUILD_DIR)/$(TARGET).hex $(BUILD_DIR)/$(TARGET).bin

# ========== 链接 ==========
$(BUILD_DIR)/$(TARGET).elf: $(OBJS)
	@echo "🔗 链接 $@ ..."
	@$(GCC) $(LD_FLAGS) $(OBJS) -o $@
	@$(SIZE) $@

$(BUILD_DIR)/$(TARGET).hex: $(BUILD_DIR)/$(TARGET).elf
	@$(OBJCOPY) -O ihex $< $@
	@echo "✅ HEX: $@"

$(BUILD_DIR)/$(TARGET).bin: $(BUILD_DIR)/$(TARGET).elf
	@$(OBJCOPY) -O binary $< $@
	@echo "✅ BIN: $@"

# ========== 编译 C ==========
$(BUILD_DIR)/%.o: %.c
	@mkdir -p $(dir $@)
	@echo "🔧 编译 $< ..."
	@$(GCC) -c $(C_FLAGS) $(INCLUDES) $< -o $@

# ========== 编译汇编 ==========
$(BUILD_DIR)/%.o: %.S
	@mkdir -p $(dir $@)
	@echo "🔧 汇编 $< ..."
	@$(GCC) -c $(AS_FLAGS) -x assembler-with-cpp $(INCLUDES) $< -o $@

# ========== 烧录 (OpenOCD + CMSIS-DAP / WCH-Link) ==========
flash: $(BUILD_DIR)/$(TARGET).hex
	@echo "🔥 烧录中 (OpenOCD + WCH-Link)..."
	@$(OPENOCD) -s "$(OPENOCD_SCRIPTS)" \
		-f "interface/cmsis-dap.cfg" \
		-f "target/infineon/cyt2bl.cfg" \
		-c "adapter speed 2000" \
		-c "init" \
		-c "targets traveo2_be_4m.cpu.cm0" \
		-c "halt 3000" \
		-c "flash write_image erase $(BUILD_DIR)/$(TARGET).hex" \
		-c "verify_image $(BUILD_DIR)/$(TARGET).hex" \
		-c "exit"
	@echo "✅ 烧录完成！"

# ========== 清理 ==========
clean:
	@echo "🧹 Cleaning..."
	rm -rf $(BUILD_DIR)
	@echo "✅ Clean done！"
