#!/usr/bin/env python3
# Copyright (c) 2026 CDNA5-M1 project.
# SPDX-License-Identifier: MIT
"""Generate the editable CDNA5-M1 architecture Word document.

The block diagrams are native VML groups (Word shapes + text boxes), not
pasted screenshots.  Open the .docx in Word, click a diagram, and edit the
shapes/text directly.  The generator is deterministic and is committed next
to the generated document.
"""
from __future__ import annotations

import os
from xml.sax.saxutils import escape

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml import OxmlElement, parse_xml
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(HERE, "doc", "CDNA5-M1_Architecture.docx")

# ---------------------------------------------------------------------------
# VML helpers (editable Word shapes)
# ---------------------------------------------------------------------------
VML_NS = (
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:v="urn:schemas-microsoft-com:vml" '
    'xmlns:o="urn:schemas-microsoft-com:office:office" '
    'xmlns:w10="urn:schemas-microsoft-com:office:word"'
)

BLUE = ("DAE8FC", "6C8EBF")
GREEN = ("D5E8D4", "82B366")
ORANGE = ("FFE6CC", "D79B00")
RED = ("F8CECC", "B85450")
PURPLE = ("E1D5E7", "9673A6")
GREY = ("F5F5F5", "666666")
YELLOW = ("FFF2CC", "D6B656")


def _rpr(size=7, bold=False, color="000000"):
    b = "<w:b/>" if bold else ""
    return (
        '<w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" '
        'w:eastAsia="Microsoft JhengHei"/>'
        f'<w:sz w:val="{int(size * 2)}"/><w:szCs w:val="{int(size * 2)}"/>'
        f'<w:color w:val="{color}"/>{b}</w:rPr>'
    )


def _txbx(lines, size=7, bold=False, color="000000", align="center"):
    paras = []
    for line in lines:
        paras.append(
            "<w:p><w:pPr>"
            f'<w:jc w:val="{align}"/>'
            '<w:spacing w:before="0" w:after="0" w:line="220" w:lineRule="auto"/>'
            f"{_rpr(size, bold, color)}</w:pPr>"
            f'<w:r>{_rpr(size, bold, color)}<w:t xml:space="preserve">{escape(line)}</w:t></w:r></w:p>'
        )
    return "<w:txbxContent>" + "".join(paras) + "</w:txbxContent>"


def shape(x, y, w, h, lines, palette=BLUE, size=7, bold=False, rounded=True,
          dash=False, text_color="000000"):
    fill, stroke = palette
    tag = "v:roundrect" if rounded else "v:rect"
    dash_attr = ' dashstyle="dash"' if dash else ""
    if isinstance(lines, str):
        lines = [lines]
    return (
        f'<{tag} style="position:absolute;left:{x};top:{y};width:{w};height:{h};z-index:2" '
        f'fillcolor="#{fill}" strokecolor="#{stroke}" strokeweight="1pt">'
        f'<v:stroke{dash_attr}/>'
        '<v:textbox inset="2pt,1pt,2pt,1pt">'
        f"{_txbx(lines, size, bold, text_color)}"
        "</v:textbox>"
        f"</{tag}>"
    )


def label(x, y, w, h, lines, size=7, bold=False, color="000000"):
    if isinstance(lines, str):
        lines = [lines]
    return (
        f'<v:rect style="position:absolute;left:{x};top:{y};width:{w};height:{h};z-index:3" '
        'filled="f" stroked="f">'
        '<v:textbox inset="0pt,0pt,0pt,0pt">'
        f"{_txbx(lines, size, bold, color)}"
        "</v:textbox></v:rect>"
    )


def line(x1, y1, x2, y2, color="333333", width=1.25, arrow=True, dash=False):
    dash_attr = ' dashstyle="dash"' if dash else ""
    arrow_attr = '<v:stroke endarrow="block"/>' if arrow else ""
    return (
        f'<v:line style="position:absolute;z-index:1" from="{x1},{y1}" to="{x2},{y2}" '
        f'strokecolor="#{color}" strokeweight="{width}pt">'
        f'{arrow_attr}<v:stroke{dash_attr}/></v:line>'
    )


def vgroup(children, width_pt=480, height_pt=350, cw=9600, ch=7000, gid="fig"):
    return (
        f"<w:pict {VML_NS}>"
        f'<v:group id="{gid}" style="width:{width_pt}pt;height:{height_pt}pt" '
        f'coordsize="{cw},{ch}" coordorigin="0,0">'
        + "".join(children)
        + "</v:group></w:pict>"
    )


# ---------------------------------------------------------------------------
# Document helpers
# ---------------------------------------------------------------------------
def set_cell_shading(cell, hex_color):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hex_color)
    tcPr.append(shd)


def add_table(doc, headers, rows, widths=None, font_size=8.5):
    table = doc.add_table(rows=1, cols=len(headers))
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    hdr = table.rows[0].cells
    for i, text in enumerate(headers):
        hdr[i].text = ""
        p = hdr[i].paragraphs[0]
        r = p.add_run(text)
        r.bold = True
        r.font.size = Pt(font_size)
        set_cell_shading(hdr[i], "D9E2F3")
    for row in rows:
        cells = table.add_row().cells
        for i, text in enumerate(row):
            cells[i].text = ""
            p = cells[i].paragraphs[0]
            r = p.add_run(str(text))
            r.font.size = Pt(font_size)
    if widths:
        for i, w in enumerate(widths):
            for row in table.rows:
                row.cells[i].width = Cm(w)
    return table


def code(doc, text):
    for line in text.strip("\n").splitlines():
        p = doc.add_paragraph(style="Code")
        p.add_run(line if line else " ")


def figure(doc, xml, caption):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run()
    run._r.append(parse_xml(xml))
    cap = doc.add_paragraph(style="Caption")
    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cap.add_run(caption)


def add_page_number(paragraph):
    run = paragraph.add_run()
    fld1 = OxmlElement("w:fldChar")
    fld1.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = " PAGE "
    fld2 = OxmlElement("w:fldChar")
    fld2.set(qn("w:fldCharType"), "end")
    run._r.append(fld1)
    run._r.append(instr)
    run._r.append(fld2)


def add_toc(doc):
    p = doc.add_paragraph()
    run = p.add_run()
    fld1 = OxmlElement("w:fldChar")
    fld1.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = ' TOC \\o "1-3" \\h \\z \\u '
    sep = OxmlElement("w:fldChar")
    sep.set(qn("w:fldCharType"), "separate")
    end = OxmlElement("w:fldChar")
    end.set(qn("w:fldCharType"), "end")
    placeholder = OxmlElement("w:t")
    placeholder.text = "（在 Word 中按右鍵 → 更新功能變數以產生目錄）"
    run._r.append(fld1)
    run._r.append(instr)
    run._r.append(sep)
    run._r.append(placeholder)
    run._r.append(end)


