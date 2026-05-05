import pdfplumber
import re

pdf_path = r"D:\03-Wheel_leg_CYT2BL3\docs\资料-Infineon-TRAVEO_T2G_TVII-B-H-4M_registers_body_controller_high_technical_reference_manual-AdditionalTechnicalInformation-v06_00-EN.pdf"

with pdfplumber.open(pdf_path) as pdf:
    total = len(pdf.pages)
    print(f"Total pages: {total}")
    
    # Search for reset/boot/debug init related content
    keywords = [
        "boot sequence", "boot rom", "rom boot", "startup",
        "reset sequence", "reset timing", "after reset",
        "debug pin", "swj", "swd", "debug interface",
        "pin configuration", "hsiom", "port configuration",
        "life cycle", "normal mode",
        "power-on reset", "system reset",
        "swj_dp", "serial wire"
    ]
    
    found_pages = set()
    for i in range(total):
        page = pdf.pages[i]
        text = page.extract_text()
        if text:
            tl = text.lower()
            for kw in keywords:
                if kw in tl:
                    found_pages.add(i)
                    break
    
    print(f"\nFound {len(found_pages)} pages with relevant keywords")
    print(f"Page range: {min(found_pages) if found_pages else 'N/A'} to {max(found_pages) if found_pages else 'N/A'}")
    
    # Print content from matching pages that are clustered
    sorted_pages = sorted(found_pages)
    clusters = []
    if sorted_pages:
        start = sorted_pages[0]
        end = sorted_pages[0]
        for p in sorted_pages[1:]:
            if p <= end + 3:
                end = p
            else:
                clusters.append((start, end))
                start = p
                end = p
        clusters.append((start, end))
    
    for s, e in clusters:
        print(f"\n{'='*60}")
        print(f"Pages {s+1} to {e+1}")
        print(f"{'='*60}")
        for pg in range(s, e+1):
            page = pdf.pages[pg]
            text = page.extract_text()
            if text:
                # Print lines containing keywords
                lines = text.split('\n')
                relevant = [l for l in lines if any(kw in l.lower() for kw in keywords)]
                if relevant:
                    print(f"\n--- Page {pg+1} ---")
                    for line in relevant[:20]:
                        print(f"  {line.strip()}")
                    if len(relevant) > 20:
                        print(f"  ... ({len(relevant)-20} more lines)")
