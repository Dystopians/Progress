## v2 界面的小部件：数字卡、进度条、标签、卡片、配图、折线。复用 JwUi / JwTheme 的字体与色板。
class_name JcUi
extends RefCounted

const GOOD: String = "teal.core"
const WARN: String = "ochre.core"
const BAD: String = "ochre.hot"
const MUTED: String = "text.muted"
## 顾问五部的徽记、托管六领域的图标（Codex 第五批）
const ADVISOR_ART: String = "res://assets/advisors/advisor_%s.png"
const STEWARD_ART: Dictionary = {
	"research": "res://assets/icons/campaign/steward_research.png",
	"build": "res://assets/icons/campaign/steward_construction.png",
	"modernize": "res://assets/icons/campaign/steward_modernization.png",
	"fiscal": "res://assets/icons/campaign/steward_fiscal.png",
	"trade": "res://assets/icons/campaign/steward_trade.png",
	"events": "res://assets/icons/campaign/steward_events.png",
}


## 第七批图片的路径约定（docs/60）：图到了放进去就生效，没到时显示占位圆章。
const TECH_ART: String = "res://assets/techs/t01/tech_%s.png"
const DECREE_ART: String = "res://assets/decrees/d01/decree_%s.png"
const DECREE_LEVEL_ART: String = "res://assets/decrees/d01/decree_%s_%d.png"
const REGIME_ART: String = "res://assets/regime/r01/regime_%s_%s.png"
const POLICY_ICON: String = "res://assets/icons/policy/%s.png"
const CLASS_ART: String = "res://assets/classes/c01/class_%s_e%d_%s.png"
const NEED_ICON: String = "res://assets/icons/needs/need_%s.png"
const MOOD_ICON: String = "res://assets/icons/mood/mood_%d.png"
const LIFE_ART: String = "res://assets/scenes/life/life_%s_e%d.png"
const CHRON_ICON: String = "res://assets/icons/chronicle/chr_%s.png"
const MILESTONE_ART: String = "res://assets/chronicle/m01/milestone_%s.png"
const SECTOR_ICON: String = "res://assets/icons/sector/sector_%s.png"
const SECTOR_ART: String = "res://assets/scenes/sector/sector_%s_e%d.png"
const STATUS_ICON: String = "res://assets/icons/status/%s.png"
const UI_ICON: String = "res://assets/icons/ui/%s.png"
const TIER_ICON: String = "res://assets/icons/status/tier_%d.png"
## 三条危机线的小图标（财政、民生、威信），与各阶段的警钟徽章（同形异色，旁边一定写阶段文字）
const CRISIS_ICON: PackedStringArray = ["crisis_fiscal", "crisis_livelihood", "crisis_mandate"]
const CHRON_DECOR: String = "res://assets/ui/chronicle/%s.png"
## 满额（ppm）
const PPM_ONE: int = 1_000_000


## 科技的时代框（Codex 第七批：科技图只画主体，框按时代共用，界面叠上去）
const TECH_FRAME: String = "res://assets/techs/frames/era_%d.svg"
## 审阅预览的默认清单（--jc-art-preview=v7）
const PREVIEW_V7: String = "res://docs/_drafts/asset_review/v7/additions_manifest.json"

## 审阅预览：新图还在审核目录、没放进游戏路径时，用命令行 --jc-art-preview=<清单> 直接从审核目录读原图，
## 看放进游戏是什么样子。只读，不搬文件；清单里每项的 target_file → file。
static var _preview: Dictionary = {}
static var _tex_cache: Dictionary = {}
static var _box_cache: Dictionary = {}


## 内容表里的图是 assets/…，补上 res://。
static func res(path: String) -> String:
	if path == "" or path.begins_with("res://"):
		return path
	return "res://" + path


static func has_art(path: String) -> bool:
	return path != "" and (ResourceLoader.exists(res(path)) or _preview.has(res(path)))


## 读审阅清单（additions_manifest.json 的 assets 与 shared_frames），返回登记了几张。
static func preview_load(manifest: String) -> int:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
	if not (d is Dictionary):
		return 0
	var base: String = ProjectSettings.globalize_path("res://")
	var n: int = 0
	for key: String in ["assets", "shared_frames"]:
		for a: Variant in (d as Dictionary).get(key, []):
			if not (a is Dictionary):
				continue
			var src: String = base.path_join(String((a as Dictionary).get("file", "")))
			if FileAccess.file_exists(src):
				_preview[res(String((a as Dictionary).get("target_file", "")))] = src
				n += 1
	_tex_cache.clear()
	return n


