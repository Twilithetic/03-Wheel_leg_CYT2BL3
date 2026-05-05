import pdfplumber
import re

pdf_path = r"D:\03-Wheel_leg_CYT2BL3\docs\资料-Infineon-TRAVEO_T2G_TVII-B-H-4M_registers_body_controller_high_technical_reference_manual-AdditionalTechnicalInformation-v06_00-EN.pdf"

debug_keywords = ["debug", "dap", "swd", "jtag", "swj", "dp ", "ap ", "access port", "debug port", "adi", "cortex", "test", "trace", "program", "flash"]

with pdfplumber.open(pdf_path) as pdf:
    total = len(pdf.pages)
    print(f"Total pages: {total}")
    
    # Extract first 30 pages for TOC
    print("\n=== TABLE OF CONTENTS (first 30 pages) ===")
    for i in range(min(30, total)):
        page = pdf.pages[i]
        text = page.extract_text()
        if text:
            lines = text.split("\n")
            for line in lines:
                line_lower = line.lower()
                if any(kw in line_lower for kw in ["table of content", "contents", "chapter", "section",
                                                     "debug", "dap", "swd", "jtag", "swj", "access port",
                                                     "debug port", "trace", "program", "flash", "test mode"]):
                    print(f"  [p{i+1}] {line.strip()}")
    
    # Search through all pages for debug-related content
    print("\n=== DEBUG-RELATED SECTIONS (scanning all pages) ===")
    debug_pages = []
    for i in range(total):
        page = pdf.pages[i]
        text = page.extract_text()
        if text:
            text_lower = text.lower()
            # Look for strong debug indicators
            if any(kw in text_lower for kw in ["debug port", "access port", "debug interface", 
                                                 "swd", "swj-dp", "sw-dp", "jtag-dp", 
                                                 "serial wire", "debug and test", "dap", 
                                                 "adi", "dp_ctrl", "swj"]):
                debug_pages.append(i+1)
    
    print(f"Found {len(debug_pages)} pages with debug content")
    if debug_pages:
        print(f"Page ranges: {min(debug_pages)} to {max(debug_pages)}")
        
        # Print representative pages
        for pg in debug_pages[:5]:
            page = pdf.pages[pg-1]
            text = page.extract_text()
            if text:
                lines = text.split("\n")
                print(f"\n--- Page {pg} ---")
                for line in lines[:30]:
                    print(f"  {line.strip()}")
