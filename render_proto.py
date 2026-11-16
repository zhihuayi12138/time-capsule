# -*- coding: utf-8 -*-
"""TimeCapsule 全页面原型渲染器 —— 375x812 逻辑尺寸，输出 537x1163（与文档内原型同尺寸）。"""
import math, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = r"D:\time-capsule\prototypes"
os.makedirs(OUT, exist_ok=True)

S = 537 / 375.0          # 输出缩放
SS = 2                   # 超采样
K = S * SS
W, H = int(round(375 * K)), int(round(812 * K))
OUTW, OUTH = 537, 1163

# ---------------- 设计令牌（取自文档内 4 张原型的实测色值）
BG      = (245, 241, 234)
INK     = (30, 36, 32)
INK2    = (69, 75, 71)
MUTED   = (140, 138, 130)
MUTED2  = (180, 176, 165)
GREEN   = (44, 95, 85)
GREEN_D = (31, 64, 57)
GSOFT   = (230, 240, 236)
LINE    = (232, 226, 214)
CARD    = (255, 255, 255)
WARM_BG = (253, 246, 232)
WARM_LN = (234, 217, 180)
WARM_INK= (168, 116, 42)
DASH    = (220, 213, 196)
WHITE   = (255, 255, 255)

FONT_R = r"C:\Windows\Fonts\msyh.ttc"
FONT_B = r"C:\Windows\Fonts\msyhbd.ttc"

_fc = {}
def F(size, bold=False, light=False):
    key = (round(size, 2), bold)
    if key not in _fc:
        path = FONT_B if bold else FONT_R
        _fc[key] = ImageFont.truetype(path, max(1, px(size)))
    return _fc[key]

def px(v):
    return int(round(v * K))

def new_canvas(bg=BG):
    img = Image.new("RGB", (W, H), bg)
    _CUR["img"] = img
    return img, ImageDraw.Draw(img)

# ---------------- 基础绘制
def txt(d, x, y, s, size, color=INK, bold=False, anchor="la"):
    d.text((px(x), px(y)), s, font=F(size, bold), fill=color, anchor=anchor)

def tw(d, s, size, bold=False):
    return d.textlength(s, font=F(size, bold)) / K

def rrect(d, box, r, fill=None, outline=None, width=1):
    x0, y0, x1, y1 = [px(v) for v in box]
    d.rounded_rectangle([x0, y0, x1, y1], radius=px(r), fill=fill,
                        outline=outline, width=max(1, px(width)))

def rect(d, box, fill):
    d.rectangle([px(box[0]), px(box[1]), px(box[2]), px(box[3])], fill=fill)

def circle(d, cx, cy, r, fill=None, outline=None, width=1):
    d.ellipse([px(cx - r), px(cy - r), px(cx + r), px(cy + r)],
              fill=fill, outline=outline, width=max(1, px(width)))

def hline(d, x0, x1, y, color=LINE, w=1):
    d.line([px(x0), px(y), px(x1), px(y)], fill=color, width=max(1, px(w)))

def vline(d, x, y0, y1, color=LINE, w=1):
    d.line([px(x), px(y0), px(x), px(y1)], fill=color, width=max(1, px(w)))

def rrect_gradient(box, r, top, bottom):
    """在圆角矩形内部填充垂直渐变，边缘不溢出。"""
    img = _CUR["img"]
    x0, y0, x1, y1 = [px(v) for v in box]
    bw, bh = x1 - x0, y1 - y0
    if bw <= 0 or bh <= 0:
        return
    grad = Image.new("RGB", (bw, bh))
    gd = ImageDraw.Draw(grad)
    for i in range(bh):
        t = i / max(1, bh - 1)
        c = tuple(int(top[j] + (bottom[j] - top[j]) * t) for j in range(3))
        gd.line([(0, i), (bw, i)], fill=c)
    mask = Image.new("L", (bw, bh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, bw - 1, bh - 1], radius=px(r), fill=255)
    img.paste(grad, (x0, y0), mask)


def _arc(cx, cy, r, a0, a1, step=0.06):
    n = max(2, int(abs(a1 - a0) / step))
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / n),
             cy + r * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]

def _rpath(x0, y0, x1, y1, r):
    pts = []
    pts += _arc(x1 - r, y0 + r, r, -math.pi / 2, 0)
    pts += [(x1, y1 - r)]                      # 右边直边
    pts += _arc(x1 - r, y1 - r, r, 0, math.pi / 2)
    pts += [(x0 + r, y1)]                      # 底边
    pts += _arc(x0 + r, y1 - r, r, math.pi / 2, math.pi)
    pts += [(x0, y0 + r)]                      # 左边直边
    pts += _arc(x0 + r, y0 + r, r, math.pi, 1.5 * math.pi)
    pts += [(x1 - r, y0)]                      # 顶边
    return pts

def dashed_rrect(d, box, r, color=DASH, w=1.5, dash=5, gap=4):
    pts = _rpath(*box, r)
    on, acc = True, 0.0
    period = dash + gap
    prev = pts[0]
    for p in pts[1:]:
        seglen = math.dist(prev, p)
        if seglen <= 0:
            continue
        # 沿线段行走，按弧长切分 dash/gap
        t = 0.0
        while t < seglen:
            remain = (dash if on else gap) - acc
            step = min(remain, seglen - t)
            a = (prev[0] + (p[0] - prev[0]) * (t / seglen),
                 prev[1] + (p[1] - prev[1]) * (t / seglen))
            b = (prev[0] + (p[0] - prev[0]) * ((t + step) / seglen),
                 prev[1] + (p[1] - prev[1]) * ((t + step) / seglen))
            if on and step > 0:
                d.line([px(a[0]), px(a[1]), px(b[0]), px(b[1])],
                       fill=color, width=max(1, px(w)))
            t += step
            acc += step
            if acc >= (dash if on else gap) - 1e-9:
                on = not on
                acc = 0.0
        prev = p

def vertical_gradient(img, top, bottom):
    d = ImageDraw.Draw(img)
    for i in range(H):
        t = i / (H - 1)
        c = tuple(int(top[j] + (bottom[j] - top[j]) * t) for j in range(3))
        d.line([(0, i), (W, i)], fill=c)

