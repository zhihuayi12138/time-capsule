"""生成应用图标：分层图标 background/foreground + 启动图标 startIcon + 单层兜底 app_icon。

统一视觉：主色圆角方块底 + 暖白虚线胶囊轮廓。
虚线是有意的——它表示"一个还没打开的东西"，与产品里「内容已封存」的虚线卡同源。

    python make_icon.py
"""
import math
from PIL import Image, ImageDraw, ImageFilter

GREEN = (44, 95, 85)
GREEN_D = (31, 64, 57)
CREAM = (253, 246, 232)


def _ss(size):
    """超采样倍率：大图降倍，避免内存爆掉。"""
    if size >= 1024:
        return 2
    if size >= 432:
        return 3
    return 4


def _capsule_outline(cx, cy, w, h, steps=72):
    """竖向胶囊的闭合轮廓：上下两个半圆 + 左右两条竖边。

    竖胶囊的圆角半径等于半宽，所以上下是半圆、左右是直边。
    之前把圆心错放在左右两侧，画出来是个带折角的怪形状——圆心必须在上下。
    """
    r = w / 2.0
    y_top = cy - h / 2.0 + r      # 上半圆的圆心 y
    y_bot = cy + h / 2.0 - r      # 下半圆的圆心 y
    pts = []
    # 上半圆：180° -> 360°，左 -> 上 -> 右
    for i in range(steps + 1):
        a = math.pi + math.pi * i / steps
        pts.append((cx + r * math.cos(a), y_top + r * math.sin(a)))
    # 右竖边：从 (x1, y_top) 下行到 (x1, y_bot)
    for i in range(1, steps + 1):
        pts.append((cx + r, y_top + (y_bot - y_top) * i / steps))
    # 下半圆：0° -> 180°，右 -> 下 -> 左
    for i in range(1, steps + 1):
        a = math.pi * i / steps
        pts.append((cx + r * math.cos(a), y_bot + r * math.sin(a)))
    # 左竖边：从 (x0, y_bot) 上行回 (x0, y_top)
    for i in range(1, steps + 1):
        pts.append((cx - r, y_bot - (y_bot - y_top) * i / steps))
    return pts


def _dash_polyline(d, pts, color, sw, dash, gap):
    """沿折线按弧长交替画 dash / gap。

    remain 跨线段连续递减，这样虚线在拐角处不会重新起算、出现一长一短。
    端点不补圆帽——线宽本身已经把短线撑成一块，再补圆帽会把 gap 吃掉，
    整圈就糊成实线（第一版就是这么翻车的）。
    """
    on = True
    remain = dash
    prev = pts[0]
    for cur in pts[1:]:
        dx = cur[0] - prev[0]
        dy = cur[1] - prev[1]
        seg = math.hypot(dx, dy)
        if seg <= 0:
            continue
        t = 0.0
        while t < seg - 1e-9:
            take = min(remain, seg - t)
            if on:
                a = (prev[0] + dx * (t / seg), prev[1] + dy * (t / seg))
                b = (prev[0] + dx * ((t + take) / seg), prev[1] + dy * ((t + take) / seg))
                d.line([a, b], fill=color + (255,), width=int(round(sw)))
            t += take
            remain -= take
            if remain <= 1e-9:
                on = not on
                remain = dash if on else gap
        prev = cur


def dashed_pill(px, color, stroke_ratio=0.082, w_ratio=0.40, h_ratio=0.62,
                dash_ratio=0.135, gap_ratio=0.078):
    """画虚线胶囊轮廓。px 是画布边长，返回 RGBA 图层。

    dash 必须明显长于线宽（这里约 1.6 倍），否则每段虚线比它自己还粗，
    连起来就是一整圈实线。
    """
    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    w = px * w_ratio
    h = px * h_ratio
    sw = max(1.0, w * stroke_ratio)
    dash = max(1.0, w * dash_ratio)
    gap = max(1.0, w * gap_ratio)

    pts = _capsule_outline(px / 2.0, px / 2.0, w, h)
    _dash_polyline(d, pts, color, sw, dash, gap)
    return img


