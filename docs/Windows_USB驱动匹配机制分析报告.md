# Windows USB 驱动匹配机制分析报告

> 📅 日期：2026-05-04  
> 🔧 触发问题：ST-Link (VID:0483 PID:3748) 在 Windows 上报错 CM_PROB_FAILED_INSTALL（代码28）  
> 📚 参考文档：Microsoft Windows Driver Documentation (Docs)

---

## 一、问题回顾

当 ST-Link 调试器插入 Windows 电脑后，设备管理器显示：

```
Device Manager Problem   : 28 (CM_PROB_FAILED_INSTALL)
DriverKeyName            : ERROR_FILE_NOT_FOUND
```

**表象**：驱动没装上。  
**深层问题**：Windows 到底是怎么判断"这个 USB 设备该用什么驱动"的？为什么 ST-Link 没有被自动识别，而 U 盘一插就能用？

---

## 二、USB 设备发现的完整流程

根据 Microsoft 官方文档 ["Step 1: The New Device is Identified"](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/step-1--the-new-device-is-identified)，当 USB 设备插入时，整个流程如下：

```
┌─────────────────────────────────────────────────────────────────┐
│ 阶段 0: 物理连接                                                │
│   USB 设备插入 → USB Hub 检测到电平变化 → 硬件枚举开始           │
└──────────────────────────┬──────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ 阶段 1: USB 协议层级枚举 (USB Specification, Chapter 9)         │
│                                                                  │
│   Host                            Device                        │
│    │                                 │                           │
│    ├──── Get Device Descriptor ────►│  (标准请求, bmRequestType │
│    │◄─── 18 bytes descriptor ──────┤   0x80, bRequest 0x06)    │
│    │                                 │                           │
│    Device Descriptor 关键字段：                                   │
│    ┌──────────────────┬─────────────────────────────────────┐    │
│    │ idVendor         │ 0x0483 (STMicroelectronics)          │    │
│    │ idProduct        │ 0x3748 (ST-Link)                    │    │
│    │ bcdDevice        │ 0x0100 (版本 1.00)                  │    │
│    │ bDeviceClass     │ 0x00 (由接口描述符定义)             │    │
│    │ bDeviceSubClass  │ 0x00                                 │    │
│    │ bDeviceProtocol  │ 0x00                                 │    │
│    │ bNumConfigurations│ 0x01                                │    │
│    └──────────────────┴─────────────────────────────────────┘    │
│                                                                  │
│    ├──── Get Config Descriptor ───►│                              │
│    │◄─── Configuration + Interface + Endpoint descriptors ───┤   │
│    │                                 │                           │
│    Interface Descriptor 关键字段：                                │
│    ┌──────────────────┬─────────────────────────────────────┐    │
│    │ bInterfaceClass  │ 0xFF (Vendor Specific - 厂商自定义) │    │
│    │ bInterfaceSubClass│ 0xFF                                │    │
│    │ bInterfaceProtocol│ 0xFF                                │    │
│    │ bNumEndpoints    │ 0x03 (3个端点: IN, OUT, IN)         │    │
│    └──────────────────┴─────────────────────────────────────┘    │
└──────────────────────────┬──────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ 阶段 2: Windows 构建设备标识符 (Hardware ID / Compatible ID)    │
│         由 USB Hub Driver (usbhub.sys) 负责生成                  │
│         (参见 "Standard USB Identifiers" 文档)                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 三、硬件 ID 的生成规则（核心机制）

根据 Microsoft 官方文档 ["Standard USB Identifiers"](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/standard-usb-identifiers)：

### 3.1 单接口设备（如 ST-Link）

USB Hub 驱动从 **设备描述符** 中提取字段，按以下规则生成 ID：

#### Hardware ID（硬件ID —— 精确匹配用）

```
格式: USB\VID_v(4)&PID_d(4)&REV_r(4)
示例: USB\VID_0483&PID_3748&REV_0100
       ↑              ↑           ↑
       │              │           └─ bcdDevice = 0x0100
       │              └─ idProduct  = 0x3748
       └─ idVendor   = 0x0483
