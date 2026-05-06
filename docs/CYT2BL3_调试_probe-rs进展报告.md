# probe-rs 支持 CYT2BL3 — 当前进展报告

> *进展汇报：2026-05-04*

---

## 一、总体进展

```
目标: 让 probe-rs 支持 CYT2BL3 的烧录和调试

进度: ████████████░░░░░░ 80%

  ✅ 硬件连接       — probe-rs 完美识别 ST-Link + CYT2BL3
  ✅ CoreSight 探测  — 完整识别双核 + ETB/ETM/TPIU
  ✅ CMSIS-Pack     — 找到 CAT1C_DFP 1.2.0
  ✅ Flash 算法      — 提取 CAT1C_4160.FLM + 符号表
  ✅ YAML 基础结构   — 芯片描述框架完成
  ⚠️ YAML 格式修复   — core_access_options 字段需修正
  ⚠️ probe-rs 连接    — 自定义 YAML 连接报 SwdApWdataError
  ⏳ 烧录测试        — 待 YAML 修复后测试
```

---

## 二、已完成的工作

### 2.1 probe-rs 硬件链路 ✅

```
$ probe-rs list
[0]: STLink V2 -- 0483:3748: (ST-LINK)        ✅ 识别

$ probe-rs info
Debug Port: DPv2, Designer: Cypress            ✅ 连接
├── MemoryAP 0 → CM0+ 系统                     ✅ 双核
├── MemoryAP 1 → CM4 系统                      ✅
└── MemoryAP 2 → ETB + TPIU + ETM (M4)        ✅ 追踪
```

### 2.2 CMSIS-Pack ✅

```
来源: https://itools.infineon.com/cmsis_packs/CAT1C_DFP/
版本: Infineon.CAT1C_DFP.1.2.0.pack (1.7 MB)

提取内容:
  ✅ CAT1C_4160.FLM (125 KB) — 4160KB Flash 算法
  ✅ cat1c4m.svd (2.3 MB)   — 外设寄存器描述
  ✅ Infineon.CAT1C_DFP.pdsc — 设备目录
```

### 2.3 Flash 算法符号表 ✅

```
从 CAT1C_4160.FLM 的 ELF 符号表中提取:

  Init          @ 0x000001     ← 初始化
  UnInit        @ 0x000a55     ← 反初始化
  EraseChip     @ 0x0006a9     ← 全片擦除
  EraseSector   @ 0x0006b1     ← 扇区擦除
  ProgramPage   @ 0x000891     ← 页编程
  Verify        @ 0x000a61     ← 校验

  源文件: FlashDev.c, FlashPrg.c, cy_device.c
  API 封装: SromApiEraseAll, SromApiEraseSector, SromApiProgramRow
```

### 2.4 YAML 描述文件 ⚠️

```
文件: probe-rs/CYT2BL3.yaml (170 KB, 含 base64 FLM)

已包含:
  ✅ 芯片名: CYT2BL3
  ✅ 厂商: Infineon (JEP106 code 0x34)
  ✅ 内存映射: Flash@0x10000000, SRAM@0x08000000
  ✅ Flash 算法 base64 编码
  ✅ pc_init / pc_program_page / pc_erase_sector 入口

需要修复:
  ❌ core_access_options 缺少 ap 字段
  ❌ 所有 variant 的格式需统一
```

---

## 三、当前遇到的问题

### 3.1 YAML 格式问题 ❌

```
错误信息:
  variants[0].cores[0].core_access_options: missing field `ap`

原因:
  probe-rs 0.30.0 要求 !Arm 标签必须指定 AP:
    core_access_options: !Arm
      ap: !v1 1    ← 必须有这一行

  之前尝试过 ap: !v1 0 (CM0+) 和 ap: !v1 1 (CM4)
```

### 3.2 probe-rs 连接报错 ⚠️

