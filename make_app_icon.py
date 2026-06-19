#!/usr/bin/env python3
"""Generate the Plaino app icon (1024x1024, no alpha) into the asset catalog.

Recreates the "big middle" mark from the brand sheet: three left-aligned,
fully-rounded horizontal bars of decreasing width on a cream background —
terracotta, warm taupe, soft gray. Run:  python3 make_app_icon.py

This is an approximation of the brand mark. For a pixel-perfect icon, export a
1024x1024 PNG from your design tool and drop it in as icon-1024.png instead.
"""
from PIL import Image, ImageDraw
import os

N = 1024
CREAM      = (247, 245, 241)   # #F7F5F1 background
TERRACOTTA = (199,  91,  70)   # #C75B46 top bar
TAUPE      = (142, 131, 118)   # #8E8376 middle bar
SOFT_GRAY  = (207, 200, 190)   # #CFC8BE bottom bar

img = Image.new("RGB", (N, N), CREAM)   # RGB = no alpha (App Store requirement)
d = ImageDraw.Draw(img)

bar_h = 160
gap = 80
left = 272
widths = [480, 370, 260]                # decreasing, left-aligned
colors = [TERRACOTTA, TAUPE, SOFT_GRAY]

total_h = len(widths) * bar_h + (len(widths) - 1) * gap
y = (N - total_h) // 2
for w, c in zip(widths, colors):
    d.rounded_rectangle([left, y, left + w, y + bar_h], radius=bar_h // 2, fill=c)
    y += bar_h + gap

out = os.path.join(os.path.dirname(__file__),
                   "Notie/Notie/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
img.save(out, "PNG")
print("Wrote", out, img.size, img.mode)