def style_document(doc):
    normal = doc.styles["Normal"]
    normal.font.name = "Arial"
    normal.font.size = Pt(10.5)
    normal.paragraph_format.space_after = Pt(4)
    normal.paragraph_format.line_spacing = 1.12

    for name, size, color in [
        ("Title", 26, "0B3D6E"),
        ("Subtitle", 13, "444444"),
        ("Heading 1", 17, "0B3D6E"),
        ("Heading 2", 13, "1F4E79"),
        ("Heading 3", 11, "2E74B5"),
    ]:
        st = doc.styles[name]
        st.font.name = "Arial"
        st.font.size = Pt(size)
        st.font.color.rgb = RGBColor.from_string(color)
        st.font.bold = name != "Subtitle"

    cap = doc.styles["Caption"]
    cap.font.name = "Arial"
    cap.font.size = Pt(9)
    cap.font.italic = True
    cap.font.color.rgb = RGBColor.from_string("555555")

    code_style = doc.styles.add_style("Code", 1)  # paragraph
    code_style.font.name = "Consolas"
    code_style.font.size = Pt(8)
    code_style.paragraph_format.space_after = Pt(0)
    code_style.paragraph_format.line_spacing = 1.0

    # East Asian font on Normal
    rpr = normal.element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = OxmlElement("w:rFonts")
        rpr.append(rfonts)
    rfonts.set(qn("w:eastAsia"), "Microsoft JhengHei")


# ---------------------------------------------------------------------------
# Figures
# ---------------------------------------------------------------------------
def fig_top():
    c = []
    # host/control side
    c.append(shape(80, 250, 1500, 700, ["Host CPU", "ROCm / HIP application"], BLUE, 8, True))
    c.append(line(1580, 600, 2250, 600))
    c.append(label(1600, 360, 650, 220, ["AXI4-Lite", "CSR"], 7, False, "555555"))
    c.append(shape(2250, 220, 1900, 760, ["Command Processor (CP)", "CSR file / launch FSM", "I$ preload engine"], GREEN, 8, True))
    c.append(shape(2250, 1150, 1900, 620, ["I$  1 KB", "256 x 32-bit, 2 read ports"], GREEN, 8, True))
    c.append(line(3200, 980, 3200, 1150, arrow=True))
    c.append(line(4150, 600, 4550, 600))
    c.append(label(4150, 360, 420, 200, ["start"], 7, False, "555555"))

    # WGP boundary
    c.append(shape(4450, 180, 5000, 5450, ["WGP  /  1 CU"], GREY, 9, True, dash=True))
    c.append(label(4560, 220, 1100, 220, ["WGP boundary"], 7, False, "666666"))

    # SIMD and compute blocks
    c.append(shape(4650, 600, 1550, 760, ["SIMD32 #0", "SALU + SGPR", "VALU + VGPR", "EXEC mask / PC"], BLUE, 8, True))
    c.append(shape(6350, 600, 1550, 760, ["SIMD32 #1", "SALU + SGPR", "VALU + VGPR", "EXEC mask / PC"], BLUE, 8, True))
    c.append(shape(4650, 1650, 1550, 900, ["LDS  4 KB", "32 banks x 32 rows", "2 lane ports", "linear + scalar ports"], ORANGE, 8, True))
    c.append(shape(6350, 1650, 1550, 900, ["WMMA  16x16x32", "MXFP4 E2M1", "512 MAC/cycle", "int32 C"], PURPLE, 8, True))
    c.append(shape(4650, 2850, 1550, 650, ["TDM", "1-D global -> LDS", "128 B blocks"], GREEN, 8, True))
    c.append(shape(6350, 2850, 700, 700, ["SFU", "exp2", "rcp"], YELLOW, 8, True))
    c.append(shape(7150, 2850, 750, 700, ["Softmax", "engine", "4 passes"], YELLOW, 8, True))
    c.append(shape(4650, 3850, 3200, 560, ["LDS / unit arbitration", "WMMA > TDM > softmax > lane ports"], GREY, 8, True))
    c.append(shape(4650, 4700, 1550, 500, ["AXI4 master", "128-bit, INCR8"], GREEN, 8, True))

    # arrows inside WGP
    c.append(line(5400, 1360, 5400, 1650))
    c.append(line(7000, 1360, 7000, 1650))
    c.append(line(6200, 2100, 6350, 2100, arrow=False))
    c.append(line(6350, 2100, 6200, 2100))
    c.append(line(5400, 2550, 5400, 2850))
    c.append(line(6200, 2550, 6700, 2850))
    c.append(line(5400, 3500, 5400, 3850))
    c.append(line(7000, 3550, 7000, 3850))
    c.append(line(6200, 4130, 6200, 4700))
    c.append(label(6250, 4300, 600, 200, ["mem_if"], 7, False, "555555"))

    # memory side
    c.append(shape(8000, 4700, 1300, 500, ["Global", "memory"], RED, 8, True))
    c.append(line(6200, 4950, 8000, 4950))
    c.append(label(6900, 4700, 900, 200, ["AXI4 128-bit"], 7, False, "555555"))
    c.append(label(90, 5300, 1900, 240, ["Clock / reset: clk = 100 MHz, rst_n active-low synchronous"], 7, False, "555555"))
    return vgroup(c, 480, 350, 9600, 7000, "fig_top")


def fig_wgp():
    c = []
    c.append(shape(120, 180, 9360, 6400, ["WGP  /  1 CU  /  2 x SIMD32"], GREY, 9, True, dash=True))
    c.append(label(180, 210, 1100, 220, ["WGP"], 8, True, "666666"))

    # SIMD 0
    c.append(shape(300, 520, 2200, 2200, ["SIMD32 #0"], BLUE, 9, True))
    c.append(shape(430, 720, 900, 560, ["SALU", "32 SGPR"], BLUE, 8, True))
    c.append(shape(1430, 720, 900, 560, ["Control", "PC / EXEC"], BLUE, 8, True))
    c.append(shape(430, 1450, 900, 650, ["VALU", "32 lanes"], GREEN, 8, True))
    c.append(shape(1430, 1450, 900, 650, ["VGPR", "16/lane"], GREEN, 8, True))
    c.append(shape(430, 2280, 1900, 300, ["lane LDS port / global port"], ORANGE, 7, True))

    # SIMD 1
    c.append(shape(2800, 520, 2200, 2200, ["SIMD32 #1"], BLUE, 9, True))
    c.append(shape(2930, 720, 900, 560, ["SALU", "32 SGPR"], BLUE, 8, True))
    c.append(shape(3930, 720, 900, 560, ["Control", "PC / EXEC"], BLUE, 8, True))
    c.append(shape(2930, 1450, 900, 650, ["VALU", "32 lanes"], GREEN, 8, True))
    c.append(shape(3930, 1450, 900, 650, ["VGPR", "16/lane"], GREEN, 8, True))
    c.append(shape(2930, 2280, 1900, 300, ["lane LDS port / global port"], ORANGE, 7, True))

    # right side units
    c.append(shape(5550, 520, 1700, 1150, ["WMMA", "16x16x32 MXFP4", "512 MAC/cycle"], PURPLE, 8, True))
    c.append(shape(5550, 1800, 1700, 600, ["TDM", "global -> LDS"], GREEN, 8, True))
    c.append(shape(7550, 520, 1650, 900, ["LDS  4 KB", "32 banks x 32 rows"], ORANGE, 8, True))
    c.append(shape(7550, 1600, 750, 700, ["SFU", "exp2 / rcp"], YELLOW, 8, True))
    c.append(shape(8400, 1600, 800, 700, ["Softmax", "engine"], YELLOW, 8, True))
    c.append(shape(5550, 2700, 3650, 500, ["LDS arbiter: 2 lane + linear + scalar"], GREY, 8, True))
    c.append(shape(5550, 3600, 1700, 500, ["AXI4 master", "128-bit"], GREEN, 8, True))
    c.append(shape(7800, 3600, 1400, 500, ["Global", "memory"], RED, 8, True))

    # arrows
    c.append(line(5250, 1550, 5550, 1550))
    c.append(line(7250, 1100, 7550, 1100))
    c.append(line(7250, 2100, 7550, 2100))
    c.append(line(8375, 1250, 8375, 1600))
    c.append(line(8050, 2310, 8050, 2700))
    c.append(line(7250, 2950, 7250, 3600))
    c.append(label(6930, 3000, 700, 200, ["mem_if"], 7, False, "555555"))
    c.append(line(7250, 3850, 7800, 3850))
    c.append(label(7300, 3650, 500, 200, ["AXI4"], 7, False, "555555"))
    c.append(line(5250, 2050, 5550, 2050, dash=True, arrow=False))
    c.append(label(5280, 2100, 300, 200, ["desc"], 6.5, False, "555555"))
    return vgroup(c, 480, 355, 9600, 6800, "fig_wgp")