def radial_glow(img, cx, cy, rx, ry, color, alpha=0.4):
    layer = Image.new("L", (W, H), 0)
    dl = ImageDraw.Draw(layer)
    steps = 44
    for i in range(steps, 0, -1):
        t = i / steps
        a = int(alpha * 255 * (1 - t) ** 1.5)
        dl.ellipse([px(cx - rx * t), px(cy - ry * t), px(cx + rx * t), px(cy + ry * t)], fill=a)
    layer = layer.filter(ImageFilter.GaussianBlur(px(18)))
    img.paste(Image.new("RGB", (W, H), color), (0, 0), layer)

_CUR = {"img": None}

def soft_shadow(box, r, blur=14, color=(0, 0, 0), alpha=40, dy=6):
    img = _CUR["img"]
    layer = Image.new("L", (W, H), 0)
    dl = ImageDraw.Draw(layer)
    dl.rounded_rectangle([px(box[0]), px(box[1] + dy), px(box[2]), px(box[3] + dy)],
                         radius=px(r), fill=alpha)
    layer = layer.filter(ImageFilter.GaussianBlur(px(blur)))
    img.paste(Image.new("RGB", (W, H), color), (0, 0), layer)

def para(d, x, y, lines, size, color=INK2, leading=None, bold=False):
    leading = leading or size * 1.9
    for i, ln in enumerate(lines):
        txt(d, x, y + i * leading, ln, size, color, bold)
    return y + len(lines) * leading

# ---------------- 图标
def icon_play(d, cx, cy, color=WHITE, s=1.0):
    pts = [(cx - 3.1 * s, cy - 4.6 * s), (cx + 4.3 * s, cy),
           (cx - 3.1 * s, cy + 4.6 * s)]
    d.polygon([(px(a), px(b)) for a, b in pts], fill=color)

def icon_chev(d, x, y, color=MUTED2, size=5.2, w=1.6):
    d.line([px(x), px(y - size), px(x + size * 0.85), px(y), px(x), px(y + size)],
           fill=color, width=max(1, px(w)), joint="curve")

def icon_back(d, x, y, color=INK2, size=6.6, w=1.7):
    d.line([px(x + size * 0.8), px(y - size), px(x), px(y), px(x + size * 0.8), px(y + size)],
           fill=color, width=max(1, px(w)), joint="curve")

def icon_dots(d, cx, cy, color=(156, 151, 137)):
    for i in (-1, 0, 1):
        circle(d, cx + i * 4.4, cy, 1.75, fill=color)

def icon_lock(d, cx, cy, color=MUTED, s=1.0):
    rrect(d, (cx - 8 * s, cy - 5 * s, cx + 8 * s, cy + 8.5 * s), 2.6 * s, outline=color, width=1.6)
    d.arc([px(cx - 4.6 * s), px(cy - 12 * s), px(cx + 4.6 * s), px(cy - 2 * s)],
          180, 360, fill=color, width=max(1, px(1.6)))
    d.line([px(cx - 4.6 * s), px(cy - 7 * s), px(cx - 4.6 * s), px(cy - 5 * s)], fill=color, width=max(1, px(1.6)))
    d.line([px(cx + 4.6 * s), px(cy - 7 * s), px(cx + 4.6 * s), px(cy - 5 * s)], fill=color, width=max(1, px(1.6)))
    circle(d, cx, cy + 2 * s, 1.6 * s, fill=color)

def icon_bell(d, cx, cy, color=GREEN, s=1.0):
    d.arc([px(cx - 9 * s), px(cy - 10 * s), px(cx + 9 * s), px(cy + 8 * s)], 180, 360,
          fill=color, width=max(1, px(1.8)))
    d.line([px(cx - 9 * s), px(cy - 1 * s), px(cx - 9 * s), px(cy + 3 * s)], fill=color, width=max(1, px(1.8)))
    d.line([px(cx + 9 * s), px(cy - 1 * s), px(cx + 9 * s), px(cy + 3 * s)], fill=color, width=max(1, px(1.8)))
    d.line([px(cx - 11 * s), px(cy + 3 * s), px(cx + 11 * s), px(cy + 3 * s)], fill=color, width=max(1, px(1.8)))
    d.arc([px(cx - 3.6 * s), px(cy + 3 * s), px(cx + 3.6 * s), px(cy + 9 * s)], 0, 180, fill=color, width=max(1, px(1.8)))

def icon_plus(d, cx, cy, color=WHITE, s=1.0, w=1.9):
    d.line([px(cx - 7 * s), px(cy), px(cx + 7 * s), px(cy)], fill=color, width=max(1, px(w)))
    d.line([px(cx), px(cy - 7 * s), px(cx), px(cy + 7 * s)], fill=color, width=max(1, px(w)))

def waveform(d, x, y, w, h, color=(198, 193, 179), n=34):
    hs = [5, 11, 7, 14, 8, 12, 6, 13, 9, 10, 5, 12, 8, 14, 7, 11, 6, 13, 9, 5,
          12, 8, 10, 6, 14, 9, 11, 7, 13, 6, 10, 8, 12, 5]
    step = w / n
    for i in range(n):
        bh = hs[i % len(hs)] / 14 * h
        rrect(d, (x + i * step, y + (h - bh) / 2, x + i * step + 1.9, y + (h + bh) / 2),
              0.9, fill=color)

def status_bar(d, dark=False):
    c = WHITE if dark else INK
    txt(d, 24, 30, "9:41", 14, c, bold=True)
    # 信号
    x = 300
    for i, hh in enumerate([3.8, 6, 8.4, 10.6]):
        rrect(d, (x + i * 4.7, 44 - 4 - hh, x + i * 4.7 + 3, 40), 1, fill=(c if i < 4 else (c[0], c[1], c[2])))
    # wifi
    wx, wy = 337, 40
    d.arc([px(wx - 8), px(wy - 9), px(wx + 8), px(wy + 7)], 200, 340, fill=c, width=max(1, px(1.5)))
    d.arc([px(wx - 4.6), px(wy - 5.6), px(wx + 4.6), px(wy + 3.4)], 200, 340, fill=c, width=max(1, px(1.5)))
    circle(d, wx, wy - 1.2, 1.25, fill=c)
    # 电量
    bx, by = 355, 30
    rrect(d, (bx, by, bx + 22, by + 12), 3.2, outline=(c[0], c[1], c[2]), width=1.1)
    rrect(d, (bx + 2, by + 2, bx + 17.4, by + 10), 1.8, fill=c)
    rrect(d, (bx + 23.4, by + 4.2, bx + 24.6, by + 7.8), 0.8, fill=c)

