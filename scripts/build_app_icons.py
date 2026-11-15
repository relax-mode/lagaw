#!/usr/bin/env python3
"""Regenerate every app icon and splash image from the 1024px master.

Source: frontend/branding/lagaw-app-icon-1024.png
Run from the repo root:  python scripts/build_app_icons.py

Writes the web favicon and PWA icons, the Android launcher icons (legacy and
adaptive), the Android launch image, and the in-app logo. Needs Pillow.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
FRONTEND = ROOT / "frontend"
MASTER = FRONTEND / "branding" / "lagaw-app-icon-1024.png"

# Sampled from the master's top edge and lower-left, for the full-bleed
# backgrounds behind the maskable and adaptive icons.
BLUE_TOP = (43, 125, 229)
BLUE_BOTTOM = (106, 183, 248)

ANDROID_RES = FRONTEND / "android/app/src/main/res"
DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}


def resized(icon: Image.Image, size: int) -> Image.Image:
    return icon.resize((size, size), Image.LANCZOS)


def gradient(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size))
    for y in range(size):
        t = y / (size - 1)
        row = tuple(round(a + (b - a) * t) for a, b in zip(BLUE_TOP, BLUE_BOTTOM))
        img.paste(row + (255,), (0, y, size, y + 1))
    return img


def on_canvas(icon: Image.Image, canvas: int, art: int, background=None) -> Image.Image:
    """Center the icon at `art` px on a `canvas` px square."""
    out = background if background is not None else Image.new("RGBA", (canvas, canvas))
    out = out.copy()
    out.alpha_composite(resized(icon, art), ((canvas - art) // 2, (canvas - art) // 2))
    return out


def save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    print("wrote", path.relative_to(ROOT))


def main() -> None:
    icon = Image.open(MASTER).convert("RGBA")
    assert icon.size == (1024, 1024), icon.size

    # Web.
    save(resized(icon, 48), FRONTEND / "web/favicon.png")
    for size in (192, 512):
        save(resized(icon, size), FRONTEND / f"web/icons/Icon-{size}.png")
        # Maskable: full-bleed background, art kept inside the 80% safe zone.
        save(
            on_canvas(icon, size, round(size * 0.8), gradient(size)),
            FRONTEND / f"web/icons/Icon-maskable-{size}.png",
        )

    # In-app logo (onboarding and the swipe menu).
    save(resized(icon, 144), FRONTEND / "assets/brand/logo.png")

    for name, scale in DENSITIES.items():
        # Legacy launcher icon, 48dp.
        save(resized(icon, round(48 * scale)), ANDROID_RES / f"mipmap-{name}/ic_launcher.png")
        # Adaptive foreground: 108dp canvas, art 60dp so circle masks keep it.
        canvas = round(108 * scale)
        save(
            on_canvas(icon, canvas, round(60 * scale)),
            ANDROID_RES / f"mipmap-{name}/ic_launcher_foreground.png",
        )
        # Launch image: 96dp, centered by launch_background.xml.
        save(resized(icon, round(96 * scale)), ANDROID_RES / f"drawable-{name}/launch_image.png")


if __name__ == "__main__":
    main()
