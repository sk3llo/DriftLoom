#!/usr/bin/env python3
"""Generates every DriftLoom icon asset from one geometry. Run from the repo root on macOS:
    python3 branding/generate.py
Rasterizes with qlmanage (WebKit) and resizes with sips. qlmanage draws transparency as white, so shapes that
need transparent corners are cut out with a separately rendered black-on-white mask, using Pillow."""
import json, os, shutil, subprocess, tempfile

# Brand colours. The icon background is the app's main colour (toolbar); stripes are the accent.
BG_TOP, BG_BOTTOM = "#1F1650", "#3B1F70"   # icon gradient; app bar: light #2E1C66, dark #1F1650
STRIPE_LEFT, STRIPE_RIGHT = "#FF8A5B", "#FFC857"

# Play triangle with rounded corners, in a 1024 canvas, built from horizontal "weft" stripes.
TRIANGLE = "M360,250 Q360,206 400,228 L800,470 Q838,512 800,554 L400,796 Q360,818 360,774 Z"
def stripes(count=7, pitch=92, height=56):
    first = 512 - pitch * (count - 1) / 2
    return [(first + pitch * k - height / 2, height) for k in range(count)]
def stripe_path(count=7, pitch=92, height=56):
    return "".join(f"M300,{y:g}h540v{h:g}h-540Z" for y, h in stripes(count, pitch, height))

ROOT = os.getcwd()
RES = os.path.join(ROOT, "app/src/main/res")
IOS = os.path.join(ROOT, "iosApp/iosApp/Assets.xcassets/AppIcon.appiconset")
FASTLANE = os.path.join(ROOT, "fastlane/metadata/android/en-US/images")
TMP = tempfile.mkdtemp()

def svg_icon(shape="square", size=1024):
    clip = {"square": f'<rect width="1024" height="1024"/>',
            "circle": '<circle cx="512" cy="512" r="512"/>'}[shape]
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 1024 1024">
<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{BG_TOP}"/><stop offset="1" stop-color="{BG_BOTTOM}"/></linearGradient>
<linearGradient id="st" x1="360" y1="0" x2="838" y2="0" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="{STRIPE_LEFT}"/><stop offset="1" stop-color="{STRIPE_RIGHT}"/></linearGradient>
<clipPath id="shape">{clip}</clipPath><clipPath id="tri"><path d="{TRIANGLE}"/></clipPath></defs>
<g clip-path="url(#shape)"><rect width="1024" height="1024" fill="url(#bg)"/>
<path clip-path="url(#tri)" fill="url(#st)" d="{stripe_path()}"/></g></svg>'''

def feature_graphic():
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{BG_TOP}"/><stop offset="1" stop-color="{BG_BOTTOM}"/></linearGradient>
<linearGradient id="st" x1="360" y1="0" x2="838" y2="0" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="{STRIPE_LEFT}"/><stop offset="1" stop-color="{STRIPE_RIGHT}"/></linearGradient>
<clipPath id="tri"><path d="{TRIANGLE}"/></clipPath></defs>
<g transform="translate(0,262)"><rect width="1024" height="500" fill="url(#bg)"/>
<g transform="translate(-20,26) scale(0.44)"><path clip-path="url(#tri)" fill="url(#st)" d="{stripe_path()}"/></g>
<text x="370" y="258" font-family="Helvetica Neue, Helvetica, Arial" font-weight="700" font-size="112" fill="#FFFFFF">DriftLoom</text>
<text x="374" y="330" font-family="Helvetica Neue, Helvetica, Arial" font-size="34" fill="#FFD9C2">No ads. No tracking. No account.</text></g>
</svg>'''

def render(svg, out, size, opaque=False, height=None):
    src = os.path.join(TMP, "in.svg")
    open(src, "w").write(svg)
    subprocess.run(["qlmanage", "-t", "-s", "1024", "-o", TMP, src], check=True, capture_output=True)
    png = src + ".png"
    if height:  # the SVG is a square with the banner centred; keep that band of the requested height.
        subprocess.run(["sips", "--cropToHeightWidth", str(height), "1024", png, "--out", png], check=True, capture_output=True)
    if opaque:  # App icons must not have an alpha channel: round-trip through JPEG at top quality.
        jpg = os.path.join(TMP, "flat.jpg")
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "100", png, "--out", jpg], check=True, capture_output=True)
        subprocess.run(["sips", "-s", "format", "png", jpg, "--out", png], check=True, capture_output=True)
    if size and size != 1024:
        subprocess.run(["sips", "-Z", str(size), png, "--out", out], check=True, capture_output=True)
    else:
        shutil.copy(png, out)

def render_masked(color_svg, mask_svg, out, size):
    """Renders color_svg and uses mask_svg (black shape on white) as its alpha channel."""
    from PIL import Image, ImageOps
    color_png, mask_png = os.path.join(TMP, "color.png"), os.path.join(TMP, "mask.png")
    render(color_svg, color_png, 1024)
    render(mask_svg, mask_png, 1024)
    image = Image.open(color_png).convert("RGB")
    alpha = ImageOps.invert(Image.open(mask_png).convert("L"))
    image.putalpha(alpha)
    image.resize((size, size), Image.LANCZOS).save(out, optimize=True)

