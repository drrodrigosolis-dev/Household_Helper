from PIL import Image, ImageDraw, ImageFilter
S = 4096
def lerp(a, b, t): return tuple(int(a[i] + (b[i]-a[i])*t) for i in range(3))
# Background: diagonal gradient, deep indigo -> teal
top, bot = (58, 44, 176), (18, 170, 160)
bg = Image.new("RGB", (S, S))
px = bg.load()
for y in range(S):
    for x in range(0, S, 1):
        t = min(1, max(0, (x*0.35 + y*0.65) / S))
        px[x, y] = lerp(top, bot, t)
# Soft glow top-left
glow = Image.new("L", (S, S), 0)
ImageDraw.Draw(glow).ellipse((-S*0.3, -S*0.35, S*0.7, S*0.55), fill=45)
glow = glow.filter(ImageFilter.GaussianBlur(S*0.12))
bg = Image.composite(Image.new("RGB", (S, S), (255, 255, 255)), bg, glow)

def rr(d, box, r, fill): d.rounded_rectangle(box, radius=r, fill=fill)
# Shadow layer for the house
shadow = Image.new("L", (S, S), 0); sd = ImageDraw.Draw(shadow)
cx = S/2
roof = [(cx, S*0.20), (S*0.80, S*0.47), (S*0.20, S*0.47)]
body = (S*0.27, S*0.42, S*0.73, S*0.80)
sd.polygon([(x, y+S*0.03) for x, y in roof], fill=110)
sd.rounded_rectangle((body[0], body[1]+S*0.03, body[2], body[3]+S*0.03), radius=S*0.07, fill=110)
shadow = shadow.filter(ImageFilter.GaussianBlur(S*0.035))
bg = Image.composite(Image.new("RGB", (S, S), (20, 20, 60)), bg, shadow)

d = ImageDraw.Draw(bg)
white = (255, 255, 255)
# Roof with rounded ridge: polygon + round joins
w = S*0.075
d.line(roof + [roof[0]], fill=white, width=int(w), joint="curve")
for p in roof: d.ellipse((p[0]-w/2, p[1]-w/2, p[0]+w/2, p[1]+w/2), fill=white)
d.polygon(roof, fill=white)
# Body
rr(d, body, S*0.07, white)
# Three rising bars (budget, tasks, wishlist) inside the house
colors = [(255, 184, 76), (255, 107, 129), (80, 200, 170)]
bw, gap = S*0.085, S*0.035
x0 = cx - (3*bw + 2*gap)/2
base = S*0.72
heights = [S*0.12, S*0.19, S*0.27]
for i, (c, h) in enumerate(zip(colors, heights)):
    x = x0 + i*(bw+gap)
    rr(d, (x, base-h, x+bw, base), bw/2, c)
# Sparkle (wishlist / delight) at the chimney spot
def sparkle(cx_, cy_, r, fill):
    k = r*0.28
    d.polygon([(cx_, cy_-r), (cx_+k, cy_-k), (cx_+r, cy_), (cx_+k, cy_+k),
               (cx_, cy_+r), (cx_-k, cy_+k), (cx_-r, cy_), (cx_-k, cy_-k)], fill=fill)
sparkle(S*0.755, S*0.215, S*0.075, (255, 220, 120))
sparkle(S*0.845, S*0.315, S*0.035, (255, 255, 255))
bg.resize((1024, 1024), Image.LANCZOS).save("/private/tmp/claude-501/icon/AppIcon-1024.png")
