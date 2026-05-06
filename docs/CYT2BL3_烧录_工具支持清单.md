# CYT2BL3 烧录工具支持清单

> *"有哪些工具能真正烧录 CYT2BL3？"*
> 截止 2026-05-04，基于实测 + 官方文档

---

## 一、支持总览

```
                    CYT2BL3 烧录工具

  ✅ 能烧的                      ❌ 不能烧的
  ────────                      ────────
  J-Flash (SEGGER)              probe-rs
  J-Link Commander              通用 OpenOCD
  Infineon OpenOCD (AFU)        pyOCD
  IAR EWARM + I-JET             st-flash
  GHS MULTI + Probe             BlackMagic Probe
  PEmicro Multilink             
  Lauterbach TRACE32
```

---

## 二、详细清单

### ✅ 1. J-Flash / J-Link Commander（最推荐！）

```
厂商:   SEGGER
费用:   免费（开发用途）
探针:   J-Link (或 ST-Link 刷 J-Link 固件)

优点:
  ✅ Infineon + SEGGER 官方合作，原生支持
  ✅ 内置 CYT2BL3 Flash 算法
  ✅ 图形界面 (J-Flash) + 命令行 (JLink.exe)
  ✅ SWD 速度可达 15 MHz
  ✅ 双核调试支持

用法:
  JLink.exe -device CYT2BL3 -if SWD -speed 4000 -autoconnect 1
  或在 J-Flash GUI 中选 CYT2BL3 → 加载 hex → Program

获取:
  https://www.segger.com/downloads/jlink/
  ST-Link → J-Link 转换: SEGGER STLinkReflash 工具 (免费)
```

### ✅ 2. Infineon OpenOCD（Auto Flash Utility）

```
厂商:   Infineon
费用:   免费（需注册 MyInfineon 账号）
探针:   J-Link / MiniProg4 / KitProg3

优点:
  ✅ Infineon 官方工具
  ✅ 内置 CYT2BL3 Flash 算法
  ✅ 开源 (GPL v2)
  ✅ 命令行，可脚本化
  ✅ 双核 GDB 调试 (CM4 @ 3334, CM0+ @ 3333)

用法:
  openocd -f interface/jlink.cfg -f target/traveo2_be_4m.cfg ^
    -c "program firmware.hex verify reset exit"

目标配置:
  traveo2_be_4m.cfg → infineon/cyt2bl.cfg

获取:
  https://www.infineon.com/auto-flash-utility (需注册)
```

### ✅ 3. IAR EWARM + I-JET

```
厂商:   IAR Systems
费用:   商业 (~$5,000/年)
探针:   I-JET / J-Link

优点:
  ✅ 汽车行业标准 IDE
  ✅ 内置 CYT2BL3 支持
  ✅ 编译 + 烧录 + 调试一体化
  ✅ ISO 26262 功能安全认证
  ✅ 代码优化最好

用法:
  Project → Options → Debugger → I-JET/J-Link
  点击 Download and Debug (Ctrl+D)

获取:
  https://www.iar.com/ewarm
```

### ✅ 4. GHS MULTI + Green Hills Probe

```
厂商:   Green Hills Software
费用:   商业 (~$10,000+/年)
探针:   Green Hills Probe / SuperTrace Probe

优点:
  ✅ 军工/航空级可靠性
  ✅ DO-178C Level A 认证
  ✅ 支持多核追踪

获取:
  https://www.ghs.com/
```

### ✅ 5. PEmicro Multilink

```
厂商:   PEmicro
费用:   商业 (Multilink ACP ~$200)
探针:   PEmicro Multilink

优点:
  ✅ 官方列出支持 CYT2BL
  ✅ 支持 Keil / IAR / GDB

获取:
  https://www.pemicro.com/
```

### ✅ 6. Lauterbach TRACE32

```
厂商:   Lauterbach
费用:   商业 (高端)
探针:   TRACE32

优点:
  ✅ 业界最强调试器
  ✅ 支持 ETM 指令追踪
  ✅ 支持多核同步调试

获取:
  https://www.lauterbach.com/
```

---

## 三、❌ 不能烧的工具

### probe-rs

```
状态:   ❌ 不支持
原因:   缺少 TRAVEO T2G 专用的双核连接序列
       (CM0+ 控制 CM4 复位，CM4 复位后不可访问)

进度:   ✅ YAML 配置完成
       ✅ Flash 算法提取完成
       ⏳ 等上游实现 TraveoArmSequence
```

### 通用 OpenOCD（上游版）

```
状态:   ❌ 不支持
原因:   没有 traveo2 目标配置
       没有 CYT2BL3 Flash 算法

替代:   用 Infineon 定制版 OpenOCD（Auto Flash Utility 内置）
```

### pyOCD

```
状态:   ❌ 不支持
原因:   和 probe-rs 相同 — 没有 TRAVEO T2G Flash 算法
```

### st-flash

```
状态:   ❌ 不支持
原因:   仅支持 STM32 系列
```

---

## 四、推荐方案

### 🥇 免费方案

| 方案 | 探针 | 时间 | 效果 |
|------|------|:---:|------|
| **ST-Link → 刷 J-Link** + J-Flash | ST-Link | 5 分钟 | ⭐⭐⭐⭐⭐ |
| 下载 Infineon AFU + OpenOCD | ST-Link/J-Link | 15 分钟 | ⭐⭐⭐⭐ |

### 🥈 命令行烧录（推荐！）

```powershell
# 方案 A: J-Link Commander
JLink.exe -device CYT2BL3 -if SWD -speed 4000 -autoconnect 1

# 方案 B: Infineon OpenOCD
openocd -f interface/jlink.cfg -f target/traveo2_be_4m.cfg ^
  -c "program firmware.hex verify reset exit"
```

### 🥉 集成到 Makefile（已有！）

```makefile
# Makefile 中已配置:
flash: build/firmware.hex
	JLink.exe -device CYT2BL3 -if SWD -speed 4000 ...
	
# 一键烧录:
make flash
```

---

## 五、快速决策

```
你现在有什么？              → 用什么？

只有 ST-Link              → 🥇 刷 J-Link 固件 (5分钟)
                           或 🥈 下 Infineon AFU (15分钟)

有 J-Link                 → make flash 直接用！
有 MiniProg4              → Infineon OpenOCD
有 IAR EWARM              → 直接 Ctrl+D
什么都没有                → 买 J-Link EDU (~¥400)
```

---

## 六、总结

```
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║  ✅ CYT2BL3 有很多烧录工具可选！                             ║
║                                                              ║
║  免费方案 (推荐):                                            ║
║    J-Flash (SEGGER)          — 刷 J-Link 固件即可           ║
║    Infineon OpenOCD (AFU)    — 官方定制版                   ║
║                                                              ║
║  商业方案:                                                   ║
║    IAR EWARM + I-JET         — 汽车行业标准                 ║
║    PEmicro Multilink          — 第三方专业烧录器             ║
║    Lauterbach TRACE32         — 顶级调试器                  ║
║                                                              ║
║  ❌ 不能用的:                                                ║
║    probe-rs / pyOCD / 通用OpenOCD / st-flash                ║
║                                                              ║
║  🥇 当下最快: ST-Link 刷 J-Link → make flash → ✅           ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

---

*报告版本：v1.0 | 2026-05-04*