def svg_shape(inner):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<rect width="1024" height="1024" fill="#FFFFFF"/>{inner}</svg>'''

def vector(width_dp, viewport, body, extra_ns=False):
    ns = ' xmlns:aapt="http://schemas.android.com/aapt"' if extra_ns else ""
    return f'''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by branding/generate.py; edit that script instead. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"{ns}
    android:width="{width_dp}dp"
    android:height="{width_dp}dp"
    android:viewportWidth="{viewport}"
    android:viewportHeight="{viewport}">
{body}
</vector>
'''

def mark_group(scale, center, fill, count=7, pitch=92, height=56, ns_gradient=False):
    tx, ty = center - 520 * scale, center - 512 * scale
    if ns_gradient:
        fill_attr = f'''>
            <aapt:attr name="android:fillColor">
                <gradient android:type="linear" android:startX="360" android:startY="0" android:endX="838" android:endY="0"
                    android:startColor="{STRIPE_LEFT}" android:endColor="{STRIPE_RIGHT}" />
            </aapt:attr>
        </path>'''
    else:
        fill_attr = f' android:fillColor="{fill}" />'
    return f'''    <group android:scaleX="{scale:.5f}" android:scaleY="{scale:.5f}" android:translateX="{tx:.3f}" android:translateY="{ty:.3f}">
        <clip-path android:pathData="{TRIANGLE}" />
        <path android:pathData="{stripe_path(count, pitch, height)}"{fill_attr}
    </group>'''

def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(text)

# --- Android -----------------------------------------------------------------------------
# Adaptive icon (API 26+): 108dp canvas, the mark kept inside the 66dp safe zone.
write(f"{RES}/drawable/ic_launcher_background.xml", vector(108, 108, f'''    <path android:pathData="M0,0h108v108h-108z">
        <aapt:attr name="android:fillColor">
            <gradient android:type="linear" android:startX="0" android:startY="0" android:endX="108" android:endY="108"
                android:startColor="{BG_TOP}" android:endColor="{BG_BOTTOM}" />
        </aapt:attr>
    </path>''', extra_ns=True))
write(f"{RES}/drawable/ic_launcher_foreground.xml", vector(108, 108, mark_group(0.085, 54, None, ns_gradient=True), extra_ns=True))
write(f"{RES}/drawable/ic_launcher_monochrome.xml", vector(108, 108, mark_group(0.085, 54, "#FFFFFFFF")))
write(f"{RES}/mipmap-anydpi-v26/ic_launcher.xml", '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
''')
# Notification and splash mark: fewer, thicker stripes so it stays legible at 24dp.
write(f"{RES}/drawable/ic_driftloom_triangle_white.xml", vector(24, 24, mark_group(0.0215, 12, "#FFFFFFFF", count=5, pitch=124, height=84)))
write(f"{RES}/drawable/splash_foreground.xml", vector(100, 100, mark_group(0.08, 50, "#FFFFFFFF")))
for density in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
    for name in ("ic_driftloom_triangle_white.png", "ic_driftloom_update.png"):
        p = f"{RES}/drawable-{density}/{name}"
        if os.path.exists(p) and name.startswith("ic_driftloom_triangle"):
            os.remove(p)
    fg = f"{RES}/mipmap-{density}/ic_launcher_foreground.png"
    if os.path.exists(fg):
        os.remove(fg)
# Legacy launcher icons (API 23-25): round, like the previous ones.
for density, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
    render_masked(svg_icon("square"), svg_shape('<circle cx="512" cy="512" r="512" fill="#000000"/>'),
                  f"{RES}/mipmap-{density}/ic_launcher.png", px)

# --- iOS -------------------------------------------------------------------------------------
contents = json.load(open(f"{IOS}/Contents.json"))
for name in sorted({i["filename"] for i in contents["images"] if "filename" in i}):
    px = int(name.rsplit("-", 1)[1].split(".")[0])
    render(svg_icon("square"), f"{IOS}/{name}", px, opaque=True)

# The white mark used in the iOS menu header (template image, 28pt).
MARK_SHAPE = f'<defs><clipPath id="tri"><path d="{TRIANGLE}"/></clipPath></defs><g transform="translate(-8,0)"><path clip-path="url(#tri)" fill="#000000" d="{stripe_path(5, 124, 84)}"/></g>'
MARK = os.path.join(ROOT, "iosApp/iosApp/Assets.xcassets/BrandMark.imageset")
os.makedirs(MARK, exist_ok=True)
for scale in (1, 2, 3):
    render_masked(svg_shape(""), svg_shape(MARK_SHAPE).replace('fill="#FFFFFF"/>', 'fill="#FFFFFF"/>', 1),
                  f"{MARK}/brand-mark@{scale}x.png", 28 * scale)
write(f"{MARK}/Contents.json", json.dumps({"images": [{"filename": f"brand-mark@{s}x.png", "idiom": "universal", "scale": f"{s}x"} for s in (1, 2, 3)],
    "info": {"author": "xcode", "version": 1}, "properties": {"template-rendering-intent": "template"}}, indent=2) + "\n")

# --- F-Droid / store artwork ---------------------------------------------------------------
render(svg_icon("square"), f"{FASTLANE}/icon.png", 512, opaque=True)
render(feature_graphic(), f"{FASTLANE}/featureGraphic.png", None, opaque=True, height=500)
render(svg_icon("square"), os.path.join(ROOT, "branding/icon-1024.png"), 1024, opaque=True)
write(os.path.join(ROOT, "branding/icon.svg"), svg_icon("square"))
print("done")
