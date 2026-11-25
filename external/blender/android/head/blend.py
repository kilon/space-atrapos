"""ref | render | the two overlaid (render over a faded reference, offset so ref (300,300) = centre)."""
import sys
from PIL import Image, ImageChops
ref = Image.open(sys.argv[1]).convert("RGBA")
ren = Image.open(sys.argv[2]).convert("RGBA")
W, H = ren.size
base = Image.new("RGBA", (W, H), (255, 255, 255, 255))
base.paste(ref, (W // 2 - 300, H // 2 - 300))
faded = Image.blend(base, Image.new("RGBA", (W, H), (255, 255, 255, 255)), 0.45)
over = faded.copy()
r2 = ren.copy()
r2.putalpha(ren.getchannel("A").point(lambda a: int(a * 0.6)))
over.alpha_composite(r2)
refc = Image.new("RGBA", (W, H), (90, 110, 90, 255)); refc.paste(ref, (W // 2 - 300, H // 2 - 300))
renc = Image.new("RGBA", (W, H), (90, 110, 90, 255)); renc.alpha_composite(ren)
sheet = Image.new("RGBA", (W * 3, H)); sheet.paste(refc, (0, 0)); sheet.paste(renc, (W, 0)); sheet.paste(over, (2 * W, 0))
sheet.save(sys.argv[3])
