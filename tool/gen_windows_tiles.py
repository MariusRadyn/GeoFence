from PIL import Image
from pathlib import Path

src = Path(r'd:\git\GeoFenceApp\assets\limitless_logo.png')
out_dir = Path(r'd:\git\GeoFenceApp\web\icons')
logo = Image.open(src).convert('RGBA')

# Windows / PWA Builder recommended tile sizes
sizes = {
    'Square44x44Logo.png': (44, 44),
    'StoreLogo.png': (50, 50),
    'Square71x71Logo.png': (71, 71),
    'Square150x150Logo.png': (150, 150),
    'Square310x310Logo.png': (310, 310),
    'Wide310x150Logo.png': (310, 150),
    'SplashScreen.png': (620, 300),
    # Manifest-friendly names
    'Icon-44.png': (44, 44),
    'Icon-50.png': (50, 50),
    'Icon-71.png': (71, 71),
    'Icon-150.png': (150, 150),
    'Icon-310.png': (310, 310),
    'Icon-310x150.png': (310, 150),
    'Icon-620x300.png': (620, 300),
}


def fit_logo(canvas_w: int, canvas_h: int, pad_ratio: float = 0.18) -> Image.Image:
    canvas = Image.new('RGBA', (canvas_w, canvas_h), (255, 255, 255, 255))
    max_w = int(canvas_w * (1 - 2 * pad_ratio))
    max_h = int(canvas_h * (1 - 2 * pad_ratio))
    ratio = min(max_w / logo.width, max_h / logo.height)
    nw = max(1, int(logo.width * ratio))
    nh = max(1, int(logo.height * ratio))
    resized = logo.resize((nw, nh), Image.Resampling.LANCZOS)
    x = (canvas_w - nw) // 2
    y = (canvas_h - nh) // 2
    canvas.alpha_composite(resized, (x, y))
    return canvas.convert('RGB')


for name, (w, h) in sizes.items():
    img = fit_logo(w, h)
    path = out_dir / name
    img.save(path, 'PNG', optimize=True)
    print(f'wrote {path.name} {w}x{h}')

print('done')
