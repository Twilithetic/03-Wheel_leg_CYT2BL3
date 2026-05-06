# STLinkReflash "Cannot find ST-LINK" — 问题分析与解决方案

> *"ERROR: Cannot find an ST-LINK, multiple ST-LINKs plugged in, or ST-LINK is in use"*
> 基于 Embedded Artistry、SEGGER 官方、ST 社区的多方验证

---

## 一、确认真相

### 1.1 你的设备完全正常

```
probe-rs list → ✅ 能看到 STLink V2
STLinkReflash  → ❌ 找不到

这矛盾吗？不！
probe-rs 用 WinUSB 驱动 → 能看到
STLinkReflash 需要 ST 官方驱动 → 看不到

你的 WinUSB 驱动是 EIDE/OpenOCD/probe-rs 安装的，
STLinkReflash 不认识它。
```

### 1.2 两种驱动的区别

```
WinUSB (当前)                    ST 官方驱动 (STLinkReflash 要的)
─────────────                    ──────────────────────────────
通用 USB 驱动                     ST 定制驱动
probe-rs/OpenOCD/pyOCD 用        STM32CubeIDE/ST-Link Utility 用
识别: "STM32 STLink"             识别: "STMicroelectronics STLink dongle"
服务: WinUSB                     服务: STTub30 或类似
```

---

## 二、解决方案（四种，按推荐度排序）

### 🥇 方案 A：安装 ST 官方驱动（最可靠）

```
Step 1: 下载 ST-Link 驱动
  → 搜索 "STSW-LINK009" 或访问:
  → https://www.st.com/en/development-tools/stsw-link009.html

Step 2: 解压后运行安装程序
  → 64位系统运行: dpinst_amd64.exe
  → 或运行: stlink_winusb_install.bat

Step 3: 检查设备管理器
  → 应该能看到 "STMicroelectronics STLink dongle"
  → 而不是 "STM32 STLink"

Step 4: 重试 STLinkReflash (管理员权限)

原理:
  ST 官方驱动安装后，设备管理器中会注册正确的硬件 ID
  STLinkReflash 通过 ST 驱动接口查找设备
```

### 🥈 方案 B：用 Zadig 切换驱动（最快）

```
Step 1: 下载 Zadig
  → https://zadig.akeo.ie/

Step 2: 打开 Zadig
  → Options → List All Devices (勾选)

Step 3: 下拉列表选择 "STM32 STLink"
  → 当前驱动显示: WinUSB

Step 4: 切换驱动
  → 选择 "libusb-win32" (或 "WinUSB (v6.1.7600.16385)")
  → 点 "Replace Driver"

Step 5: 重试 STLinkReflash (管理员权限)

注意:
  ✅ 有人用 libusb-win32 成功了
  ⚠️ 切换后 probe-rs/OpenOCD 可能需要重新适配
  ⚠️ 可用 Zadig 随时切回 WinUSB
```

### 🥉 方案 C：用 STM32CubeProgrammer 升级固件（绕路）

```
Step 1: 下载 STM32CubeProgrammer
  → https://www.st.com/en/development-tools/stm32cubeprog.html

Step 2: 用 CubeProgrammer 连接 ST-Link
  → 它会自动安装正确的驱动
  → 可以在工具中升级 ST-Link 固件到最新版

Step 3: 升级完成后关闭 CubeProgrammer
  → 重试 STLinkReflash

原理:
  CubeProgrammer 自带了 ST 驱动
  新固件可能兼容性更好
```

### 🏅 方案 D：降级 ST-Link 固件后升级

```
来自 Embedded Artistry 的发现 (2020):
  ST-Link 固件 V2.32.22 → STLinkReflash 可能崩溃
  需要先降级固件 → 再运行 STLinkReflash

  "Sometimes STLinkReflash crashes with firmware V2.32.22.
   Just re-open and re-run. I haven't seen it crash twice."

步骤:
  1. 用 ST-Link Utility 降级固件
  2. 重试 STLinkReflash
```

---

## 三、社区验证

| 来源 | 方法 | 结果 |
|------|------|:---:|
| Embedded Artistry (2020) | 安装 ST 驱动 + J-Link 软件 | ✅ |
| ST 社区 (2025) | 用 Zadig 换 libusb-win32 | ✅ |
| ST 社区 (2022) | 手动更新驱动 → 选 ST 驱动 | ✅ |
| SEGGER 论坛 | 先升级 ST-Link 固件，再转换 | ✅ |
| mbed 社区 | 修改 .inf 文件适配硬件 ID | ⚠️ |

---

## 四、⚠️ 重要法律提示

### SEGGER 许可协议明确规定：

> **"The firmware is only to be used with ST target devices. 
>  Using it with other devices is prohibited and illegal."**
>
> — SEGGER STLinkReflash Terms of Use

```
翻译:
  刷完 J-Link 固件后：
  ✅ 可以调试 STM32/STM8 (授权范围)
  ❌ 调试 CYT2BL3 违反 SEGGER 许可协议！
  ❌ 量产使用禁止
  ✅ 学习研究 (灰色地带)

这意味着:
  如果你用刷了 J-Link 的 ST-Link 来烧录 CYT2BL3:
  → 技术上完全可行 (SWD 通用 + J-Link 有 CYT2BL3 算法)
  → 法律上违反了 SEGGER 的授权条款
  → 个人学习可能被容忍，商业使用不行
```

---

## 五、合法替代方案

### 方案 1：下载 Infineon OpenOCD（完全合法免费）

```
Infineon Auto Flash Utility:
  ✅ Infineon 官方工具
  ✅ 原生 CYT2BL3 支持
  ✅ 开源 (GPL v2)
  ✅ 支持 ST-Link 作为 SWD 探针
  ✅ 没有任何授权问题

需要: 注册 MyInfineon 账号 (免费)
下载: https://www.infineon.com/auto-flash-utility
```

### 方案 2：购买正版 J-Link EDU

```
SEGGER J-Link EDU:
  ✅ 全功能 J-Link
  ✅ 合法调试任何芯片
  ✅ 价格 ~¥400
  ✅ 学生/教育优惠

J-Link EDU Mini:
  ✅ 精简版
  ✅ 价格 ~¥200
```

---

## 六、快速决策

```
你想...                  → 用什么

合法免费烧录 CYT2BL3     → Infineon OpenOCD (注册下载)
最快但灰色地带           → 刷 J-Link + 自己承担许可风险
长期合法方案             → 买 J-Link EDU (~¥400)

当前 STLinkReflash 卡住  → 选方案 A (装 ST 驱动) 或 B (Zadig)
```

---

## 七、总结

```
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║  STLinkReflash 找不到设备的根因：                             ║
║                                                              ║
║  你的 ST-Link 用 WinUSB 驱动                                 ║
║  STLinkReflash 要 ST 官方驱动                                ║
║  两套驱动互不兼容                                            ║
║                                                              ║
║  🔧 解决：装 ST 官方驱动 (STSW-LINK009)                      ║
║     或用 Zadig 把 WinUSB 换成 libusb-win32                   ║
║                                                              ║
║  ⚠️ 即使转换成功，SEGGER 协议禁止用于非 ST 芯片              ║
║                                                              ║
║  🥇 合法方案：下载 Infineon OpenOCD（免费注册即可）           ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

---

*报告版本：v1.0 | 2026-05-04 | 基于 Embedded Artistry + SEGGER 官方 + ST 社区*
