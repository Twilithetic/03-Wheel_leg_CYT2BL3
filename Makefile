# CYT2BL3 Makefile — GCC ARM 编译
# 烧录/调试用 probe-rs（见 .vscode/tasks.json）

# ========== 工具链 ==========
GCC     = C:/Users/29344/.eide/tools/gcc_arm/bin/arm-none-eabi-gcc.exe
SIZE    = C:/Users/29344/.eide/tools/gcc_arm/bin/arm-none-eabi-size.exe
OBJCOPY = C:/Users/29344/.eide/tools/gcc_arm/bin/arm-none-eabi-objcopy.exe

# ========== 目标 ==========
TARGET    = firmware
BUILD_DIR = build

# ========== Cortex-M4F 编译标志 ==========
CPU_FLAGS = -mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16
C_DEFS    = -D__CORTEX_M4 -DCYT2BL3
C_FLAGS   = $(CPU_FLAGS) $(C_DEFS) -std=c11 -O0 -g3 -Wall -Wextra
C_FLAGS  += -ffunction-sections -fdata-sections -fno-common
AS_FLAGS  = $(CPU_FLAGS) -g
LD_FLAGS  = $(CPU_FLAGS) -T src/cyt2bl3_flash.ld -nostartfiles
LD_FLAGS += --specs=nano.specs --specs=nosys.specs
LD_FLAGS += -Wl,-Map=$(BUILD_DIR)/$(TARGET).map
LD_FLAGS += -Wl,--gc-sections -Wl,--print-memory-usage

# ========== Include 路径 ==========
INCLUDES  = -Isrc
INCLUDES += -Isrc/infineon_cylibs/CMSIS_5/CMSIS/Core/Include
INCLUDES += -Isrc/infineon_cylibs/CMSIS_5/Device/ARM/ARMCM4/Include

# ========== 源文件 ==========
C_SRCS   = src/main.c
ASM_SRCS = src/startup_cyt2bl3_cm4.S

# ========== 目标文件 ==========
C_OBJS   = $(C_SRCS:%.c=$(BUILD_DIR)/%.o)
ASM_OBJS = $(ASM_SRCS:%.S=$(BUILD_DIR)/%.o)
OBJS     = $(C_OBJS) $(ASM_OBJS)

# ========== 默认目标 ==========
.PHONY: build clean rebuild

build: $(BUILD_DIR)/$(TARGET).elf $(BUILD_DIR)/$(TARGET).hex $(BUILD_DIR)/$(TARGET).bin

# ========== 强制重编 ==========
rebuild: clean
	@$(MAKE) build

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

# ========== 清理 ==========
clean:
	@cmd /c "if exist $(BUILD_DIR) rmdir /s /q $(BUILD_DIR)"
