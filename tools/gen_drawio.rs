#!/usr/bin/env cargo
---
[package]
name = "gen-drawio-diagrams"
edition = "2024"

[dependencies]
anyhow = "1"
---

//! 生成 CYT2BL3 SWD 调试流程的 draw.io 图表
//!
//! 用法: cargo +nightly -Zscript tools/gen_drawio.rs
//! 输出: docs/*.drawio (3 个文件)

use std::fs;

fn main() -> anyhow::Result<()> {
    let out_dir = "docs";

    fs::write(
        &format!("{out_dir}/01_probe-rs_调用链.drawio"),
        diagram_call_chain(),
    )?;
    println!("✅ 01_probe-rs_调用链.drawio");

    fs::write(
        &format!("{out_dir}/02_CYT2BL3_启动时序.drawio"),
        diagram_boot_timing(),
    )?;
    println!("✅ 02_CYT2BL3_启动时序.drawio");

    fs::write(
        &format!("{out_dir}/03_SWD协议_NACK分析.drawio"),
        diagram_swd_nack(),
    )?;
    println!("✅ 03_SWD协议_NACK分析.drawio");

    println!("\n🎉 全部完成! 用 draw.io 打开 docs/*.drawio 查看");
    Ok(())
}

// ── 辅助函数 ──

fn s(fill: &str) -> String {
    let stroke = match fill {
        "#fff2cc" => "#d6b656",
        "#dae8fc" => "#6c8ebf",
        "#d5e8d4" => "#82b366",
        "#e1d5e7" => "#9673a6",
        "#f8cecc" => "#b85450",
        "#ffe6cc" => "#d79b00",
        "#ffffff" => "#666666",
        _ => "#666666",
    };
    let rounding = if fill == "#ffffff" { "" } else { "rounded=1;" };
    format!("{rounding}whiteSpace=wrap;html=1;fillColor={fill};strokeColor={stroke};fontSize=10;")
}