## 取图：游戏路径里有就照常载入；审阅预览时从审核目录读原图（长边缩到 768 以内并做多级纹理，省内存、缩小不起锯齿）。
static func tex(path: String) -> Texture2D:
	var p: String = res(path)
	if p == "":
		return null
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	if not _preview.has(p):
		return null
	if _tex_cache.has(p):
		return _tex_cache[p] as Texture2D
	var src: String = String(_preview[p])
	var img: Image = null
	if src.get_extension().to_lower() == "svg":
		img = Image.new()
		if img.load_svg_from_string(FileAccess.get_file_as_string(src), 1.0) != OK:
			return null
	else:
		img = Image.load_from_file(src)
	if img == null or img.is_empty():
		return null
	var m: int = maxi(img.get_width(), img.get_height())
	if m > 768:
		var k: float = 768.0 / float(m)
		img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	var t: ImageTexture = ImageTexture.create_from_image(img)
	_tex_cache[p] = t
	return t


## 政令配图：给了档位就先找那一档的图；不分档的那张没有时，退到第 0 档的图；都没有返回不分档的路径（显示占位）。
static func decree_art(id: String, level: int = -1) -> String:
	if level >= 0:
		var lp: String = DECREE_LEVEL_ART % [id, level]
		if has_art(lp):
			return lp
	var p: String = DECREE_ART % id
	if not has_art(p):
		var l0: String = DECREE_LEVEL_ART % [id, 0]
		if has_art(l0):
			return l0
	return p


## 图标：有图用图（等比居中）；没图用占位圆章，写名字的头一个字。
static func badge(path: String, side: float, name_text: String = "", tone_token: String = "line.strong") -> Control:
	var tx: Texture2D = tex(path) if has_art(path) else null
	if tx != null:
		var tr: TextureRect = TextureRect.new()
		tr.texture = tx
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.custom_minimum_size = Vector2(side, side)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var gl: JcGlyph = JcGlyph.new()
	gl.text = name_text.substr(0, 1)
	gl.tone = tone_token
	gl.custom_minimum_size = Vector2(side, side)
	return gl


## 圈里放图：小图（情绪小脸）外面套一道状态色的圈，图小到看不清时颜色照样说明好坏；没图时写一个字。
static func ringed(path: String, side: float, name_text: String, tone_token: String) -> Control:
	var gl: JcGlyph = JcGlyph.new()
	gl.image = tex(path) if has_art(path) else null
	gl.text = name_text.substr(0, 1)
	gl.tone = tone_token
	gl.custom_minimum_size = Vector2(side, side)
	return gl


## 科技徽章：底板 ＋ 主体图 ＋ 本时代的框（见 JcTechBadge）。tone 是状态色，dim 是还不能研究。
static func tech_badge(id: String, era: int, side: float, name_text: String, tone_token: String, dim: bool = false) -> Control:
	var b: JcTechBadge = JcTechBadge.new()
	b.subject = tex(TECH_ART % id) if has_art(TECH_ART % id) else null
	var fp: String = TECH_FRAME % clampi(era, 1, 4)
	b.frame = tex(fp) if has_art(fp) else null
	b.tone = tone_token
	b.dim = dim
	b.glyph = name_text.substr(0, 1)
	b.custom_minimum_size = Vector2(side, side)
	return b



## 只取图里看得见的那一块（细长装饰四周有大片透明边，整张缩放会小得看不清），按图缓存。
static func cropped(path: String) -> Texture2D:
	var t: Texture2D = tex(path) if has_art(path) else null
	if t == null:
		return null
	var key: String = "crop:" + res(path)
	if _tex_cache.has(key):
		return _tex_cache[key] as Texture2D
	var b: Rect2 = content_box(t)
	var w: float = float(t.get_width())
	var h: float = float(t.get_height())
	var r: Rect2 = Rect2(b.position.x * w, b.position.y * h, b.size.x * w, b.size.y * h).grow(minf(w, h) * 0.03)
	r = r.intersection(Rect2(0, 0, w, h))
	var at: AtlasTexture = AtlasTexture.new()
	at.atlas = t
	at.region = r
	_tex_cache[key] = at
	return at


