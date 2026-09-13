"""Regenerate the Android and iOS app icons from icon.png.

The source is a square artwork (a rounded-square photo sitting on a cream
background). Run after changing icon.png:

    python3 -m venv /tmp/iconenv && /tmp/iconenv/bin/pip install Pillow
    /tmp/iconenv/bin/python tool/generate_icons.py

Pillow is only needed for this script, so it is deliberately not a project
dependency.
"""

import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android/app/src/main/res")
IOS = os.path.join(ROOT, "ios/Runner/Assets.xcassets/AppIcon.appiconset")

CREAM = (251, 249, 243)        # sampled from the artwork's own border
CORNER = 0.26                  # artwork's corner radius, as a fraction of its side
BUCKETS = {                    # density: (legacy icon px, adaptive foreground px)
    "mdpi": (48, 108),
    "hdpi": (72, 162),
    "xhdpi": (96, 216),
    "xxhdpi": (144, 324),
    "xxxhdpi": (192, 432),
}
IOS_SIZES = {
    "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40, "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29, "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80, "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120, "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76, "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}


def trimmed_artwork(path, size=1024):
    """Crop the artwork away from its cream margin and square it up."""
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    bg = px[0, 0]

    def is_art(c, tol=26):
        return any(abs(a - b) > tol for a, b in zip(c, bg))

    minx, miny, maxx, maxy = w, h, 0, 0
    for y in range(h):
        for x in range(w):
            if is_art(px[x, y]):
                minx, maxx = min(minx, x), max(maxx, x)
                miny, maxy = min(miny, y), max(maxy, y)
    cx, cy = (minx + maxx) // 2, (miny + maxy) // 2
    half = max(maxx - minx + 1, maxy - miny + 1) // 2
    return im.crop((cx - half, cy - half, cx + half, cy + half)).resize(
        (size, size), Image.LANCZOS)


def masked(img, shape):
    s = img.size[0]
    mask = Image.new("L", (s, s), 0)
    draw = ImageDraw.Draw(mask)
    if shape == "circle":
        draw.ellipse([0, 0, s - 1, s - 1], fill=255)
    else:
        draw.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * CORNER), fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def max_safe_scale():
    """Largest foreground scale whose rounded corners stay inside a circular mask.

    The adaptive canvas is 108dp and a circular mask is inscribed in it, so the
    artwork's farthest point must stay within radius 54.
    """
    best = 0.70
    for step in range(700, 900):
        scale = step / 1000
        side = scale * 108
        reach = math.sqrt(2) * (side / 2 - CORNER * side) + CORNER * side
        if reach > 54:
            break
        best = scale
    return round(best - 0.005, 3)


def main():
    art = trimmed_artwork(os.path.join(ROOT, "icon.png"))
    art_rounded = masked(art, "rounded")
    art_circle = masked(art, "circle")
    fg_scale = max_safe_scale()
    print(f"foreground scale: {fg_scale}")

    for bucket, (legacy, fg) in BUCKETS.items():
        d = os.path.join(RES, f"mipmap-{bucket}")
        os.makedirs(d, exist_ok=True)
        art_rounded.resize((legacy, legacy), Image.LANCZOS).save(
            os.path.join(d, "ic_launcher.png"))
        art_circle.resize((legacy, legacy), Image.LANCZOS).save(
            os.path.join(d, "ic_launcher_round.png"))
        canvas = Image.new("RGBA", (fg, fg), (0, 0, 0, 0))
        inner = int(fg * fg_scale)
        scaled = art_rounded.resize((inner, inner), Image.LANCZOS)
        canvas.paste(scaled, ((fg - inner) // 2, (fg - inner) // 2), scaled)
        canvas.save(os.path.join(d, "ic_launcher_foreground.png"))
        print(f"  android {bucket}: {legacy}px / {fg}px")

    # iOS rounds icons itself and rejects alpha, so fill the corners with a
    # zoomed copy rather than cream — otherwise its mask clips into the border.
    s = art.size[0]
    big = art.resize((int(s * 1.30), int(s * 1.30)), Image.LANCZOS)
    o = (big.size[0] - s) // 2
    base = big.crop((o, o, o + s, o + s))
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1],
                                           radius=int(s * CORNER), fill=255)
    base.paste(art, (0, 0), mask)
    base = base.convert("RGB")
    for name, px in IOS_SIZES.items():
        base.resize((px, px), Image.LANCZOS).save(os.path.join(IOS, name))
    print(f"  ios: {len(IOS_SIZES)} icons")


if __name__ == "__main__":
    main()
