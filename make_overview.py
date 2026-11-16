# -*- coding: utf-8 -*-
"""把 14 张原型拼成一张总览图（含标题栏），并生成索引 HTML。"""
import os
from PIL import Image, ImageDraw, ImageFont

SRC = r"D:\time-capsule\prototypes"
OUT = r"D:\time-capsule\prototypes"

FONT_R = r"C:\Windows\Fonts\msyh.ttc"
FONT_B = r"C:\Windows\Fonts\msyhbd.ttc"

BG = (238, 234, 226)
INK = (30, 36, 32)
MUTED = (140, 138, 130)
GREEN = (44, 95, 85)

FILES = [
    ("01", "首页 · 胶囊架", "首页 / P1"),
    ("02", "首页 · 空状态", "首页 / P1"),
    ("03", "约定时间 · 初始", "新建 / P2"),
    ("04", "约定时间 · 编辑中", "新建 / P2"),
    ("05", "封存确认", "封存 / P3"),
    ("06", "详情 · 封存中", "详情 / P4"),
    ("07", "详情 · 已开启", "详情 / P5"),
    ("08", "我的", "我的 / P6"),
    ("09", "通知与卡片", "我的 / P6·1"),
    ("10", "备份与导出", "我的 / P6·2"),
    ("11", "关于", "我的 / P6·3"),
    ("12", "通知授权引导", "首次进入"),
    ("13", "到期通知", "外部入口"),
    ("14", "桌面服务卡片", "外部入口"),
]

COLS = 5
TW, TH = 537, 1163
SC = 0.52
pw, ph = int(TW * SC), int(TH * SC)      # 279 x 604
GAPX, GAPY = 30, 62
PADX, PADY = 56, 44
HEAD = 150

rows = (len(FILES) + COLS - 1) // COLS
W = PADX * 2 + COLS * pw + (COLS - 1) * GAPX
H = HEAD + PADY + rows * (ph + GAPY) + 60

canvas = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(canvas)

f_title = ImageFont.truetype(FONT_B, 40)
f_sub = ImageFont.truetype(FONT_R, 21)
f_cap = ImageFont.truetype(FONT_B, 20)
f_tag = ImageFont.truetype(FONT_R, 15)

d.text((PADX, 44), "时间胶囊 · 全页面原型", font=f_title, fill=INK)
d.text((PADX, 98), "14 个画面 · 375×812 · 鸿蒙原生 · 设计令牌与原文档一致", font=f_sub, fill=MUTED)

# 顶部细线
d.line([(PADX, HEAD - 14), (W - PADX, HEAD - 14)], fill=(214, 208, 197), width=1)

for i, (num, name, tag) in enumerate(FILES):
    r, c = divmod(i, COLS)
    x = PADX + c * (pw + GAPX)
    y = HEAD + PADY + r * (ph + GAPY)

    # 阴影
    d.rounded_rectangle([x + 5, y + 8, x + pw + 5, y + ph + 8], radius=18, fill=(224, 219, 209))
    im = Image.open(os.path.join(SRC, f"{num}.png")).convert("RGB").resize((pw, ph), Image.LANCZOS)
    mask = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, pw - 1, ph - 1], radius=18, fill=255)
    canvas.paste(im, (x, y), mask)
    d.rounded_rectangle([x, y, x + pw, y + ph], radius=18, outline=(214, 208, 198), width=1)

    # 序号徽标
    d.rounded_rectangle([x + 12, y + 12, x + 46, y + 38], radius=8, fill=(255, 255, 255))
    d.text((x + 20, y + 16), num, font=ImageFont.truetype(FONT_B, 16), fill=GREEN)

    # 说明
    d.text((x, y + ph + 16), name, font=f_cap, fill=INK)
    d.text((x, y + ph + 42), tag, font=f_tag, fill=MUTED)

out = os.path.join(OUT, "overview.png")
canvas.save(out, "PNG")
print("OK", out, canvas.size)