## 装饰上压一行字：装饰按原比例放（高 h），字居中压在上面（字由界面排，不画进图里）。没图时只有字。
static func ornament(path: String, text: String, h: float, role: String = "title_sub", tone_token: String = "text.primary") -> Control:
	var tx: Texture2D = cropped(path)
	var l: Label = JwUi.label(text, role, tone_token)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if tx == null:
		return l
	var holder: Control = Control.new()
	var w: float = h * float(tx.get_width()) / maxf(1.0, float(tx.get_height()))
	holder.custom_minimum_size = Vector2(maxf(w, l.get_minimum_size().x + 24.0), h)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr: TextureRect = TextureRect.new()
	tr.texture = tx
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(tr)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(l)
	return holder


## 图里看得见的部分占整张的范围（0—1 的比例，alpha≥16 才算），按图缓存；读不到像素时返回整张。
static func content_box(t: Texture2D) -> Rect2:
	if t == null:
		return Rect2(0, 0, 1, 1)
	var key: int = t.get_instance_id()
	if _box_cache.has(key):
		return _box_cache[key] as Rect2
	var r: Rect2 = Rect2(0, 0, 1, 1)
	var img: Image = t.get_image()
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var w: int = 128
		var h: int = maxi(1, int(128.0 * float(img.get_height()) / maxf(1.0, float(img.get_width()))))
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
		var data: PackedByteArray = img.get_data()
		var x0: int = w
		var y0: int = h
		var x1: int = -1
		var y1: int = -1
		for y: int in h:
			for x: int in w:
				if data[(y * w + x) * 4 + 3] >= 16:
					x0 = mini(x0, x)
					y0 = mini(y0, y)
					x1 = maxi(x1, x)
					y1 = maxi(y1, y)
		if x1 >= 0:
			r = Rect2(float(x0) / w, float(y0) / h, float(x1 - x0 + 1) / w, float(y1 - y0 + 1) / h)
	_box_cache[key] = r
	return r


## 按好坏给色：好（青绿）、要注意（赭）、坏（橙红）。
static func tone(good: bool, warn: bool = false) -> String:
	if good:
		return GOOD
	return WARN if warn else BAD


## 按钮配小图标（图在才配；icon_max_width 限住大小，原图再大也只画这么大）。
static func set_icon(b: Button, path: String, side: int = 22) -> void:
	var tx: Texture2D = tex(path) if has_art(path) else null
	b.icon = tx
	if tx != null:
		b.add_theme_constant_override("icon_max_width", side)
		b.expand_icon = false
		b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## 走势小箭头：比上一期涨了、跌了、差不多（变化不到 0.2% 算持平）。
static func trend_icon(now: int, before: int) -> String:
	if before <= 0:
		return ""
	var r: int = JCMath.ratio_ppm(now - before, before)
	return STATUS_ICON % ("trend_up" if r >= 2_000 else ("trend_down" if r <= -2_000 else "trend_flat"))


## 带小图标的标签：图 + 字（图不在就只有字）。
static func icon_label(path: String, text: String, role: String = "body", tone_token: String = "text.secondary",
		side: float = 20.0) -> HBoxContainer:
	var h: HBoxContainer = JwUi.hbox(5)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if has_art(path):
		h.add_child(icon(path, side))
	var l: Label = JwUi.label(text, role, tone_token)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return h


## 数字卡：小标题 + 大数字 + 一行说明（可带颜色）；给了图标就放在左边。
static func tile(label: String, value: String, sub: String = "", sub_tone: String = MUTED, tip: String = "",
		icon_path: String = "", sub_icon: String = "") -> PanelContainer:
	var p: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.panel", "line.hair", 1, 14, 10, 14, 10))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v: VBoxContainer = JwUi.vbox(2)
	if has_art(icon_path):
		var hb: HBoxContainer = JwUi.hbox(10)
		var ic: Control = icon(icon_path, 34.0)
		ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		hb.add_child(ic)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(v)
		p.add_child(hb)
	else:
		p.add_child(v)
	v.add_child(JwUi.label(label, "caption", "text.muted"))
	var big: Label = JwUi.label(value, "block_num", "text.primary")
	v.add_child(big)
	if sub != "" and has_art(sub_icon):
		v.add_child(icon_label(sub_icon, sub, "caption", sub_tone, 16.0))
	elif sub != "":
		v.add_child(JwUi.label(sub, "caption", sub_tone, true))
	if tip != "":
		p.tooltip_text = tip
		p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


