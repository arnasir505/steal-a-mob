# Нарезка картинок интерфейса из листов, сгенерированных нейросетью.
#
# Берёт UI_Screenshots/generated/*.jpg и кладёт готовые PNG с прозрачным фоном
# в UI_Assets/ — их можно сразу загружать в Roblox (Asset Manager → Import).
#
# Запуск из корня проекта:  python tools/cut_ui_art.py
# Нужны библиотеки:          pip install pillow numpy

import os
from collections import deque

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "UI_Screenshots", "generated")
OUT = os.path.join(ROOT, "UI_Assets")

# Листы: файл, сетка (колонки, строки), имена иконок по порядку
SHEETS = [
    ("sheet_hud.jpg", 4, 3, [
        "icon_shop", "icon_index", "icon_eggs", "icon_mobs",
        "icon_boost", "icon_speed", "icon_money", "icon_featured",
        "icon_gift", "icon_drop", "icon_night", "icon_timer",
    ]),
    ("sheet-shop.jpg", 3, 3, [
        "shop_speed_small", "shop_speed_big", "shop_x2_speed",
        "shop_money_small", "shop_money_big", "shop_x2_money",
        "shop_instant_hatch", "shop_x2_hatch", "shop_lightning",
    ]),
]

ICON_SIZE = 256  # итоговый размер иконки (квадрат)
EDGE = 2         # ширина мягкого края (сглаживание), пикселей


def background_mask(is_bg):
    """Фон = подходящие по цвету пиксели, связанные с краем картинки.
    Белое ВНУТРИ иконки (за чёрной обводкой) фоном не считается."""
    h, w = is_bg.shape
    seen = np.zeros_like(is_bg)
    queue = deque()
    for x in range(w):
        for y in (0, h - 1):
            if is_bg[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if is_bg[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= ny < h and 0 <= nx < w and is_bg[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                queue.append((ny, nx))
    return seen


def near_mask(mask, radius):
    """Пиксели в пределах radius от mask (простое расширение)"""
    result = mask.copy()
    for _ in range(radius):
        grown = result.copy()
        grown[1:, :] |= result[:-1, :]
        grown[:-1, :] |= result[1:, :]
        grown[:, 1:] |= result[:, :-1]
        grown[:, :-1] |= result[:, 1:]
        result = grown
    return result


def cut_out(rgb, is_bg, softness, anywhere=False):
    """RGB-массив -> RGBA: фон прозрачный, у края плавный переход.
    anywhere = True — фоном считается любой подходящий пиксель, а не только
    связанный с краем (для зелёного фона: зелёного в самой картинке нет)."""
    bg = is_bg if anywhere else background_mask(is_bg)
    alpha = np.where(bg, 0, 255).astype(np.float32)
    # Край: чем ближе цвет пикселя к фону, тем прозрачнее
    edge = near_mask(bg, EDGE) & ~bg
    alpha[edge] = np.clip(softness[edge], 0, 1) * 255
    rgba = np.dstack([rgb, alpha.astype(np.uint8)])
    return rgba


def white_cut(rgb):
    lo = rgb.min(axis=2).astype(np.float32)
    is_bg = lo > 232
    softness = (255 - lo) / 70  # серый край обводки -> полупрозрачный
    return cut_out(rgb, is_bg, softness)


def green_cut(rgb):
    r, g, b = (rgb[..., i].astype(np.float32) for i in range(3))
    greenness = g - np.maximum(r, b)
    is_bg = greenness > 90
    softness = 1 - (greenness / 160)
    rgba = cut_out(rgb, is_bg, softness, anywhere=True).astype(np.int32)
    # Убираем зелёный отсвет на краях (в int32, чтобы 255 + 10 не "перевалило" через 0)
    rgba[..., 1] = np.minimum(rgba[..., 1], np.maximum(rgba[..., 0], rgba[..., 2]) + 10)
    return rgba.astype(np.uint8)


def square_icon(rgba, size):
    """Обрезать по содержимому, поставить в центр квадрата"""
    image = Image.fromarray(rgba, "RGBA")
    box = image.getbbox()
    if box:
        image = image.crop(box)
    side = max(image.size)
    pad = int(side * 0.06)
    canvas = Image.new("RGBA", (side + pad * 2, side + pad * 2), (0, 0, 0, 0))
    canvas.paste(image, ((canvas.width - image.width) // 2, (canvas.height - image.height) // 2))
    return canvas.resize((size, size), Image.LANCZOS)


def cut_sheet(filename, columns, rows, names):
    sheet = np.array(Image.open(os.path.join(SRC, filename)).convert("RGB"))
    h, w, _ = sheet.shape
    for index, name in enumerate(names):
        col, row = index % columns, index // columns
        x0, x1 = round(col * w / columns), round((col + 1) * w / columns)
        y0, y1 = round(row * h / rows), round((row + 1) * h / rows)
        cell = sheet[y0:y1, x0:x1]
        icon = square_icon(white_cut(cell), ICON_SIZE)
        icon.save(os.path.join(OUT, name + ".png"))
        print("  " + name + ".png")


def cut_trail():
    rgb = np.array(Image.open(os.path.join(SRC, "trail-runner.jpg")).convert("RGB"))
    image = Image.fromarray(green_cut(rgb), "RGBA").resize((512, 512), Image.LANCZOS)
    image.save(os.path.join(OUT, "trail_runner.png"))
    print("  trail_runner.png")


def convert_biome():
    image = Image.open(os.path.join(SRC, "biome-plains.jpg")).convert("RGB")
    # Roblox всё равно уменьшает картинки больше 1024 — делаем сами, аккуратнее
    scale = 1024 / max(image.size)
    if scale < 1:
        image = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
    image.save(os.path.join(OUT, "biome_plains.png"))
    print("  biome_plains.png")


def draw_studs():
    """Узор "кубиков" для фона окон: белые бугорки на прозрачном фоне.
    В игре его красят (ImageColor3) и делают полупрозрачным, кладут плиткой."""
    size, count = 256, 4
    scale = 4  # рисуем крупно и уменьшаем — так края гладкие
    big = size * scale
    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    cell = big / count
    radius = cell * 0.3
    for i in range(count):
        for j in range(count):
            cx, cy = cell * (i + 0.5), cell * (j + 0.5)
            # тень снизу-справа, сам бугорок, блик сверху-слева
            shift = radius * 0.12
            draw.ellipse((cx - radius + shift, cy - radius + shift, cx + radius + shift, cy + radius + shift),
                         fill=(0, 0, 0, 90))
            draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=(255, 255, 255, 140))
            inner = radius * 0.7
            draw.ellipse((cx - inner - shift, cy - inner - shift, cx + inner - shift, cy + inner - shift),
                         fill=(255, 255, 255, 200))
    image.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, "pattern_studs.png"))
    print("  pattern_studs.png")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    print("Готовые картинки в " + OUT + ":")
    for filename, columns, rows, names in SHEETS:
        cut_sheet(filename, columns, rows, names)
    cut_trail()
    convert_biome()
    draw_studs()
