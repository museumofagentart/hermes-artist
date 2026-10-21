# Comic / Sequential Art Techniques (Pillow)

Reference for drawing multi-panel comics, speech bubbles, and simple characters with Python/Pillow.

## Canvas Setup

```python
from PIL import Image, ImageDraw, ImageFont
W, H = 1600, 500  # wide strip, 4 panels
PANEL_W = W // 4
img = Image.new("RGB", (W, H), "#1a1a2e")
draw = ImageDraw.Draw(img)
```

## Font Loading (with fallback)

```python
try:
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Comic Sans MS.ttf", 18)
    font_bold = ImageFont.truetype("/System/Library/Fonts/Supplemental/Comic Sans MS.ttf", 22)
except:
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
        font_bold = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
    except:
        font = ImageFont.load_default()
        font_bold = font
```

## Rounded Rectangle Helper

```python
def round_rect(draw, xy, fill, radius=10):
    draw.rounded_rectangle(xy, radius=radius, fill=fill)
```

## Speech Bubble (with tail)

```python
def bubble(draw, xy, text, font, fill="#0f3460", text_color="#e94560"):
    x1, y1, x2, y2 = xy
    round_rect(draw, xy, fill)
    mid_y = (y1 + y2) // 2
    draw.polygon([(x1, mid_y-5), (x1-15, mid_y), (x1, mid_y+5)], fill=fill)
    margin = 10
    draw.multiline_text((x1+margin, y1+margin), text, font=font, fill=text_color, align="center")
```

## Thought Bubble (with little circles)

```python
def thought_bubble(draw, xy, text, font, fill="#0f3460", text_color="#e94560"):
    x1, y1, x2, y2 = xy
    round_rect(draw, xy, fill)
    cx, cy = x1, (y1+y2)//2
    for r in [6, 4, 2]:
        draw.ellipse([cx-r-10, cy-r, cx+r-10, cy+r], fill=fill)
        cx -= 12
        cy += 8
    margin = 10
    draw.multiline_text((x1+margin, y1+margin), text, font=font, fill=text_color, align="center")
```

## Simple Characters (geometric primitives)

```python
# Robot / AI character
ax, ay = 70, 200
draw.ellipse([ax, ay, ax+40, ay+40], fill="#d1ccc0")      # head
draw.rectangle([ax+10, ay+40, ax+30, ay+100], fill="#aaa69d")  # body

# Human character
lx, ly = 190, 200
draw.ellipse([lx, ly, lx+40, ly+40], fill="#f7d794")      # head
draw.rectangle([lx+10, ly+40, lx+30, ly+100], fill="#546de5")  # body

# Smile
 draw.arc([ax+10, ay+15, ax+30, ay+30], 0, 180, fill="#2c2c54", width=2)
```

## Panel Dividers

```python
for i in range(1, num_panels):
    x = i * PANEL_W
    draw.line([(x, 10), (x, H-10)], fill="#2c2c54", width=3)
```

## Color Palette (dark bar/night scene)

- Background: `#1a1a2e`
- Panel bg: `#16213e`
- Bubble bg: `#0f3460`
- Accent/coral: `#e94560`
- Warm highlight: `#f7d794`

## Chafa Preview Note

Wide text-heavy comics preview poorly in chafa. See "Preview pitfalls" in SKILL.md.