def indicator(d, dark=False):
    c = (255, 255, 255) if dark else (30, 36, 32)
    rrect(d, (128.5, 800, 246.5, 805), 2.5, fill=c)

def nav_bar(d, title="", left_back=True, right="", right_color=GREEN, right_off=False, show_back=False):
    y = 57
    if left_back:
        icon_back(d, 24, y, INK2, 7.4, 1.7)
        if show_back:
            txt(d, 36, y - 7.5, "返回", 15, INK2)
    else:
        txt(d, 24, y - 7.5, "取消", 15, INK2)
    if title:
        txt(d, 187.5, y - 8.5, title, 15.5, INK, bold=True, anchor="ma")
    if right:
        txt(d, 351, y - 8, right, 15, MUTED2 if right_off else GREEN, bold=not right_off, anchor="ra")
    else:
        icon_dots(d, 338, y)

# ---------------- 组件
def card_title(d, x, y, t, size=19):
    txt(d, x, y, t, size, INK, bold=True)

def progress(d, x, y, w, pct, h=4, bg=(237, 230, 219), fg=GREEN):
    rrect(d, (x, y, x + w, y + h), h / 2, fill=bg)
    if pct > 0:
        rrect(d, (x, y, x + max(w * pct, h), y + h), h / 2, fill=fg)

def pill(d, x, y, s, fg=GREEN, bg=GSOFT, size=11.5):
    w = tw(d, s, size, True) + 22
    rrect(d, (x, y, x + w, y + 24), 12, fill=bg)
    txt(d, x + 11, y + 6.2, s, size, fg, bold=True)
    return w

def toggle(d, x, y, on=True):
    if on:
        rrect(d, (x, y, x + 44, y + 26), 13, fill=GREEN)
        circle(d, x + 31, y + 13, 10, fill=WHITE)
    else:
        rrect(d, (x, y, x + 44, y + 26), 13, fill=(220, 214, 200))
        circle(d, x + 13, y + 13, 10, fill=WHITE)

def btn_primary(d, x, y, w, h, s, soft=False):
    if soft:
        rrect(d, (x, y, x + w, y + h), 14, fill=(239, 234, 225))
        txt(d, x + w / 2, y + h / 2 - 8.5, s, 16, INK2, bold=True, anchor="ma")
    else:
        soft_shadow((x, y, x + w, y + h), 14, blur=10, color=GREEN, alpha=45, dy=4)
        rrect(d, (x, y, x + w, y + h), 14, fill=GREEN)
        txt(d, x + w / 2, y + h / 2 - 9, s, 16, WHITE, bold=True, anchor="ma")

def btn_disabled(d, x, y, w, h, s):
    rrect(d, (x, y, x + w, y + h), 14, fill=(218, 213, 201))
    txt(d, x + w / 2, y + h / 2 - 8.5, s, 16, (156, 151, 137), bold=True, anchor="ma")


# ============================================================ 01 首页·胶囊架
def frame01():
    img, d = new_canvas()
    status_bar(d)
    txt(d, 24, 60, "我的胶囊", 30, INK, bold=True)
    txt(d, 24, 106, "还有 4 个约定在时间里等着", 12.5, MUTED)

    # tabs
    tabs = [("待开启", "1", True, 24), ("已封存", "3", False, 96), ("已开启", "2", False, 178)]
    for name, n, on, x in tabs:
        col = INK if on else MUTED2
        txt(d, x, 138, name, 14, col, bold=on)
        cw = tw(d, name, 14, on)
        txt(d, x + cw + 2.5, 132, n, 10.5, col, bold=True)
        if on:
            rrect(d, (x - 1, 169.5, x + cw + 12, 172), 1.6, fill=GREEN)
    hline(d, 0, 375, 172)

    # 到期卡
    y = 190
    soft_shadow((24, y, 351, y + 148), 16, blur=9, color=(168, 116, 42), alpha=26, dy=3)
    d = ImageDraw.Draw(img)
    rrect(d, (24, y, 351, y + 148), 16, fill=(255, 252, 243), outline=WARM_LN, width=1)
    circle(d, 29.5, y + 23, 2.6, fill=WARM_INK)
    txt(d, 38, y + 15.5, "今天到期 · 可以打开了", 11.5, WARM_INK, bold=True)
    txt(d, 42, y + 38, "给一年后的我", 19, INK, bold=True)
    txt(d, 42, y + 68, "封存于 2026.10.19 · 等待了 365 天", 12, MUTED)
    rrect(d, (42, y + 90, 333, y + 134), 11, fill=GREEN)
    txt(d, 187.5, y + 104, "打开胶囊", 15, WHITE, bold=True, anchor="ma")

    # 其余卡片
    items = [("期末结束的那个晚上", 87, 0.12), ("毕业那天", 621, 0.06), ("写给二十岁的生日", 204, 0.09)]
    y = 356
    for name, days, pct in items:
        rrect(d, (24, y, 351, y + 96), 16, fill=CARD)
        txt(d, 42, y + 18, name, 19, INK, bold=True)
        txt(d, 42, y + 48, "距离开启还有", 12, MUTED)
        dw = tw(d, "距离开启还有", 12)
        txt(d, 42 + dw + 4, y + 47, str(days), 12.5, GREEN, bold=True)
        dw2 = tw(d, str(days), 12.5, True)
        txt(d, 42 + dw + 4 + dw2 + 3, y + 48, "天", 12, MUTED)
        progress(d, 42, y + 72, 291, pct)
        y += 110

    btn_primary(d, 24, 736, 327, 50, "+ 与时间约定")
    indicator(d)
    return img


