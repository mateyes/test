# -*- coding: utf-8 -*-
import re
from docx import Document
from docx.shared import Pt, RGBColor, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.oxml.ns import qn

TITLE = "3.5小时，把线穿进太空的“针眼”"
PARAS = [
    "11月25日清晨5时28分，酒泉问天阁，汤洪波、武毅和巴基斯坦航天员齐尚·阿里在《歌唱祖国》的旋律中领命出征。8时18分，长征二号F火箭托举神舟二十四号腾空而起；11时56分，飞船稳稳“吻”上天和核心舱前向端口。从点火到对接，只用了3个多小时。",
    "这速度有多难？空间站以每秒7.9公里飞行，约合时速2.8万公里。交会对接就像在万米高空穿针引线：空间站是针眼，飞船是那根线。过去要飞两天，2021年缩到6.5小时，如今3.5小时——飞船少绕一圈地球，在更近的“起跑线”出发，剩下的交给飞船自己算。每一次缩短，都是火箭入轨精度、飞船自主控制与地面测控同时进步的结果。",
    "更暖的是，乘组里坐着首位到访天宫的外籍航天员。2025年2月，中巴签署合作协议；阿里从初选、复选、定选一路闯关，来华与中国航天员同班训练，压哨拿到这张“太空船票”。在轨期间，他将完成中巴合作科学实验。",
    "有个冷知识：空间站90分钟绕地球一圈，航天员一天要看16次日出。而快速对接的意义，是把“随时能上、随时能回”从设想变成现实——一年前，神舟二十二号就曾用16天应急发射，为同伴重建回家路。这份应急底气，正是快速对接给的。",
    "从“追得上”到“追得快”，再到把舱门向世界打开：3.5小时是技术的速度，开门迎客是胸怀的宽度。下一次，会是谁来敲门？",
]

text = TITLE + "\n\n" + "\n\n".join(PARAS)
cjk = len(re.findall(r'[\u4e00-\u9fff]', text))
print("汉字数：", cjk, " 总字符：", len(text.replace("\n", "")))

# ---- TXT（UTF-8 BOM + CRLF，Windows 记事本友好）----
with open("/workspace/build_sz24/短文.txt", "w", encoding="utf-8-sig", newline="\r\n") as f:
    f.write(text + "\n")

# ---- DOCX ----
doc = Document()
sec = doc.sections[0]
sec.top_margin = Cm(2.6)
sec.bottom_margin = Cm(2.6)
sec.left_margin = Cm(3.0)
sec.right_margin = Cm(3.0)

normal = doc.styles["Normal"]
normal.font.name = "微软雅黑"
normal.font.size = Pt(12)
normal.element.rPr.rFonts.set(qn("w:eastAsia"), "微软雅黑")
normal.font.color.rgb = RGBColor(0x1A, 0x1A, 0x1A)

t = doc.add_paragraph()
t.alignment = WD_ALIGN_PARAGRAPH.CENTER
t.paragraph_format.space_after = Pt(18)
run = t.add_run(TITLE)
run.font.name = "微软雅黑"
run._element.rPr.rFonts.set(qn("w:eastAsia"), "微软雅黑")
run.font.size = Pt(20)
run.font.bold = True
run.font.color.rgb = RGBColor(0x14, 0x2A, 0x4C)

sub = doc.add_paragraph()
sub.alignment = WD_ALIGN_PARAGRAPH.CENTER
sub.paragraph_format.space_after = Pt(16)
srun = sub.add_run("—— 神舟二十四号 3.5 小时快速交会对接小记")
srun.font.name = "微软雅黑"
srun._element.rPr.rFonts.set(qn("w:eastAsia"), "微软雅黑")
srun.font.size = Pt(10.5)
srun.font.color.rgb = RGBColor(0x6B, 0x7A, 0x93)

for p in PARAS:
    para = doc.add_paragraph()
    para.paragraph_format.first_line_indent = Pt(24)
    para.paragraph_format.line_spacing = 1.75
    para.paragraph_format.space_after = Pt(6)
    r = para.add_run(p)
    r.font.name = "微软雅黑"
    r._element.rPr.rFonts.set(qn("w:eastAsia"), "微软雅黑")
    r.font.size = Pt(12)

doc.save("/workspace/build_sz24/短文.docx")
print("saved docx/txt")
