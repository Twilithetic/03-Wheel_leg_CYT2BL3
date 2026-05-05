import pdfplumber
pdf_path = r"D:\03-Wheel_leg_CYT2BL3\docs\CYT2BL3核心板资料含IAR开发环境链接\芯片官方手册\Infineon-TRAVEO_2G_CY2BL-DataSheet-v09_00-EN.pdf"
with pdfplumber.open(pdf_path) as pdf:
    total = len(pdf.pages)
    print(f"Total pages: {total}")
    for i in range(total):
        page = pdf.pages[i]
        text = page.extract_text()
        if text:
            tl = text.lower()
            if any(kw in tl for kw in ["debug", "dap", "swd", "jtag", "swj", "swclk", "swdio", "tck", "tms", "tdi", "tdo", "trace", "swo"]):
                print(f"\n--- Page {i+1} ---")
                print(text[:2000])
