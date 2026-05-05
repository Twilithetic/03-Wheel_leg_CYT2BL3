import pdfplumber
import re

pdf_path = r"D:\03-Wheel_leg_CYT2BL3\docs\资料-Infineon-TRAVEO_T2G_TVII-B-H-4M_registers_body_controller_high_technical_reference_manual-AdditionalTechnicalInformation-v06_00-EN.pdf"

with pdfplumber.open(pdf_path) as pdf:
    total = len(pdf.pages)
    print(f"Total pages: {total}")
    
    # Step 1: Extract TOC (first 50 pages) - but specifically look for debug/cpu related
    print("\n===== TOC: DEBUG / CPU / PROGRAMMING RELATED SECTIONS =====")
    for i in range(min(80, total)):
        page = pdf.pages[i]
        text = page.extract_text()
        if text:
            for line in text.split("\n"):
                line_lower = line.lower()
                if any(kw in line_lower for kw in ["debug", "dap", "swd", "jtag", "swj",
                                                     "cortex", "cpu", "program", "flash",
                                                     "test", "trace", "system", "10.", "11.", "12.",
                                                     "13.", "14.", "15.", "16.", "17.", "18."]):
                    if len(line.strip()) > 3:  # skip empty
                        print(f"  [p{i+1}] {line.strip()}")
    
    # Step 2: Find pages with "Debug" or "debug" in heading-style text (larger font)
    print("\n\n===== SEARCHING FOR DEBUG CHAPTER HEADINGS =====")
    debug_chapter_start = None
    for i in range(total):
        page = pdf.pages[i]
        text = page.extract_text()
        if text:
            # Look for chapter/section headings about debug
            for line in text.split("\n"):
                clean = line.strip()
                if re.search(r'(?i)(chapter|section)\s+\d+.*debug', clean):
                    print(f"  [p{i+1}] >>> HEADING: {clean}")
                    if debug_chapter_start is None:
                        debug_chapter_start = i
                elif re.search(r'(?i)^\d+\.\d+.*(debug|dap|swd|jtag|access port)', clean):
                    print(f"  [p{i+1}] >>> SECTION: {clean}")
    
    if debug_chapter_start:
        print(f"\n\n===== PRINTING DEBUG CHAPTER CONTENT (starting p{debug_chapter_start+1}) =====")
        pages_to_show = min(30, total - debug_chapter_start)
        for offset in range(pages_to_show):
            pg = debug_chapter_start + offset
            page = pdf.pages[pg]
            text = page.extract_text()
            if text:
                print(f"\n--- Page {pg+1} ---")
                print(text[:3000])
