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
WCHLINK_SERIAL  = F3EE7D40070E
# 接口配置: kitprog3 / jlink / cmsis-dap / stlink-v2
PROBE_IF        = cmsis-dap

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
.PHONY: all clean flash debug check-chip gdb-server debug-cm4 debug-cm0

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
#
# ⚠️ WCH-Link 烧录 CYT2BL3 当前不可用
#
# 根因: WCH-Link 不支持 Test Mode acquire
#       → 无法在复位后恢复 SWD 连接
#       → CM0+ 无法获得干净状态
#       → SROM Flash API 调用超时
#
# 替代方案:
#   1. KitProg3 (随 CYT2BL3 开发板附带)
#   2. MiniProg4 + KBA 设置
#   3. J-Link + libusbK 驱动
#
flash: $(BUILD_DIR)/$(TARGET).hex
	@echo "🔥 烧录中 (OpenOCD + $(PROBE_IF))..."
	@echo "   ⚠️  WCH-Link 烧录 CYT2BL3 可能失败 (Test Mode acquire 缺失)"
	@echo "   推荐使用 KitProg3 / MiniProg4 / J-Link"
	@$(OPENOCD) -s "$(OPENOCD_SCRIPTS)" \
		-f "interface/$(PROBE_IF).cfg" \
		-c "adapter serial $(WCHLINK_SERIAL)" \
		-f "target/infineon/cyt2bl.cfg" \
		-c "adapter speed 2000" \
		-c "init" \
		-c "targets traveo2_be_4m.cpu.cm0" \
		-c "halt 3000" \
		-c "flash write_image erase $(BUILD_DIR)/$(TARGET).hex" \
		-c "verify_image $(BUILD_DIR)/$(TARGET).hex" \
		-c "exit"
	@echo "✅ 烧录完成！"

flash: $(BUILD_DIR)/$(TARGET).hex
	@echo "🔥 烧录中 (OpenOCD + $(PROBE_IF) / WCH-Link)..."
	@echo "   ⚠️  非首次烧录请先断电重启！或试试 make flash-first"
	@$(OPENOCD) -s "$(OPENOCD_SCRIPTS)" \
		-f "interface/$(PROBE_IF).cfg" \
		-c "adapter serial $(WCHLINK_SERIAL)" \
		-f "target/infineon/cyt2bl.cfg" \
		-c "adapter speed 2000" \
		-c "init" \
		-c "targets traveo2_be_4m.cpu.cm0" \
		-c "traveo2 reset_halt" \
		-c "halt 3000" \
		-c "flash write_image erase $(BUILD_DIR)/$(TARGET).hex" \
		-c "verify_image $(BUILD_DIR)/$(TARGET).hex" \
		-c "reset run" \
		-c "exit"
	@echo "✅ 烧录完成！"

# ========== 检测芯片 ==========
check-chip:
	@echo "🔍 检测芯片 (OpenOCD + $(PROBE_IF))..."
	@$(OPENOCD) -s "$(OPENOCD_SCRIPTS)" \
		-f "interface/$(PROBE_IF).cfg" \
		-c "adapter serial $(WCHLINK_SERIAL)" \
		-f "target/infineon/cyt2bl.cfg" \
		-c "init" \
		-c "targets" \
		-c "shutdown"

# ========== GDB Server（后台运行，不退出） ==========
# 启动后在另一个终端用 "make debug-cm4" 连接
gdb-server:
	@echo "📡 启动 GDB Server (OpenOCD + $(PROBE_IF))..."
	@echo "   CM0+ GDB → localhost:3333"
	@echo "   CM4  GDB → localhost:3334"
	@echo "   按 Ctrl+C 停止"
	@$(OPENOCD) -s "$(OPENOCD_SCRIPTS)" \
		-f "interface/$(PROBE_IF).cfg" \
		-c "adapter serial $(WCHLINK_SERIAL)" \
		-f "target/infineon/cyt2bl.cfg"

# ========== GDB 命令行调试 (CM4) ==========
debug-cm4: $(BUILD_DIR)/$(TARGET).elf
	@echo "🐛 连接 GDB → CM4 (localhost:3334)"
	@echo "   提示: 先用另一个终端运行 'make gdb-server'"
	@echo "   GDB 命令: break main → continue → step/next/print ..."
	@$(GDB) -q \
		-ex "target extended-remote localhost:3334" \
		-ex "monitor reset init" \
		-ex "load" \
		-ex "break main" \
		-ex "echo ====== 停在 main(), 输入 continue 运行 ======\n" \
		$(BUILD_DIR)/$(TARGET).elf

# ========== GDB 命令行调试 (CM0+) ==========
debug-cm0: $(BUILD_DIR)/$(TARGET).elf
	@echo "🐛 连接 GDB → CM0+ (localhost:3333)"
	@$(GDB) -q \
		-ex "target extended-remote localhost:3333" \
		-ex "monitor reset init" \
		-ex "load" \
		$(BUILD_DIR)/$(TARGET).elf

# ========== 清理 ==========
clean:
	@echo "🧹 Cleaning..."
	rm -rf $(BUILD_DIR)
	@echo "✅ Clean done！"