static func chip(text: String, tone_token: String = MUTED, filled: bool = false, icon_path: String = "") -> PanelContainer:
	var p: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.raised" if not filled else "bg.abyss", tone_token, 1, 8, 2, 8, 2))
	if has_art(icon_path):
		p.add_child(icon_label(icon_path, text, "caption", tone_token, 16.0))
	else:
		p.add_child(JwUi.label(text, "caption", tone_token))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


## 卡片：标题（可带副标题与右侧按钮区）+ 内容。返回 {root, body, head}。
static func card(title: String, subtitle: String = "", pad: int = 14) -> Dictionary:
	var root: PanelContainer = JwUi.panel("bg.panel", "line.hair", pad)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v: VBoxContainer = JwUi.vbox(10)
	root.add_child(v)
	var head: HBoxContainer = JwUi.hbox(10)
	head.add_child(JwUi.label(title, "title_sub", "text.primary"))
	if subtitle != "":
		var s: Label = JwUi.label(subtitle, "caption", "text.muted")
		s.size_flags_vertical = Control.SIZE_SHRINK_END
		head.add_child(s)
	head.add_child(JwUi.spacer())
	v.add_child(head)
	var body: VBoxContainer = JwUi.vbox(8)
	v.add_child(body)
	return {"root": root, "body": body, "head": head}


## 小图标（顾问徽记、托管图标）：图在就显示，不在就什么都不放（不留色块）。
static func icon(path: String, side: float) -> Control:
	var tx: Texture2D = tex(path) if has_art(path) else null
	if tx == null:
		var spacer: Control = Control.new()
		spacer.custom_minimum_size = Vector2(0, 0)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return spacer
	var tr: TextureRect = TextureRect.new()
	tr.texture = tx
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.custom_minimum_size = Vector2(side, side)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## 配图（路径不存在就返回一块底色）。
static func art(path: String, size: Vector2, cover: bool = true) -> Control:
	var tx: Texture2D = tex(path) if has_art(path) else null
	if tx != null:
		var tr: TextureRect = TextureRect.new()
		tr.texture = tx
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.custom_minimum_size = size
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if cover else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.clip_contents = true
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var c: ColorRect = ColorRect.new()
	c.color = JwTheme.c("bg.abyss")
	c.custom_minimum_size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func meter(ppm: int, tone_token: String = GOOD, width: float = 140.0, height: float = 8.0,
		marker_ppm: int = -1) -> JcMeter:
	var m: JcMeter = JcMeter.new()
	m.value = clampi(ppm, 0, 1_000_000)
	m.token = tone_token
	m.marker = marker_ppm
	m.custom_minimum_size = Vector2(width, height)
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return m


## 一行：左标签、右数值，中间一条进度（可选）。
static func row(label: String, value: String, value_tone: String = "text.primary", meter_ppm: int = -1,
		meter_tone: String = GOOD) -> HBoxContainer:
	var h: HBoxContainer = JwUi.hbox(10)
	var l: Label = JwUi.label(label, "body", "text.secondary")
	l.custom_minimum_size = Vector2(110, 0)
	h.add_child(l)
	if meter_ppm >= 0:
		var m: JcMeter = meter(meter_ppm, meter_tone, 120.0)
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(m)
	else:
		h.add_child(JwUi.spacer())
	h.add_child(JwUi.label(value, "num", value_tone))
	return h


static func button(text: String, primary: bool = false, cb: Callable = Callable()) -> Button:
	var b: Button = JwUi.button(text, "PrimaryButton" if primary else "")
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func link(text: String, cb: Callable) -> Button:
	var b: Button = JwUi.link(text)
	b.pressed.connect(cb)
	return b


static func spark(values: Array, token: String = GOOD, size: Vector2 = Vector2(220, 56)) -> JcSpark:
	var s: JcSpark = JcSpark.new()
	s.values = values
	s.token = token
	s.custom_minimum_size = size
	return s


static func grid(cols: int, hsep: int = 10, vsep: int = 10) -> GridContainer:
	var g: GridContainer = GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", hsep)
	g.add_theme_constant_override("v_separation", vsep)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g


static func flow(hsep: int = 8, vsep: int = 8) -> HFlowContainer:
	var f: HFlowContainer = HFlowContainer.new()
	f.add_theme_constant_override("h_separation", hsep)
	f.add_theme_constant_override("v_separation", vsep)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return f
