## 缩放与断点（docs/20 §5.2、§5.3）。
##
## 唯一缩放入口：`Window.content_scale_factor = ui_scale`，项目设置 stretch/mode = disabled。
## ui_scale 的确定顺序（前者优先）：
##   1 命令行 `--ui-scale=1.00|1.25|1.50`（测试与验收一律走这条）；
##   2 用户设置 user://ui_settings.cfg 的 [display] ui_scale；
##   3 snap({1.00, 1.25, 1.50}, screen_get_dpi / 96)，clamp 到 [1.00, 1.50]。
## 禁止使用 DisplayServer.screen_get_scale()：它在 Windows 上恒返回 1.0（B-16）。
class_name JwScale
extends RefCounted

const SETTINGS_PATH: String = "user://ui_settings.cfg"
const STEPS: PackedFloat64Array = [1.0, 1.25, 1.5]

## 宽档
enum WBand { WIDE = 0, MID = 1, UNSUPPORTED = 2 }
## 高档（按主区高）
enum HBand { TALL = 0, MID = 1, SHORT = 2 }

const TOPBAR_H: int = 56
const TABS_H: int = 40
const DOCK_H_TALL: int = 104
const DOCK_H_SHORT: int = 80
const MIN_LOGICAL: Vector2i = Vector2i(1280, 720)


## 命令行参数（`--ui-scale=` 与 `--window-size=`），用户参数与引擎参数都查。
static func cmd_value(prefix: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	for a: String in OS.get_cmdline_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


static func snap(v: float) -> float:
	var best: float = STEPS[0]
	var best_d: float = 99.0
	for s: float in STEPS:
		var d: float = absf(v - s)
		if d < best_d:
			best_d = d
			best = s
	return clampf(best, 1.0, 1.5)


## 解析 ui_scale，并返回 {scale, source, dpi}（启动时写调试日志）。
static func resolve() -> Dictionary:
	var arg: String = cmd_value("--ui-scale=")
	if arg != "" and arg.is_valid_float():
		return {"scale": snap(arg.to_float()), "source": "cmdline", "dpi": -1}
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and cfg.has_section_key("display", "ui_scale"):
		var v: float = float(cfg.get_value("display", "ui_scale", 1.0))
		return {"scale": snap(v), "source": "settings", "dpi": -1}
	var dpi: int = 96
	if DisplayServer.get_name() != "headless":
		dpi = DisplayServer.screen_get_dpi(DisplayServer.window_get_current_screen())
	if dpi <= 0:
		dpi = 96
	return {"scale": snap(float(dpi) / 96.0), "source": "dpi", "dpi": dpi}


static func save_scale(v: float) -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("display", "ui_scale", snap(v))
	cfg.save(SETTINGS_PATH)


static func dock_height(logical_h: float) -> int:
	return DOCK_H_TALL if logical_h >= 900.0 else DOCK_H_SHORT


static func body_height(logical: Vector2) -> float:
	return logical.y - TOPBAR_H - TABS_H - dock_height(logical.y)


static func width_band(logical_w: float) -> int:
	if logical_w >= 1600.0:
		return WBand.WIDE
	if logical_w >= 1280.0:
		return WBand.MID
	return WBand.UNSUPPORTED


static func height_band(body_h: float) -> int:
	if body_h >= 800.0:
		return HBand.TALL
	if body_h >= 640.0:
		return HBand.MID
	return HBand.SHORT