def fig_wmma():
    c = []
    c.append(shape(250, 500, 2400, 1350, ["A tile", "16 rows x 32 FP4", "64 words = 16 x 32 nibbles"], ORANGE, 8, True))
    c.append(shape(250, 2450, 2400, 1350, ["B tile", "32 rows x 16 FP4", "64 words = 32 x 16 nibbles"], ORANGE, 8, True))
    c.append(shape(3300, 800, 2500, 2450, ["MAC array", "32 K-slices", "16 x 16 outputs", "512 FP4 MAC / cycle"], PURPLE, 9, True))
    c.append(shape(6400, 1250, 2200, 1250, ["C tile", "16 x 16 int32", "256 words"], GREEN, 8, True))
    c.append(shape(3300, 3900, 5300, 750, ["LDS packing: two FP4 nibbles per byte, low nibble first; C is 32-bit int32"], GREY, 8, True))
    c.append(line(2650, 1150, 3300, 1500))
    c.append(line(2650, 3100, 3300, 2750))
    c.append(line(5800, 2000, 6400, 1900))
    c.append(label(5850, 2050, 500, 200, ["int32"], 7, False, "555555"))
    c.append(label(2400, 4000, 850, 200, ["LDS"], 7, False, "555555"))
    # cycle timeline
    c.append(shape(250, 5000, 1800, 500, ["cycle 0..7", "load A/B"], BLUE, 7, True))
    c.append(shape(2200, 5000, 1800, 500, ["cycle 7..23", "compute"], PURPLE, 7, True))
    c.append(shape(4150, 5000, 1800, 500, ["cycle 23..31", "store C"], GREEN, 7, True))
    c.append(line(2050, 5250, 2200, 5250))
    c.append(line(4000, 5250, 4150, 5250))
    return vgroup(c, 480, 340, 9000, 6200, "fig_wmma")


def fig_mem():
    c = []
    c.append(shape(200, 400, 1700, 650, ["Global memory", "linear 32-bit words"], RED, 8, True))
    c.append(shape(2350, 400, 1600, 650, ["TDM", "1-D copy", "128 B / block"], GREEN, 8, True))
    c.append(shape(4400, 400, 1700, 900, ["LDS  4 KB", "32 banks x 32 rows"], ORANGE, 8, True))
    c.append(shape(6600, 400, 1800, 650, ["WMMA", "16x16x32"], PURPLE, 8, True))
    c.append(shape(6600, 1550, 1800, 650, ["SIMD32", "lane LDS port"], BLUE, 8, True))
    c.append(shape(4400, 1900, 1700, 800, ["SFU / Softmax", "row-wise"], YELLOW, 8, True))
    c.append(shape(2350, 3200, 1600, 650, ["AXI4 master", "128-bit INCR8"], GREEN, 8, True))
    c.append(shape(200, 3200, 1700, 650, ["Host", "AXI4-Lite CSR"], BLUE, 8, True))
    c.append(line(1900, 725, 2350, 725))
    c.append(line(3950, 725, 4400, 725))
    c.append(line(6100, 850, 6600, 725))
    c.append(line(6100, 2200, 6600, 1875))
    c.append(line(6100, 2100, 6100, 2250, arrow=False))
    c.append(line(5250, 1300, 5250, 1900))
    c.append(line(4400, 2300, 3950, 2300))
    c.append(line(3950, 2300, 3950, 3200))
    c.append(label(3980, 2700, 500, 200, ["AXI4"], 7, False, "555555"))
    c.append(line(2000, 3525, 2350, 3525))
    c.append(label(150, 1300, 1800, 220, ["AXI4 master is shared by CP, TDM and SIMD"], 7, False, "555555"))
    c.append(label(4400, 2900, 1700, 300, ["address map: 0x1000 A, 0x2000 B, 0x3000 C"], 7, False, "555555"))
    return vgroup(c, 480, 330, 9000, 6200, "fig_mem")


def fig_sw():
    c = []
    c.append(shape(300, 300, 2600, 700, ["HIP application", "GEMM / Softmax / attention"], BLUE, 8, True))
    c.append(shape(300, 1300, 2600, 700, ["HIP runtime shim", "hipMalloc / Memcpy / Launch"], GREEN, 8, True))
    c.append(shape(300, 2300, 2600, 700, ["HSA API shim", "agents / signals / queues"], ORANGE, 8, True))
    c.append(shape(300, 3300, 2600, 900, ["M1 runtime", "functional / cycle model"], PURPLE, 8, True))
    c.append(shape(5200, 300, 2600, 900, ["M1 kernels", "GEMM  MXFP4", "Softmax  FP16", "FlashAttention"], ORANGE, 8, True))
    c.append(shape(5200, 1600, 2600, 700, ["ROCm libraries", "hipBLASLt / rocBLAS / MIOpen", "NOT native"], RED, 8, True, dash=True))
    c.append(shape(5200, 2700, 2600, 700, ["gfx1250 binaries", "ELF / HSACO / ROCr ABI", "NOT supported"], RED, 8, True, dash=True))
    c.append(line(1600, 1000, 1600, 1300))
    c.append(line(1600, 2000, 1600, 2300))
    c.append(line(1600, 3000, 1600, 3300))
    c.append(line(2900, 3650, 5200, 3650))
    c.append(line(5200, 3650, 5200, 750))
    c.append(label(3300, 3400, 700, 200, ["dispatch"], 7, False, "555555"))
    c.append(label(300, 4300, 8000, 300, ["Source/API compatibility only: no gfx1250 machine code, no ROCr ABI, no native ROCm libraries."], 7, False, "555555"))
    return vgroup(c, 480, 300, 8500, 5400, "fig_sw")


