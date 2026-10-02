## v2 界面的数字与文字格式（docs/57 §14：平实、不用代号与缩写）。
## 钱：厘 → 「3,456 两」「12.3 万两」「1.25 亿两」；人：「580 人」「3.4 万人」；比例：「12.5%」；
## 数量：千分单位 → 「1.2 万担」；时间：「1650 年春」。中文字样一律取自文案表。
## 引擎、应用层给的键（reason.* / chron.* / stw.* / adv.* / need.* / warn.* / cause.*）在文案表里都加前缀 jc.。
class_name JcFmt
extends RefCounted

const PPM: int = 1_000_000
const MINUS: String = "−"


static func t(key: String) -> String:
	return JwText.t(key)


## 引擎给的键 → 文案（自动加 jc. 前缀）。
static func k(engine_key: String) -> String:
	return JwText.t("jc." + engine_key)


static func r(engine_key: String, slots: Dictionary) -> String:
	return JwText.render("jc." + engine_key, slots)


static func _g3(n: int) -> String:
	return JwFormat.group3(n)


static func _dec(v: int, scale: int, places: int) -> String:
	# v / scale，保留 places 位小数（离零取半）
	var neg: bool = v < 0
	var a: int = absi(v)
	var mul: int = 1
	for i: int in places:
		mul *= 10
	var q: int = JwFormat.round_div(a * mul, scale)
	@warning_ignore("integer_division")
	var whole: int = q / mul
	var frac: int = q % mul
	var s: String = _g3(whole)
	if places > 0:
		var fs: String = str(frac)
		while fs.length() < places:
			fs = "0" + fs
		s += "." + fs
	return (MINUS if neg else "") + s


## 钱（厘）。
static func money(li: int) -> String:
	var a: int = absi(li)
	if a >= 100_000_000_000:          # ≥ 1 亿两
		return _dec(li, 100_000_000_000, 2) + " " + t("jc.u.yi_liang")
	if a >= 10_000_000:               # ≥ 1 万两
		return _dec(li, 10_000_000, 1 if a < 1_000_000_000 else 0) + " " + t("jc.u.wan_liang")
	if a >= 1_000:
		return _dec(li, 1000, 0) + " " + t("jc.u.liang")
	if li == 0:
		return "0 " + t("jc.u.liang")
	return _dec(li, 1000, 2) + " " + t("jc.u.liang")


static func money_signed(li: int) -> String:
	var s: String = money(li)
	return ("+" + s) if li > 0 else s


## 人。
static func people(n: int) -> String:
	if absi(n) >= 10_000:
		return _dec(n, 10_000, 1 if absi(n) < 10_000_000 else 0) + " " + t("jc.u.wan_ren")
	return _g3(n) + " " + t("jc.u.ren")


static func pct(ppm: int, places: int = 1) -> String:
	if ppm != 0 and absi(ppm) < 1000 and places <= 1:
		return (MINUS if ppm < 0 else "") + "0.1%"
	return _dec(ppm, 10_000, places) + "%"


static func pct_signed(ppm: int) -> String:
	var s: String = pct(ppm)
	return ("+" + s) if ppm > 0 else s


## 倍数（ppm → 「1.25 倍」）。
static func times(ppm: int) -> String:
	return _dec(ppm, PPM, 2) + " " + t("jc.u.times")


## 数量（千分单位）+ 单位。
static func qty(milli: int, unit: String) -> String:
	var a: int = absi(milli)
	if a >= 10_000_000:               # ≥ 1 万单位
		return _dec(milli, 10_000_000, 1) + " " + t("jc.u.wan") + unit
	if a >= 1000:
		return _dec(milli, 1000, 0) + " " + unit
	return _dec(milli, 1000, 2) + " " + unit


static func date(q: int, start_year: int) -> String:
	@warning_ignore("integer_division")
	var y: int = start_year + q / 4
	return JwText.render("jc.u.date", {"year": str(y), "season": t("jc.u.season.%d" % (q % 4))})


static func quarters(n: int) -> String:
	if n >= 4:
		@warning_ignore("integer_division")
		var y: int = n / 4
		var q: int = n % 4
		if q == 0:
			return JwText.render("jc.u.years", {"n": str(y)})
		return JwText.render("jc.u.years_q", {"n": str(y), "q": str(q)})
	return JwText.render("jc.u.quarters", {"n": str(maxi(n, 0))})


static func era_name(e: int) -> String:
	return t("jc.era.%d" % clampi(e, 1, 4))


