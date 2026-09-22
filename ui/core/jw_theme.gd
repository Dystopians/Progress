## 视觉语言（docs/20 §12）：色板、字体、主题与 StyleBox。
##
## 色板唯一来源：res://ui/theme/palette.json。字体一律用 SystemFont，不随包分发字体文件：
##   无衬线（正文）：Microsoft YaHei UI → Microsoft YaHei → PingFang SC → Noto Sans CJK SC → SimHei
##   数字（tnum）：Segoe UI → Arial，CJK 放 fallbacks（FT-1）
##   标题：与正文同一 CJK 字族，字重 600。docs/20 §12.4 的衬线标题需要随包分发 Noto Serif SC，
##   本版遵守「中文一律用上列 SystemFont、不下载字体文件」的约束，不使用系统衬线（如 SimSun）替代。
##   等宽（引用码、hash、算式）：Consolas → Cascadia Mono → Courier New
## 全部字号按 lu 字面值编写；缩放只经 Window.content_scale_factor（docs/20 §5.2）。
class_name JwTheme
extends RefCounted

const PALETTE_PATH: String = "res://ui/theme/palette.json"

const SANS_NAMES: PackedStringArray = [
	"Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "SimHei",
]
const NUM_NAMES: PackedStringArray = ["Segoe UI", "Arial", "Helvetica"]
const MONO_NAMES: PackedStringArray = ["Consolas", "Cascadia Mono", "Courier New"]

## 字体角色（docs/20 §12.4）：[字族, 字号 lu, 字重]。
const ROLES: Dictionary = {
	"title_page": ["serif", 26, 600],
	"title_block": ["serif", 20, 600],
	"title_sub": ["sans", 17, 600],
	"body": ["sans", 16, 400],
	"body_bold": ["sans", 16, 600],
	"dense": ["sans", 16, 400],
	"hero": ["num", 34, 600],
	"block_num": ["num", 24, 600],
	"num": ["num", 16, 500],
	"num_bold": ["num", 16, 600],
	"caption": ["sans", 14, 400],
	"mono": ["mono", 16, 400],
	"tab": ["sans", 17, 600],
}

## 间距 token（lu，基数 4）。
const S1: int = 4
const S2: int = 8
const S3: int = 12
const S4: int = 16
const S5: int = 24
const S6: int = 32

static var _palette: Dictionary = {}
static var _fonts: Dictionary = {}
static var _theme: Theme = null


static func _ensure_palette() -> void:
	if not _palette.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PALETTE_PATH))
	if not (parsed is Dictionary):
		push_error("JwTheme: palette missing")
		return
	var tokens: Variant = (parsed as Dictionary).get("tokens", {})
	if tokens is Dictionary:
		for k: Variant in (tokens as Dictionary).keys():
			var rec: Variant = (tokens as Dictionary)[k]
			if rec is Dictionary:
				_palette[String(k)] = Color.html(String((rec as Dictionary).get("hex", "#FF00FF")))


## 色板取色；未知 token 返回洋红并 push_error（色板是唯一来源，不许临时造色）。
static func c(token: String) -> Color:
	_ensure_palette()
	if _palette.has(token):
		return _palette[token]
	push_error("JwTheme: unknown color token " + token)
	return Color.MAGENTA


static func has_token(token: String) -> bool:
	_ensure_palette()
	return _palette.has(token)


static func palette_tokens() -> PackedStringArray:
	_ensure_palette()
	var out: PackedStringArray = PackedStringArray()
	for k: Variant in _palette.keys():
		out.append(String(k))
	return out


static func _sys_font(names: PackedStringArray, weight: int) -> SystemFont:
	var f: SystemFont = SystemFont.new()
	f.font_names = names
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.allow_system_fallback = true
	return f


