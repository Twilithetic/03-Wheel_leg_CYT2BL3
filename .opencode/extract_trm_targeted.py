import pdfplumber
import re

pdf_path = r"D:\03-Wheel_leg_CYT2BL3\docs\资料-Infineon-TRAVEO_T2G_TVII-B-H-4M_registers_body_controller_high_technical_reference_manual-AdditionalTechnicalInformation-v06_00-EN.pdf"

with pdfplumber.open(pdf_path) as pdf:
    total = len(pdf.pages)
    print(f"Total pages: {total}")
    
    # Quick scan for chapter headings around debug/cpu/programming
    # Look at TOC first
    print("\n========== CHAPTER/SECTION HEADINGS ==========")
    for i in range(min(200, total)):
        page = pdf.pages[i]
        text = page.extract_text()
        if text:
            for line in text.split("\n"):
                clean = line.strip()
                # Match chapter headings like "1. Introduction" or "10. Debug"
                if re.match(r'^\d{1,2}\.\s', clean) and len(clean) > 5:
                    if any(kw in clean.lower() for kw in ["overview", "debug", "cpu", "program", "flash", 
                                                           "cortex", "test", "dap", "access", "trace",
                                                           "system", "introduction"]):
                        print(f"  [p{i+1}] {clean}")
    
    # Now specifically look for "Debug" or "CPU Subsystem" related sections
    print("\n========== SEARCHING FOR KEY SECTIONS ==========")
    target_sections = {
        "cpu_subsystem": [],
        "debug": [],
        "programming": [],
        "dap": []
    }
    
    for i in range(total):
        page = pdf.pages[i]
        text = page.extract_text()
        if text:
            tl = text.lower()
            
            # Look for CPU subsystem
            if re.search(r'(?i)(cpu\s+subsystem|cortex.cm4\s+subsystem|arm\s+cortex.cm4)', tl):
                target_sections["cpu_subsystem"].append(i)
            
            # Look for Debug Access Port
            if re.search(r'(?i)(debug\s+access\s+port|dap)', tl):
                target_sections["dap"].append(i)
    
    for section_name, pages in target_sections.items():
        if pages:
            # Merge consecutive pages into ranges
            ranges = []
            start = pages[0]
            end = pages[0]
            for p in pages[1:]:
                if p == end + 1:
                    end = p
                else:
                    ranges.append((start, end))
                    start = p
                    end = p
            ranges.append((start, end))
            print(f"\n{section_name}: {len(pages)} pages, ranges: {ranges}")
            
            # Print first range content
            if ranges:
                s, e = ranges[0]
                print(f"  Content of pages {s+1}-{e+1}:")
                for pg in range(s, min(s+5, e+1)):
                    page = pdf.pages[pg]
                    text = page.extract_text()
                    if text:
                        print(f"\n  --- Page {pg+1} ---")
                        print(text[:1500])