# ============================================================ 02 首页·空状态
def frame02():
    img, d = new_canvas()
    status_bar(d)
    txt(d, 24, 60, "我的胶囊", 30, INK, bold=True)
    txt(d, 24, 106, "还没有约定在时间里等着", 12.5, MUTED)

    for name, n, on, x in [("待开启", "0", True, 24), ("已封存", "0", False, 96), ("已开启", "0", False, 178)]:
        col = INK if on else MUTED2
        txt(d, x, 138, name, 14, col, bold=on)
        cw = tw(d, name, 14, on)
        txt(d, x + cw + 2.5, 132, n, 10.5, col, bold=True)
        if on:
            rrect(d, (x - 1, 169.5, x + cw + 12, 172), 1.6, fill=GREEN)
    hline(d, 0, 375, 172)

    # 中心图示 + 标题 + 两行提示 + 中部按钮
    cx, cy = 187.5, 356
    circle(d, cx, cy, 43, outline=MUTED2, width=1.4)
    dashed_rrect(d, (cx - 15, cy - 22, cx + 15, cy + 22), 15, color=(201, 196, 182), w=1.6, dash=4, gap=4)
    d.line([px(cx - 7), px(cy), px(cx - 2.5), px(cy + 4.5), px(cx + 8), px(cy - 5.5)],
           fill=(201, 196, 182), width=max(1, px(1.8)), joint="curve")

    txt(d, cx, cy + 76, "时间还没有开始", 20, INK, bold=True, anchor="ma")
    for i, ln in enumerate(["你现在想对未来的自己说什么？", "写完封起来，到那天它会来找你。"]):
        lw = tw(d, ln, 13)
        txt(d, cx - lw / 2, cy + 116 + i * 26, ln, 13, MUTED)

    soft_shadow((114, 544, 261, 590), 13, blur=10, color=GREEN, alpha=45, dy=4)
    d = ImageDraw.Draw(img)
    rrect(d, (114, 544, 261, 590), 13, fill=GREEN)
    icon_plus(d, 143, 567, WHITE, 0.85)
    txt(d, 157, 558, "与时间约定", 15, WHITE, bold=True)

    btn_primary(d, 24, 736, 327, 50, "+ 与时间的第一个约定")
    indicator(d)
    return img


# ============================================================ 03/04 约定时间
def editor_frame(initial=False):
    img, d = new_canvas()
    status_bar(d)
    nav_bar(d, "约定时间", left_back=False, right="封存", right_off=initial)

    y = 92
    txt(d, 24, y, "标题", 11.5, MUTED, bold=True)
    y += 24
    if initial:
        txt(d, 24, y, "给这一刻起个名字", 22, MUTED2, bold=True)
    else:
        txt(d, 24, y, "给一年后的我", 22, INK, bold=True)
    y += 40
    hline(d, 24, 351, y)

    y += 14
    txt(d, 24, y + 13, "开启时间", 14.5, INK2)
    date_s = "2027 年 10 月 19 日"
    dw = tw(d, date_s, 16, True)
    txt(d, 351 - dw - 12, y + 12, date_s, 16, GREEN, bold=True)
    icon_chev(d, 351 - 6, y + 21, MUTED2, 4.8, 1.6)
    y += 46
    hline(d, 24, 351, y)

    # 创建时间：创建后不可修改，只读展示
    y += 14
    txt(d, 24, y + 13, "创建时间", 14.5, MUTED)
    made_s = "2026.10.19 09:41"
    mw = tw(d, made_s, 13.5)
    txt(d, 351 - mw, y + 15, made_s, 13.5, MUTED2)
    y += 46
    hline(d, 24, 351, y)

    y += 14
    txt(d, 24, y, "内容", 11.5, MUTED, bold=True)
    y += 26

    if initial:
        rrect(d, (24, y, 351, y + 170), 16, fill=(250, 248, 242))
        dashed_rrect(d, (24, y, 351, y + 170), 16, color=DASH, w=1.5, dash=5, gap=4)
        for i, ln in enumerate(["你现在最想告诉", "未来的自己哪件事？"]):
            lw = tw(d, ln, 14.5, True)
            txt(d, 187.5 - lw / 2, y + 62 + i * 25, ln, 14.5, (156, 151, 137), bold=True)
        ln = "从下面添加文字、图片或语音"
        txt(d, 187.5 - tw(d, ln, 11.5) / 2, y + 130, ln, 11.5, MUTED2)
        y += 190
    else:
        rrect(d, (24, y, 351, y + 108), 16, fill=CARD)
        para(d, 40, y + 17, ["不知道你现在怎么样了。今天刚开学一个月，我还在",
                             "为要不要转专业这件事纠结。如果你已经决定了，希",
                             "望你不后悔。"], 14, INK2, 24)
        y += 120
        # 图片块
        rrect(d, (24, y, 351, y + 100), 16, fill=CARD)
        for i, (c1, c2) in enumerate([((239, 231, 216), (227, 217, 197)), ((231, 234, 228), (214, 220, 212))]):
            bx = 36 + i * 86
            rrect(d, (bx, y + 12, bx + 76, y + 88), 10, fill=c1)
            rrect(d, (bx, y + 52, bx + 76, y + 88), 10, fill=c2)
        rrect(d, (208, y + 12, 284, y + 88), 10, fill=(250, 248, 242))
        dashed_rrect(d, (208, y + 12, 284, y + 88), 10, color=DASH, w=1.5, dash=5, gap=4)
        icon_plus(d, 246, y + 50, MUTED2, 1.0, 1.5)
        y += 112
        # 音频块
        rrect(d, (24, y, 351, y + 58), 16, fill=CARD)
        circle(d, 52, y + 29, 17, fill=GREEN)
        icon_play(d, 52, y + 29, WHITE, 0.95)
        waveform(d, 78, y + 20, 118, 18)
        txt(d, 337, y + 22, "0:42", 12, MUTED, anchor="ra")
        y += 70

    y += 2
    for i, s in enumerate(["+ 文字", "+ 图片", "+ 语音"]):
        bx = 24 + i * 108.5
        rrect(d, (bx, y, bx + 100, y + 44), 12, fill=(250, 248, 242))
        dashed_rrect(d, (bx, y, bx + 100, y + 44), 12, color=DASH, w=1.5, dash=5, gap=4)
        txt(d, bx + 50, y + 13.5, s, 13.5, (124, 120, 110), bold=True, anchor="ma")

    y += 58
    txt(d, 24, y, "至少添加一种内容才能封存", 11.5, MUTED2)

    if initial:
        btn_disabled(d, 24, 736, 327, 50, "封存胶囊")
    else:
        btn_primary(d, 24, 736, 327, 50, "封存胶囊")
    indicator(d)
    return img


