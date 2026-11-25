"""Cut a mask out of the reference picture with Segment Anything, from clicked points and / or a box.

  python -I sam_mask.py <image> <cache dir> <out mask.png> [--points "x,y,1;x,y,0;..."] [--box x0,y0,x1,y1]
                        [--pick best|0|1|2|largest|smallest] [--overlay out_overlay.png] [--add other_mask.png]
                        [--sub other_mask.png]

Points: label 1 = inside, 0 = outside (picture pixels). The image embedding is computed once and kept in
<cache dir> (about a minute on the CPU); each call after that takes seconds. --add / --sub combine the
result with an existing mask (union / difference), so a mask can be built up over several calls.
The overlay shows the mask in green on the picture with the points (inside green, outside red)."""
import os
import sys
import numpy as np
import torch
from PIL import Image, ImageDraw
from transformers import SamModel, SamProcessor

MODEL = "facebook/sam-vit-huge"


def main():
    a = sys.argv[1:]
    src, cache, out = a[0], a[1], a[2]
    opt = {"--points": "", "--box": "", "--pick": "best", "--overlay": "", "--add": "", "--sub": ""}
    i = 3
    while i < len(a):
        if a[i] in opt:
            opt[a[i]] = a[i + 1]
            i += 2
        else:
            raise SystemExit("unknown option " + a[i])
    img = Image.open(src).convert("RGB")
    W, H = img.size
    os.makedirs(cache, exist_ok=True)
    proc = SamProcessor.from_pretrained(MODEL)
    model = SamModel.from_pretrained(MODEL).eval()
    pts, labels = [], []
    for p in [p for p in opt["--points"].split(";") if p.strip()]:
        x, y, l = p.split(",")
        pts.append([float(x), float(y)])
        labels.append(int(l))
    box = [float(v) for v in opt["--box"].split(",")] if opt["--box"] else None
    kw = {}
    if pts:
        kw["input_points"] = [[pts]]
        kw["input_labels"] = [[labels]]
    if box:
        kw["input_boxes"] = [[box]]
    inputs = proc(img, return_tensors="pt", **kw)
    emb_path = os.path.join(cache, "sam_vit_huge_embedding.pt")
    if os.path.exists(emb_path):
        emb = torch.load(emb_path)
    else:
        with torch.no_grad():
            emb = model.get_image_embeddings(inputs["pixel_values"])
        torch.save(emb, emb_path)
    fwd = {k: v for k, v in inputs.items() if k in ("input_points", "input_labels", "input_boxes")}
    with torch.no_grad():
        o = model(image_embeddings=emb, multimask_output=True, **fwd)
    masks = proc.image_processor.post_process_masks(o.pred_masks.cpu(), inputs["original_sizes"].cpu(),
                                                    inputs["reshaped_input_sizes"].cpu())[0][0].numpy()  # (3, H, W)
    scores = o.iou_scores[0, 0].cpu().numpy()
    areas = masks.reshape(3, -1).sum(1)
    pick = opt["--pick"]
    k = {"best": int(scores.argmax()), "largest": int(areas.argmax()), "smallest": int(areas.argmin())}.get(pick)
    if k is None:
        k = int(pick)
    m = masks[k].astype(bool)
    print("candidates:", [(i, round(float(s), 3), int(ar)) for i, (s, ar) in enumerate(zip(scores, areas))], "picked", k)
    if opt["--add"]:
        m |= np.asarray(Image.open(opt["--add"]).convert("L")) > 127
    if opt["--sub"]:
        m &= ~(np.asarray(Image.open(opt["--sub"]).convert("L")) > 127)
    Image.fromarray((m * 255).astype(np.uint8)).save(out)
    ys, xs = np.nonzero(m)
    if len(xs):
        print("mask", out, "area", int(m.sum()), "bbox", int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))
    if opt["--overlay"]:
        rgb = np.asarray(img).astype(np.float32)
        rgb[m] = rgb[m] * 0.45 + np.array([40, 255, 80]) * 0.55
        im = Image.fromarray(rgb.astype(np.uint8))
        d = ImageDraw.Draw(im)
        for (x, y), l in zip(pts, labels):
            d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(0, 255, 0) if l else (255, 0, 0), outline=(255, 255, 255))
        if box:
            d.rectangle(box, outline=(255, 255, 0), width=2)
        im.save(opt["--overlay"])


if __name__ == "__main__":
    main()