# ── 槽位格式化：内容 ID 换名字，_li 结尾是钱，_ppm 结尾是比例 ───────────
static func slots(game: JCGame, raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in raw.keys():
		var ks: String = String(key)
		if ks.begins_with("_"):
			continue
		var v: Variant = raw[key]
		out[ks] = _slot(game, ks, v, raw)
	# 政令的档位：换成档位名（分档政令）或「施行 / 停止」
	if raw.has("decree") and raw.has("level"):
		out["level_text"] = _decree_level(game, String(raw["decree"]), int(raw["level"]))
	return out


static func _slot(game: JCGame, ks: String, v: Variant, raw: Dictionary) -> String:
	if ks.ends_with("_li"):
		return money(int(v))
	if ks.ends_with("_ppm"):
		return pct(int(v), 0 if absi(int(v)) >= 100_000 else 1)
	match ks:
		"building", "region", "good", "tech", "partner", "decree", "event", "landmark", "class":
			return game.name_of(ks, String(v)) if game != null else String(v)
		"need":
			# 三种用法：数目（还差几座）、设施缺口键（need.market）、居民的一项需要（staple）
			if v is int or v is float:
				return str(int(v))
			if String(v).begins_with("need."):
				# 设施缺口的标题里本身带地区、建筑，要一并填好
				var sub: Dictionary = {}
				if game != null and raw.has("region"):
					sub["region"] = game.name_of("region", String(raw["region"]))
				if game != null and raw.has("building"):
					sub["building"] = game.name_of("building", String(raw["building"]))
				return JwText.render("jc." + String(v) + ".t", sub)
			return game.name_of("need", String(v)) if game != null else String(v)
		"method", "from", "to":
			return game.name_of("method", String(v)) if game != null else String(v)
		"regime", "regime_from":
			return game.name_of("regime", String(v)) if game != null else String(v)
		"reform":
			return game.name_of("reform", String(v)) if game != null else String(v)
		"sit":
			return t("jc.sit.name.%s" % String(v))
		"rstage":
			return t("jc.sit.stage.%s" % String(v))
		"opt":
			return t("jc.sit.opt.%s.%s" % [String(raw.get("set", "")).trim_prefix("stage:"), String(v)])
		"how":
			return t("jc.pol.how.%s" % String(v))
		"factor":
			var fk: String = String(v)
			if fk.begins_with("class:"):
				return JwText.render("jc.pol.factor.class", {"class": game.name_of("class", fk.substr(6)) if game != null else fk})
			return t("jc.pol.factor.%s" % fk) if fk != "" else ""
		"x":
			return _dec(int(v), PPM, 1)
		"until":
			return date(int(v), game.st.start_year) if game != null and game.is_ready() else str(v)
		"owner":
			return t("jc.owner.%s" % ("gov" if (str(v) == "1" or str(v) == "gov") else "private"))
		"era", "world_era":
			return era_name(int(v))
		"leading", "auto", "full":
			return "1" if bool(v) else ""
		"source":
			var src: String = String(v)
			if src.begins_with("steward"):
				return t("jc.src.steward")
			if src.begins_with("advisor"):
				return t("jc.src.advisor")
			return ""
		"tax":
			return t("jc.tax.%s" % String(v))
		"line":
			return t("jc.budget.%d" % int(v))
		"track":
			return t("jc.crisis.%d" % int(v))
		"stage":
			return t("jc.stage.%d" % int(v))
		"domain":
			return t("jc.stw.domain.%s" % String(v))
		"mode":
			return t("jc.stw.mode.%d" % int(v))
		"stance":
			return t("jc.stw.stance.%s" % String(v))
		"ministry":
			return t("jc.adv.m.%s" % String(v))
		"cause":
			return k(String(v))
		"reason":
			return t("jc.over.%s" % String(v))
		"option":
			# 事件的选项：写出选的是哪一条；找不到文字才写「第几项」
			if game != null and raw.has("event"):
				var ot: String = game.event_option(String(raw["event"]), int(v))
				if ot != "":
					return ot
			return JwText.render("jc.fmt.option_n", {"n": str(int(v) + 1)})
		"value":
			if String(raw.get("tax", "")) == "salt":
				return money(int(v)) + t("jc.u.per_dan")
			if raw.has("tax") or raw.has("line"):
				return pct(int(v), 1)
			return str(v)
		"amount", "cost", "treasury", "limit":
			return money(int(v))
		"pop":
			return people(int(v))
		"pct":
			return pct(int(v), 0)
		"runway", "quarters":
			return quarters(int(v))
		"qty":
			return qty(int(v), t("jc.u.dan"))
		"first":
			var kind: String = String(raw.get("first_kind", ""))
			if kind == "tech":
				return game.name_of("tech", String(v))
			if kind == "building":
				return game.name_of("building", String(v))
			return t("jc.social_do.%s" % String(v))
	return str(v)


## 一条纪事 → 一行字。
static func chron(game: JCGame, e: Dictionary) -> String:
	var args: Dictionary = e.get("args", {})
	var s: Dictionary = slots(game, args)
	return r(String(e.get("key", "")), s)


static func _decree_level(game: JCGame, id: String, lvl: int) -> String:
	if game == null:
		return str(lvl)
	var nm: String = game.decree_level_name(id, lvl)
	if nm != "":
		return nm
	return t("jc.decree.on") if lvl > 0 else t("jc.decree.off")


## 命令被拒的原因 → 一句话。
static func reason(game: JCGame, res: Dictionary) -> String:
	var key: String = String(res.get("reason", ""))
	if key == "":
		return ""
	var raw: Dictionary = {}
	for kk: Variant in res.keys():
		if String(kk) in ["cost", "limit", "lo", "hi", "until"]:
			raw[String(kk) + ("_li" if String(kk) in ["cost", "limit"] else "")] = res[kk]
	var s: Dictionary = slots(game, raw)
	if s.has("cost_li"):
		s["cost"] = s["cost_li"]
	if s.has("limit_li"):
		s["limit"] = s["limit_li"]
	if res.has("until") and game != null and game.is_ready():
		s["until"] = date(int(res["until"]), game.st.start_year)
	var out: String = JwText.render("jc." + key, s) if JwText.has("jc." + key) else ""
	return out if out != "" else k("reason.bad_command")