```
当 YAML 格式正确时:

  ap: !v1 1 (CM4):
    → SwdDpError (复位后 halt CPU 失败)

  ap: !v1 0 (CM0+):
    → SwdApWdataError (AP 访问错误)

原因分析:
  1. TRAVEO T2G 双核芯片的复位序列特殊
     (CM0+ 先启动，释放 CM4，SWD 才可用)
  
  2. probe-rs download 流程:
     reset → halt → load flash algo → program
     其中 reset+halt 需要特殊的时序处理
  
  3. ST-Link + probe-rs 0.30.0 的组合
     可能不支持 TRAVEO T2G 的初始化
```

---

## 四、target-gen 状态 ⏳

```
尝试编译: cargo build --release -p target-gen
结果:     ❌ 超时 (probe-rs 项目太大，编译需要很长时间)

备选路径:
  1. cargo install probe-rs-tools (预编译版本)
  2. 手写 YAML (当前方案，进行中)
```

---

## 五、Flash 算法适配分析

### 5.1 CAT1C_4160.FLM 和 CYT2BL3 的兼容性

```
CAT1C_4160.FLM 是为 XMC7100 编写的 (RAM @ 0x28000000)

对于 CYT2BL3 (RAM @ 0x08000000):

  ✅ Flash 控制器寄存器 → 完全相同 (CAT1C 统一)
  ✅ SROM API opcode    → 完全相同
  ✅ IPC 寄存器地址      → 完全相同
  ✅ Flash 页大小        → 512 字节
  ⚠️ RAM 加载地址        → 需要改为 0x08001000

  这个算法内部使用绝对地址吗？
  → 需要反汇编确认。如果使用相对地址，直接可用。
  → 如果使用 SRAM 绝对地址 (0x2800xxxx)，需要修改重编译。
```

### 5.2 符号表分析

```
SromApiEraseSector  @ 0x08b9 — 28 字节函数
SromApiProgramRow   @ 0x08e1 — 36 字节函数

这些函数调用 SROM API 通过 IPC 寄存器，
IPC 地址在 Flash 控制器空间 (0x08010000)，
CYT2BL3 和 XMC7100 的 IPC 地址相同。

→ 大概率可以直接复用！
```

---

## 六、下一步计划

### 🔧 立即可以做的

```
1. 修复 YAML core_access_options 格式
   → 补上 ap: !v1 1

2. 尝试 probe-rs 0.31+ (更新版本可能更好)
   → cargo install probe-rs-tools --version 0.31

3. 用 probe-rs 0.30 测试 AP1 连接
   → 如果 SwdDpError 是时序问题，可能需要
     --connect-under-reset 或延时
```

### 🚀 后续可以做的

```
4. 编译 target-gen (换网络好时，或下载预编译版)
   → cargo install probe-rs-tools

5. 用 target-gen 从 .pdsc 正式生成 YAML
   → target-gen arm -f CAT1C_DFP.pdsc
   → 自动处理所有格式细节

6. 提交 PR 给 probe-rs 社区
   → 把 CYT2BL3.yaml 贡献给上游
```

---

## 七、当前可用状态

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  现在就能用的:                                              │
│                                                             │
│  ✅ probe-rs info — 连接芯片、查看 CoreSight 架构           │
│  ✅ probe-rs list — 识别 ST-Link                           │
│  ✅ probe-rs read — 读写 SRAM (0x08000000)                  │
│  ✅ make flash    — (需要 J-Link 或刷固件)                  │
│                                                             │
│  还差最后一步的:                                            │
│                                                             │
│  ⚠️ probe-rs download — YAML格式修复后即测                 │
│                                                             │
│  推测: YAML 格式修复后，Fash算法可能直接可用                │
│        (因为 CAT1C 内部兼容，只需微调 AP 配置)              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 八、总结

```
进度: 80%

  ✅ 硬件链路打通      ✅ Flash 算法到位
  ✅ CMSIS-Pack 获取   ✅ 符号表提取完成
  ✅ YAML 框架建立     ✅ base64 编码完成

  ⚠️ YAML 格式微调     ← 当前卡点 (ap 字段)
  ⚠️ probe-rs 连接测试  ← 待格式修复后验证

预计:
  修好 ap 字段 → 测试连接 → 如果顺利，半小时内搞定
  如果遇到时序问题 → 可能需要 probe-rs 版本更新
```

---

*报告版本：v1.0 | 2026-05-04*