## 按字族与字重取字体（缓存）。
static func family_font(family: String, weight: int) -> Font:
	var key: String = family + "@" + str(weight)
	if _fonts.has(key):
		return _fonts[key]
	var cjk: SystemFont = _sys_font(SANS_NAMES, weight)
	var fb: Array[Font] = [cjk]
	var out: Font = null
	match family:
		"sans":
			out = cjk
		"num":
			var nf: SystemFont = _sys_font(NUM_NAMES, weight)
			nf.fallbacks = fb
			var fv: FontVariation = FontVariation.new()
			fv.base_font = nf
			var tags: Dictionary = {}
			tags[TextServerManager.get_primary_interface().name_to_tag("tnum")] = 1
			fv.opentype_features = tags
			out = fv
		"serif":
			out = cjk
		"mono":
			var mf: SystemFont = _sys_font(MONO_NAMES, weight)
			mf.fallbacks = fb
			out = mf
		_:
			out = cjk
	_fonts[key] = out
	return out


static func font(role: String) -> Font:
	var r: Array = ROLES.get(role, ROLES["body"])
	return family_font(String(r[0]), int(r[2]))


static func size(role: String) -> int:
	var r: Array = ROLES.get(role, ROLES["body"])
	return int(r[1])


## 纯色 StyleBox。pad 为四边内边距（lu）。
static func box(bg_token: String, border_token: String = "", border_w: int = 0, radius: int = 2,
		pad: int = 0) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	if bg_token == "":
		sb.draw_center = false
	else:
		sb.bg_color = c(bg_token)
	if border_token != "" and border_w > 0:
		sb.border_color = c(border_token)
		sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	sb.anti_aliasing = false
	return sb


