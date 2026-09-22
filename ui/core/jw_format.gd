## 数字格式化器（docs/21 §1.5）：内部整数 → 显示字符串。
##
## **只做整数运算**，舍入统一为「离零取半」，只在显示层发生，不回写状态。
## 标度与 docs/10 §0.1 一致：1 U = 1 000 000 000 μU；比率与指数为 ppm；数量 1 Q = 1 000 000 μQ。
## 非零显示为零的禁令：|v| 不足最小显示单位时渲染固定词「小于 0.01 U」，不渲染 0.00。
## 单位与量词等中文字样一律取自文案表（JwText），本文件不含中文字面量。
class_name JwFormat
extends RefCounted

const U_SCALE: int = 1_000_000_000
const CENT_UU: int = 10_000_000
const PPM: int = 1_000_000
const Q_SCALE: int = 1_000_000
const MINUS: String = "−"
const EN_DASH: String = "–"
const RANGE_OPEN: String = "〔"
const RANGE_CLOSE: String = "〕"


## 离零取半的整数除法（b > 0）。
static func round_div(a: int, b: int) -> int:
	if b <= 0:
		return 0
	var s: int = -1 if a < 0 else 1
	var m: int = absi(a)
	@warning_ignore("integer_division")
	var q: int = (m + b / 2) / b
	return s * q


## 半角千分位。
static func group3(n: int) -> String:
	var neg: bool = n < 0
	var s: String = str(absi(n))
	var out: String = ""
	var cnt: int = 0
	var i: int = s.length() - 1
	while i >= 0:
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
		i -= 1
	return (MINUS if neg else "") + out


## 定点两位小数（cents 已是 1/100 单位的整数）。
static func _fixed2(cents: int) -> String:
	var neg: bool = cents < 0
	var a: int = absi(cents)
	@warning_ignore("integer_division")
	var whole: int = a / 100
	var frac: int = a % 100
	var fs: String = str(frac) if frac >= 10 else "0" + str(frac)
	return (MINUS if neg else "") + group3(whole) + "." + fs


## 定点一位小数（tenths 是 1/10 单位的整数）。
static func _fixed1(tenths: int) -> String:
	var neg: bool = tenths < 0
	var a: int = absi(tenths)
	@warning_ignore("integer_division")
	var whole: int = a / 10
	var frac: int = a % 10
	return (MINUS if neg else "") + group3(whole) + "." + str(frac)


## 金额：`1,204.35 U`。
static func u(v_uu: int) -> String:
	var cents: int = round_div(v_uu, CENT_UU)
	if v_uu != 0 and cents == 0:
		return JwText.t("fmt.lt_u") if v_uu > 0 else JwText.t("fmt.gt_neg_u")
	return _fixed2(cents) + " U"


## 金额数值（不带单位，表格单元格用；单位由列头承载）。
static func u_num(v_uu: int) -> String:
	var cents: int = round_div(v_uu, CENT_UU)
	if v_uu != 0 and cents == 0:
		return JwText.t("fmt.lt_u_num") if v_uu > 0 else JwText.t("fmt.gt_neg_u_num")
	return _fixed2(cents)


## 人均金额：人均可支配收入等量级远小于 0.01 U，按内部整数 μU 显示（千分位），不做四舍五入到 U：`612 μU`。
static func uu_pc(v_uu: int) -> String:
	return uu_pc_num(v_uu) + " μU"


static func uu_pc_num(v_uu: int) -> String:
	return (MINUS if v_uu < 0 else "") + group3(absi(v_uu))


## 带符号金额：`+0.42 U` / `−1.10 U`。
static func u_signed(v_uu: int) -> String:
	var s: String = u(v_uu)
	if v_uu >= 0 and not s.begins_with(MINUS):
		return "+" + s
	return s


## 比率：`8.0 %`。
static func pct(v_ppm: int) -> String:
	var tenths: int = round_div(v_ppm, 1000)
	if v_ppm != 0 and tenths == 0:
		return JwText.t("fmt.lt_pct")
	return _fixed1(tenths) + " %"


## 带符号比率：`+15.0 %` / `−10.0 %`（情景参数与变化量用）。
static func pct_signed(v_ppm: int) -> String:
	var s: String = pct(v_ppm)
	if v_ppm >= 0 and not s.begins_with(MINUS):
		return "+" + s
	return s


static func pct_num(v_ppm: int) -> String:
	return _fixed1(round_div(v_ppm, 1000))


## 倍数（ppm → 两位小数）：`2.35`。
static func ratio(v_ppm: int) -> String:
	return _fixed2(round_div(v_ppm, 10_000))


## 百分点差：`+1.2 个百分点`。
static func ppt(v_ppm: int) -> String:
	var tenths: int = round_div(v_ppm, 1000)
	var s: String = _fixed1(tenths)
	if tenths >= 0:
		s = "+" + s
	return s + " " + JwText.t("unit.ppt")


## 指数：`100.0`（必须同屏带基期，调用方负责）。
static func index(v_ppm: int) -> String:
	return _fixed1(round_div(v_ppm, 1000))


## 人数：不足一百万写整数人，否则写「万人」一位小数。
static func persons(n: int) -> String:
	if absi(n) < 1_000_000:
		return group3(n) + " " + JwText.t("unit.persons")
	return _fixed1(round_div(n, 1_000)) + " " + JwText.t("unit.wan_persons")


## 人次（排队等跨服务种类加总的量，同一人可计多次）：不足一百万写整数人次，否则写「万人次」。
static func person_times(n: int) -> String:
	if absi(n) < 1_000_000:
		return group3(n) + " " + JwText.t("unit.person_times")
	return _fixed1(round_div(n, 1_000)) + " " + JwText.t("unit.wan_person_times")