def fig_ops():
    c = []
    # GEMM row
    y = 300
    c.append(label(200, y, 1500, 220, ["GEMM  64x64x64 MXFP4"], 8, True))
    for i, (txt, pal) in enumerate([
        ("global A/B", RED), ("TDM", GREEN), ("LDS", ORANGE), ("WMMA 16x16x32", PURPLE), ("C int32", GREEN)
    ]):
        c.append(shape(200 + i * 1750, y + 300, 1450, 650, [txt], pal, 8, True))
        if i < 4:
            c.append(line(1650 + i * 1750, y + 625, 1950 + i * 1750, y + 625))
    # Softmax row
    y = 2000
    c.append(label(200, y, 2200, 220, ["Softmax  32 x Q4.12"], 8, True))
    for i, (txt, pal) in enumerate([
        ("row max", BLUE), ("exp2 (SFU)", YELLOW), ("sum", BLUE), ("rcp (SFU)", YELLOW), ("normalize", GREEN)
    ]):
        c.append(shape(200 + i * 1750, y + 300, 1450, 650, [txt], pal, 8, True))
        if i < 4:
            c.append(line(1650 + i * 1750, y + 625, 1950 + i * 1750, y + 625))
    # attention row
    y = 3700
    c.append(label(200, y, 2600, 220, ["FlashAttention  seq=32, dim=16, causal"], 8, True))
    for i, (txt, pal) in enumerate([
        ("Q / K", RED), ("QK^T", PURPLE), ("softmax", YELLOW), ("PV", PURPLE), ("O", GREEN)
    ]):
        c.append(shape(200 + i * 1750, y + 300, 1450, 650, [txt], pal, 8, True))
        if i < 4:
            c.append(line(1650 + i * 1750, y + 625, 1950 + i * 1750, y + 625))
    return vgroup(c, 480, 350, 9500, 5200, "fig_ops")