static func box4(bg_token: String, border_token: String, bw: int, l: int, t: int, r: int,
		b: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = box(bg_token, border_token, bw, 2, 0)
	sb.content_margin_left = l
	sb.content_margin_top = t
	sb.content_margin_right = r
	sb.content_margin_bottom = b
	return sb


## 左侧粗边的面板（告警态左边框 3 lu 赭色，docs/20 §8.1）。
static func box_left_rule(bg_token: String, rule_token: String, rule_w: int, pad: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = box(bg_token, "", 0, 2, pad)
	sb.border_color = c(rule_token)
	sb.border_width_left = rule_w
	return sb


static func focus_box() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = c("focus.ring")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	sb.expand_margin_left = 2
	sb.expand_margin_right = 2
	sb.expand_margin_top = 2
	sb.expand_margin_bottom = 2
	return sb


## 全局主题（缓存）。
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var th: Theme = Theme.new()
	th.default_font = font("body")
	th.default_font_size = size("body")

	th.set_color("font_color", "Label", c("text.primary"))
	th.set_constant("line_spacing", "Label", 4)

	var btn_normal: StyleBoxFlat = box4("bg.raised", "line.strong", 1, 12, 6, 12, 6)
	var btn_hover: StyleBoxFlat = box4("bg.raised", "focus.ring", 1, 12, 6, 12, 6)
	var btn_pressed: StyleBoxFlat = box4("bg.abyss", "focus.ring", 1, 12, 6, 12, 6)
	var btn_disabled: StyleBoxFlat = box4("bg.panel", "line.hair", 1, 12, 6, 12, 6)
	th.set_stylebox("normal", "Button", btn_normal)
	th.set_stylebox("hover", "Button", btn_hover)
	th.set_stylebox("pressed", "Button", btn_pressed)
	th.set_stylebox("hover_pressed", "Button", btn_pressed)
	th.set_stylebox("disabled", "Button", btn_disabled)
	th.set_stylebox("focus", "Button", focus_box())
	th.set_color("font_color", "Button", c("text.primary"))
	th.set_color("font_hover_color", "Button", c("text.primary"))
	th.set_color("font_pressed_color", "Button", c("text.primary"))
	th.set_color("font_focus_color", "Button", c("text.primary"))
	th.set_color("font_disabled_color", "Button", c("text.muted"))
	th.set_font("font", "Button", font("body"))
	th.set_font_size("font_size", "Button", size("body"))

	# 主按钮：青绿底 + 深墨字（docs/20 §12.1：主按钮上的文字用 text.ink，不用纯白）。
	th.set_type_variation("PrimaryButton", "Button")
	th.set_stylebox("normal", "PrimaryButton", box4("teal.core", "", 0, 16, 8, 16, 8))
	th.set_stylebox("hover", "PrimaryButton", box4("focus.ring", "", 0, 16, 8, 16, 8))
	th.set_stylebox("pressed", "PrimaryButton", box4("teal.dim", "", 0, 16, 8, 16, 8))
	th.set_stylebox("hover_pressed", "PrimaryButton", box4("teal.dim", "", 0, 16, 8, 16, 8))
	th.set_color("font_color", "PrimaryButton", c("text.ink"))
	th.set_color("font_hover_color", "PrimaryButton", c("text.ink"))
	th.set_color("font_pressed_color", "PrimaryButton", c("text.primary"))
	th.set_color("font_focus_color", "PrimaryButton", c("text.ink"))
	th.set_font("font", "PrimaryButton", font("body_bold"))

	# 警示按钮（不可推进时的描边：赭色深档，docs/20 §12.2）。
	th.set_type_variation("AlertButton", "Button")
	th.set_stylebox("normal", "AlertButton", box4("bg.raised", "ochre.hot", 2, 16, 8, 16, 8))
	th.set_stylebox("hover", "AlertButton", box4("bg.raised", "ochre.core", 2, 16, 8, 16, 8))
	th.set_stylebox("pressed", "AlertButton", box4("bg.abyss", "ochre.core", 2, 16, 8, 16, 8))
	th.set_color("font_color", "AlertButton", c("text.primary"))
	th.set_color("font_hover_color", "AlertButton", c("text.primary"))
	th.set_font("font", "AlertButton", font("body_bold"))

	# 链接式按钮（进入台账、跳页）。
	th.set_type_variation("LinkBtn", "Button")
	var flat: StyleBoxFlat = box4("", "", 0, 4, 4, 4, 4)
	th.set_stylebox("normal", "LinkBtn", flat)
	th.set_stylebox("hover", "LinkBtn", box4("bg.raised", "", 0, 4, 4, 4, 4))
	th.set_stylebox("pressed", "LinkBtn", box4("bg.abyss", "", 0, 4, 4, 4, 4))
	th.set_color("font_color", "LinkBtn", c("teal.core"))
	th.set_color("font_hover_color", "LinkBtn", c("focus.ring"))
	th.set_color("font_pressed_color", "LinkBtn", c("focus.ring"))
	th.set_color("font_focus_color", "LinkBtn", c("teal.core"))

	# 页签（选中态用 3 lu 底线 + 粗体，不靠颜色单独表达）。
	th.set_type_variation("TabBtn", "Button")
	th.set_stylebox("normal", "TabBtn", box4("bg.panel", "", 0, 18, 6, 18, 6))
	th.set_stylebox("hover", "TabBtn", box4("bg.raised", "", 0, 18, 6, 18, 6))
	var tab_sel: StyleBoxFlat = box4("bg.base", "", 0, 18, 6, 18, 6)
	tab_sel.border_color = c("teal.core")
	tab_sel.border_width_bottom = 3
	th.set_stylebox("pressed", "TabBtn", tab_sel)
	th.set_stylebox("hover_pressed", "TabBtn", tab_sel)
	th.set_color("font_color", "TabBtn", c("text.secondary"))
	th.set_color("font_pressed_color", "TabBtn", c("text.primary"))
	th.set_color("font_hover_color", "TabBtn", c("text.primary"))
	th.set_color("font_hover_pressed_color", "TabBtn", c("text.primary"))
	th.set_font("font", "TabBtn", font("tab"))
	th.set_font_size("font_size", "TabBtn", size("tab"))

	th.set_stylebox("panel", "PanelContainer", box("bg.panel", "", 0, 2, 0))
	th.set_stylebox("panel", "Panel", box("bg.panel", "", 0, 2, 0))

	var edit: StyleBoxFlat = box4("bg.abyss", "line.strong", 1, 8, 4, 8, 4)
	th.set_stylebox("normal", "LineEdit", edit)
	th.set_stylebox("focus", "LineEdit", focus_box())
	th.set_stylebox("read_only", "LineEdit", box4("bg.panel", "line.hair", 1, 8, 4, 8, 4))
	th.set_color("font_color", "LineEdit", c("text.primary"))
	th.set_color("caret_color", "LineEdit", c("focus.ring"))
	th.set_color("selection_color", "LineEdit", c("teal.dim"))

	th.set_stylebox("normal", "OptionButton", btn_normal)
	th.set_stylebox("hover", "OptionButton", btn_hover)
	th.set_stylebox("pressed", "OptionButton", btn_pressed)
	th.set_stylebox("focus", "OptionButton", focus_box())
	th.set_color("font_color", "OptionButton", c("text.primary"))
	th.set_color("font_hover_color", "OptionButton", c("text.primary"))

	th.set_color("font_color", "CheckBox", c("text.primary"))
	th.set_color("font_hover_color", "CheckBox", c("text.primary"))
	th.set_color("font_pressed_color", "CheckBox", c("text.primary"))
	th.set_stylebox("focus", "CheckBox", focus_box())

	th.set_stylebox("slider", "HSlider", box("bg.abyss", "line.strong", 1, 2, 0))
	th.set_stylebox("grabber_area", "HSlider", box("teal.dim", "", 0, 2, 0))
	th.set_stylebox("grabber_area_highlight", "HSlider", box("teal.core", "", 0, 2, 0))
	th.set_stylebox("focus", "HSlider", focus_box())

	th.set_stylebox("panel", "TooltipPanel", box4("bg.raised", "line.strong", 1, 10, 8, 10, 8))
	th.set_color("font_color", "TooltipLabel", c("text.primary"))
	th.set_font("font", "TooltipLabel", font("body"))
	th.set_font_size("font_size", "TooltipLabel", size("body"))

	th.set_stylebox("panel", "PopupMenu", box4("bg.raised", "line.strong", 1, 6, 6, 6, 6))
	th.set_stylebox("hover", "PopupMenu", box("bg.abyss", "", 0, 2, 0))
	th.set_color("font_color", "PopupMenu", c("text.primary"))
	th.set_color("font_hover_color", "PopupMenu", c("text.primary"))

	th.set_stylebox("panel", "Tree", box("bg.panel", "line.hair", 1, 2, 0))
	th.set_stylebox("focus", "Tree", focus_box())
	th.set_stylebox("selected", "Tree", box("bg.raised", "focus.ring", 1, 2, 0))
	th.set_stylebox("selected_focus", "Tree", box("bg.raised", "focus.ring", 1, 2, 0))
	th.set_stylebox("title_button_normal", "Tree", box4("bg.raised", "", 0, 6, 4, 6, 4))
	th.set_color("font_color", "Tree", c("text.secondary"))
	th.set_color("font_selected_color", "Tree", c("text.primary"))
	th.set_color("title_button_color", "Tree", c("text.primary"))
	th.set_color("guide_color", "Tree", c("line.hair"))
	th.set_constant("v_separation", "Tree", 10)
	th.set_constant("h_separation", "Tree", 12)

	th.set_stylebox("separator", "HSeparator", box("line.hair", "", 0, 0, 0))
	th.set_constant("separation", "HSeparator", 9)
	th.set_stylebox("separator", "VSeparator", box("line.hair", "", 0, 0, 0))

	th.set_stylebox("background", "ProgressBar", box("bg.abyss", "line.strong", 1, 2, 0))
	th.set_stylebox("fill", "ProgressBar", box("teal.core", "", 0, 2, 0))
	th.set_color("font_color", "ProgressBar", c("text.primary"))

	th.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	_theme = th
	return th