```

此外，INF 文件还可以声明一条更宽泛的硬件 ID：

```
格式: USB\VID_v(4)&PID_d(4)        （不含版本号，更通用）
示例: USB\VID_0483&PID_3748
```

#### Compatible ID（兼容ID —— 模糊匹配用）

```
格式: USB\CLASS_c(2)&SUBCLASS_s(2)&PROT_p(2)
      USB\CLASS_c(2)&SUBCLASS_s(2)
      USB\CLASS_c(2)

对于 ST-Link (class=0xFF):
      USB\CLASS_FF&SUBCLASS_FF&PROT_FF
      USB\CLASS_FF&SUBCLASS_FF
      USB\CLASS_FF
```

### 3.2 多接口设备（复合设备）

对于复合设备（如同时有 ST Debug + Virtual COM Port 的 ST-Link V2-1），流程更复杂：

```
1. 先用 USB\COMPOSITE 匹配通用父驱动 (usbccgp.sys)
2. 父驱动为每个接口创建独立的 PDO (Physical Device Object)
3. 每个接口生成独立的 Hardware ID:
   USB\VID_v(4)&PID_d(4)&MI_z(2)     ← z = 接口号 (bInterfaceNumber)
```

> 📌 **ST-Link (VID:0483 PID:3748) 是单接口设备**，只有一个 Vendor-Specific 接口，所以走 3.1 的流程。

---

## 四、驱动匹配算法：Windows 如何找到合适的驱动

根据 Microsoft 文档 ["How Windows Selects a Driver Package for a Device"](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/how-windows-selects-a-driver-for-a-device) 和 ["How Windows Ranks Driver Packages"](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/how-windows-ranks-driver-packages)：

### 4.1 搜索路径（Windows 10/11）

```
┌──────────────────┐
│  插入 USB 设备    │
└────────┬─────────┘
         ▼
┌──────────────────────────────────────┐
│ Step A: 搜索 Driver Store            │  ← 系统预装的驱动仓库
│   (C:\Windows\System32\DriverStore)  │
└────────┬─────────────────────────────┘
         │ 未找到
         ▼
┌──────────────────────────────────────┐
│ Step B: 搜索 DevicePath              │  ← 注册表指定的路径
│   (默认: %SystemRoot%\INF)           │
│   HKEY_LOCAL_MACHINE\Software\       │
│   Microsoft\Windows\CurrentVersion\  │
│   DevicePath                         │
└────────┬─────────────────────────────┘
         │ 未找到
         ▼
┌──────────────────────────────────────┐
│ Step C: Windows Update               │  ← 在线搜索（24h内生效）
│   (Win10 v1703+ 有24h延迟)          │
└──────────────────────────────────────┘
```

### 4.2 INF 文件中的匹配声明

驱动程序通过 INF 文件的 `[Models]` 节声明自己能驱动哪些设备：

```inf
; STSW-LINK009 的 INF 文件(cr简化示意)
[Manufacturer]
%STMfg% = STMfg, NTamd64

[STMfg.NTamd64]
;   设备描述             安装节名      硬件ID                        兼容ID
%STM_STLink.DeviceDesc% = STLink_Inst, USB\VID_0483&PID_3748,       \
                                       USB\VID_0483&PID_3748&REV_0100
```

每一行定义了一个设备模型，可以有多条 `compatible-id`。

### 4.3 排名算法（Ranking Algorithm）

Windows 对每个候选驱动包计算一个 **32 位排名分数**，分数越低越好：

```
Rank = 0xSSGGTHHH
       ││││└─── Identifier Score (标识符匹配分)
       ││└──── Feature Score    (特性得分)
       └└───── Signature Score  (签名得分)
