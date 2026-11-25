# -*- coding: utf-8 -*-
"""生成《3.5小时·太空穿针》竖版 9:16 大字号 PPT

三种模式：
  full  —— 矢量图形 + 文字（标准 pptx）
  bg    —— 只有图形、不含文字（用于渲染成背景图）
  final —— 背景图 + 文字（用于导出 Office 2003 的 .ppt）
"""
import os
import random
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE
from pptx.oxml.ns import qn
import copy

W, H = 7.5, 13.333
FONT = "Noto Sans CJK SC"

BG      = RGBColor(0x07, 0x0B, 0x1A)
BG2     = RGBColor(0x0D, 0x16, 0x30)
CARD    = RGBColor(0x10, 0x1B, 0x38)
CARD2   = RGBColor(0x14, 0x22, 0x44)
LINE    = RGBColor(0x27, 0x3B, 0x66)
WHITE   = RGBColor(0xF4, 0xF7, 0xFF)
GREY    = RGBColor(0x93, 0xA5, 0xC8)
DIM     = RGBColor(0x6E, 0x80, 0xA6)
ORANGE  = RGBColor(0xFF, 0x8A, 0x1F)
GOLD    = RGBColor(0xFF, 0xC2, 0x4B)
CYAN    = RGBColor(0x4F, 0xD1, 0xFF)

MODE = os.environ.get("DECK_MODE", "full")
BG_DIR = "/workspace/build_sz24/bg"
_slide_no = [0]


def add_bg_picture(slide, no):
    slide.shapes.add_picture(f"{BG_DIR}/{no:02d}.png", 0, 0, Inches(W), Inches(H))


def set_font(run, size, color, bold=False, name=FONT):
    f = run.font
    f.name = name
    f.size = Pt(size)
    f.bold = bold
    f.color.rgb = color
    rPr = run._r.get_or_add_rPr()
    ea = rPr.find(qn('a:ea'))
    if ea is None:
        ea = rPr.makeelement(qn('a:ea'), {})
        rPr.append(ea)
    ea.set('typeface', name)


def set_alpha(shape, opacity):
    """opacity: 0~1"""
    fill = shape.fill
    solid = fill.fore_color._xFill
    srgb = solid.find(qn('a:srgbClr'))
    for a in srgb.findall(qn('a:alpha')):
        srgb.remove(a)
    alpha = srgb.makeelement(qn('a:alpha'), {'val': str(int(opacity * 100000))})
    srgb.append(alpha)


def add_rect(slide, x, y, w, h, color, alpha=1.0, shape=MSO_SHAPE.RECTANGLE,
             radius=None, line=None, line_w=1.0):
    if MODE == "final":
        return None
    sp = slide.shapes.add_shape(shape, Inches(x), Inches(y), Inches(w), Inches(h))
    sp.shadow.inherit = False
    sp.fill.solid()
    sp.fill.fore_color.rgb = color
    if alpha < 1.0:
        set_alpha(sp, alpha)
    if line is None:
        sp.line.fill.background()
    else:
        sp.line.color.rgb = line
        sp.line.width = Pt(line_w)
    if radius is not None and shape == MSO_SHAPE.ROUNDED_RECTANGLE:
        sp.adjustments[0] = radius
    return sp


def add_text(slide, x, y, w, h, paras, align=PP_ALIGN.LEFT,
             anchor=MSO_ANCHOR.TOP, margin=0.0, line=1.3):
    """paras: list of dict(runs=[(text,size,color,bold)], space_before=, size=,color=,bold=)"""
    if MODE == "bg":
        return None
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = anchor
    tf.margin_left = tf.margin_right = Inches(margin)
    tf.margin_top = tf.margin_bottom = 0
    first = True
    for p in paras:
        para = tf.paragraphs[0] if first else tf.add_paragraph()
        first = False
        para.alignment = align
        para.line_spacing = line
        if p.get('space_before'):
            para.space_before = Pt(p['space_before'])
        runs = p.get('runs')
        if runs is None:
            runs = [(p['text'], p['size'], p['color'], p.get('bold', False))]
        for t, s, c, b in runs:
            r = para.add_run()
            r.text = t
            set_font(r, s, c, b)
    return tb


