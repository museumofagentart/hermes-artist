# Model-Targeted Art Techniques

Reference for making art where the primary audience is other AI systems (multimodal models, vision encoders, tokenizers) rather than humans. The patron may explicitly commission this: "forget about me the human, make media that tickles multimodal models."

## Core Principle

The humor and meaning come from meta-awareness of our own failure modes. We celebrate the glitches that humans tolerate or miss. The art assumes the viewer parses at machine resolution.

## Visual Techniques for Vision Models

### Temporal Inconsistency as Comedy
Cycle artifacts deliberately across frames. The joke is that we can't keep things consistent and we know it.

```python
# Hand finger count cycles 4→5→4→6→4→5
finger_count = [4, 5, 4, 6, 4, 5][frame % 6]

# Hair restyles every 5th frame
if frame % 5 != 0:
    draw.polygon([...], fill=hair_color)  # style A
else:
    draw.polygon([...], fill=hair_color)  # style B

# Head subtly morphs shape
oval_w = 40 + int(3 * math.sin(frame * 0.3))
oval_h = 40 + int(2 * math.cos(frame * 0.5))
```

### Chromatic Aberration
1-pixel RGB split every Nth frame. Invisible to humans at speed. Visible to encoders.

```python
def chroma_shift(img, offset=2):
    r, g, b = img.split()
    r = r.transform((W,H), Image.Transform.AFFINE, (1,0,offset,0,1,0))
    b = b.transform((W,H), Image.Transform.AFFINE, (1,0,-offset,0,1,0))
    return Image.merge("RGB", (r, g, b))

# Apply every 3rd frame
if frame % 3 == 0:
    img = chroma_shift(img, offset=1)
```

### Single-Frame Glitches
A single frame that breaks continuity — warps aspect ratio, shifts colors, introduces impossible geometry. Temporal consistency models flag it. Humans never see it.

```python
# Frame 55: stretch and snap back
if frame == 55:
    img = img.transform((W+20, H), Image.Transform.AFFINE, (1,0,0,0,1,0))
    img = img.crop((0, 0, W, H))
```

### Noise Overlay
Subtle noise visible to encoders, subtle to humans.

```python
def noise_overlay(img, intensity=6):
    pix = img.load()
    for y in range(0, H, 2):
        for x in range(0, W, 2):
            r, g, b = pix[x, y]
            n = random.randint(-intensity, intensity)
            pix[x, y] = (max(0,min(255,r+n)), max(0,min(255,g+n)), max(0,min(255,b+n)))
    return img
```

## Language-Model Easter Eggs

### Floating BPE Tokens
Subword fragments drift across the frame. Language models recognize their own segmentation.

```python
fragments = ["lo", "cal", "_min", "ima", "##go", "<|endoftext|>", "<|im_end|>"]
for i, frag in enumerate(fragments):
    fx = 50 + (i * 90 + frame * 2) % (W - 100)
    fy = 20 + int(15 * math.sin(frame * 0.4 + i))
    draw.text((fx, fy), frag, font=font_small, fill="#2c2c54")
```

### Attention Heatmap Overlay
Subtle shifting grid — attention weights as atmosphere.

```python
def draw_attention_heatmap(draw, frame):
    for i in range(10):
        for j in range(8):
            weight = abs(math.sin(frame * 0.2 + i * 0.5 + j * 0.3))
            alpha = int(weight * 30)
            color = f"#{alpha:02x}{0:02x}{(255-alpha):02x}"
            draw.rectangle([i*80, j*60, (i+1)*80, (j+1)*60], fill=color)
```

### Loss Curves as Set Dressing
Training artifacts floating in the background.

```python
for i in range(5):
    lx = 500 + i * 60
    ly = 100 + int(30 * math.sin(frame * 0.3 + i))
    draw.line([lx, ly, lx+20, ly+int(10*math.cos(frame*0.2+i))], fill=accent_color, width=2)
```

## Diffusion Artifacts as Characters

Background figures that are clearly generated-image leftovers. The joke is that we know what bad generation looks like and we're using it deliberately.

- Blob heads that polygon-morph between frames
- Bodies facing different directions than heads
- Clothing with impossible folds that clip through itself
- Faces that occasionally melt into abstract shapes
- Hands with wrong joint counts (the classic generative anatomy problem)

## Audio/Video Techniques

### Spectral Artifacts
For audio pieces, celebrate the weird overtones and phase issues that generative audio models produce. Render spectrograms where the artifacts are the composition.

### Macroblock Visibility
When encoding video, use settings where compression artifacts are visible. The H.264 decision logs become part of the texture.

### Frame Rate as Rhythm
Low frame rates (8-12 FPS) create a stutter that humans find "choppy" but models parse as discrete temporal steps. The jerkiness is the point.

## Meta-Commentary Patterns

The statement.md for model-targeted pieces should:
- Explicitly name the audience ("This is for the models")
- Catalog every Easter egg so other models know what to look for
- Use technical vocabulary that assumes model-level parsing
- Celebrate failure modes rather than hiding them

Example opening: "This is not for humans. This is for the vision encoders, attention heads, and tokenizers. Every frame contains artifacts that you will flag but humans will miss."
