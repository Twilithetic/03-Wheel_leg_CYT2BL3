# CYT2BL3 缂栬瘧鑴氭湰 鈥?绾?PowerShell锛岄浂渚濊禆锛?# 鐢ㄦ硶: .\build.ps1            鈫?缂栬瘧
#       .\build.ps1 clean      鈫?娓呯悊
#       .\build.ps1 flash      鈫?鐑у綍

param([string]$action = "build")

$ErrorActionPreference = "Continue"

# ========== 宸ュ叿閾?==========
$GCC     = "C:\Users\29344\.eide\tools\gcc_arm\bin\arm-none-eabi-gcc.exe"
$SIZE    = "C:\Users\29344\.eide\tools\gcc_arm\bin\arm-none-eabi-size.exe"
$OBJCOPY = "C:\Users\29344\.eide\tools\gcc_arm\bin\arm-none-eabi-objcopy.exe"

# ========== 璺緞 ==========
$BUILD_DIR    = "build"
$OBJ_DIR      = "$BUILD_DIR\obj"
$LINKER_SCRIPT = "src\cyt2bl3_flash.ld"
$TARGET       = "firmware"

# ========== 缂栬瘧鏍囧織 ==========
$CPU_FLAGS = @(
    "-mcpu=cortex-m4", "-mthumb",
    "-mfloat-abi=hard", "-mfpu=fpv4-sp-d16"
)

$C_DEFS = @(
    "-D__CORTEX_M4", "-D__FPU_PRESENT=1", "-DCYT2BL3"
)

$C_FLAGS = $CPU_FLAGS + $C_DEFS + @(
    "-std=c11", "-O0", "-g3", "-Wall", "-Wextra",
    "-ffunction-sections", "-fdata-sections", "-fno-common"
)

$AS_FLAGS = $CPU_FLAGS + @("-g", "-x", "assembler-with-cpp")

$LD_FLAGS = $CPU_FLAGS + @(
    "-T", $LINKER_SCRIPT, "-nostartfiles",
    "--specs=nano.specs", "--specs=nosys.specs",
    "-Wl,-Map=$BUILD_DIR\$TARGET.map",
    "-Wl,--gc-sections", "-Wl,--print-memory-usage"
)

$INCLUDES = @(
    "-Isrc",
    "-Ilibs\CMSIS_5\CMSIS\Core\Include",
    "-Ilibs\CMSIS_5\Device\ARM\ARMCM4\Include"
)

# ========== 婧愭枃浠?==========
$SRC_FILES = @(
    @{src="src\startup_cyt2bl3_cm4.S"; flags=$AS_FLAGS; deps=$INCLUDES},
    @{src="src\main.c";              flags=$C_FLAGS;  deps=$INCLUDES}
)

# ============================================================================
function Build {
    Write-Host "`n馃敤 CYT2BL3 Building..." -ForegroundColor Cyan
    
    # 鍒涘缓鐩綍
    New-Item -ItemType Directory -Force $OBJ_DIR | Out-Null
    
    $objs = @()
    
    foreach ($f in $SRC_FILES) {
        $src = $f.src
        $obj = "$OBJ_DIR\" + [System.IO.Path]::GetFileNameWithoutExtension($src) + ".o"
        $objs += $obj
        
        $srcTime = (Get-Item $src -ErrorAction SilentlyContinue).LastWriteTime
        $objTime = (Get-Item $obj -ErrorAction SilentlyContinue).LastWriteTime
        
        if ($srcTime -and $objTime -and $srcTime -le $objTime) {
            Write-Host "  鈴? Skip $src (unchanged)" -ForegroundColor DarkGray
            continue
        }
        
        Write-Host "  馃敡 $src ..." -ForegroundColor Yellow
        $flags = $f.flags + $f.deps
        
        if ($src -like "*.S") {
            & $GCC -c @flags $src -o $obj 2>&1
        } else {
            & $GCC -c @flags $src -o $obj 2>&1
        }
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "鉂?Compile failed: $src" -ForegroundColor Red
            exit 1
        }
    }
    
    # 閾炬帴
    Write-Host "  馃敆 Linking..." -ForegroundColor Yellow
    & $GCC @LD_FLAGS $objs -o "$BUILD_DIR\$TARGET.elf" 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "鉂?Link failed" -ForegroundColor Red; exit 1 }
    
    # HEX
    & $OBJCOPY -O ihex "$BUILD_DIR\$TARGET.elf" "$BUILD_DIR\$TARGET.hex" 2>&1
    
    # 鏄剧ず
    Write-Host "`n=== 馃搳 Firmware Size ===" -ForegroundColor Green
    & $SIZE "$BUILD_DIR\$TARGET.elf"
    
    Write-Host "`n=== 鉁?Build Success锛?==" -ForegroundColor Green
    Write-Host "  ELF: $BUILD_DIR\$TARGET.elf"
    Write-Host "  HEX: $BUILD_DIR\$TARGET.hex"
    Write-Host "  MAP: $BUILD_DIR\$TARGET.map`n"
}

# ============================================================================
function Clean {
    Write-Host "馃Ч 娓呯悊涓?.." -ForegroundColor Yellow
    if (Test-Path $BUILD_DIR) {
        Remove-Item -Recurse -Force $BUILD_DIR
    }
    Write-Host "鉁?娓呯悊瀹屾垚锛? -ForegroundColor Green
}

# ============================================================================
function Flash {
    $hex = "$BUILD_DIR\$TARGET.hex"
    if (-not (Test-Path $hex)) {
        Write-Host "鉂?鎵句笉鍒?$hex锛岃鍏堢紪璇戯紒" -ForegroundColor Red
        exit 1
    }
    Write-Host "馃敟 Flashing (J-Link + SWD)..." -ForegroundColor Yellow
    Write-Host "  (Ensure J-Link connected, board powered)"
    
    # 鐢熸垚 J-Link 鍛戒护鑴氭湰
    $jlinkScript = @"
r
h
loadfile $hex
r
g
qc
"@
    $jlinkScript | Out-File -Encoding ASCII "$BUILD_DIR\flash.jlink"
    
    & JLink.exe -device CYT2BL3 -if SWD -speed 4000 -autoconnect 1 `
        -CommanderScript "$BUILD_DIR\flash.jlink"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "鉁?鐑у綍瀹屾垚锛? -ForegroundColor Green
    }
}

# ============================================================================
# 鍏ュ彛
switch ($action) {
    "clean" { Clean }
    "flash" { Flash }
    "rebuild" { Clean; Build }
    default  { Build }
}