# ============================================================ 05 封存确认
def frame05():
    base = editor_frame(initial=False).convert("RGBA")
    scrim = Image.new("RGBA", (W, H), (147, 148, 143, 199))
    img = Image.alpha_composite(base, scrim).convert("RGB")
    _CUR["img"] = img

    # sheet（弹层从 300 起，内容整体压缩以完整落在安全区内）
    sy = 300
    soft_shadow((0, sy + 8, 375, 812), 26, blur=22, color=(0, 0, 0), alpha=90, dy=-4)
    d = ImageDraw.Draw(img)
    rrect(d, (0, sy, 375, 830), 24, fill=WHITE)
    rect(d, (0, sy + 24, 375, 830), WHITE)
    rrect(d, (169.5, sy + 10, 205.5, sy + 15), 2.5, fill=(228, 223, 210))

    txt(d, 187.5, sy + 38, "要封存了吗？", 23, INK, bold=True, anchor="ma")
    ln = "封存之后，它会安静地等上 365 天"
    txt(d, 187.5 - tw(d, ln, 12.5) / 2, sy + 78, ln, 12.5, MUTED)

    rows = [("标题", "给一年后的我"), ("开启时间", "2027.10.19"), ("内容", "文字 1 · 图片 2 · 语音 1")]
    ry = sy + 112
    for i, (k, v) in enumerate(rows):
        txt(d, 24, ry + 13, k, 11.5, MUTED, bold=True)
        vw = tw(d, v, 14.5, True)
        txt(d, 351 - vw, ry + 11, v, 14.5, INK, bold=True)
        if i < 2:
            hline(d, 24, 351, ry + 44)
        ry += 44

    wy = ry + 14
    rrect(d, (24, wy, 351, wy + 78), 12, fill=WARM_BG, outline=WARM_LN, width=1)
    para(d, 40, wy + 15, ["封存后不可修改、删除，也不能提前打开。在 2027",
                          "年 10 月 19 日之前，它不会以任何方式被看见——包",
                          "括你自己。"], 12, (135, 97, 42), 21)

    btn_primary(d, 24, wy + 94, 327, 50, "确认封存")
    ln = "再想想"
    txt(d, 187.5 - tw(d, ln, 13) / 2, wy + 162, ln, 13, MUTED)
    indicator(d)
    return img


# ============================================================ 06 详情·封存中
def frame06():
    img, d = new_canvas()
    status_bar(d)
    nav_bar(d, "", show_back=True)

    y = 100
    # pill with lock
    s = "已封存 · 还剩 87 天"
    w = tw(d, s, 11.5, True) + 38
    rrect(d, (24, y, 24 + w, y + 24), 12, fill=GSOFT)
    icon_lock(d, 36, y + 12.5, GREEN, 0.52)
    txt(d, 46, y + 6.2, s, 11.5, GREEN, bold=True)

    txt(d, 24, y + 42, "期末结束的那个晚上", 27, INK, bold=True)
    txt(d, 24, y + 84, "封存于 2026.10.19 · 开启于 2027.01.15", 12, MUTED)

    by = y + 122
    rrect(d, (24, by, 351, by + 176), 18, fill=(252, 250, 246))
    dashed_rrect(d, (24, by, 351, by + 176), 18, color=DASH, w=1.5, dash=5, gap=4)
    circle(d, 187.5, by + 46, 26, fill=(239, 234, 225))
    icon_lock(d, 187.5, by + 46, MUTED, 1.35)
    txt(d, 187.5, by + 88, "内容已封存", 15.5, (92, 90, 83), bold=True, anchor="ma")
    for i, ln in enumerate(["到 2027 年 1 月 15 日才会打开", "现在，连你也看不到"]):
        txt(d, 187.5 - tw(d, ln, 12) / 2, by + 116 + i * 22, ln, 12, MUTED)

    cy = by + 200
    txt(d, 24, cy + 6, "87", 40, GREEN, bold=True)
    txt(d, 24 + tw(d, "87", 40, True) + 8, cy + 27, "天后开启", 14, GREEN, bold=True)
    txt(d, 351, cy + 27, "已等待 278 天", 11.5, MUTED2, anchor="ra")
    progress(d, 24, cy + 62, 327, 0.76)

    iy = cy + 92
    hline(d, 24, 351, iy)
    for i, (k, v) in enumerate([("内含", "文字 1 · 图片 2 · 语音 1"),
                                ("提醒", "到期当天通知 · 已在桌面卡片倒计时")]):
        ry = iy + 6 + i * 44
        txt(d, 24, ry + 14, k, 11.5, MUTED, bold=True)
        txt(d, 351, ry + 13, v, 13.5, INK2, anchor="ra")
        if i == 0:
            hline(d, 24, 351, ry + 44)

    for i, ln in enumerate(["封存后无法提前打开。", "那天到了，它会自己来找你。"]):
        txt(d, 187.5 - tw(d, ln, 11.5) / 2, 748 + i * 21, ln, 11.5, MUTED2)
    indicator(d)
    return img


# ============================================================ 07 详情·已开启
def frame07():
    img, d = new_canvas()
    status_bar(d)
    icon_back(d, 24, 57, INK2, 7.4, 1.7)
    txt(d, 38, 49.5, "返回", 15, INK2)
    icon_dots(d, 338, 57)

    y = 100
    s = "已等待 365 天 · 刚刚开启"
    w = tw(d, s, 11.5, True) + 22
    rrect(d, (24, y, 24 + w, y + 24), 12, fill=(237, 243, 240))
    txt(d, 35, y + 6.2, s, 11.5, GREEN, bold=True)

    txt(d, 24, y + 42, "给一年后的我", 27, INK, bold=True)
    txt(d, 24, y + 84, "封存于 2026.10.19 · 开启于 2027.10.19", 12, MUTED)
    hline(d, 24, 351, y + 112)

    para(d, 24, y + 134, ["不知道你现在怎么样了。今天刚开学一个月，我还在",
                          "为要不要转专业这件事纠结。如果你已经决定了，希",
                          "望你不后悔。"], 14.5, (46, 51, 47), 27)

    iy = y + 236
    for i, (c1, c2) in enumerate([((239, 231, 216), (226, 216, 195)), ((231, 235, 229), (213, 219, 211))]):
        bx = 24 + i * 168.5
        rrect(d, (bx, iy, bx + 158.5, iy + 104), 14, fill=c1)
        rrect(d, (bx, iy + 56, bx + 158.5, iy + 104), 14, fill=c2)

    ay = iy + 118
    rrect(d, (24, ay, 351, ay + 58), 16, fill=CARD)
    circle(d, 52, ay + 29, 17, fill=GREEN)
    icon_play(d, 52, ay + 29, WHITE, 0.95)
    waveform(d, 78, ay + 20, 118, 18)
    txt(d, 337, ay + 22, "0:42", 12, MUTED, anchor="ra")
    indicator(d)
    return img