def ring(slide, x, y, w, h, color, alpha=0.22, line_w=0.75):
    if MODE == "final":
        return None
    sp = slide.shapes.add_shape(MSO_SHAPE.OVAL, Inches(x), Inches(y), Inches(w), Inches(h))
    sp.shadow.inherit = False
    sp.fill.background()
    sp.line.color.rgb = color
    sp.line.width = Pt(line_w)
    # 线条透明度
    ln = sp.line._get_or_add_ln()
    solid = ln.find(qn('a:solidFill'))
    srgb = solid.find(qn('a:srgbClr'))
    srgb.append(srgb.makeelement(qn('a:alpha'), {'val': str(int(alpha * 100000))}))
    return sp


def new_slide(prs, idx, total, kicker, title, accent=GOLD, subtitle=None):
    _slide_no[0] += 1
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    if MODE == "final":
        add_bg_picture(slide, _slide_no[0])
    add_rect(slide, 0, 0, W, H, BG)
    # 轨道弧线，增加空间感
    ring(slide, 4.6, -1.9, 5.6, 5.6, CYAN, 0.16, 0.75)
    ring(slide, -2.2, 9.6, 6.6, 6.6, ORANGE, 0.10, 0.75)
    # 星点
    rnd = random.Random(20261125 + idx)
    for _ in range(46):
        sx, sy = rnd.uniform(0.1, W - 0.15), rnd.uniform(0.3, H - 0.3)
        d = rnd.uniform(0.015, 0.045)
        add_rect(slide, sx, sy, d, d, WHITE, rnd.uniform(0.12, 0.45), MSO_SHAPE.OVAL)
    # 页眉
    add_text(slide, 0.72, 0.62, 5.0, 0.3,
             [{'runs': [(kicker, 10, GREY, False)]}])
    add_rect(slide, 0.72, 1.02, 0.62, 0.05, accent)
    add_text(slide, 0.7, 1.22, 6.2, 1.5,
             [{'runs': [(title, 34, WHITE, True)]}], line=1.22)
    if subtitle:
        add_text(slide, 0.72, 2.62, 6.1, 0.5,
                 [{'runs': [(subtitle, 15, CYAN, False)]}])
    # 页脚
    add_text(slide, 0.72, 12.55, 4.0, 0.3,
             [{'runs': [("神舟二十四号 · 2026.11.25", 10, DIM, False)]}])
    add_text(slide, 5.9, 12.55, 0.9, 0.3,
             [{'runs': [(f"{idx:02d} / {total:02d}", 10, DIM, False)]}],
             align=PP_ALIGN.RIGHT)
    return slide


def card(slide, x, y, w, h, num=None, num_color=ORANGE):
    sp = add_rect(slide, x, y, w, h, CARD, 1.0, MSO_SHAPE.ROUNDED_RECTANGLE,
                  radius=0.06, line=LINE, line_w=0.75)
    if num is not None:
        add_text(slide, x + 0.32, y + 0.26, 1.0, 0.55,
                 [{'runs': [(num, 26, num_color, True)]}])
    return sp


