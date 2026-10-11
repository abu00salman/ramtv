from PIL import Image, ImageDraw
S = 2048
img = Image.new("RGB", (S, S))
px = img.load()
c1, c2 = (0, 87, 255), (8, 26, 150)
for y in range(S):
    for x in range(0, S):
        t = (x + y) / (2 * S)
        px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
d = ImageDraw.Draw(img)
k = S / 1024
def R(x0, y0, x1, y1, r, fill):
    d.rounded_rectangle([x0 * k, y0 * k, x1 * k, y1 * k], radius=r * k, fill=fill)
# TV body
R(192, 236, 832, 696, 96, (255, 255, 255))
# screen
R(236, 280, 788, 652, 64, (6, 22, 120))
# play triangle
d.polygon([(450 * k, 380 * k), (450 * k, 552 * k), (606 * k, 466 * k)], fill=(255, 255, 255))
# stand
R(470, 696, 554, 758, 10, (255, 255, 255))
R(356, 744, 668, 790, 23, (255, 255, 255))
img = img.resize((1024, 1024), Image.LANCZOS)
img.save("RaMtv/Assets.xcassets/AppIcon.appiconset/icon.png")
img.resize((256, 256), Image.LANCZOS).save("icon-preview.png")