```

#### Identifier Score 详解（最关键的部分）

根据 ["Identifier Score" 文档](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/identifier-score--windows-vista-and-later-)，四种匹配类型的得分如下：

| 匹配类型 | 得分范围 | 含义 | 优先级 |
|----------|---------|------|--------|
| **硬件ID ↔ 硬件ID** | 0x0000 ~ 0x0FFF | 设备的 Hardware ID 精确命中 INF 的 Hardware ID | 🥇 最优 |
| **硬件ID ↔ 兼容ID** | 0x1000 ~ 0x1FFF | 设备的 Hardware ID 命中了 INF 的 Compatible ID | 🥈 |
| **兼容ID ↔ 硬件ID** | 0x2000 ~ 0x2FFF | 设备的 Compatible ID 命中了 INF 的 Hardware ID | 🥉 |
| **兼容ID ↔ 兼容ID** | 0x3000 ~ 0x3FFF | 设备的 Compatible ID 命中了 INF 的 Compatible ID | 🏅 最差 |

**Identifier Score = 匹配类型分 + 列表位置分**

- 列表位置分：设备报告的 ID 列表中，越靠前的 ID 得分越低（越好）
  - 位置 1 → `0x000`
  - 位置 2 → `0x001`
  - ...
  - 位置 N → `0x(N-1)` (最多 `0xFFF`)

---

## 五、ST-Link (VID:0483 PID:3748) 的案例分析

### 5.1 设备报告的 ID 列表

根据 USB 描述符，Windows 为 ST-Link 生成以下 ID（从具体到通用排列）：

```
Hardware IDs (设备报告):
  1. USB\VID_0483&PID_3748&REV_0100    ← 最精确
  2. USB\VID_0483&PID_3748             ← 忽略版本号

Compatible IDs (设备报告):
  1. USB\CLASS_FF&SUBCLASS_FF&PROT_FF   ← 厂商自定义类
  2. USB\CLASS_FF&SUBCLASS_FF
  3. USB\CLASS_FF
```

### 5.2 为什么 Windows 找不到驱动？

```
Windows 搜索流程（针对 ST-Link）：

① 搜索 Driver Store
   → 查找匹配 USB\VID_0483&PID_3748&REV_0100 的 INF
   → ❌ 未安装 STSW-LINK009，Driver Store 中没有相关条目

② 搜索 %SystemRoot%\INF
   → 扫描所有 .inf 文件
   → ❌ 没有任何 INF 声明 USB\VID_0483&PID_3748

③ Windows Update
   → ❌ 24小时内可能不会触发
   → ❌ ST-Link 驱动不一定在 Windows Update 目录中

结果: CM_PROB_FAILED_INSTALL (错误码 28)
      → "此设备的驱动程序未安装"
```

### 5.3 对比：为什么 U 盘插上就能用？

U 盘的设备描述符中 `bDeviceClass = 0x08`（Mass Storage），Windows 内置的 `usbstor.inf` 中已经声明了 `USB\CLASS_08` 作为 Compatible ID：

```
USB Mass Storage Device 的 Compatible ID:
  USB\CLASS_08&SUBCLASS_06&PROT_50
  USB\CLASS_08&SUBCLASS_06
  USB\CLASS_08                      ← 匹配！
```

因为这是一个 **标准设备类**，Windows 自带泛型驱动，Compatible ID 匹配即可工作。而 ST-Link 的 class = 0xFF（Vendor Specific），没有标准类驱动可以匹配，必须有人为它提供精确的 VID/PID 匹配。

### 5.4 两种修复方案的技术原理

#### 方案 A：安装 ST 官方驱动 (STSW-LINK009)

```
STSW-LINK009 做的事情：
  1. 将 .inf 和 .sys 文件复制到 Driver Store
  2. 在 INF 的 [Models] 节中声明:
     USB\VID_0483&PID_3748 ← 硬件 ID 精确匹配
  3. 设备重新枚举时，Windows 找到匹配 → 加载 ST 的驱动栈

匹配结果：硬件ID ↔ 硬件ID，Rank = 0x00000000（最优匹配）
```

#### 方案 B：Zadig 替换为 WinUSB

```
Zadig 做的事情：
  1. 生成一个 INF 文件，声明:
     USB\VID_0483&PID_3748 → WinUSB.sys
  2. 通过 SetupAPI (SetupCopyOEMInf) 安装到 Driver Store
  3. 调用 CM_Reenumerate_DevNode 触发驱动重装