## 人数数值（万人，一位小数，不带单位）。
static func wan_num(n: int) -> String:
	return _fixed1(round_div(n, 1_000))


## 数量：`10.00 单位`（unit_label 由调用方从名表取）。
static func qty(v_uqs: int, unit_label: String) -> String:
	var cents: int = round_div(v_uqs, 10_000)
	if v_uqs != 0 and cents == 0:
		return JwText.render("fmt.lt_qty", {"unit": unit_label})
	return _fixed2(cents) + " " + unit_label


static func qty_num(v_uqs: int) -> String:
	return _fixed2(round_div(v_uqs, 10_000))


## 内部季索引 → `第 8 季`（显示季号 = q + 1）。q == −1 为开账。
static func quarter(q: int) -> String:
	if q == -1:
		return JwText.t("fmt.quarter_open")
	if q < -1:
		push_error("JwFormat.quarter: bad quarter index " + str(q))
		return JwText.t("fmt.quarter_open")
	return JwText.render("fmt.quarter", {"n": str(q + 1)})


## 两位显示季号（引用码与表头用）：`07`。
static func q2(q: int) -> String:
	var n: int = maxi(q + 1, 0)
	return str(n) if n >= 10 else "0" + str(n)


## 季数：`3 季`；0 → `本季内`。
static func quarters(n: int) -> String:
	if n == 0:
		return JwText.t("fmt.quarters_zero")
	return JwText.render("fmt.quarters", {"n": str(n)})


## 年内第几季（显示用）：内部 q → (年, 季)。
static func year_of(q: int) -> int:
	@warning_ignore("integer_division")
	var y: int = q / 4
	return y + 1


static func quarter_in_year(q: int) -> int:
	return q % 4 + 1


## 金额区间：`〔1.80–2.60〕U`（只用于情景预测）。lo > hi → 交换并 push_error。
static func range_u(lo: int, hi: int) -> String:
	var a: int = lo
	var b: int = hi
	if a > b:
		push_error("JwFormat.range_u: lower bound above upper bound")
		var t: int = a
		a = b
		b = t
	return RANGE_OPEN + u_num(a) + EN_DASH + u_num(b) + RANGE_CLOSE + "U"


static func range_pct(lo: int, hi: int) -> String:
	var a: int = mini(lo, hi)
	var b: int = maxi(lo, hi)
	return RANGE_OPEN + pct_num(a) + EN_DASH + pct_num(b) + RANGE_CLOSE + "%"


static func range_index(lo: int, hi: int) -> String:
	var a: int = mini(lo, hi)
	var b: int = maxi(lo, hi)
	return RANGE_OPEN + index(a) + EN_DASH + index(b) + RANGE_CLOSE


## 区间的纯数值形（表格单元格，单位在列头）。
static func range_u_num(lo: int, hi: int) -> String:
	var a: int = mini(lo, hi)
	var b: int = maxi(lo, hi)
	return RANGE_OPEN + u_num(a) + EN_DASH + u_num(b) + RANGE_CLOSE


## 方向三通道（字 + 箭头 + 符号），色彩由调用方按 direction 取。
## better_when_up：该指标上升是否为改善。返回 {text, dir}，dir ∈ {1 改善, −1 恶化, 0 持平}。
static func delta_u(d_uu: int, better_when_up: bool, flat_band_uu: int = 0) -> Dictionary:
	if absi(d_uu) <= flat_band_uu:
		return {"text": JwText.t("dir.flat") + " ▸ " + u_signed(d_uu), "dir": 0}
	var improving: bool = (d_uu > 0) == better_when_up
	var arrow: String = "▲" if d_uu > 0 else "▼"
	var word: String = JwText.t("dir.better") if improving else JwText.t("dir.worse")
	return {"text": word + " " + arrow + " " + u_signed(d_uu), "dir": 1 if improving else -1}


static func delta_ppt(d_ppm: int, better_when_up: bool, flat_band_ppm: int = 0) -> Dictionary:
	if absi(d_ppm) <= flat_band_ppm:
		return {"text": JwText.t("dir.flat") + " ▸ " + ppt(d_ppm), "dir": 0}
	var improving: bool = (d_ppm > 0) == better_when_up
	var arrow: String = "▲" if d_ppm > 0 else "▼"
	var word: String = JwText.t("dir.better") if improving else JwText.t("dir.worse")
	return {"text": word + " " + arrow + " " + ppt(d_ppm), "dir": 1 if improving else -1}


static func delta_index(d_ppm: int, better_when_up: bool, flat_band_ppm: int = 0) -> Dictionary:
	var tenths: int = round_div(d_ppm, 1000)
	var s: String = _fixed1(tenths)
	if tenths >= 0:
		s = "+" + s
	if absi(d_ppm) <= flat_band_ppm:
		return {"text": JwText.t("dir.flat") + " ▸ " + s, "dir": 0}
	var improving: bool = (d_ppm > 0) == better_when_up
	var arrow: String = "▲" if d_ppm > 0 else "▼"
	var word: String = JwText.t("dir.better") if improving else JwText.t("dir.worse")
	return {"text": word + " " + arrow + " " + s, "dir": 1 if improving else -1}


## 引用码（docs/21 §6.2）：`<台账别名>#Q07.014`。别名由调用方经 JwText 取得（不在代码里写字面量）。
static func citation(ledger_alias: String, q: int, row: int) -> String:
	var r: String = str(maxi(row, 1))
	while r.length() < 3:
		r = "0" + r
	return ledger_alias + "#Q" + q2(q) + "." + r


## 金额的内部记账形（台账与调试导出用）：`1204350000 μU`。
static func uu_raw(v_uu: int) -> String:
	return (MINUS if v_uu < 0 else "") + str(absi(v_uu)) + " μU"
