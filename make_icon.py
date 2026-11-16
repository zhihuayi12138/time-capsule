"""生成应用图标：分层图标 background/foreground + 启动图标 startIcon + 单层兜底 app_icon。

设计令牌与原型一致：主色 #2C5F55，暖白 #FDF6E8，暖线 #EAD9B4。
    python make_icon.py
"""
from PIL import Image, ImageDraw, ImageFilter

GREEN = (44, 95, 85)
GREEN_L = (58, 116, 104)
GREEN_HI = (66, 128, 115)
CREAM = (253, 246, 232)
WARM = (234, 217, 180)


def _ss(size):
    """超采样倍率：大图降倍，避免内存爆掉。"""
    if size >= 1024:
        return 2
    if size >= 432:
        return 3
    return 4


def pill(px, body_color, seam_color, hi_alpha=55, w_ratio=0.42, h_ratio=0.86):
    """在 px×px 画布上画竖向药丸（时间胶囊）。返回该分辨率的 RGBA 图。"""
    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    w = px * w_ratio
    h = px * h_ratio
    x0 = (px - w) / 2
    y0 = (px - h) / 2
    x1 = x0 + w
    y1 = y0 + h
    r = w / 2

    d.rounded_rectangle([x0, y0, x1, y1], radius=r, fill=body_color + (255,))

    # 中缝：横贯胶囊，两端各补一个半圆，视觉上是两段对齐的壳
    sy = y0 + h * 0.42
    th = max(2.0, w * 0.085)
    d.rectangle([x0, sy - th / 2, x1, sy + th / 2], fill=seam_color + (255,))
    d.ellipse([x0 - th / 2, sy - th / 2, x0 + th / 2, sy + th / 2], fill=seam_color + (255,))
    d.ellipse([x1 - th / 2, sy - th / 2, x1 + th / 2, sy + th / 2], fill=seam_color + (255,))

    # 左上半高光
    if hi_alpha:
        gl = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        gd = ImageDraw.Draw(gl)
        gd.rounded_rectangle(
            [x0 + w * 0.17, y0 + h * 0.12, x0 + w * 0.33, y0 + h * 0.32],
            radius=w * 0.08, fill=(255, 255, 255, hi_alpha))
        img = Image.alpha_composite(img, gl)

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
    """分层图标底层：主色径向渐变（不透明）。"""
    px = size * _ss(size)
    img = Image.new("RGB", (px, px), GREEN)
    d = ImageDraw.Draw(img)
    d.ellipse([-px * 0.35, -px * 0.40, px * 1.35, px * 1.10], fill=GREEN_HI)
    d.ellipse([px * 0.10, px * 0.06, px * 0.90, px * 0.86], fill=GREEN_L)
    img = img.filter(ImageFilter.GaussianBlur(px * 0.09))
    return img.resize((size, size), Image.LANCZOS).convert("RGB")


def make_foreground(size=1024):
    """分层图标顶层：暖白胶囊，压在 58% 安全区内，背景全透明。"""
    px = size * _ss(size)
    inner = int(px * 0.58)
    art = pill(inner, CREAM, GREEN, hi_alpha=95)
    canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    canvas.paste(art, ((px - inner) // 2, (px - inner) // 2), art)
    return canvas.resize((size, size), Image.LANCZOS)


def make_start_icon(size=432):
    """启动图标：暖白圆角底 + 主色胶囊。"""
    ss = _ss(size)
    px = size * ss
    canvas = Image.new("RGBA", (px, px), CREAM + (255,))
    art = pill(int(px * 0.80), GREEN, CREAM, hi_alpha=45)
    off = (px - int(px * 0.80)) // 2
    canvas.paste(art, (off, off), art)
    canvas.info["ss"] = ss
    return rounded(canvas, 0.22)


def make_launcher_icon(size=1024):
    """单层兜底图标（app_icon）：暖白圆角底 + 主色胶囊。"""
    ss = _ss(size)
    px = size * ss
    canvas = Image.new("RGBA", (px, px), CREAM + (255,))
    art = pill(int(px * 0.80), GREEN, CREAM, hi_alpha=45)
    off = (px - int(px * 0.80)) // 2
    canvas.paste(art, (off, off), art)
    canvas.info["ss"] = ss
    return rounded(canvas, 0.22)


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