原理：Zadig 绕过了 ST 官方驱动，用 Microsoft 的通用 WinUSB 驱动
      来接管设备。WinUSB.sys 提供的是原始 USB bulk 传输接口，
      OpenOCD/pyOCD 通过 libusb 可以直接调用。
```

### 5.5 注册表中的痕迹

你报告中这一行很有意思：

```
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\usbflags\048337480100
 osvc : REG_BINARY 00 00
```

根据 Microsoft 文档 ["USB Device Registry Entries"](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/usb-device-specific-registry-settings)：

- 键名 `048337480100` = `0x0483`(VID) + `0x3748`(PID) + `0x0100`(bcdDevice)
- `osvc = 0x0000` → 说明 Windows 尝试过查询 Microsoft OS Descriptor，但设备没有返回有效响应

这说明 Windows **已经做了 USB 协议层的枚举**（阶段2完成了），但卡在了**驱动匹配阶段**（阶段3）。

---

## 六、总结：驱动匹配的本质

```
┌──────────────────────────────────────────────────────────────────┐
│                    Windows USB 驱动匹配的核心逻辑                  │
│                                                                    │
│   USB 设备 ──► USB 描述符 ──► Hardware ID List ──┐               │
│                                                   │               │
│   INF 文件 ──► [Models] 节 ──► ID 声明列表 ──────┤               │
│                                                   │               │
│                                          ┌────────▼──────────┐    │
│                                          │   字符串匹配      │    │
│                                          │    + 排名打分     │    │
│                                          └────────┬──────────┘    │
│                                                   │               │
│                                    ┌──────────────▼───────────┐   │
│                                    │ 有匹配? → 加载驱动       │   │
│                                    │ 无匹配? → 错误码 28      │   │
│                                    └──────────────────────────┘   │
│                                                                    │
│   关键变量:                                                        │
│   - bDeviceClass = 0x00~0xFE (标准类) → 有兼容ID, 可自动匹配      │
│   - bDeviceClass = 0xFF (厂商自定义) → 必须精确VID/PID匹配        │
│   - bDeviceClass = 0x00 (由接口定义) → 看接口描述符               │
└──────────────────────────────────────────────────────────────────┘
```

> 📚 **一句话总结**：Windows 通过比较"USB 描述符生成的 Hardware ID / Compatible ID"与"INF 文件中声明的 ID"来做字符串匹配，然后按照签名、特性、匹配精度三个维度打分排名，选最低分的驱动加载。ST-Link 因为用的是 Vendor-Specific class (0xFF)，没有标准类驱动兜底，必须有人提供精确的 VID/PID 匹配。

---

## 七、参考文档

| 文档 | 链接 |
|------|------|
| Step 1: The New Device is Identified | https://learn.microsoft.com/en-us/windows-hardware/drivers/install/step-1--the-new-device-is-identified |
| Standard USB Identifiers | https://learn.microsoft.com/en-us/windows-hardware/drivers/install/standard-usb-identifiers |
| Identifiers for USB Devices | https://learn.microsoft.com/en-us/windows-hardware/drivers/install/identifiers-for-usb-devices |
| How Windows Selects a Driver | https://learn.microsoft.com/en-us/windows-hardware/drivers/install/how-windows-selects-a-driver-for-a-device |
| How Windows Ranks Driver Packages | https://learn.microsoft.com/en-us/windows-hardware/drivers/install/how-windows-ranks-driver-packages |
| Identifier Score | https://learn.microsoft.com/en-us/windows-hardware/drivers/install/identifier-score--windows-vista-and-later- |
| INF Models Section | https://learn.microsoft.com/en-us/windows-hardware/drivers/install/inf-models-section |
| USB Device Registry Entries | https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/usb-device-specific-registry-settings |
| Device and Driver Installation Overview | https://learn.microsoft.com/en-us/windows-hardware/drivers/install/ |
| STSW-LINK009 Official Page | https://www.st.com/en/development-tools/stsw-link009.html |
| USB Device Descriptor (MS Docs) | https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/usbspec/ns-usbspec-_usb_device_descriptor |

---

*由知心姐姐基于 Microsoft 官方文档编写 ✨*