# ============================================================ 08 我的
def frame08():
    img, d = new_canvas()
    status_bar(d)
    txt(d, 24, 62, "我的", 30, INK, bold=True)
    txt(d, 24, 108, "时间胶囊 · 1.0.0", 12.5, MUTED)

    y = 148
    def group_label(t, y):
        txt(d, 28, y, t, 11.5, MUTED, bold=True)

    def row(k, v=None, right=None, y0=y, last=False, h=56):
        txt(d, 42, y0 + 19, k, 14.5, INK2)
        if right == "chev":
            icon_chev(d, 341, y0 + 27, MUTED2, 4.8, 1.6)
        elif right:
            rrect(d, (0, 0, 0, 0), 0, fill=BG)
        if v:
            vw = tw(d, v, 13.5)
            txt(d, 334 - vw, y0 + 20, v, 13.5, MUTED)
        return y0 + h

    def card_box(top, bottom):
        rrect(d, (24, top, 351, bottom), 16, fill=CARD)

    group_label("提醒", y)
    card_box(y + 20, y + 20 + 168)
    ty = y + 20
    txt(d, 42, ty + 19, "到期通知", 14.5, INK2)
    toggle(d, 289, ty + 15, True)
    hline(d, 42, 333, ty + 56)
    txt(d, 42, ty + 75, "通知权限", 14.5, INK2)
    txt(d, 320, ty + 76, "已授权", 13.5, MUTED, anchor="ra")
    icon_chev(d, 341, ty + 83, MUTED2, 4.8, 1.6)
    hline(d, 42, 333, ty + 112)
    txt(d, 42, ty + 131, "桌面服务卡片", 14.5, INK2)
    toggle(d, 289, ty + 127, True)

    y = ty + 168 + 32
    group_label("数据", y)
    card_box(y + 20, y + 20 + 168)
    ty = y + 20
    txt(d, 42, ty + 19, "备份与导出", 14.5, INK2)
    txt(d, 320, ty + 20, "上次 10.19", 13.5, MUTED, anchor="ra")
    icon_chev(d, 341, ty + 27, MUTED2, 4.8, 1.6)
    hline(d, 42, 333, ty + 56)
    txt(d, 42, ty + 75, "存储占用", 14.5, INK2)
    txt(d, 333, ty + 76, "36.4 MB", 13.5, MUTED, anchor="ra")
    hline(d, 42, 333, ty + 112)
    txt(d, 42, ty + 131, "胶囊统计", 14.5, INK2)
    txt(d, 333, ty + 132, "6 个 · 4 个在等", 13.5, MUTED, anchor="ra")

    y = ty + 168 + 32
    group_label("其他", y)
    card_box(y + 20, y + 20 + 112)
    ty = y + 20
    txt(d, 42, ty + 19, "关于时间胶囊", 14.5, INK2)
    icon_chev(d, 341, ty + 27, MUTED2, 4.8, 1.6)
    hline(d, 42, 333, ty + 56)
    txt(d, 42, ty + 75, "意见反馈", 14.5, INK2)
    icon_chev(d, 341, ty + 83, MUTED2, 4.8, 1.6)
    indicator(d)
    return img


# ============================================================ 09 通知与卡片设置
def frame09():
    img, d = new_canvas()
    status_bar(d)
    nav_bar(d, "通知与卡片", show_back=True)

    y = 96
    txt(d, 28, y, "到期通知", 11.5, MUTED, bold=True)
    rrect(d, (24, y + 20, 351, y + 20 + 168), 16, fill=CARD)
    ty = y + 20
    txt(d, 42, ty + 19, "开启到期通知", 14.5, INK2)
    toggle(d, 289, ty + 15, True)
    hline(d, 42, 333, ty + 56)
    txt(d, 42, ty + 75, "系统通知权限", 14.5, INK2)
    txt(d, 333, ty + 76, "已授权", 13.5, GREEN, bold=True, anchor="ra")
    hline(d, 42, 333, ty + 112)
    txt(d, 42, ty + 131, "提醒时间", 14.5, INK2)
    txt(d, 325, ty + 132, "到期当天 09:00", 13.5, MUTED, anchor="ra")
    icon_chev(d, 341, ty + 139, MUTED2, 4.8, 1.6)

    txt(d, 28, ty + 178, "当日提醒只在开启日期当天发送一次，不会重复打扰。", 11.5, MUTED2)

    y = ty + 212
    txt(d, 28, y, "桌面服务卡片", 11.5, MUTED, bold=True)
    rrect(d, (24, y + 20, 351, y + 20 + 112), 16, fill=CARD)
    ty = y + 20
    txt(d, 42, ty + 19, "显示最近一个待开启胶囊", 14.5, INK2)
    toggle(d, 289, ty + 15, True)
    hline(d, 42, 333, ty + 56)
    txt(d, 42, ty + 75, "卡片尺寸", 14.5, INK2)
    txt(d, 325, ty + 76, "2×2 / 4×2", 13.5, MUTED, anchor="ra")
    icon_chev(d, 341, ty + 83, MUTED2, 4.8, 1.6)

    # 预览卡
    py = ty + 132
    rrect(d, (24, py, 351, py + 190), 16, fill=CARD)
    txt(d, 40, py + 16, "卡片预览", 11.5, MUTED, bold=True)
    wp = (40, py + 42, 335, py + 174)
    soft_shadow(wp, 14, blur=10, color=GREEN, alpha=42, dy=4)
    d = ImageDraw.Draw(img)
    rrect_gradient(wp, 14, GREEN, GREEN_D)
    d = ImageDraw.Draw(img)
    txt(d, 56, wp[1] + 16, "距离下一个胶囊开启", 10.5, (196, 214, 208))
    txt(d, 56, wp[1] + 36, "87", 29, WHITE, bold=True)
    txt(d, 56 + tw(d, "87", 29, True) + 4, wp[1] + 52, "天", 13, (214, 226, 221), bold=True)
    txt(d, 56, wp[1] + 78, "期末结束的那个晚上", 12, (226, 236, 232))
    rrect(d, (56, wp[1] + 104, 319, wp[1] + 107), 1.5, fill=(72, 112, 101))
    rrect(d, (56, wp[1] + 104, 56 + 263 * 0.76, wp[1] + 107), 1.5, fill=(232, 240, 236))

    wy = py + 210
    rrect(d, (24, wy, 351, wy + 76), 12, fill=WARM_BG, outline=WARM_LN, width=1)
    para(d, 40, wy + 16, ["如果系统通知权限被拒绝，桌面卡片会继续倒计时——",
                          "这是提醒没送到时的兜底。"], 12, (135, 97, 42), 21)
    indicator(d)
    return img


