## 三类信息与严重度的枚举（docs/20 §3.1、§9.1）及其呈现字样。
##
## 三类信息：已经发生 ACTUAL（实）/ 规则推断 DERIVED（算）/ 情景预测 PROJECTED（预）。
## NONE 只给不承载数字的说明块用，任何数字控件都不得取 NONE（调试构建下渲染红底占位）。
## 严重度：NOTE（提示）< GAP（缺口）< BLOCK（阻断）。
class_name JwInfo
extends RefCounted

enum Cls { ACTUAL = 0, DERIVED = 1, PROJECTED = 2, NONE = 3 }
enum Sev { NOTE = 0, GAP = 1, BLOCK = 2 }


## 徽章字：实 / 算 / 预。
static func badge(c: int) -> String:
	match c:
		Cls.ACTUAL:
			return JwText.t("cls.badge.actual")
		Cls.DERIVED:
			return JwText.t("cls.badge.derived")
		Cls.PROJECTED:
			return JwText.t("cls.badge.projected")
	return ""


## 词前缀：实记 · / 推算 · / 预测 · （散文行最左）。
static func prefix(c: int) -> String:
	match c:
		Cls.ACTUAL:
			return JwText.t("cls.prefix.actual")
		Cls.DERIVED:
			return JwText.t("cls.prefix.derived")
		Cls.PROJECTED:
			return JwText.t("cls.prefix.projected")
	return ""


static func cls_name(c: int) -> String:
	match c:
		Cls.ACTUAL:
			return JwText.t("cls.name.actual")
		Cls.DERIVED:
			return JwText.t("cls.name.derived")
		Cls.PROJECTED:
			return JwText.t("cls.name.projected")
	return ""


## 图标种类名（JwIcon.kind）。
static func icon_kind(c: int) -> String:
	match c:
		Cls.ACTUAL:
			return "actual"
		Cls.DERIVED:
			return "derived"
		Cls.PROJECTED:
			return "projected"
	return ""


## 标尺与图标的色板 token（赭色不用于三类信息，docs/20 §12.2）。
static func color_token(c: int, paper: bool = false) -> String:
	match c:
		Cls.ACTUAL:
			return "teal.deep" if paper else "teal.core"
		Cls.DERIVED:
			return "text.ink2" if paper else "line.strong"
		Cls.PROJECTED:
			return "warm.ink" if paper else "warm.text"
	return "text.muted"


## 严重度的等级词（AC-38：提示 / 需要注意 / 需立即处理）。
static func sev_word(s: int) -> String:
	match s:
		Sev.BLOCK:
			return JwText.t("sev.word.block")
		Sev.GAP:
			return JwText.t("sev.word.gap")
	return JwText.t("sev.word.note")


## 严重度类别名（阻断 / 缺口 / 提示）。
static func sev_name(s: int) -> String:
	match s:
		Sev.BLOCK:
			return JwText.t("sev.name.block")
		Sev.GAP:
			return JwText.t("sev.name.gap")
	return JwText.t("sev.name.note")


static func sev_icon(s: int) -> String:
	match s:
		Sev.BLOCK:
			return "block"
		Sev.GAP:
			return "warn"
	return "note"


static func sev_color_token(s: int, paper: bool = false) -> String:
	if s == Sev.BLOCK:
		return "ochre.ink" if paper else "ochre.hot"
	return "ochre.ink" if paper else "ochre.core"
