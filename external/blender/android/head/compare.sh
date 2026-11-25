#!/bin/sh
# Render the head at the reference's view and make head/ov_sheet.png + head/zoom.png.
cd "$(dirname "$0")/.."
blender -b android.blend --python head/overlay.py -- head/ov.png 64 2>&1 | grep -iE "error|trace"
python3 head/blend.py head/ref_head.png head/ov.png head/ov_sheet.png
python3 -c "
from PIL import Image
a=Image.open('head/ref_head.png').convert('RGBA').crop((150,130,720,560))
b=Image.new('RGBA',(800,640),(90,110,90,255)); b.alpha_composite(Image.open('head/ov.png').convert('RGBA')); b=b.crop((250,150,820,580))
s=Image.new('RGBA',(1140,430)); s.paste(a,(0,0)); s.paste(b,(570,0)); s=s.resize((1710,645)); s.save('head/zoom.png')"