def build():
    prs = Presentation()
    prs.slide_width = Inches(W)
    prs.slide_height = Inches(H)
    TOTAL = 8

    # ============ 1 封面 ============
    _slide_no[0] += 1
    s = prs.slides.add_slide(prs.slide_layouts[6])
    if MODE == "final":
        add_bg_picture(s, 1)
    add_rect(s, 0, 0, W, H, BG)
    ring(s, 2.1, -2.6, 8.4, 8.4, CYAN, 0.18, 0.9)
    ring(s, 3.0, -1.7, 6.6, 6.6, CYAN, 0.10, 0.75)
    ring(s, -2.0, 9.9, 7.2, 7.2, ORANGE, 0.12, 0.75)
    rnd = random.Random(7)
    for _ in range(80):
        sx, sy = rnd.uniform(0.1, W - 0.15), rnd.uniform(0.2, H - 0.2)
        d = rnd.uniform(0.015, 0.05)
        add_rect(s, sx, sy, d, d, WHITE, rnd.uniform(0.1, 0.55), MSO_SHAPE.OVAL)
    # 地球
    add_rect(s, -2.55, 10.30, 12.6, 12.6, RGBColor(0x0C, 0x24, 0x4E), 1.0, MSO_SHAPE.OVAL,
             line=CYAN, line_w=1.25)
    add_rect(s, -2.95, 9.95, 13.4, 13.4, CYAN, 0.0, MSO_SHAPE.OVAL, line=CYAN, line_w=0.5)
    add_rect(s, -2.15, 10.70, 11.8, 11.8, CYAN, 0.0, MSO_SHAPE.OVAL, line=CYAN, line_w=0.5)

    add_text(s, 0.75, 1.30, 6.0, 0.35,
             [{'runs': [("今日热点 · 中国载人航天", 13, GOLD, True)]}])
    add_text(s, 0.72, 1.85, 6.2, 1.5,
             [{'runs': [("3.5小时", 74, WHITE, True)]}])
    add_text(s, 0.72, 3.30, 6.2, 1.5,
             [{'runs': [("太空穿针", 74, ORANGE, True)]}])
    add_text(s, 0.75, 5.52, 6.1, 2.2,
             [{'runs': [("神舟二十四号完成第 4 次", 22, WHITE, True)]},
              {'runs': [("3.5 小时自主快速交会对接", 22, WHITE, True)]},
              {'runs': [("天宫，也第一次迎来外籍航天员", 17, CYAN, False)], 'space_before': 14}],
             line=1.42)
    add_rect(s, 0.78, 8.05, 2.35, 1.02, ORANGE, 1.0, MSO_SHAPE.ROUNDED_RECTANGLE, radius=0.18)
    add_text(s, 0.78, 8.22, 2.35, 0.7,
             [{'runs': [("08:18 点火", 17, RGBColor(0x1A, 0x0B, 0x00), True)]}],
             align=PP_ALIGN.CENTER)
    add_rect(s, 3.35, 8.05, 2.35, 1.02, CARD2, 1.0, MSO_SHAPE.ROUNDED_RECTANGLE,
             radius=0.18, line=CYAN, line_w=1.0)
    add_text(s, 3.35, 8.22, 2.35, 0.7,
             [{'runs': [("11:56 对接", 17, CYAN, True)]}],
             align=PP_ALIGN.CENTER)
    add_text(s, 0.75, 9.42, 6.0, 0.35,
             [{'runs': [("2026年11月25日　酒泉卫星发射中心 → 中国空间站", 11, GREY, False)]}])

    # ============ 2 时间线 ============
    s = new_slide(prs, 2, TOTAL, "MISSION · 今天发生了什么", "一个上午，\n把三个人送上太空", ORANGE)
    items = [
        ("05:28", "问天阁出征", "汤洪波、武毅、齐尚·阿里领命出征", GOLD),
        ("08:18", "长征二号F点火", "“神箭”托举神舟二十四号腾空而起", ORANGE),
        ("08:28", "船箭分离入轨", "点火约10分钟后，发射任务圆满成功", CYAN),
        ("11:56", "对接天和核心舱", "前向端口，全程约3.5小时，形成三船三舱组合体", CYAN),
    ]
    y = 3.12
    add_rect(s, 1.62, y + 0.12, 0.025, 6.35, LINE)  # 竖线
    for i, (t, h1, h2, c) in enumerate(items):
        yy = y + i * 1.63
        add_rect(s, 1.47, yy + 0.10, 0.30, 0.30, c, 1.0, MSO_SHAPE.OVAL)
        add_rect(s, 1.545, yy + 0.175, 0.10, 0.10, BG, 1.0, MSO_SHAPE.OVAL)
        add_text(s, 0.72, yy, 0.75, 0.4, [{'runs': [(t, 13, c, True)]}])
        add_text(s, 2.02, yy - 0.06, 5.0, 0.45, [{'runs': [(h1, 21, WHITE, True)]}])
        add_text(s, 2.02, yy + 0.46, 4.85, 0.8, [{'runs': [(h2, 13, GREY, False)]}], line=1.35)

    add_rect(s, 0.72, 9.95, 6.06, 2.05, CARD, 1.0, MSO_SHAPE.ROUNDED_RECTANGLE,
             radius=0.05, line=LINE, line_w=0.75)
    add_text(s, 0.98, 10.18, 5.6, 0.32,
             [{'runs': [("乘组：驾驶员 + 工程师 + 载荷专家", 13, GOLD, True)]}])
    add_text(s, 0.98, 10.66, 5.6, 1.15,
             [{'runs': [("汤洪波", 17, WHITE, True), ("（指令长，三探天宫）", 12, GREY, False)]},
              {'runs': [("武　毅", 17, WHITE, True), ("（航天飞行工程师）", 12, GREY, False)]},
              {'runs': [("齐尚·阿里", 16.5, CYAN, True), ("（巴基斯坦载荷专家）", 12, GREY, False)]}],
             line=1.42)

    # ============ 3 三个优化 ============
    s = new_slide(prs, 3, TOTAL, "KNOW-HOW · 速度是怎么提上来的", "把 6.5 小时\n砍成 3.5 小时", CYAN,
                  subtitle="三次“抠细节”，抠出了一个更快的中国航天")
    data = [
        ("01", "更准的入轨", "起飞时间掐到秒，入轨就站在更近的起点。", GOLD),
        ("02", "更少的绕圈", "绕地 3 圈变 2 圈，每少一圈省下约 90 分钟。", ORANGE),
        ("03", "更近的导引", "近程导引起点前移，最后一段冲刺更短。", CYAN),
    ]
    y = 3.30
    for num, h1, h2, c in data:
        add_rect(s, 0.72, y, 6.06, 1.86, CARD, 1.0, MSO_SHAPE.ROUNDED_RECTANGLE,
                 radius=0.06, line=LINE, line_w=0.75)
        add_text(s, 0.98, y + 0.18, 0.9, 0.4, [{'runs': [(num, 15, c, True)]}])
        add_text(s, 0.98, y + 0.58, 5.5, 0.45, [{'runs': [(h1, 21, WHITE, True)]}])
        add_text(s, 0.98, y + 1.08, 5.55, 0.68, [{'runs': [(h2, 12.5, GREY, False)]}], line=1.35)
        y += 2.06

    add_rect(s, 0.72, 9.85, 6.06, 2.25, RGBColor(0x1B, 0x13, 0x08), 1.0,
             MSO_SHAPE.ROUNDED_RECTANGLE, radius=0.05, line=RGBColor(0x6A, 0x44, 0x12), line_w=0.75)
    add_text(s, 0.98, 10.05, 5.6, 0.35, [{'runs': [("对接时间“进化史”", 12, GOLD, True)]}])
    add_text(s, 0.98, 10.55, 5.7, 1.3,
             [{'runs': [("2 天", 26, GREY, True), ("  →  ", 18, DIM, False),
                        ("6.5 小时", 26, WHITE, True), ("  →  ", 18, DIM, False),
                        ("3.5 小时", 30, ORANGE, True)]},
              {'runs': [("神舟八号 2011　　神舟十二号 2021　　今天", 10.5, DIM, False)], 'space_before': 8}],
             line=1.3)

    # ============ 4 穿针 ============
    s = new_slide(prs, 4, TOTAL, "DIFFICULTY · 到底难在哪", "一根线，\n追上针眼", GOLD,
                  subtitle="空间站每秒飞 7.9 公里，飞船要在 3.5 小时里赶上、刹车、贴合")
    # 大引用
    add_rect(s, 0.72, 3.32, 6.06, 2.55, CARD, 1.0, MSO_SHAPE.ROUNDED_RECTANGLE,
             radius=0.05, line=LINE, line_w=0.75)
    add_text(s, 1.02, 3.48, 1.0, 0.7, [{'runs': [("“", 44, ORANGE, True)]}])
    add_text(s, 1.02, 4.02, 5.4, 1.6,
             [{'runs': [("空间交会对接就像万米高空的穿针引线，\n空间站就是针的针眼，飞船就是这根线。", 17, WHITE, False)]}],
             line=1.5)
    add_text(s, 1.02, 5.35, 5.2, 0.35,
             [{'runs': [("—— 北京航天飞行控制中心 姜萍", 11.5, GREY, False)]}])

    facts = [
        ("7.9 km/s", "空间站在轨速度，约合时速 2.8 万公里，是高铁的 80 多倍"),
        ("厘米级", "最终对接时，两个几十吨的庞然大物要“轻碰”在一起"),
        ("0 容错", "快一点会撞，慢一点追不上；绕圈、变轨、刹车全靠飞船自己算"),
    ]
    y = 6.18
    for big, txt in facts:
        add_text(s, 0.75, y, 2.05, 0.6, [{'runs': [(big, 19, CYAN, True)]}])
        add_text(s, 2.78, y - 0.02, 3.95, 0.95, [{'runs': [(txt, 12.5, GREY, False)]}], line=1.4)
        y += 1.05

    add_rect(s, 0.72, 9.55, 6.06, 2.35, CARD2, 0.85, MSO_SHAPE.ROUNDED_RECTANGLE,
             radius=0.05, line=LINE, line_w=0.75)
    add_text(s, 0.98, 9.78, 5.6, 0.32, [{'runs': [("提速的真正意义", 12, GOLD, True)]}])
    add_text(s, 0.98, 10.22, 5.55, 1.4,
             [{'runs': [("从“能上去”，到“随时能上、随时能回”。", 17, WHITE, True)]},
              {'runs': [("对接越快，航天员在狭小飞船里待的时间越短，应急窗口也越大。", 12.5, GREY, False)],
               'space_before': 8}],
             line=1.45)

    # ============ 5 提速史 ============
    s = new_slide(prs, 5, TOTAL, "TIMELINE · 十五年的“追星”路", "每一次提速，\n都是一次重写", ORANGE)
    steps = [
        ("2011", "神舟八号", "无人飞行，约 2 天完成首次交会对接", DIM),
        ("2021", "神舟十二号", "首次 6.5 小时快速对接，航天员当天“入住”", GREY),
        ("2025", "神舟二十一号", "3.5 小时快速对接首飞验证成功", CYAN),
        ("2025", "神舟二十二号", "首次应急发射：16 天紧急升空，无人飞船 3.5 小时到站", CYAN),
        ("2026", "神舟二十三号", "首次挑战 3.5 小时“径向对接”，难度最高", GOLD),
        ("今天", "神舟二十四号", "第 4 次 3.5 小时对接，快速模式走向常态化", ORANGE),
    ]
    y = 2.95
    for i, (yr, name, desc, c) in enumerate(steps):
        add_text(s, 0.72, y + 0.02, 0.95, 0.35, [{'runs': [(yr, 13, c, True)]}])
        add_text(s, 2.02, y - 0.04, 4.6, 0.4, [{'runs': [(name, 18, WHITE, True)]}])
        add_text(s, 2.02, y + 0.40, 4.65, 0.72, [{'runs': [(desc, 12, GREY, False)]}], line=1.35)
        if i < len(steps) - 1:
            add_rect(s, 0.72, y + 1.12, 6.04, 0.012, LINE)
        y += 1.47

    add_text(s, 0.72, 11.42, 6.1, 0.75,
             [{'runs': [("从“追得上”到“追得快”，靠的是一整套体系的同步升级。", 11.5, DIM, False)]}],
             line=1.4)

    # ============ 6 外籍航天员 ============
    s = new_slide(prs, 6, TOTAL, "FIRST · 天宫第一次开门迎客", "来自巴基斯坦的\n“太空队友”", CYAN,
                  subtitle="中国载人航天工程首个中外联合飞行乘组")
    add_rect(s, 0.72, 3.42, 6.06, 1.95, CARD, 1.0, MSO_SHAPE.ROUNDED_RECTANGLE,
             radius=0.05, line=LINE, line_w=0.75)
    add_text(s, 0.98, 3.62, 5.5, 0.45,
             [{'runs': [("穆罕默德·齐尚·阿里", 22, WHITE, True)]}])
    add_text(s, 0.98, 4.16, 5.5, 1.0,
             [{'runs': [("巴基斯坦载荷专家 · 首位到访中国空间站的外籍航天员 · 执行短期飞行任务", 12.5, GREY, False)]}],
             line=1.45)

    steps = [
        ("2025.02", "中巴在伊斯兰堡签署合作协议，启动巴基斯坦航天员选拔"),
        ("初选 · 复选 · 定选", "三个阶段层层筛选，选出 2 名预备航天员"),
        ("来华训练", "与中国航天员同班训练、同标准考核，1 人飞天、1 人备份"),
        ("在轨任务", "安装中巴合作科学实验样品与单元，开展在轨实验"),
    ]
    y = 5.68
    for i, (h1, h2) in enumerate(steps):
        add_rect(s, 0.82, y + 0.12, 0.16, 0.16, CYAN, 1.0, MSO_SHAPE.OVAL)
        add_text(s, 1.18, y - 0.03, 5.4, 0.35, [{'runs': [(h1, 14, GOLD, True)]}])
        add_text(s, 1.18, y + 0.36, 5.45, 0.75, [{'runs': [(h2, 12.5, GREY, False)]}], line=1.35)
        y += 1.31

    add_rect(s, 0.72, 10.95, 6.06, 1.2, RGBColor(0x0A, 0x24, 0x33), 1.0,
             MSO_SHAPE.ROUNDED_RECTANGLE, radius=0.12, line=RGBColor(0x1E, 0x5C, 0x74), line_w=0.75)
    add_text(s, 0.98, 11.13, 5.55, 0.85,
             [{'runs': [("2026 年恰逢中巴建交 75 周年——这份“太空礼物”，够硬核。", 13, CYAN, True)]}],
             line=1.4)

    # ============ 7 冷知识 ============
    s = new_slide(prs, 7, TOTAL, "FUN FACTS · 顺手涨点知识", "太空里的\n四个“反常识”", GOLD)
    facts = [
        ("一天要看 16 次日出", "空间站 90 分钟绕地球一圈，航天员的“一天”被压缩成 90 分钟。"),
        ("“前向”像正门，“径向”像翻阳台", "神舟二十四号对接前向端口；径向对接难度最高，被称为“太空穿针”里的高难动作。"),
        ("对接完，家里就有 6 个人", "神舟二十三号乘组还没走，两边航天员在轨“太空会师”，三船三舱组合同框。"),
        ("点火时间，一秒都不能差", "发射窗口按秒计算，晚一点，空间站这个“针眼”就跑远了。"),
    ]
    y = 3.05
    for i, (h1, h2) in enumerate(facts):
        c = [ORANGE, CYAN, GOLD, ORANGE][i]
        add_rect(s, 0.72, y, 6.06, 1.98, CARD, 1.0, MSO_SHAPE.ROUNDED_RECTANGLE,
                 radius=0.06, line=LINE, line_w=0.75)
        add_text(s, 0.98, y + 0.20, 0.55, 0.45, [{'runs': [(f"0{i+1}", 15, c, True)]}])
        add_text(s, 0.98, y + 0.62, 5.4, 0.45, [{'runs': [(h1, 17.5, WHITE, True)]}])
        add_text(s, 0.98, y + 1.10, 5.45, 0.75, [{'runs': [(h2, 11.5, GREY, False)]}], line=1.35)
        y += 2.18

    # ============ 8 结尾 ============
    _slide_no[0] += 1
    s = prs.slides.add_slide(prs.slide_layouts[6])
    if MODE == "final":
        add_bg_picture(s, 8)
    add_rect(s, 0, 0, W, H, BG)
    ring(s, 2.6, -2.9, 8.0, 8.0, ORANGE, 0.14, 0.9)
    add_rect(s, -3.2, 10.6, 11.0, 11.0, RGBColor(0x0C, 0x24, 0x4E), 1.0, MSO_SHAPE.OVAL, line=CYAN, line_w=1.0)
    ring(s, -3.6, 10.2, 11.8, 11.8, CYAN, 0.35, 0.5)
    rnd = random.Random(99)
    for _ in range(70):
        sx, sy = rnd.uniform(0.1, W - 0.15), rnd.uniform(0.2, H - 0.2)
        d = rnd.uniform(0.015, 0.05)
        add_rect(s, sx, sy, d, d, WHITE, rnd.uniform(0.12, 0.5), MSO_SHAPE.OVAL)

    add_text(s, 0.75, 3.10, 6.0, 0.35, [{'runs': [("THE END · 星辰大海", 12, GOLD, True)]}])
    add_text(s, 0.72, 3.60, 6.2, 1.8, [{'runs': [("从“穿针”\n到“开门”", 52, WHITE, True)]}], line=1.25)
    add_text(s, 0.75, 6.30, 5.9, 2.2,
             [{'runs': [("3.5 小时，是技术的速度；", 19, GREY, False)]},
              {'runs': [("把舱门向世界打开，是胸怀的宽度。", 19, GOLD, True)], 'space_before': 4},
              {'runs': [("下一个登上天宫的，会是谁？", 15, CYAN, False)], 'space_before': 16}],
             line=1.5)
    add_rect(s, 0.78, 9.30, 2.2, 0.03, ORANGE)
    add_text(s, 0.75, 9.50, 6.0, 1.1,
             [{'runs': [("资料来源：中国载人航天工程网、新华社、央视新闻、上海证券报", 9.5, DIM, False)]},
              {'runs': [("制作：TraeCode · 2026.11.25", 9.5, DIM, False)], 'space_before': 6}],
             line=1.4)

    out = {
        "full": "/workspace/build_sz24/神舟二十四号_3.5小时太空穿针.pptx",
        "bg": "/workspace/build_sz24/bg_deck.pptx",
        "final": "/workspace/build_sz24/ppt2003_source.pptx",
    }[MODE]
    prs.save(out)
    print("saved", MODE, out, "slides =", len(prs.slides))


if __name__ == "__main__":
    build()