# ============================================================ 10 备份与导出
def frame10():
    img, d = new_canvas()
    status_bar(d)
    nav_bar(d, "备份与导出", show_back=True)

    y = 96
    rrect(d, (24, y, 351, y + 92), 16, fill=CARD)
    stats = [("6", "胶囊"), ("14", "内容块"), ("36.4", "占用")]
    for i, (v, k) in enumerate(stats):
        cx = 24 + 54.5 + i * 109
        vw = tw(d, v, 23, True)
        if i < 2:
            txt(d, cx - vw / 2, y + 20, v, 23, INK, bold=True)
        else:
            mw = tw(d, "MB", 12, True)
            total = vw + 2 + mw
            txt(d, cx - total / 2, y + 20, v, 23, INK, bold=True)
            txt(d, cx - total / 2 + vw + 2, y + 32, "MB", 12, MUTED, bold=True)
        ln = k
        txt(d, cx - tw(d, ln, 11.5) / 2, y + 58, ln, 11.5, MUTED)
        if i < 2:
            vline(d, 24 + 109 * (i + 1), y + 22, y + 70)

    y += 116
    txt(d, 28, y, "备份", 11.5, MUTED, bold=True)
    rrect(d, (24, y + 20, 351, y + 20 + 112), 16, fill=CARD)
    ty = y + 20
    txt(d, 42, ty + 20, "导出备份文件", 14.5, INK2)
    icon_chev(d, 341, ty + 27, MUTED2, 4.8, 1.6)
    hline(d, 42, 333, ty + 56)
    txt(d, 42, ty + 76, "从备份恢复", 14.5, INK2)
    icon_chev(d, 341, ty + 83, MUTED2, 4.8, 1.6)
    txt(d, 28, ty + 126, "导出后请存到网盘或电脑。换手机时用它把胶囊带过去。", 11.5, MUTED2)

    y = ty + 152
    rrect(d, (24, y, 351, y + 104), 16, fill=CARD)
    txt(d, 40, y + 18, "上次备份", 11.5, MUTED, bold=True)
    txt(d, 335, y + 18, "2026.10.19 21:04", 13, INK2, anchor="ra")
    hline(d, 40, 335, y + 52)
    txt(d, 40, y + 68, "文件大小", 11.5, MUTED, bold=True)
    txt(d, 335, y + 68, "34.8 MB", 13, INK2, anchor="ra")

    btn_primary(d, 24, y + 130, 327, 50, "立即导出备份")

    wy = y + 212
    rrect(d, (24, wy, 351, wy + 96), 12, fill=WARM_BG, outline=WARM_LN, width=1)
    para(d, 40, wy + 17, ["备份中包含已封存内容。请把备份文件保存到你信任的",
                          "位置——胶囊里的东西，只有到那天才该被打开。"], 12, (135, 97, 42), 21)
    indicator(d)
    return img


# ============================================================ 11 关于
def frame11():
    img, d = new_canvas()
    status_bar(d)
    nav_bar(d, "关于", show_back=True)

    soft_shadow((150.5, 122, 224.5, 196), 22, blur=13, color=GREEN, alpha=52, dy=6)
    d = ImageDraw.Draw(img)
    rrect(d, (150.5, 122, 224.5, 196), 22, fill=GREEN)
    dashed_rrect(d, (163, 135, 212, 183), 12.5, color=(225, 233, 229), w=1.4, dash=3.2, gap=3.2)
    circle(d, 187.5, 152, 4.2, fill=(245, 241, 234))
    d.line([px(178), px(168), px(197), px(168)], fill=(245, 241, 234), width=max(1, px(1.6)))

    txt(d, 187.5, 216, "时间胶囊", 19, INK, bold=True, anchor="ma")
    txt(d, 187.5, 250, "版本 1.0.0（build 26）", 12, MUTED, anchor="ma")
    ln = "把话锁进时间里"
    txt(d, 187.5 - tw(d, ln, 13) / 2, 288, ln, 13, INK2)

    y = 348
    rrect(d, (24, y, 351, y + 216), 16, fill=CARD)
    rows = [("隐私政策", "chev"), ("开源许可", "chev"), ("检查更新", "已是最新"), ("评分与反馈", "chev")]
    ry = y
    for i, (k, v) in enumerate(rows):
        txt(d, 42, ry + 19, k, 14.5, INK2)
        if v == "chev":
            icon_chev(d, 341, ry + 27, MUTED2, 4.8, 1.6)
        else:
            txt(d, 333, ry + 20, v, 13.5, MUTED, anchor="ra")
        if i < 3:
            hline(d, 42, 333, ry + 54)
        ry += 54

    for i, ln in enumerate(["所有胶囊仅保存在你的设备上", "不上传，不联网，不分析"]):
        txt(d, 187.5 - tw(d, ln, 11) / 2, 616 + i * 21, ln, 11, MUTED2)
    indicator(d)
    return img


# ============================================================ 12 通知授权引导
def frame12():
    img, d = new_canvas()
    status_bar(d)

    cx = 187.5
    circle(d, cx, 300, 48, fill=GSOFT)
    icon_bell(d, cx, 298, GREEN, 1.55)

    txt(d, cx, 388, "让胶囊", 23, INK, bold=True, anchor="ma")
    txt(d, cx, 424, "准时来找你", 23, INK, bold=True, anchor="ma")
    for i, ln in enumerate(["只有当某天有胶囊到期时，", "才会给你发一条通知。", "其余时间，它一声不响。"]):
        txt(d, cx - tw(d, ln, 13) / 2, 474 + i * 25, ln, 13, MUTED)

    btn_primary(d, 24, 664, 327, 50, "允许通知")
    ln = "暂不开启，用桌面卡片代替"
    txt(d, cx - tw(d, ln, 13) / 2, 736, ln, 13, MUTED)
    indicator(d)
    return img


