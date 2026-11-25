class_name TextureAtlas
## Many images packed into one texture, so what's drawn from them batches:
## Godot draws consecutive sprites / tiles of the same texture in one draw
## call, and every change of texture starts another - a planet's ground and
## buildings, a texture per piece, were ~1000 draw calls a frame.
##   var a := TextureAtlas.pack(images)   -> [Image, [Vector2i top-left or null per image]]
## Each image gets PAD px of its own edge pixels round it (so filtering at its
## edge never fades to clear or bleeds a neighbour in), packed in rows WIDTH wide.

const PAD := 3
const WIDTH := 4096


static func pack(images: Array, width := WIDTH) -> Array:
	var pos := []
	var imgs := []
	var x := PAD
	var y := PAD
	var row_h := 0
	for img0 in images:
		var img: Image = img0
		if img == null or img.is_empty():
			pos.append(null)
			imgs.append(null)
			continue
		if img.is_compressed():
			img = img.duplicate()
			img.decompress()
		if img.has_mipmaps():
			img = img.duplicate()
			img.clear_mipmaps()
		if img.get_format() != Image.FORMAT_RGBA8:
			img = img.duplicate()
			img.convert(Image.FORMAT_RGBA8)
		if x + img.get_width() + PAD > width:
			x = PAD
			y += row_h + 2 * PAD
			row_h = 0
		pos.append(Vector2i(x, y))
		imgs.append(img)
		x += img.get_width() + 2 * PAD   # (each image's own PAD of edge pixels on either side)
		row_h = maxi(row_h, img.get_height())
	if imgs.all(func(im): return im == null):
		return [null, pos]
	var atlas := Image.create_empty(width, y + row_h + PAD, false, Image.FORMAT_RGBA8)
	for i in imgs.size():
		if imgs[i] == null:
			continue
		var im: Image = imgs[i]
		var p: Vector2i = pos[i]
		var w := im.get_width()
		var h := im.get_height()
		atlas.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), p)
		for k in range(1, PAD + 1):
			atlas.blit_rect(im, Rect2i(0, 0, w, 1), p + Vector2i(0, -k))
			atlas.blit_rect(im, Rect2i(0, h - 1, w, 1), p + Vector2i(0, h - 1 + k))
		for k in range(1, PAD + 1):
			atlas.blit_rect(atlas, Rect2i(p.x, p.y - PAD, 1, h + 2 * PAD), Vector2i(p.x - k, p.y - PAD))
			atlas.blit_rect(atlas, Rect2i(p.x + w - 1, p.y - PAD, 1, h + 2 * PAD), Vector2i(p.x + w - 1 + k, p.y - PAD))
	return [atlas, pos]


## AtlasTextures for `images` (null where an image was missing), all regions
## of one texture.
static func textures(images: Array, width := WIDTH) -> Array:
	var packed := pack(images, width)
	var out := []
	if packed[0] == null:
		out.resize(images.size())
		return out
	var tex := ImageTexture.create_from_image(packed[0])
	for i in images.size():
		if packed[1][i] == null:
			out.append(null)
			continue
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(packed[1][i], (images[i] as Image).get_size())
		out.append(at)
	return out


## A TileSetAtlasSource showing `tex` - an AtlasTexture as a region of its
## atlas (no padded copy of its own: Godot's texture padding would make each
## source a texture again, unbatchable).
static func set_source_texture(src: TileSetAtlasSource, tex: Texture2D) -> void:
	if tex is AtlasTexture and (tex as AtlasTexture).atlas != null:
		src.texture = (tex as AtlasTexture).atlas
		src.margins = Vector2i((tex as AtlasTexture).region.position)
		src.use_texture_padding = false
	else:
		src.texture = tex
		src.margins = Vector2i.ZERO
		src.use_texture_padding = true
