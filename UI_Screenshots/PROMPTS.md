# Промпты для картинок интерфейса — 4 генерации вместо 28

Чтобы не тратить лимиты, иконки рисуются **листами**: много иконок на одной картинке.
Нарезку, удаление фона и подготовку к загрузке в Roblox делает Claude.

Что делать:
1. Сгенерируй 4 картинки по промптам ниже (лучше квадрат или 4:3, максимальное качество).
2. Сохрани их в папку `UI_Screenshots/generated/` с именами из заголовков
   (`sheet_hud.png`, `sheet_shop.png`, `trail_runner.png`, `biome_plains.png`).
3. Скажи Claude — он нарежет иконки по отдельным файлам с прозрачным фоном.

Если какая-то иконка на листе вышла плохо — не перегенерируй весь лист,
скажи Claude, и он даст промпт только для неё.

Фон на листах — **чисто белый, однотонный**: по нему фон легко убрать автоматически
(у иконок чёрная обводка, белое внутри иконки при этом сохранится).

Не копируй картинки Steal an Egg один в один — делаем свои в похожем стиле.

---

## 1. `sheet_hud.png` — 12 иконок для кнопок на экране

```
A sprite sheet of 12 separate cartoon game UI icons for a Roblox simulator game,
arranged in a neat grid of 4 columns and 3 rows, each icon centered in its own cell
with lots of empty space between icons, icons do not touch or overlap.
Style: bold thick black outline around every icon, glossy 3D-cartoon shading,
bright highlights, vibrant saturated colors.
Background: plain solid pure white, completely flat, no shadows on the background,
no grid lines, no borders, no text, no letters, no numbers.
Icons in order, left to right, top to bottom:
1 a white shopping cart with dark wheels,
2 a closed thick book with a light-blue cover,
3 a single cream-colored egg with soft speckles,
4 an orange paw print with four toe pads,
5 a round glass potion flask with bubbling bright green liquid and a cork,
6 a blue-and-white running sneaker,
7 a thick stack of green dollar bills with a yellow paper band,
8 a red sale price tag with a percent sign,
9 a pink-purple gift box with a white ribbon bow,
10 a red trash can with lid,
11 a yellow crescent moon behind a small grey cloud,
12 a golden hourglass with blue sand.
```

## 2. `sheet_shop.png` — 9 картинок товаров магазина

```
A sprite sheet of 9 separate cartoon game shop item illustrations for a Roblox
simulator game, arranged in a neat grid of 3 columns and 3 rows, each item centered
in its own cell with lots of empty space between items, items do not touch or overlap.
Style: bold thick black outline, glossy 3D-cartoon shading, bright highlights,
vibrant saturated colors, rich detailed items.
Background: plain solid pure white, completely flat, no shadows on the background,
no grid lines, no borders, no text, no letters, no numbers.
Items in order, left to right, top to bottom:
1 one glowing blue running sneaker with small lightning sparks,
2 an open treasure chest overflowing with many glowing blue sneakers,
3 a pair of blue sneakers with white angel wings,
4 two stacks of green dollar bills with yellow bands,
5 a heavy open steel safe overflowing with stacks of green dollar bills,
6 a big green money bag with a dollar sign, bills sticking out,
7 a cracking egg with bright yellow light shining through the cracks,
8 two eggs next to a small golden stopwatch with sparkles,
9 a big yellow lightning bolt.
```

## 3. `trail_runner.png` — фигурка для магазина трейлов

Одна белая фигурка на все трейлы — цвет (синий, зелёный, огненный...) задаётся в игре.
Фон тут зелёный, потому что фигурка сама белая.

```
A blocky toy-like humanoid figure made of simple rectangular blocks, running fast
to the right in a dynamic pose, leaving a wide flowing ribbon trail behind it.
The figure and the trail are colored only in pure white and light grey shades
(monochrome, no other colors), with a bold thick black outline and soft cartoon shading.
Background: plain solid bright green (#00FF00), completely flat, no shadows,
no text. Square image, the figure centered.
```

## 4. `biome_plains.png` — картинка биома для индекса

```
Cartoon game illustration of a sunny green meadow with a wooden fence, a red barn
in the distance, hay bales, a few trees and a bright blue sky with fluffy clouds.
Vertical portrait composition 2:3, bright saturated colors, soft shading,
no characters, no text.
```

Для следующих биомов — тот же промпт, только с их пейзажем.

---

## Что делать не нужно

Это Claude сделает сам, без генератора:
- узор «кубиков» на фоне окон;
- окна, заголовки с полосками, кнопки, рамки, градиенты;
- значок Robux (встроенный символ Roblox);
- силуэты и превью мобов в индексе — из твоих 3D-моделей;
- плашка «RUN!!», красная рамка при погоне, переключатели, полоски прогресса.