def rounded(canvas, radius_ratio):
    """把超采样画布裁成圆角，再降采样到 1/SS 尺寸。"""
    px = canvas.size[0]
    ss = canvas.info.get("ss", 1)
    mask = Image.new("L", (px, px), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, px - 1, px - 1],
                                           radius=int(px * radius_ratio), fill=255)
    canvas.putalpha(mask)
    return canvas.resize((px // ss, px // ss), Image.LANCZOS)


def make_background(size=1024):
    """分层图标底层：主色方块（不透明）。

    分层图标由系统裁圆角，所以这里必须是满幅方形——自己裁圆角会露出白边。
    渐变只做很轻的一点，避免在不同桌面壁纸上显得脏。
    """
    px = size * _ss(size)
    img = Image.new("RGB", (px, px), GREEN)
    d = ImageDraw.Draw(img)
    d.ellipse([-px * 0.30, -px * 0.35, px * 1.30, px * 1.05], fill=(52, 106, 94))
    d.ellipse([px * 0.16, px * 0.12, px * 0.94, px * 0.90], fill=GREEN)
    img = img.filter(ImageFilter.GaussianBlur(px * 0.08))
    return img.resize((size, size), Image.LANCZOS).convert("RGB")


def make_foreground(size=1024):
    """分层图标顶层：暖白虚线胶囊，压在 60% 安全区内，背景全透明。"""
    px = size * _ss(size)
    # 70% 画布 + 内部图形自身占比，合成后落在安全区内
    inner = int(px * 0.70)
    art = dashed_pill(inner, CREAM, stroke_ratio=0.085, w_ratio=0.56, h_ratio=0.88)
    canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    canvas.paste(art, ((px - inner) // 2, (px - inner) // 2), art)
    return canvas.resize((size, size), Image.LANCZOS)


def _flat_icon(size, radius_ratio):
    """单层图标：主色圆角方块 + 暖白虚线胶囊，圆角自己裁。"""
    ss = _ss(size)
    px = size * ss
    canvas = Image.new("RGBA", (px, px), GREEN + (255,))
    # 轻微径向提亮，让方块不显得死板
    glow = Image.new("L", (px, px), 0)
    ImageDraw.Draw(glow).ellipse([px * 0.02, px * 0.0, px * 0.98, px * 0.96], fill=26)
    tint = Image.new("RGBA", (px, px), (66, 128, 115, 255))
    canvas = Image.composite(tint, canvas, glow.filter(ImageFilter.GaussianBlur(px * 0.10)))

    art = dashed_pill(px, CREAM, stroke_ratio=0.082, w_ratio=0.40, h_ratio=0.62)
    canvas = Image.alpha_composite(canvas, art)
    canvas.info["ss"] = ss
    return rounded(canvas, radius_ratio)


def make_start_icon(size=432):
    """启动图标：主色圆角方块 + 暖白虚线胶囊。"""
    return _flat_icon(size, 0.23)


def make_launcher_icon(size=1024):
    """单层兜底图标（app_icon）。"""
    return _flat_icon(size, 0.23)


if __name__ == "__main__":
    import os

    app_media = os.path.join("AppScope", "resources", "base", "media")
    entry_media = os.path.join("entry", "src", "main", "resources", "base", "media")
    for p in (app_media, entry_media):
        os.makedirs(p, exist_ok=True)

    bg = make_background()
    fg = make_foreground()
    si = make_start_icon()

    bg.save(os.path.join(app_media, "background.png"))
    fg.save(os.path.join(app_media, "foreground.png"))
    si.save(os.path.join(app_media, "startIcon.png"))

    bg.save(os.path.join(entry_media, "background.png"))
    fg.save(os.path.join(entry_media, "foreground.png"))
    si.save(os.path.join(entry_media, "startIcon.png"))

    make_launcher_icon().save(os.path.join(app_media, "app_icon.png"))
    print("icons written")
