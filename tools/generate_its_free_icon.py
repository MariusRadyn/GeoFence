"""Generate assets/its_free_icon.png — friendly mascot + IT'S FREE! speech bubble."""
from PIL import Image, ImageDraw, ImageFont
import math

SIZE = 512
BG_TOP = (8, 18, 38)
BG_BOTTOM = (4, 12, 28)
TEAL = (4, 145, 246)
TEAL_LIGHT = (80, 190, 255)
GOLD = (255, 196, 58)
GOLD_DARK = (210, 150, 28)
SKIN = (255, 210, 170)
SKIN_SHADOW = (235, 175, 140)
HAIR = (55, 35, 25)
GRID_CYAN = (0, 180, 220)


def lerp(a, b, t):
    return int(a + (b - a) * t)


def vertical_gradient(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        for x in range(size):
            px[x, y] = (
                lerp(BG_TOP[0], BG_BOTTOM[0], t),
                lerp(BG_TOP[1], BG_BOTTOM[1], t),
                lerp(BG_TOP[2], BG_BOTTOM[2], t),
                255,
            )
    return img


def draw_grid(draw, size):
    base_y = int(size * 0.78)
    for i in range(-5, 6):
        x = size * 0.5 + i * 52
        draw.line([(x, base_y), (x - 80, size)], fill=(*GRID_CYAN, 30), width=2)
    for j in range(5):
        y = base_y + j * 24
        draw.line([(0, y), (size, y)], fill=(*GRID_CYAN, 22), width=1)


def draw_character(draw):
    cx, cy = 200, 300

    # Body / jacket
    draw.ellipse([cx - 70, cy - 20, cx + 70, cy + 95], fill=TEAL)
    draw.arc([cx - 70, cy - 20, cx + 70, cy + 95], 200, 340, fill=GOLD, width=5)

    # Head
    draw.ellipse([cx - 58, cy - 115, cx + 58, cy + 5], fill=SKIN)
    draw.arc([cx - 58, cy - 115, cx + 58, cy + 5], 30, 210, fill=GOLD, width=4)

    # Hair tuft
    draw.pieslice([cx - 50, cy - 135, cx + 50, cy - 55], 200, 340, fill=HAIR)
    draw.ellipse([cx - 18, cy - 128, cx + 18, cy - 98], fill=HAIR)

    # Eyes (friendly, wide)
    for ex in (cx - 22, cx + 10):
        draw.ellipse([ex, cy - 78, ex + 22, cy - 56], fill=(255, 255, 255, 255))
        draw.ellipse([ex + 8, cy - 72, ex + 18, cy - 62], fill=(30, 30, 40, 255))
    # Smile
    draw.arc([cx - 28, cy - 58, cx + 28, cy - 28], 10, 170, fill=(180, 80, 70, 255), width=4)

    # Arm holding megaphone
    draw.line([(cx + 45, cy + 10), (cx + 95, cy - 30)], fill=SKIN_SHADOW, width=14)
    draw.ellipse([cx + 82, cy - 42, cx + 108, cy - 16], fill=SKIN)

    # Megaphone
    horn = [(cx + 95, cy - 35), (cx + 155, cy - 55), (cx + 168, cy - 15), (cx + 108, cy + 5)]
    draw.polygon(horn, fill=GOLD)
    draw.polygon(horn, outline=GOLD_DARK, width=3)
    bell = [(cx + 155, cy - 55), (cx + 198, cy - 62), (cx + 192, cy - 8), (cx + 168, cy - 15)]
    draw.polygon(bell, fill=TEAL_LIGHT)
    draw.polygon(bell, outline=GOLD, width=3)

    # Left arm wave
    draw.line([(cx - 48, cy + 5), (cx - 88, cy - 35)], fill=SKIN_SHADOW, width=12)
    draw.ellipse([cx - 100, cy - 48, cx - 76, cy - 24], fill=SKIN)


def draw_speech_bubble(draw):
    # Bubble
    bubble = [248, 48, 492, 168]
    draw.rounded_rectangle(bubble, radius=28, fill=(255, 255, 255, 255), outline=GOLD, width=5)
    # Tail
    tail = [(270, 168), (240, 210), (310, 168)]
    draw.polygon(tail, fill=(255, 255, 255, 255))
    draw.line([(270, 168), (240, 210), (310, 168)], fill=GOLD, width=4)

    try:
        font_big = ImageFont.truetype("arialbd.ttf", 38)
        font_sub = ImageFont.truetype("arialbd.ttf", 44)
    except OSError:
        font_big = ImageFont.load_default()
        font_sub = font_big

    draw.text((268, 58), "IT'S", fill=TEAL, font=font_big)
    draw.text((268, 98), "FREE!", fill=(255, 77, 141, 255), font=font_sub)

    # Sparkles
    for sx, sy, r in [(255, 42, 8), (478, 55, 6), (485, 145, 5)]:
        pts = []
        for i in range(8):
            ang = i * math.pi / 4 - math.pi / 2
            rad = r if i % 2 == 0 else r * 0.4
            pts.append((sx + rad * math.cos(ang), sy + rad * math.sin(ang)))
        draw.polygon(pts, fill=GOLD)


def main():
    img = vertical_gradient(SIZE)
    draw = ImageDraw.Draw(img, "RGBA")
    draw_grid(draw, SIZE)
    draw.ellipse([80, 100, 420, 420], fill=(4, 145, 246, 22))
    draw_character(draw)
    draw_speech_bubble(draw)

    vignette = Image.new("L", (SIZE, SIZE), 0)
    vd = ImageDraw.Draw(vignette)
    vd.ellipse([-40, -40, SIZE + 40, SIZE + 40], fill=210)
    img = Image.composite(img, Image.new("RGBA", (SIZE, SIZE), (*BG_BOTTOM, 255)), vignette)

    out = "assets/its_free_icon.png"
    img.save(out, "PNG")
    print(f"saved {out}")


if __name__ == "__main__":
    main()