fn mxfile(name: &str, cells: String) -> String {
    format!(r#"<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="app.diagrams.net" modified="2026-05-06T00:00:00.000Z" version="24.0.0">
  <diagram id="diagram-1" name="{name}">
    <mxGraphModel dx="1200" dy="900" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1200" pageHeight="900" math="0" shadow="0">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
        {cells}
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>"#)
}

fn rect(id: &str, x: i32, y: i32, w: i32, h: i32, text: &str, style: &str) -> String {
    format!(
        r#"        <mxCell id="{id}" value="{text}" style="{style}" vertex="1" parent="1">
          <mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/>
        </mxCell>"#
    )
}

fn arrow(id: &str, src: &str, tgt: &str, style: &str) -> String {
    format!(
        r#"        <mxCell id="{id}" style="{style}" edge="1" parent="1" source="{src}" target="{tgt}">
          <mxGeometry relative="1" as="geometry"/>
        </mxCell>"#
    )
}

fn label(id: &str, x: i32, y: i32, text: &str, color: &str) -> String {
    rect(id, x, y, 150, 24, text, &format!("text;html=1;align=center;fontSize=10;fontColor={};fillColor=none;strokeColor=none;", color))
}

// ── 图1: probe-rs 调用链 ──

fn diagram_call_chain() -> String {
    let s = |spec: &str| format!("rounded=1;whiteSpace=wrap;html=1;fillColor={};strokeColor={};fontSize=11;", spec, spec);

    let mut cells = String::new();

    // 标题
    cells += &label("title", 400, 10, "probe-rs download 调用链 — 从 CLI 到 Flash 烧录", "#000000");

    // 第0行: CLI
    cells += &rect("cli", 40, 50, 200, 36, "probe-rs download\ndownload --chip CYT2BL3BAS --protocol swd", &s("#fff2cc"));
    cells += &rect("main", 300, 50, 150, 36, "main.rs:536\n#[tokio::main]\nasync fn main()", &s("#dae8fc"));
    cells += &rect("sub", 510, 50, 160, 36, "cmd/download.rs:26\nCmd::run()", &s("#dae8fc"));
    cells += &arrow("a0", "cli", "main", "endArrow=classic;html=1;exitX=1;exitY=0.5;entryX=0;entryY=0.5;");
    cells += &arrow("a0b", "main", "sub", "endArrow=classic;html=1;exitX=1;exitY=0.5;entryX=0;entryY=0.5;");

    // 第1行: attach + flash
    cells += &rect("attach", 40, 130, 280, 36, "cli::attach_probe(&client, ...)\n→ 打开探针 → select_protocol(swd) → attach()", &s("#d5e8d4"));
    cells += &rect("flash_fn", 380, 130, 200, 36, "cli::flash(&session, &path, ...)\n→ 分析ELF段 → 创建Flasher", &s("#d5e8d4"));
    cells += &arrow("a1", "sub", "attach", "endArrow=classic;html=1;exitX=0;exitY=1;entryX=0;entryY=0.5;exitDx=0;exitDy=20;");
    cells += &arrow("a1b", "sub", "flash_fn", "endArrow=classic;html=1;exitX=1;exitY=1;entryX=0;entryY=0.5;exitDx=0;exitDy=20;");

    // 第2行: sequence 层
    cells += &rect("seq", 40, 210, 280, 36, "ArmDebugSequence::debug_port_setup()\n→ SWD Line Reset → JTAG→SWD → DPIDR读", &s("#e1d5e7"));
    cells += &rect("flasher_load", 380, 210, 200, 36, "Flasher::load()\n★ 我们改的地方!", &s("#f8cecc"));
    cells += &arrow("a2", "attach", "seq", "endArrow=classic;html=1;exitX=0.5;exitY=1;entryX=0.5;entryY=0;");
    cells += &arrow("a2b", "flash_fn", "flasher_load", "endArrow=classic;html=1;exitX=0.5;exitY=1;entryX=0.5;entryY=0;");

    // 第3行: 详细展开
    cells += &rect("dp_setup", 40, 290, 280, 60, "debug_port_setup() (sequences.rs:512)\n  → swd_line_reset()  51 HIGH cycles\n  → swj_sequence(16, 0xE79E)  JTAG→SWD\n  → debug_port_connect()", &s("#e1d5e7"));
    cells += &rect("halt_check", 380, 290, 320, 60, "Flasher::load() (flasher.rs:192)\n  let already_halted = core.core_halted().unwrap_or(true);\n  if already_halted { 跳过 reset }\n  else { core.reset_and_halt() }", &s("#f8cecc"));
    cells += &arrow("a3", "seq", "dp_setup", "endArrow=classic;html=1;exitX=0.5;exitY=1;entryX=0.5;entryY=0;");
    cells += &arrow("a3b", "flasher_load", "halt_check", "endArrow=classic;html=1;exitX=0.5;exitY=1;entryX=0.5;entryY=0;");

    // 第4行: probe 层
    cells += &rect("dpidr", 40, 390, 200, 50, "debug_port_connect() (seq:957)\n  → raw_read_register(DPIDR)\n  → process_batch()\n  → ACK=OK / NACK", &s("#ffe6cc"));
    cells += &rect("core_halt", 300, 390, 150, 50, "CYT2BL3: core已halt\n  → 跳过reset ✅", &s("#d5e8d4"));
    cells += &rect("other_chip", 510, 390, 170, 50, "其他芯片: core未halt\n  → 正常reset ✅", &s("#d5e8d4"));
    cells += &arrow("a4", "dp_setup", "dpidr", "endArrow=classic;html=1;exitX=0;exitY=1;entryX=0;entryY=0.5;exitDx=0;exitDy=20;");
    cells += &arrow("a4b", "halt_check", "core_halt", "endArrow=classic;html=1;exitX=0;exitY=1;entryX=0.5;entryY=0;exitDx=0;exitDy=20;");
    cells += &arrow("a4c", "halt_check", "other_chip", "endArrow=classic;html=1;exitX=1;exitY=1;entryX=0.5;entryY=0;exitDx=0;exitDy=20;");

    // 第5行: 结果
    cells += &rect("result", 200, 480, 250, 40, "Flash 烧录成功 ✅", &s("#d5e8d4;fontSize=14;fontStyle=1"));

    mxfile("probe-rs 调用链", cells)
}

// ── 图2: CYT2BL3 启动时序 ──

fn diagram_boot_timing() -> String {
    let s_rom = "rounded=0;whiteSpace=wrap;html=1;fillColor=#f8cecc;strokeColor=#b85450;fontSize=10;";
    let s_fb = "rounded=0;whiteSpace=wrap;html=1;fillColor=#ffe6cc;strokeColor=#d79b00;fontSize=10;";
    let s_swd = "rounded=0;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;fontSize=10;";
    let s_hi = "rounded=0;whiteSpace=wrap;html=1;fillColor=#e1d5e7;strokeColor=#9673a6;fontSize=10;";
    let s_user = "rounded=0;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;fontSize=10;";

    let mut cells = String::new();
    cells += &label("title", 350, 10, "CYT2BL3 启动时序 — SWD 引脚可用性", "#000000");

    // 时间轴
    cells += &rect("axis", 40, 50, 1050, 2, "", "line;strokeWidth=2;html=1;");
    cells += &label("t0", 40, 55, "T+0ms", "#666666");
    cells += &label("t5", 240, 55, "T+5ms", "#666666");
    cells += &label("t25", 440, 55, "T+25ms", "#666666");
    cells += &label("t50", 800, 55, "T+50ms+", "#666666");

    // 阶段块
    cells += &rect("rom", 40, 80, 380, 50, "ROM Boot (32KB)\n施加 DAP 访问限制", s_rom);
    cells += &rect("fb", 420, 80, 380, 50, "FlashBoot (SFlash @0x1700 2000)\n配置 HSIOM → SWD 引脚就绪", s_fb);
    cells += &rect("listen", 800, 80, 200, 50, "Listen\nWindow\n~20ms", s_swd);
    cells += &rect("user", 1020, 80, 120, 50, "用户\n程序", s_user);

    // 状态指示
    cells += &rect("hisw", 40, 160, 760, 25, "SWD 引脚状态: ██████████████ Hi-Z / GPIO ██████████████████████████████ 已配置为 SWD ████████████████████████", s_hi);
    cells += &rect("daps", 40, 200, 380, 25, "DAP 状态: 施加访问限制", s_rom);
    cells += &rect("dapok", 420, 200, 400, 25, "DAP 状态: 可访问", s_swd);

    // probe 行为
    cells += &rect("pr_reset", 40, 260, 200, 40, "probe-rs:\nreset_and_halt()\n→ 在此窗口内重连 → NACK ❌", &s("#f8cecc"));
    cells += &rect("pr_ok", 440, 260, 200, 40, "probe-rs:\n新 session 连接\n→ DPIDR 读成功 ✅", &s("#d5e8d4"));

    // 箭头
    cells += &arrow("e1", "pr_reset", "rom", "endArrow=classic;html=1;exitX=0.5;exitY=0;entryX=0.5;entryY=1;");
    cells += &arrow("e2", "pr_ok", "fb", "endArrow=classic;html=1;exitX=0.5;exitY=0;entryX=1;entryY=1;");

    // 图例
    cells += &rect("leg_rom", 40, 340, 20, 14, "", s_rom);
    cells += &label("leg1", 65, 338, "ROM Boot (DAP限制)", "#000000");
    cells += &rect("leg_fb", 200, 340, 20, 14, "", s_fb);
    cells += &label("leg2", 225, 338, "FlashBoot (HSIOM配置)", "#000000");
    cells += &rect("leg_swd", 420, 340, 20, 14, "", s_swd);
    cells += &label("leg3", 445, 338, "SWD可用", "#000000");

    // HSIOM 架构
    cells += &rect("hsiom_title", 40, 390, 200, 22, "HSIOM 可编程矩阵架构", &s("#fff2cc;fontStyle=1;fontSize=12;"));
    cells += &rect("pin1", 40, 430, 100, 28, "P23.5", &s("#dae8fc"));
    cells += &rect("pin2", 40, 470, 100, 28, "P23.6", &s("#dae8fc"));
    cells += &rect("pin3", 40, 510, 100, 28, "P23.7", &s("#dae8fc"));
    cells += &rect("hsiom_box", 180, 420, 150, 130, "HSIOM\n可编程矩阵\n(复位后=GPIO)", &s("#f8cecc"));
    cells += &rect("swclk", 370, 430, 100, 28, "SWCLK", &s("#d5e8d4"));
    cells += &rect("swdio", 370, 470, 100, 28, "SWDIO", &s("#d5e8d4"));
    cells += &rect("swdoe", 370, 510, 100, 28, "SWDOE/TDI", &s("#d5e8d4"));
    cells += &rect("dap_box", 510, 420, 120, 130, "SWJ-DP\n→ DAP", &s("#d5e8d4"));

    cells += &arrow("h1", "pin1", "hsiom_box", "endArrow=classic;html=1;exitX=1;exitY=0.5;entryX=0;entryY=0.2;");
    cells += &arrow("h2", "pin2", "hsiom_box", "endArrow=classic;html=1;exitX=1;exitY=0.5;entryX=0;entryY=0.5;");
    cells += &arrow("h3", "pin3", "hsiom_box", "endArrow=classic;html=1;exitX=1;exitY=0.5;entryX=0;entryY=0.8;");
    cells += &arrow("h4", "hsiom_box", "swclk", "endArrow=classic;html=1;exitX=1;exitY=0.2;entryX=0;entryY=0.5;");
    cells += &arrow("h5", "hsiom_box", "swdio", "endArrow=classic;html=1;exitX=1;exitY=0.5;entryX=0;entryY=0.5;");
    cells += &arrow("h6", "hsiom_box", "swdoe", "endArrow=classic;html=1;exitX=1;exitY=0.8;entryX=0;entryY=0.5;");
    cells += &arrow("h7", "swclk", "dap_box", "endArrow=classic;html=1;exitX=1;exitY=0.5;entryX=0;entryY=0.2;");
    cells += &arrow("h8", "swdio", "dap_box", "endArrow=classic;html=1;exitX=1;exitY=0.5;entryX=0;entryY=0.5;");
    cells += &arrow("h9", "swdoe", "dap_box", "endArrow=classic;html=1;exitX=1;exitY=0.5;entryX=0;entryY=0.8;");

    mxfile("CYT2BL3 启动时序", cells)
}

// ── 图3: SWD NACK 分析 ──

fn diagram_swd_nack() -> String {
    let s_ok = "rounded=1;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;fontSize=10;";
    let s_err = "rounded=1;whiteSpace=wrap;html=1;fillColor=#f8cecc;strokeColor=#b85450;fontSize=10;";
    let s_probe = "rounded=1;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;fontSize=10;";
    let s_chip = "rounded=1;whiteSpace=wrap;html=1;fillColor=#ffe6cc;strokeColor=#d79b00;fontSize=10;";

    let mut cells = String::new();
    cells += &label("title", 320, 5, "SWD 协议 — NACK 根因分析 (ADIv5 规范对照)", "#000000");

    // ========== 成功路径 ==========
    cells += &label("ok_title", 40, 35, "✅ 成功路径", "#008800");
    
    cells += &rect("p1", 40, 60, 160, 28, "Host: 发送请求头\nStart|AP|R/W|A2|A3|P|0|1\n= 0xA5 (DPIDR Read)", s_probe);
    cells += &rect("c1", 240, 60, 160, 28, "SW-DP: 收到有效请求\n→ 返回 ACK=001 (OK)", s_ok);
    cells += &rect("c1b", 440, 60, 160, 28, "SW-DP: 发送 RDATA\n32-bit DPIDR + Parity", s_ok);
    cells += &rect("c1c", 640, 60, 160, 28, "Host: 解析 DPIDR\n0x6ba02477 ✅", s_probe);
    cells += &arrow("ok1", "p1", "c1", "endArrow=classic;html=1;");
    cells += &arrow("ok2", "c1", "c1b", "endArrow=classic;html=1;");
    cells += &arrow("ok3", "c1b", "c1c", "endArrow=classic;html=1;");

    // ========== 失败路径 ==========
    cells += &label("err_title", 40, 115, "❌ 失败路径 (NACK)", "#880000");

    cells += &rect("p2", 40, 140, 160, 28, "Host: 发送请求头\n= 0xA5 (DPIDR Read)", s_probe);
    cells += &rect("chip_state", 240, 140, 200, 55, "芯片状态:\nHSIOM 未配置 → 引脚=Hi-Z\n或 ROM Boot → DAP限制\n或 协议错误 → Lockout", s_err);
    cells += &rect("c2", 480, 140, 160, 28, "SW-DP: 不驱动线路\n→ 上拉电阻 → 111", s_err);
    cells += &rect("c2b", 680, 140, 180, 28, "CMSIS-DAP 探针:\n读回 ACK=7 → NACK", s_err);
    cells += &arrow("err1", "p2", "chip_state", "endArrow=classic;html=1;");
    cells += &arrow("err2", "chip_state", "c2", "endArrow=classic;html=1;");
    cells += &arrow("err3", "c2", "c2b", "endArrow=classic;html=1;");

    // ADIv5 规范
    cells += &label("spec_title", 40, 200, "📖 ADIv5 规范 (ARM IHI 0031C) 关键条文", "#0000aa");

    cells += &rect("spec1", 40, 225, 340, 55, "§4.3.6 Protocol error response:\n\"When a protocol error is detected by the SW-DP,\nthe SW-DP does not reply ... and does not drive the line.\"", &s("#fff2cc"));
    cells += &rect("spec2", 420, 225, 300, 55, "§4.4.3 Line reset:\n\"The only valid transactions in reset state are:\nA) read DPIDR  B) switching sequences  C) write TARGETSEL\"", &s("#fff2cc"));
    cells += &rect("spec3", 760, 225, 320, 55, "§4.3.6 Lockout state:\n\"If SW-DP implements SWD v2, it must enter lockout\nafter a single protocol error immediately after line reset.\"\n(CYT2BL3 = DPv2!)", &s("#f8cecc"));

    // 恢复路径
    cells += &label("rec_title", 40, 310, "🔄 恢复路径", "#008888");

    cells += &rect("rec1", 40, 335, 200, 40, "1. SWD Line Reset\n(51 cycles HIGH + 3 LOW)\n→ 强制状态机进入 RESET", s_chip);
    cells += &rect("rec2", 280, 335, 200, 40, "2. 读 DPIDR\n(唯一合法操作)\n→ 状态机 → IDLE", s_chip);
    cells += &rect("rec3", 520, 335, 200, 40, "3. 如果还是 NACK:\n再 Line Reset\n重复直到成功", s_chip);
    cells += &arrow("rec_a", "rec1", "rec2", "endArrow=classic;html=1;");
    cells += &arrow("rec_b", "rec2", "rec3", "endArrow=classic;html=1;");

    // 我们的方案
    cells += &label("fix_title", 40, 405, "🛠️ 我们的解决方案", "#008800");

    cells += &rect("fix1", 40, 430, 280, 60, "flasher.rs 改动:\n  let already_halted = core.core_halted().unwrap_or(true);\n  if already_halted { 跳过 reset }\n\n核心已在 session init 时 halt → 不触发复位\n→ SWD 不断开 → 烧录成功 ✅", &s("#d5e8d4"));
    cells += &rect("fix2", 360, 430, 280, 60, "cyt2bl.rs (Infineon Vendor Sequence):\n  注册 CYT2BL 专用 ArmDebugSequence\n  reset_system 重写:\n  触发复位 → 每100ms轮询DPIDR → 最多100次\n\n(架构限制: reinitialize会刷新底层但caller不知道)", &s("#e1d5e7"));
    cells += &rect("fix3", 680, 430, 280, 60, "XMC4000 对比:\n  类似机制: DAPSA安全位阻断DAP\n  解决方案: spin_until_dapsa_is_clear()\n  轮询直到 ROM Boot 结束\n\n我们对 CYT2BL3 采取类似思路", &s("#ffe6cc"));

    mxfile("SWD NACK 分析", cells)
}