# ---------------------------------------------------------------------------
# Main document
# ---------------------------------------------------------------------------
def main():
    doc = Document()
    sec = doc.sections[0]
    sec.page_width = Cm(21.0)
    sec.page_height = Cm(29.7)
    sec.top_margin = Cm(1.8)
    sec.bottom_margin = Cm(1.8)
    sec.left_margin = Cm(1.9)
    sec.right_margin = Cm(1.9)
    style_document(doc)

    # header / footer
    hp = sec.header.paragraphs[0]
    hp.text = "CDNA5-M1  |  AI-only compute slice architecture"
    hp.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    for r in hp.runs:
        r.font.size = Pt(8)
        r.font.color.rgb = RGBColor(0x66, 0x66, 0x66)
    fp = sec.footer.paragraphs[0]
    fp.alignment = WD_ALIGN_PARAGRAPH.CENTER
    fp.add_run("CDNA5-M1 architecture  ·  page ").font.size = Pt(8)
    add_page_number(fp)

    # ---------------------------------------------------------------- cover
    doc.add_paragraph("").paragraph_format.space_after = Pt(40)
    t = doc.add_paragraph(style="Title")
    t.alignment = WD_ALIGN_PARAGRAPH.CENTER
    t.add_run("CDNA5-M1")
    st = doc.add_paragraph(style="Subtitle")
    st.alignment = WD_ALIGN_PARAGRAPH.CENTER
    st.add_run("AI-only CDNA5-derived 0.1 TFLOP/s MXFP4 compute slice\n架構文檔 (Architecture Document)")
    doc.add_paragraph("").paragraph_format.space_after = Pt(30)

    add_table(doc, ["項目", "內容"], [
        ["文件版本", "1.0 (2026-11-08)"],
        ["設計名稱", "CDNA5-M1"],
        ["設計類型", "AI-only 加速器；CDNA5 運算模型之 1 WGP / 1 CU 縮放切片"],
        ["製程 / PDK", "SkyWater Sky130A, sky130_fd_sc_hd, tt_025C_1v80, 1.8 V"],
        ["目標時脈", "100 MHz，單一時脈域"],
        ["峰值算力", "102.4 GFLOP/s (MXFP4, 512 MAC/cycle)"],
        ["主要介面", "AXI4-Lite host CSR; AXI4 128-bit global memory"],
        ["交付狀態", "RTL + full-chip functional verification；backend P&R 尚未 signoff"],
        ["圖形功能", "無 graphics/video/display/raster/texture/codec（全部移除）"],
        ["文件狀態", "設計基線；所有數字以 RTL/model 實測為準"],
    ], widths=[4.0, 12.5], font_size=9)

    doc.add_paragraph("")
    note = doc.add_paragraph()
    note.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = note.add_run("本文件中的所有架構圖均為 Word 原生 VML 群組（不是截圖）。\n"
                     "在 Word 中點選圖形即可編輯文字、移動區塊、改變顏色或解除群組。")
    r.italic = True
    r.font.size = Pt(9)
    r.font.color.rgb = RGBColor(0x55, 0x55, 0x55)

    doc.add_page_break()
    doc.add_heading("文件控制與修訂", level=1)
    add_table(doc, ["版本", "日期", "修訂內容", "作者"], [
        ["1.0", "2026-11-08", "初版：AI-only scope、RTL 架構、full-chip softmax/GEMM、ROCm shim、量測與限制", "CDNA5-M1 project"],
    ], widths=[2.0, 3.0, 9.0, 3.0], font_size=9)
    doc.add_heading("閱讀說明", level=2)
    for s in [
        "本文件的 normative 架構來源是 spec/ 與 rtl/；若文件與 RTL 衝突，以 RTL 為行為依據、以 spec/AI_SCOPE.md 為 scope 依據。",
        "標記「量測」的數字來自 iverilog RTL 模擬或 sim/ 的 cycle model；標記「估計」的數字是分析值，不是 Silicon 數據。",
        "圖形使用 Word VML 群組，可直接編輯；文字方塊中的英文是 block/訊號名稱，中文是說明。",
    ]:
        doc.add_paragraph(s, style="List Bullet")

    doc.add_heading("目錄", level=1)
    add_toc(doc)
    doc.add_page_break()

    # ---------------------------------------------------------------- 1
    doc.add_heading("1. 文件目的與範圍", level=1)
    doc.add_paragraph(
        "本文描述 CDNA5-M1 的完整架構：從 AI-only 設計範圍、頂層介面、WGP/CU/SIMD "
        "微架構、LDS/TDM 記憶體子系統、16x16x32 MXFP4 矩陣核心、SFU/Softmax 引擎、"
        "指令集與程式設計模型，到 full-chip 驗證、ROCm/HIP/HSA 兼容層與後端狀態。"
    )
    doc.add_paragraph(
        "CDNA5-M1 不是 AMD gfx1250 的 binary-compatible 實作，也不是完整 CDNA5 WGP。"
        "它保留 CDNA5 的執行模型（wave32、EXEC mask、SGPR/VGPR split、SALU/VALU split、"
        "LDS、WGP-level matrix core、TDM），並以 1 CU、2x SIMD32、4 KB LDS、1 KB I$ 的"
        "規模，在 Sky130 上達到 0.1 TFLOP/s 等級的 MXFP4 峰值。"
    )

    doc.add_heading("2. 設計目標與非目標", level=1)
    doc.add_heading("2.1 設計目標", level=2)
    for s in [
        "AI-only：只保留 GEMM、Softmax、FlashAttention 等 AI 算子所需的資料通路與控制。",
        "0.1 TFLOP/s 峰值：16x16x32 MXFP4 WMMA，512 MAC/cycle，100 MHz。",
        "可合成的 Verilog-2005：單一時脈、active-low synchronous reset、無 latch/tristate。",
        "以 LDS 為中心、cacheless：TDM 將 global tile 搬入 LDS，矩陣核心與 SIMD 從 LDS 取用。",
        "可驗證：WMMA/Softmax/GEMM 有 full-chip RTL test；運算子有 functional/cycle model。",
        "可軟體映射：提供 HIP/HSA source/API shim，讓既有 HIP 原始碼可以連到 M1 執行環境。",
    ]:
        doc.add_paragraph(s, style="List Bullet")

    doc.add_heading("2.2 明確非目標 / 已移除", level=2)
    doc.add_paragraph(
        "所有 graphics、video、display、raster、texture、JPEG/HEVC/AV1 codec、ray tracing、"
        "audio、GPUVM/MMU 與圖形記憶體格式皆不在本晶片中。完整移除表與 enforcement 見 "
        "spec/AI_SCOPE.md。"
    )
    add_table(doc, ["移除類別", "CDNA5 對應", "M1 處置"], [
        ["Graphics command / draw", "MEC/ME, ring, context", "移除；CP 只做 launch + I$ preload"],
        ["Raster / ROP / depth", "PA/SC/DB/CB", "移除；無 render target / framebuffer"],
        ["Texture / sampler", "TA/TD/TCP", "移除；LDS 是 scratchpad，不是 texture cache"],
        ["Display / PHY", "DCN, DP/HDMI", "移除；無 pixel clock / CRTC / plane"],
        ["Video codec", "VCN/UVD (JPEG/AVC/HEVC/VP9/AV1)", "全部移除；無 entropy decode / MC / SAO"],
        ["Ray tracing", "RT core / BVH", "移除；無 BVH / ray-box / ray-tri"],
        ["GPUVM / MMU", "GPUVM, page tables", "移除；單一 flat 32-bit address space"],
        ["Graphics formats", "tile swizzle / DCC", "移除；linear little-endian words"],
    ], widths=[4.0, 5.5, 8.0], font_size=8.5)

    doc.add_heading("3. 系統總覽", level=1)
    doc.add_paragraph(
        "圖 1 是晶片頂層。Host 透過 AXI4-Lite 寫 CSR，Command Processor 先將 1 KB kernel "
        "image 從 global memory 預載到 I$，再啟動 WGP。WGP 內兩個 SIMD32 共用 4 KB LDS、"
        "一個 WMMA 矩陣核心、一個 1-D TDM、SFU 與 softmax engine。Global memory 經由 "
        "128-bit AXI4 master 存取。"
    )
    figure(doc, fig_top(), "圖 1. CDNA5-M1 頂層架構（Word 可編輯群組）")
    doc.add_paragraph(
        "設計上刻意把 LDS 放在中心：TDM 將 A/B tile 搬入 LDS，WMMA 從 LDS 讀取 packed "
        "MXFP4 並把 int32 C 寫回 LDS，SIMD 再以 lane port 讀取 C 或做 epilogue。"
        "這個資料流避免了 cache 與不確定 latency，適合 bring-up 與 static schedule。"
    )

    doc.add_heading("4. 頂層區塊與介面", level=1)
    doc.add_heading("4.1 Host / AXI4-Lite CSR", level=2)
    doc.add_paragraph(
        "Host 端只透過 32-bit AXI4-Lite 存取 CSR。CSR 視窗為 4 KB（addr[7:0] decode），"
        "未實作的 offset 讀回 0、寫入忽略。Host 的 launch sequence 是：寫 KERNEL_PC、"
        "ARG_PTR、GRID_X、WG_SIZE、IRQ_EN，再寫 CONTROL.START=1；之後輪詢 STATUS 或等 irq。"
    )
    doc.add_heading("4.2 Command Processor (CP)", level=2)
    doc.add_paragraph(
        "CP 是固定功能的 launch FSM，不是圖形 command processor。它負責：接收 CSR 寫入、"
        "在 START 時以 8 個 128 B AXI burst 將 256-word kernel image 載入 I$、發出 "
        "wgp_start、维护 STATUS.BUSY/DONE/ERROR 與 cycle counter、在完成時assert irq。"
    )
    doc.add_heading("4.3 WGP", level=2)
    doc.add_paragraph(
        "WGP 是 M1 的運算邊界：1 CU、2x SIMD32、4 KB LDS、1 KB I$、1 個 WMMA、1 個 TDM、"
        "SFU 與 softmax engine。兩個 SIMD 共用 I$ 的兩個 read port，透過 LDS 的兩個 lane "
        "port、linear port 與 scalar port 存取資料。"
    )
    doc.add_heading("4.4 AXI4 global memory", level=2)
    doc.add_paragraph(
        "128-bit AXI4 master，INCR8 傳輸（128 B），一次一個 outstanding。CP 的 I$ preload、"
        "TDM 的 tile 搬運與 SIMD 的 V_MEM_LD/ST 都經過 top-level arbiter；TDM 取得 AXI "
        "時直接寫 LDS，SIMD 則取得 128 B block 到 VGPR。"
    )
    doc.add_heading("4.5 Clock / reset / power", level=2)
    doc.add_paragraph(
        "單一 clk，nominal 100 MHz；rst_n 為 active-low synchronous reset，至少維持 2 個 "
        "clock。所有暫存器都是 posedge clk；沒有非同步 reset、沒有 latch、沒有 tri-state、"
        "沒有 clock gating。Sky130 signoff corner 為 tt_025C_1v80、1.8 V、25 °C。"
    )

    doc.add_heading("5. 運算核心：WGP / CU / SIMD32", level=1)
    doc.add_paragraph(
        "圖 2 展開 WGP。每個 SIMD32 有獨立的 SALU/SGPR、VALU/VGPR、PC/EXEC 與 lane LDS "
        "port；兩個 SIMD 共用 WMMA、TDM、LDS 與 SFU/softmax。"
    )
    figure(doc, fig_wgp(), "圖 2. WGP / CU / SIMD32 內部架構（Word 可編輯群組）")
    doc.add_heading("5.1 執行模型", level=2)
    for s in [
        "Wave32：一個 wave 有 32 個 work-item，一個 PC；SIMD 一次執行一個 wave。",
        "EXEC mask：32-bit；inactive lane 不寫 VGPR、不產生 side effect。",
        "SALU/SGPR：32 個 scalar register，處理純量運算、branch、descriptor 與 CSR 讀取。",
        "VALU/VGPR：每個 lane 16 個 VGPR；支援 integer/bitwise、dot4 INT8、dot8 MXFP4。",
        "每個 SIMD 有 32-lane LDS port；lane address 必須 conflict-free，否則 wave error。",
        "SIMD 以 descriptor 把 WMMA/TDM/softmax 工作交給 WGP 單元，完成後回報 done。",
    ]:
        doc.add_paragraph(s, style="List Bullet")
    doc.add_heading("5.2 指令流", level=2)
    doc.add_paragraph(
        "SIMD FSM 為 IDLE -> FETCH -> FETCH_W -> DEC -> EXEC；記憶體/WMMA/TDM/softmax "
        "指令會進入各自的 WAIT state。因為 fetch+decode 需要兩個 cycle，back-to-back "
        "dependent ALU 指令不需要 bypass network。S_ENDPGM 結束 wave，WGP 在最後一個 "
        "wave 完成後拉高 done。"
    )

    doc.add_heading("6. 記憶體子系統：LDS / TDM / global", level=1)
    doc.add_paragraph(
        "圖 3 描述 LDS 與 global 的資料流。LDS 是 4 KB scratchpad：32 banks x 32 rows x "
        "32-bit。word index w = byte_addr[11:2]；bank = w[4:0]；row = w[9:5]。"
    )
    figure(doc, fig_mem(), "圖 3. LDS / TDM / AXI4 資料流（Word 可編輯群組）")
    doc.add_heading("6.1 LDS ports", level=2)
    add_table(doc, ["Port", "寬度", "用途", "仲裁"], [
        ["lane port 0", "32 x 32-bit", "SIMD0 的 V_LDS_LD/ST（per-lane address）", "conflict-free；與 linear/scalar 共用陣列"],
        ["lane port 1", "32 x 32-bit", "SIMD1 的 V_LDS_LD/ST", "conflict-free；與 linear/scalar 共用陣列"],
        ["linear port", "32 x 32-bit", "WMMA / TDM 的 row 存取", "WMMA 優先，TDM 次之"],
        ["scalar port", "32-bit", "softmax engine 的單字讀寫", "softmax 持有時使用"],
    ], widths=[3.2, 3.2, 7.8, 4.0], font_size=8.5)
    doc.add_heading("6.2 TDM", level=2)
    doc.add_paragraph(
        "TDM 是 1-D contiguous copy：S_TDM_COPY 的 descriptor 為 s[dst]=global byte address、"
        "s[dst+1]=LDS word address、s[dst+2]=word count。它以 128 B block 搬運，將 global "
        "tile 寫入 LDS；M1 不做 2-D/5-D descriptor、不做 transpose、不做 multicast。"
    )
    doc.add_heading("6.3 Global address map（bring-up）", level=2)
    add_table(doc, ["位址", "大小", "內容", "用途"], [
        ["0x0000_0000", "1 KB", "kernel image (256 words)", "CP preload 到 I$"],
        ["0x0000_1000", "128 B", "A[0..31] int32", "vecadd / softmax logits"],
        ["0x0000_2000", "128 B", "B[0..31] int32", "vecadd"],
        ["0x0000_3000", "128 B", "C[0..31] int32", "vecadd / softmax output"],
        ["0x0000_4000", "256 B", "A: 16x32 MXFP4", "GEMM tile"],
        ["0x0000_4100", "256 B", "B: 32x16 MXFP4", "GEMM tile"],
        ["0x0000_5000", "1 KB", "C: 16x16 int32", "GEMM tile output"],
    ], widths=[3.2, 2.2, 7.0, 5.5], font_size=8.5)

    doc.add_heading("7. 矩陣核心：WMMA 16x16x32 MXFP4", level=1)
    doc.add_paragraph(
        "WMMA 是 0.1 TFLOP/s 的來源。每個 operation 計算 C[16][16] += A[16][32] x "
        "B[32][16]；A/B 是 MXFP4 E2M1 nibbles，C 是 int32。A 與 B 各 64 words（512 "
        "nibbles），C 是 256 words。"
    )
    figure(doc, fig_wmma(), "圖 4. WMMA 16x16x32 資料通路與週期（Word 可編輯群組）")
    doc.add_heading("7.1 數值格式", level=2)
    doc.add_paragraph(
        "MXFP4 E2M1 的 magnitude 為 {0, 0.5, 1, 1.5, 2, 3, 4, 6}，RTL 以 ×2 的整數 "
        "{0,1,2,3,4,6,8,12} 解碼，累加器為 int32；軟體在 epilogue 套用 E8M0 block scale。"
        "這個「整數 decodes + int32 accumulate」讓每個 tile 的結果是 exact、可 bit-compare，"
        "也讓 C 的儲存不需要浮點 ALU。"
    )
    doc.add_heading("7.2 吞吐", level=2)
    doc.add_paragraph(
        "WMMA 以 16 cycles 完成一個 16x16x32 operation：512 MAC/cycle x 2 FLOP/MAC x "
        "100 MHz = 102.4 GFLOP/s。RTL 的 full-chip tile test 量到 256 cycles（含 TDM、"
        "I$、store），這是 latency/整合數字，不是峰值吞吐。"
    )
    doc.add_heading("7.3 與 LDS 的關係", level=2)
    doc.add_paragraph(
        "A/B 必須以 packed nibble 形式存在 LDS；WMMA 使用 linear port 讀取，並將 C 以 "
        "256 個 int32 寫回 LDS。這個設計讓 matrix core 不需要 register file 級的 operand "
        "頻寬，代價是 LDS 與 TDM 的排程必須配合。"
    )

    doc.add_heading("8. SFU 與 Softmax 引擎", level=1)
    doc.add_paragraph(
        "Softmax 是 full-chip 已驗證的 AI 算子。它由 serialized SFU 與 LDS softmax engine "
        "組成，透過 S_SOFTMAX 指令由 SIMD 發動。"
    )
    doc.add_heading("8.1 SFU", level=2)
    add_table(doc, ["項目", "實作"], [
        ["運算", "exp2 (Q4.12 signed -> Q0.12 unsigned), rcp (Q1.15 unsigned)"],
        ["精度", "exp2 max abs 3.53e-4；rcp max rel 2.51e-4（窮舉測試）"],
        ["latency", "4 cycles，valid/ready handshake"],
        ["面積", "1,728 cells / 12,714.7 µm² (Sky130 HD)"],
        ["狀態", "IMPL block；由 softmax_engine 使用，尚未成為獨立 SIMD 指令"],
    ], widths=[3.0, 14.0], font_size=8.5)
    doc.add_heading("8.2 Softmax engine", level=2)
    doc.add_paragraph(
        "softmax_engine 在 LDS 上做四個 pass： (1) 找 row max； (2) 以 SFU 算 "
        "exp2(x-max)； (3) 累加 sum； (4) 以 serial restoring divider 算 2^24/sum，"
        "再 normalize 寫回。輸入 Q4.12、輸出 Q0.12；row sum 約 4096。"
    )
    add_table(doc, ["項目", "數值"], [
        ["row length", "2..64（偶數）；full-chip test 使用 32"],
        ["面積", "4,410 cells / 33,388.3 µm²；304 dfxtp"],
        ["divider", "25-cycle serial restoring divider（避免 combinational divider 的合成 timeout）"],
        ["full-chip latency", "940 cycles（TDM -> LDS -> softmax -> AXI）"],
    ], widths=[3.5, 13.5], font_size=8.5)
    doc.add_heading("8.3 S_SOFTMAX 指令", level=2)
    doc.add_paragraph(
        "S_SOFTMAX 的 descriptor 為 s[dst]=LDS base word、s[dst+1]=element count。SIMD "
        "在 S_DEC 發出 request，WGP 在 WMMA/TDM idle 時啟動 engine；完成後以 softmax_done "
        "回報。這是一個 WGP-level AI command，不是 lane-wise 指令。"
    )

    doc.add_heading("9. AI 算子與資料流", level=1)
    doc.add_paragraph(
        "圖 5 把三個 bring-up 算子放在同一張圖：GEMM 走 TDM/WMMA，Softmax 走 row engine，"
        "FlashAttention 由 QK^T、softmax、PV 三個階段組成。"
    )
    figure(doc, fig_ops(), "圖 5. GEMM / Softmax / FlashAttention 算子資料流（Word 可編輯群組）")
    doc.add_heading("9.1 GEMM", level=2)
    doc.add_paragraph(
        "GEMM 以 16x16x32 tile 為單位：A/B 由 TDM 搬入 LDS，WMMA 計算，C 留在 LDS，"
        "SIMD 以 V_LDS_LD 讀出並以 V_MEM_ST 寫回 global。64x64x64 的 model 結果是 exact "
        "int32、512 cycles、102.4 GFLOP/s；full-chip RTL tile 是 256 cycles。"
    )
    doc.add_heading("9.2 Softmax", level=2)
    doc.add_paragraph(
        "row-wise stable softmax：先減 max，再做 exp2、sum、rcp、normalize。"
        "model 的 8x128 FP16 結果 max error 1.716e-3；RTL 的 32xQ4.12 full-chip 結果"
        " row sum 4064、940 cycles。"
    )
    doc.add_heading("9.3 FlashAttention", level=2)
    doc.add_paragraph(
        "single-head、causal、seq=32、dim=16 的 model：QK^T -> softmax -> PV。"
        "model 結果 max error 1.004e-3。這是 functional/cycle model 的結果，"
        "不是 RTL；RTL 目前沒有 FP16 matrix path。"
    )

    doc.add_heading("10. 指令集與程式設計模型", level=1)
    doc.add_paragraph(
        "M1 使用固定 32-bit 編碼，opcode[31:26]；literal 形式多一個 32-bit word。"
        "這個編碼與 gfx1250 不相容，是 M1 自己的 ISA subset。"
    )
    code(doc, """
31      26 25 24    20 19    15 14    10 9      5 4       0
+---------+--+--------+--------+--------+--------+---------+
| opcode  |I |  dst   |  src0  |  src1  |  src2  |  flags  |
+---------+--+--------+--------+--------+--------+---------+
""")
    doc.add_heading("10.1 主要 scalar opcodes", level=2)
    add_table(doc, ["Opcode", "Mnemonic", "語意"], [
        ["0x00", "S_NOP", "no operation"],
        ["0x01", "S_MOV_B32", "sd = src / literal"],
        ["0x02-0x08", "S_ADD/SUB/AND/OR/XOR/SHL/SHR", "scalar ALU"],
        ["0x09", "S_CMP_LT_U32", "SCC = ss0 < ss1"],
        ["0x0A/0x0B", "S_CBRANCH_SCC / S_BRANCH", "signed 11-bit word offset"],
        ["0x0C", "S_ENDPGM", "wave complete"],
        ["0x0D/0x0E", "S_BARRIER / S_WAITCNT", "structural wait"],
        ["0x0F-0x13", "S_GET_WG_ID / SIZE / MOV_B64 / LDS_ADDR / CSR_READ", "launch/CSR helpers"],
        ["0x14", "S_TDM_COPY", "descriptor: global src, LDS dst, words"],
        ["0x15", "S_WMMA", "descriptor: A/B/C LDS words"],
        ["0x16/0x17", "S_GET_LANE_BASE / S_SET_EXEC", "lane base / EXEC"],
        ["0x18", "S_SOFTMAX", "descriptor: LDS base, length"],
    ], widths=[2.6, 4.2, 10.2], font_size=8.2)
    doc.add_heading("10.2 主要 vector opcodes", level=2)
    doc.add_paragraph(
        "0x20-0x2E 為 integer/bitwise、compare、dot4 INT8、dot8 MXFP4；0x30-0x33 為 "
        "LDS/global block load/store；0x38-0x3A 為 indexed LDS 與 read-first-lane。"
        "0x34-0x37 的 F16 向量運算在 v1 保留，尚未實作 RTL。"
    )
    doc.add_heading("10.3 CSR map", level=2)
    add_table(doc, ["Offset", "Name", "Access", "Description"], [
        ["0x00", "CONTROL", "RW", "bit0 START"],
        ["0x04", "STATUS", "RO", "bit0 BUSY, bit1 DONE, bit2 ERROR"],
        ["0x08", "KERNEL_PC", "RW", "global byte address of 1 KB image"],
        ["0x0C", "ARG_PTR", "RW", "arg pointer (s1)"],
        ["0x10", "GRID_X", "RW", "1..8 workgroups"],
        ["0x14/0x18", "GRID_Y/Z", "RW", "reserved; write 1"],
        ["0x1C", "WG_SIZE", "RW", "1..32 work-items"],
        ["0x20", "IRQ_EN", "RW", "bit0 completion irq"],
        ["0x24/0x28", "CYCLE_LO/HI", "RO", "64-bit cycle counter"],
        ["0x2C", "WAVE_DONE", "RO", "completed launches"],
        ["0x30", "ID", "RO", "0x4344_4E35 (\"CDN5\")"],
    ], widths=[2.3, 3.0, 3.0, 9.0], font_size=8.2)

    doc.add_heading("11. 驗證與量測", level=1)
    doc.add_paragraph(
        "以下全部是這個 repository 內可重跑的測試；指令在 Appendix C。"
        "「RTL」表示 iverilog 全芯片/模組模擬，「model」表示 sim/ 的 functional/cycle model。"
    )
    add_table(doc, ["項目", "層級", "結果"], [
        ["SFU exp2/rcp", "RTL", "PASS；exp2 3.53e-4, rcp 2.51e-4, 4 cycles"],
        ["Softmax engine", "RTL", "PASS；row sums 4064/4090/4036"],
        ["WGP softmax", "RTL", "PASS；one-hot 1393/87, sum 4090"],
        ["Full-chip softmax", "RTL", "PASS；TDM→LDS→S_SOFTMAX→AXI, 940 cycles, sum 4064"],
        ["Full-chip GEMM tile", "RTL", "PASS；16x16x32 MXFP4, 256 cycles"],
        ["GEMM 64x64x64", "model", "PASS；exact int32, 512 cycles, 102.4 GFLOP/s"],
        ["Softmax 8x128", "model", "PASS；max err 1.716e-3"],
        ["FlashAttention seq32 dim16", "model", "PASS；max err 1.004e-3"],
        ["HIP/HSA examples", "host", "5/5 PASS"],
        ["TDM P&R", "OpenROAD", "WNS/TNS 0.00 ns, 10.1 mW, 0 route DRC"],
        ["TDM KLayout DRC", "KLayout", "0 violations"],
        ["make preflight", "toolchain", "ok:true"],
    ], widths=[5.0, 3.0, 9.0], font_size=8.2)
    doc.add_heading("11.1 面積", level=2)
    add_table(doc, ["Block", "Cells", "Area (µm²)", "Flops", "備註"], [
        ["wmma", "126,245", "1,218,412.3", "—", "matrix core"],
        ["tdm", "4,476", "36,216.0", "1,093", "1-D mover"],
        ["axi_lite_slave", "397", "3,783.6", "—", "host CSR"],
        ["sfu", "1,728", "12,714.7", "145", "exp2/rcp"],
        ["softmax_engine", "4,410", "33,388.3", "304", "serial divider"],
    ], widths=[3.5, 2.3, 3.3, 2.2, 6.0], font_size=8.2)

    doc.add_heading("12. ROCm / HIP / HSA 兼容", level=1)
    doc.add_paragraph(
        "M1 提供 source/API-level 的 HIP 與 HSA shim，讓既有 HIP 程式的 host 端 API 可以"
        "編譯、連結，並將 kernel 對應到 M1 的 operator model。這不是 gfx1250 binary runtime。"
    )
    figure(doc, fig_sw(), "圖 6. ROCm / HIP / HSA 兼容層（Word 可編輯群組）")
    add_table(doc, ["層級", "M1 支援", "說明"], [
        ["HIP host API", "支援 subset", "hipMalloc/Memcpy/Memset/streams/events/Launch"],
        ["HIP kernel source", "支援受限 C++", "g++ 編譯；kernel 以 host 序列執行"],
        ["HSA API", "支援 subset", "agent/signal/queue/memory/dispatch"],
        ["M1 operators", "支援", "GEMM/Softmax/FlashAttention"],
        ["gfx1250 ELF/HSACO", "不支援", "無 AMDGPU code object loader"],
        ["ROCr ABI / AQL ring", "不支援", "沒有 ROCr runtime"],
        ["hipBLASLt/rocBLAS/MIOpen", "不支援原生", "只能做 operator 映射"],
    ], widths=[5.0, 4.0, 8.0], font_size=8.2)
    doc.add_paragraph(
        "五個可執行範例：hip_saxpy、hip_gemm_m1、hip_softmax_m1、"
        "hip_flash_attention_m1、hsa_demo；全部 PASS。詳細 non-claims 見 spec/ROCM_COMPAT.md。"
    )

    doc.add_heading("13. 後端狀態與限制", level=1)
    doc.add_paragraph(
        "這一節刻意列出未完成項目，避免把 functional PASS 誤認為 backend signoff。"
    )
    for s in [
        "WMMA flat P&R 尚未收斂：2,096 pins 與 1,024-bit LDS read/write bus 造成 detailed route violation（45%: 126,726；30%: 255,357→355,997）。",
        "WGP 全模組 synthesis 在 600 s 內未完成；serial divider 已移除 softmax 的合成瓶頸，但 WMMA 的展開讓 ABC 過大。",
        "TDM KLayout DRC 為 0；LVS 尚未完成（KLayout LVS 在 comparison 階段 OOM，netgen 尚未完成）。",
        "SFU 尚未成為獨立 SIMD 指令；目前由 softmax_engine 使用。",
        "FlashAttention 目前只有 model 結果；RTL 沒有 FP16 matrix path。",
        "ROCm 是 source/API shim，不是 gfx1250 binary compatibility。",
    ]:
        doc.add_paragraph(s, style="List Bullet")
    doc.add_paragraph(
        "要把 design 推進到可 signoff 的 GDS，優先處理 WMMA bus 切窄/SRAM macro 化、"
        "hierarchical synthesis 與 LVS。"
    )

    doc.add_heading("14. 檔案與重現", level=1)
    doc.add_heading("14.1 RTL 對照", level=2)
    add_table(doc, ["檔案", "模組", "職責"], [
        ["rtl/cdna5_m1_top.v", "cdna5_m1_top", "top boundary, AXI/CSR/arbiter"],
        ["rtl/command_processor.v", "command_processor", "CSR, launch FSM, I$ preload"],
        ["rtl/axi_lite_slave.v", "axi_lite_slave", "AXI4-Lite -> CSR"],
        ["rtl/axi_master.v", "axi_master", "128-bit AXI4 master"],
        ["rtl/wgp.v", "wgp", "1 CU, 2 SIMD, LDS/TDM/WMMA/SFU/softmax"],
        ["rtl/simd32.v", "simd32", "SALU/VALU/PC/EXEC, descriptor hand-off"],
        ["rtl/lds.v", "lds", "4 KB, 2 lane + linear + scalar ports"],
        ["rtl/wmma.v", "wmma", "16x16x32 MXFP4 -> int32"],
        ["rtl/tdm.v", "tdm", "1-D global -> LDS"],
        ["rtl/sfu.v", "sfu", "exp2/rcp, 4-cycle"],
        ["rtl/softmax_engine.v", "softmax_engine", "4-pass row softmax"],
    ], widths=[5.0, 4.0, 8.0], font_size=8.2)
    doc.add_heading("14.2 一鍵重現", level=2)
    code(doc, """
cd /workspace/菩提树/coresmith/designs/cdna5-m1
./scripts/check_all.sh
""")
    doc.add_paragraph(
        "check_all.sh 會跑 SFU、softmax engine、WGP softmax、full-chip softmax、"
        "full-chip GEMM tile、operator model 與 ROCm 5/5。"
    )
    doc.add_heading("14.3 相關文件", level=2)
    for s in [
        "spec/AI_SCOPE.md — AI-only scope 與 graphics 移除表",
        "spec/ROCM_COMPAT.md — HIP/HSA 兼容矩陣與 non-claims",
        "doc/OPERATORS.md — GEMM/Softmax/FlashAttention 合約與量測",
        "doc/BACKEND.md — P&R/DRC/LVS 狀態",
        "progress_logs/CURRENT_STATUS.md — 單一現況總表",
    ]:
        doc.add_paragraph(s, style="List Bullet")

    doc.add_heading("15. 詞彙表", level=1)
    add_table(doc, ["詞彙", "說明"], [
        ["WGP", "Work-Group Processor；CDNA5 的運算群組，M1 為 1 CU 版本"],
        ["CU", "Compute Unit；M1 有 1 CU、2 SIMD32"],
        ["SIMD32", "32-lane SIMD；一個 wave32"],
        ["EXEC", "32-bit lane mask；inactive lane 不寫回"],
        ["SGPR/VGPR", "scalar / vector general-purpose registers"],
        ["LDS", "Local Data Share；4 KB scratchpad"],
        ["WMMA", "wave matrix multiply-accumulate；M1 為 16x16x32 MXFP4"],
        ["MXFP4", "E2M1 4-bit floating point，block scale E8M0"],
        ["TDM", "Tensor Data Mover；M1 為 1-D contiguous copy"],
        ["SFU", "Special Function Unit；exp2/rcp"],
        ["HIP/HSA", "AMD ROCm 的 host API / runtime API"],
        ["I$", "1 KB instruction RAM，host preload"],
    ], widths=[3.5, 13.5], font_size=8.5)

    doc.add_heading("Appendix A. 量測輸出摘要", level=1)
    code(doc, """
PASS tb_top_softmax (full chip, 940 cycles, sum 4064)
PASS tb_wmma_top (16x16x32 MXFP4, 256 cycles)
PASS tb_wgp_softmax (one-hot first=1393 other=87 sum=4090)
PASS softmax_engine (row sums 4064/4090/4036)
PASS check_sfu (exp2 3.53e-4, rcp 2.51e-4)
GEMM 64x64x64 MXFP4: exact int32, 512 cycles, 102.40 GFLOP/s
Softmax 8x128: max err 1.716e-3, 3168 cycles
FlashAttention seq=32 dim=16: max err 1.004e-3, 3744 cycles
HIP/HSA: 5/5 PASS
""")
    doc.add_heading("Appendix B. 重要限制與 next steps", level=1)
    for s in [
        "WMMA 1,024-bit LDS bus 與 2,096 pins 是 flat P&R 的主要瓶頸；先切窄 bus 或使用 SRAM macro。",
        "WGP synthesis 需要 hierarchical flow 或較小的 WMMA 展開。",
        "LVS 需要 sequential netgen flow / 更乾淨的 CDL。",
        "若要做 FlashAttention RTL，必須新增 FP16/BF16 matrix datapath，或明確採用 FP4 attention 數值方案。",
        "ROCm 若要 binary compatibility，需獨立的 gfx1250 ISA/loader/ROCr 工程。",
    ]:
        doc.add_paragraph(s, style="List Bullet")

    doc.add_paragraph("")
    end = doc.add_paragraph()
    end.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = end.add_run("— End of document —")
    r.italic = True
    r.font.color.rgb = RGBColor(0x77, 0x77, 0x77)

    doc.save(OUT)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
