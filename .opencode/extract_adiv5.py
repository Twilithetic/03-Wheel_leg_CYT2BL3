import pdfplumber

pdf_path = r"D:\03-Wheel_leg_CYT2BL3\docs\资料-ARM_ADIv5_Specification.pdf"

with pdfplumber.open(pdf_path) as pdf:
    total = len(pdf.pages)
    print(f"Total pages: {total}")
    
    # Extract all pages for overview
    print("\n=== FULL CONTENT ===")
    for i in range(total):
        page = pdf.pages[i]
        text = page.extract_text()
        if text:
            print(f"\n--- Page {i+1} ---")
            print(text)
