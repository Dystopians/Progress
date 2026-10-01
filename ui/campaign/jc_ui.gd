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
## 满额（ppm）
const PPM_ONE: int = 1_000_000


## 内容表里的图是 assets/…，补上 res://。
static func res(path: String) -> String:
	if path == "" or path.begins_with("res://"):
		return path
	return "res://" + path


static func has_art(path: String) -> bool:
	return path != "" and ResourceLoader.exists(res(path))


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
	if has_art(path):
		var tr: TextureRect = TextureRect.new()
		tr.texture = load(res(path)) as Texture2D
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


## 按好坏给色：好（青绿）、要注意（赭）、坏（橙红）。
static func tone(good: bool, warn: bool = false) -> String:
	if good:
		return GOOD
	return WARN if warn else BAD


## 数字卡：小标题 + 大数字 + 一行说明（可带颜色）。
static func tile(label: String, value: String, sub: String = "", sub_tone: String = MUTED, tip: String = "") -> PanelContainer:
	var p: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.panel", "line.hair", 1, 14, 10, 14, 10))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v: VBoxContainer = JwUi.vbox(2)
	p.add_child(v)
	v.add_child(JwUi.label(label, "caption", "text.muted"))
	var big: Label = JwUi.label(value, "block_num", "text.primary")
	v.add_child(big)
	if sub != "":
		v.add_child(JwUi.label(sub, "caption", sub_tone, true))
	if tip != "":
		p.tooltip_text = tip
		p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


static func chip(text: String, tone_token: String = MUTED, filled: bool = false) -> PanelContainer:
	var p: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.raised" if not filled else "bg.abyss", tone_token, 1, 8, 2, 8, 2))
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
	if path == "" or not ResourceLoader.exists(path):
		var spacer: Control = Control.new()
		spacer.custom_minimum_size = Vector2(0, 0)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return spacer
	var tr: TextureRect = TextureRect.new()
	tr.texture = load(path) as Texture2D
	tr.custom_minimum_size = Vector2(side, side)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## 配图（路径不存在就返回一块底色）。
static func art(path: String, size: Vector2, cover: bool = true) -> Control:
	if path != "" and ResourceLoader.exists(path):
		var tr: TextureRect = TextureRect.new()
		tr.texture = load(path) as Texture2D
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