# ============================================================ 13 到期通知
def frame13():
    img = Image.new("RGB", (W, H), (42, 50, 47)); _CUR["img"] = img
    vertical_gradient(img, (74, 90, 84), (32, 37, 36))
    radial_glow(img, 187.5, 10, 240, 180, (255, 255, 255), 0.10)
    d = ImageDraw.Draw(img)

    status_bar(d, dark=True)
    txt(d, 187.5, 118, "10 月 19 日　星期一", 13, (188, 199, 193), anchor="ma")
    txt(d, 187.5, 146, "9:41", 74, (250, 250, 248), bold=False, anchor="ma")

    # 通知卡
    cy = 300
    soft_shadow((16, cy, 359, cy + 132), 20, blur=18, color=(0, 0, 0), alpha=110, dy=8)
    d = ImageDraw.Draw(img)
    rrect(d, (16, cy, 359, cy + 132), 20, fill=(252, 250, 246))
    rrect(d, (30, cy + 14, 52, cy + 36), 6, fill=GREEN)
    dashed_rrect(d, (35, cy + 19, 47, cy + 31), 6, color=(235, 242, 238), w=1, dash=2, gap=1.8)
    txt(d, 60, cy + 17, "时间胶囊", 12, (62, 68, 63), bold=True)
    txt(d, 345, cy + 18, "现在", 11, (154, 150, 140), anchor="ra")
    txt(d, 30, cy + 50, "「给一年后的我」可以打开了", 15.5, INK, bold=True)
    txt(d, 30, cy + 80, "它等了你 365 天。点击查看。", 13, (90, 96, 91))

    cy2 = cy + 148
    rrect(d, (16, cy2, 359, cy2 + 62), 20, fill=(236, 236, 231))
    circle(d, 41, cy2 + 25, 11, fill=(160, 160, 154))
    txt(d, 60, cy2 + 17, "其他通知", 12, (62, 68, 63), bold=True)
    txt(d, 345, cy2 + 18, "8:12", 11, (154, 150, 140), anchor="ra")

    indicator(d, dark=True)
    return img


# ============================================================ 14 桌面服务卡片
def frame14():
    img = Image.new("RGB", (W, H), (200, 210, 203)); _CUR["img"] = img
    vertical_gradient(img, (220, 228, 221), (175, 189, 180))
    radial_glow(img, 60, 40, 260, 200, (255, 255, 255), 0.45)
    d = ImageDraw.Draw(img)
    status_bar(d)

    txt(d, 24, 62, "桌面 · 服务卡片", 12, (91, 107, 98), bold=True)

    # 4x2 卡片
    wy = 92
    soft_shadow((18, wy, 357, wy + 176), 22, blur=16, color=(30, 60, 52), alpha=70, dy=8)
    d = ImageDraw.Draw(img)
    rrect_gradient((18, wy, 357, wy + 176), 22, GREEN, GREEN_D)
    d = ImageDraw.Draw(img)

    txt(d, 38, wy + 22, "距离下一个胶囊开启", 10.5, (188, 208, 201))
    txt(d, 38, wy + 46, "87", 42, WHITE, bold=True)
    txt(d, 38 + tw(d, "87", 42, True) + 7, wy + 68, "天", 15, (216, 228, 223), bold=True)
    rrect(d, (309, wy + 20, 339, wy + 50), 9, fill=(60, 116, 104))
    dashed_rrect(d, (317, wy + 27, 331, wy + 43), 7, color=(226, 235, 231), w=1.1, dash=2.2, gap=2)

    txt(d, 38, wy + 108, "期末结束的那个晚上", 12.5, (228, 238, 234))
    rrect(d, 0, 0, 0, 0, 0, fill=None) if False else None
    rrect(d, (38, wy + 134, 337, wy + 137), 1.5, fill=(76, 118, 107))
    rrect(d, (38, wy + 134, 38 + 299 * 0.76, wy + 137), 1.5, fill=(236, 242, 239))
    txt(d, 38, wy + 148, "2026.10.19 封存", 9.5, (150, 176, 167))
    txt(d, 337, wy + 148, "2027.01.15 开启", 9.5, (150, 176, 167), anchor="ra")

    # 2x2 卡片
    cy = wy + 194
    for i, (label, big, sub, fillc, tcol) in enumerate([
        ("下一个胶囊", "87", "天后开启", (252, 250, 246), GREEN),
        ("在时间里等着", "4", "个胶囊", (232, 236, 231), (62, 74, 68))]):
        bx = 18 + i * 174
        soft_shadow((bx, cy, bx + 165, cy + 150), 22, blur=12, color=(30, 60, 52), alpha=45, dy=6)
        d = ImageDraw.Draw(img)
        rrect(d, (bx, cy, bx + 165, cy + 150), 22, fill=fillc)
        txt(d, bx + 18, cy + 18, label, 10, (124, 138, 130), bold=True)
        txt(d, bx + 18, cy + 44, big, 34, tcol, bold=True)
        txt(d, bx + 18, cy + 92, sub, 11, (91, 107, 98))

    # dock
    dy = 690
    rrect(d, (18, dy, 357, dy + 76), 26, fill=(246, 246, 242))
    for i in range(4):
        bx = 34 + i * 78
        if i == 3:
            rrect(d, (bx, dy + 14, bx + 48, dy + 62), 14, fill=GREEN)
            dashed_rrect(d, (bx + 15, dy + 25, bx + 33, dy + 51), 9, color=(240, 245, 242), w=1.1, dash=2.4, gap=2.2)
        else:
            rrect(d, (bx, dy + 14, bx + 48, dy + 62), 14, fill=(214, 220, 214))
    indicator(d, dark=True)
    return img


# ============================================================ 导出
FRAMES = [
    ("01", "首页 · 胶囊架", frame01),
    ("02", "首页 · 空状态", frame02),
    ("03", "约定时间 · 初始", lambda: editor_frame(True)),
    ("04", "约定时间 · 编辑中", lambda: editor_frame(False)),
    ("05", "封存确认", frame05),
    ("06", "胶囊详情 · 封存中", frame06),
    ("07", "胶囊详情 · 已开启", frame07),
    ("08", "我的", frame08),
    ("09", "通知与卡片设置", frame09),
    ("10", "备份与导出", frame10),
    ("11", "关于", frame11),
    ("12", "通知授权引导", frame12),
    ("13", "到期通知（系统）", frame13),
    ("14", "桌面服务卡片", frame14),
]

if __name__ == "__main__":
    import sys
    only = sys.argv[1:] if len(sys.argv) > 1 else None
    for num, name, fn in FRAMES:
        if only and num not in only:
            continue
        img = fn()
        img = img.resize((OUTW, OUTH), Image.LANCZOS)
        p = os.path.join(OUT, f"{num}.png")
        img.save(p, "PNG")
        print("OK", p, name)










