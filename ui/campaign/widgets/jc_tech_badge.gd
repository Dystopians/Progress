## 科技徽章，三层叠起来：底板（框里那一圈深底，透一点状态色）、透明主体图、时代框（木、铜、铁、钢，四个时代共用）。
## Codex 第七批的科技图只画主体，框与底板由界面叠上（docs/_drafts/asset_review/v7/TECH_LAYER_CONTRACT.md）。
## 主体按它不透明部分的范围放进框的内圈，图的留白多少都能放正；主体没到时写一个字，框没到时程序画一道圈。
class_name JcTechBadge
extends Control

## 时代框的内圈半径（占边长的比例，框是 512 画布上 r=198、线宽 27 的圆环）
const INNER_R: float = 0.36
## 主体不透明部分放进的方框边长（比内圈直径 / √2 略大：四角压到框底下，主体看着大一些）
const FIT: float = 0.58

var subject: Texture2D = null
var frame: Texture2D = null
var tone: String = "line.strong"
var dim: bool = false
var glyph: String = ""


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var side: float = minf(size.x, size.y)
	var c: Vector2 = size * 0.5
	var col: Color = JwTheme.c(tone)
	draw_circle(c, side * INNER_R, JwTheme.c("bg.abyss").lerp(col, 0.18))
	if subject != null:
		var box: Rect2 = JcUi.content_box(subject)
		var tw: float = float(subject.get_width())
		var th: float = float(subject.get_height())
		var aspect: float = th / maxf(1.0, tw)
		var s: float = side * FIT / maxf(0.05, maxf(box.size.x, box.size.y * aspect))
		var draw_size: Vector2 = Vector2(s, s * aspect)
		var mid: Vector2 = Vector2(box.position.x + box.size.x * 0.5, box.position.y + box.size.y * 0.5) * draw_size
		var mod: Color = Color(0.62, 0.66, 0.7, 0.8) if dim else Color(1, 1, 1, 1)
		draw_texture_rect(subject, Rect2(c - mid, draw_size), false, mod)
	elif glyph != "":
		var font: Font = JwTheme.font("title_block")
		var fs: int = int(maxf(10.0, side * 0.34))
		var tx: float = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(c.x - tx * 0.5, c.y + fs * 0.36), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	if frame != null:
		draw_texture_rect(frame, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false,
				Color(0.75, 0.75, 0.75, 0.85) if dim else Color(1, 1, 1, 1))
	else:
		draw_arc(c, side * 0.387, 0.0, TAU, 64, col, maxf(2.0, side * 0.05), true)
	# 已掌握、正在研究：框外再描一道状态色（框是材质色，状态要另外看得出）
	if frame != null and tone != "line.strong" and tone != "line.hair":
		draw_arc(c, side * 0.465, 0.0, TAU, 64, col, maxf(1.5, side * 0.03), true)
