## v2 状态：一局里全部会跨季保存的量（docs/57）。
## 存档 = to_dict()（JSON）；状态哈希 = 按 FIELDS 固定顺序拼出的规范文本的 SHA-256（纪事与曲线不进哈希）。
class_name JCState
extends RefCounted

const VERSION: int = 1

## 财政拨款项（每项 0—150%）
const BUD_ADMIN: int = 0
const BUD_ARMY: int = 1
const BUD_EDU: int = 2
const BUD_HEALTH: int = 3
const BUD_WORKS: int = 4
const BUD_RELIEF: int = 5
const BUD_COURT: int = 6
const BUD_N: int = 7
## 收入项
const REV_LAND: int = 0
const REV_SALT: int = 1
const REV_COMMERCE: int = 2
const REV_CUSTOMS: int = 3
const REV_STATE: int = 4
const REV_INCOME: int = 5
const REV_OTHER: int = 6
const REV_N: int = 7
## 支出项
const EXP_ADMIN: int = 0
const EXP_ARMY: int = 1
const EXP_EDU: int = 2
const EXP_HEALTH: int = 3
const EXP_WORKS: int = 4
const EXP_RELIEF: int = 5
const EXP_COURT: int = 6
const EXP_BUILD: int = 7
const EXP_INTEREST: int = 8
const EXP_DECREE: int = 9
const EXP_EVENT: int = 10
const EXP_STATE_LOSS: int = 11
const EXP_N: int = 12
## 建筑堆状态
const ST_ACTIVE: int = 0
const ST_MOTHBALL: int = 1
const ST_NEW: int = 2
const ST_UPGRADE: int = 3
## 危机三轨
const CR_FISCAL: int = 0
const CR_LIVELIHOOD: int = 1
const CR_LEGITIMACY: int = 2

## 进哈希、进存档的字段（顺序不得改）
const FIELDS: PackedStringArray = [
	"q", "start_year", "seed", "content_hash", "era", "over", "over_reason", "over_q", "rng_state", "uid_seq",
	"land", "hidden", "literacy", "harvest", "flood", "logistics",
	"pop", "savings", "income", "spend", "employed", "jobs", "wage", "basket", "living", "unrest", "sat",
	"comfort",
	"support",
	"s_uid", "s_region", "s_b", "s_m", "s_owner", "s_level", "s_status", "s_pending", "s_prog", "s_needq",
	"s_target", "s_u", "s_bind", "s_profit", "s_loss", "s_built", "s_fund",
	"price", "premium", "stock", "f_prod", "f_hh", "f_use", "f_gov", "f_exp", "f_imp", "f_unmet", "f_demand",
	"treasury", "debt", "debt_rate_ppm", "tax_land_ppm", "tax_salt_li", "tax_commerce_ppm", "tax_customs_ppm",
	"tax_income_ppm", "budget", "soldiers", "arrears", "arrears_streak", "rev", "exp", "coll_eff", "silver",
	"money0", "gov_fund",
	"d_level", "d_since", "d_until", "d_cool",
	"focus", "t_prog", "t_done", "points", "rpool", "gstore",
	"p_dev", "p_rel", "p_treaty", "p_active", "p_noise", "p_exp", "p_imp", "world_era", "world_era_q", "era_q",
	"led", "prestige", "legitimacy",
	"l_state", "l_prog", "l_needq", "l_region", "lead_pick",
	"e_cool", "pend",
	"tm_target", "tm_scope", "tm_value", "tm_until",
	"cr_stage", "cr_since", "cr_bad",
]
## 进存档、不进哈希
const EXTRA: PackedStringArray = ["chron", "hist", "last", "annals", "marks"]
## 收进国史的纪事（另有里程碑与升到第二级以上的危机）：纪事只留最近 400 条、多是民间开坊的流水账，国史不会被刷掉
const ANNAL_KEYS: PackedStringArray = ["chron.era_enter", "chron.world_era", "chron.game_over", "chron.tech_done",
	"chron.landmark_done", "chron.event_answered", "chron.treaty", "chron.partner_appear", "chron.decree",
	"chron.crisis_down"]
const ANNAL_MAX: int = 3000

# ── 元 ──
var q: int = 0
var start_year: int = 1600
var seed: int = 1
var content_hash: String = ""
var era: int = 1
var over: int = 0
var over_reason: String = ""
var over_q: int = -1
var rng_state: int = 0
var uid_seq: int = 0

# ── 地区（R） ──
var land: PackedInt64Array = PackedInt64Array()
var hidden: PackedInt64Array = PackedInt64Array()
var literacy: PackedInt64Array = PackedInt64Array()
var harvest: PackedInt64Array = PackedInt64Array()
var flood: PackedInt64Array = PackedInt64Array()
var logistics: PackedInt64Array = PackedInt64Array()

# ── 人群（R × C） ──
var pop: PackedInt64Array = PackedInt64Array()
var savings: PackedInt64Array = PackedInt64Array()
var income: PackedInt64Array = PackedInt64Array()
var spend: PackedInt64Array = PackedInt64Array()
var employed: PackedInt64Array = PackedInt64Array()
var jobs: PackedInt64Array = PackedInt64Array()
var wage: PackedInt64Array = PackedInt64Array()
var basket: PackedInt64Array = PackedInt64Array()
## 日用水平相对「世人期待」的比例（ppm，(R*C)）：实际买到的日用 ÷（开局篮子 × 本时代期待倍数）
var comfort: PackedInt64Array = PackedInt64Array()
var living: PackedInt64Array = PackedInt64Array()
var unrest: PackedInt64Array = PackedInt64Array()
## (r * C + c) * N + n
var sat: PackedInt64Array = PackedInt64Array()
var support: PackedInt64Array = PackedInt64Array()

# ── 建筑堆（动态） ──
var s_uid: PackedInt64Array = PackedInt64Array()
var s_region: PackedInt64Array = PackedInt64Array()
var s_b: PackedInt64Array = PackedInt64Array()
var s_m: PackedInt64Array = PackedInt64Array()
var s_owner: PackedInt64Array = PackedInt64Array()
var s_level: PackedInt64Array = PackedInt64Array()
var s_status: PackedInt64Array = PackedInt64Array()
var s_pending: PackedInt64Array = PackedInt64Array()
var s_prog: PackedInt64Array = PackedInt64Array()
var s_needq: PackedInt64Array = PackedInt64Array()
var s_target: PackedInt64Array = PackedInt64Array()
var s_u: PackedInt64Array = PackedInt64Array()
var s_bind: PackedInt64Array = PackedInt64Array()
var s_profit: PackedInt64Array = PackedInt64Array()
var s_loss: PackedInt64Array = PackedInt64Array()
var s_built: PackedInt64Array = PackedInt64Array()
## 在建的出资方：0 国库，1 本地区商贾与士绅
var s_fund: PackedInt64Array = PackedInt64Array()

# ── 商品（G） ──
var price: PackedInt64Array = PackedInt64Array()
var premium: PackedInt64Array = PackedInt64Array()
var stock: PackedInt64Array = PackedInt64Array()
var f_prod: PackedInt64Array = PackedInt64Array()
var f_hh: PackedInt64Array = PackedInt64Array()
var f_use: PackedInt64Array = PackedInt64Array()
var f_gov: PackedInt64Array = PackedInt64Array()
var f_exp: PackedInt64Array = PackedInt64Array()
var f_imp: PackedInt64Array = PackedInt64Array()
var f_unmet: PackedInt64Array = PackedInt64Array()
var f_demand: PackedInt64Array = PackedInt64Array()

# ── 国家 ──
var treasury: int = 0
var debt: int = 0
var debt_rate_ppm: int = 30000
var tax_land_ppm: int = 0
var tax_salt_li: int = 0
var tax_commerce_ppm: int = 0
var tax_customs_ppm: int = 0
var tax_income_ppm: int = 0
var budget: PackedInt64Array = PackedInt64Array()
var soldiers: int = 0
var arrears: int = 0
var arrears_streak: int = 0
var rev: PackedInt64Array = PackedInt64Array()
var exp: PackedInt64Array = PackedInt64Array()
var coll_eff: int = 1_000_000
## 累计白银净流入（出口 − 进口 − 对外支付）。货币守恒：Σ 储蓄 + 国库 == money0 + silver。
var silver: int = 0
var money0: int = 0
## 本季国家开支的到位比例（国库不够时按比例欠饷、减员）
var gov_fund: int = 1_000_000

# ── 政令（D） ──
var d_level: PackedInt64Array = PackedInt64Array()
var d_since: PackedInt64Array = PackedInt64Array()
var d_until: PackedInt64Array = PackedInt64Array()
var d_cool: PackedInt64Array = PackedInt64Array()

# ── 研究（T） ──
var focus: int = -1
var t_prog: PackedInt64Array = PackedInt64Array()
var t_done: PackedInt64Array = PackedInt64Array()
var points: int = 0
## 没有研究方向时攒下的研究点（选了方向后一次性投入）
var rpool: int = 0
## 官仓存粮（千分石，稻米麦粟通算）
var gstore: int = 0

# ── 世界（P） ──
var p_dev: PackedInt64Array = PackedInt64Array()
var p_rel: PackedInt64Array = PackedInt64Array()
var p_treaty: PackedInt64Array = PackedInt64Array()
var p_active: PackedInt64Array = PackedInt64Array()
var p_noise: PackedInt64Array = PackedInt64Array()
var p_exp: PackedInt64Array = PackedInt64Array()
var p_imp: PackedInt64Array = PackedInt64Array()
var world_era: int = 1
var world_era_q: PackedInt64Array = PackedInt64Array()
var era_q: PackedInt64Array = PackedInt64Array()
var led: PackedInt64Array = PackedInt64Array()
var prestige: int = 0
var legitimacy: int = 600_000

# ── 地标（L） ──
var l_state: PackedInt64Array = PackedInt64Array()
var l_prog: PackedInt64Array = PackedInt64Array()
var l_needq: PackedInt64Array = PackedInt64Array()
var l_region: PackedInt64Array = PackedInt64Array()
var lead_pick: PackedInt64Array = PackedInt64Array()

# ── 事件（E） ──
var e_cool: PackedInt64Array = PackedInt64Array()
## 待决事件：[{e, r, until}]
var pend: Array = []

# ── 限时修正 ──
var tm_target: PackedStringArray = PackedStringArray()
var tm_scope: PackedStringArray = PackedStringArray()
var tm_value: PackedInt64Array = PackedInt64Array()
var tm_until: PackedInt64Array = PackedInt64Array()

# ── 危机 ──
var cr_stage: PackedInt64Array = PackedInt64Array()
var cr_since: PackedInt64Array = PackedInt64Array()
var cr_bad: PackedInt64Array = PackedInt64Array()

# ── 不进哈希 ──
## 纪事：[{q, kind, text_key, args}]，保留最近 200 条
var chron: Array = []
## 历年曲线：每年春季一条 {year, gdp, pop, treasury, living, era, ...}
var hist: Array = []
## 国史（只收大事，见 note）与已达成的里程碑（id → 第几季；以 _ 开头的是计数）
var annals: Array = []
var marks: Dictionary = {}
## 上季摘要（给界面与分析用）
var last: Dictionary = {}


func stack_count() -> int:
	return s_uid.size()


## 记一条纪事：kind 分类（build、trade、decree、era、event、crisis、advisor、steward……），
## key 是界面文案键，args 是文案参数。只保留最近 400 条。
func note(kind: String, key: String, args: Dictionary = {}) -> void:
	chron.append({"q": q, "kind": kind, "key": key, "args": args})
	if chron.size() > 400:
		chron = chron.slice(chron.size() - 400)
	# 国史：大事另记一份（赈济这种随灾情开开关关的不记）
	var big: bool = kind == "milestone" or ANNAL_KEYS.has(key) or (key == "chron.crisis_up" and int(args.get("stage", 0)) >= 2)
	if key == "chron.decree" and String(args.get("decree", "")) == "famine_relief":
		big = false
	if big:
		annals.append({"q": q, "kind": kind, "key": key, "args": args})
		if annals.size() > ANNAL_MAX:
			annals = annals.slice(annals.size() - ANNAL_MAX)


func gi(r: int, c: int, cn: int) -> int:
	return r * cn + c


func year() -> int:
	@warning_ignore("integer_division")
	return start_year + q / 4


func season() -> int:
	return q % 4


## 新增一个建筑堆，返回行号。
func add_stack(r: int, b: int, m: int, owner: int, level: int, status: int, pending: int, needq: int) -> int:
	uid_seq += 1
	s_uid.append(uid_seq)
	s_region.append(r)
	s_b.append(b)
	s_m.append(m)
	s_owner.append(owner)
	s_level.append(level)
	s_status.append(status)
	s_pending.append(pending)
	s_prog.append(0)
	s_needq.append(needq)
	s_target.append(-1)
	s_u.append(1_000_000 if status == ST_ACTIVE else 0)
	s_bind.append(0)
	s_profit.append(0)
	s_loss.append(0)
	s_built.append(q)
	s_fund.append(0 if owner == 1 else 1)
	return s_uid.size() - 1


func stack_of_uid(uid: int) -> int:
	for i: int in s_uid.size():
		if s_uid[i] == uid:
			return i
	return -1


## 删掉规模为 0 且不在建的堆（顺序保持）。
func compact_stacks() -> void:
	var keep: PackedInt64Array = PackedInt64Array()
	for i: int in s_uid.size():
		if s_level[i] > 0 or s_pending[i] > 0:
			keep.append(i)
	if keep.size() == s_uid.size():
		return
	for f: String in ["s_uid", "s_region", "s_b", "s_m", "s_owner", "s_level", "s_status", "s_pending", "s_prog",
			"s_needq", "s_target", "s_u", "s_bind", "s_profit", "s_loss", "s_built", "s_fund"]:
		var src: PackedInt64Array = get(f)
		var dst: PackedInt64Array = PackedInt64Array()
		for i: int in keep:
			dst.append(src[i])
		set(f, dst)


# ── 存档与哈希 ──────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	var d: Dictionary = {"version": VERSION}
	for f: String in FIELDS:
		d[f] = _plain(get(f))
	for f2: String in EXTRA:
		d[f2] = get(f2)
	return d


static func from_dict(d: Dictionary) -> JCState:
	var s: JCState = JCState.new()
	for f: String in FIELDS:
		if not d.has(f):
			continue
		var cur: Variant = s.get(f)
		var v: Variant = d[f]
		match typeof(cur):
			TYPE_PACKED_INT64_ARRAY:
				var a: PackedInt64Array = PackedInt64Array()
				for x: Variant in v:
					a.append(int(x))
				s.set(f, a)
			TYPE_PACKED_STRING_ARRAY:
				var b: PackedStringArray = PackedStringArray()
				for x2: Variant in v:
					b.append(String(x2))
				s.set(f, b)
			TYPE_INT:
				s.set(f, int(v))
			TYPE_STRING:
				s.set(f, String(v))
			TYPE_ARRAY:
				s.set(f, _ints_deep(v))
			_:
				s.set(f, v)
	for f2: String in EXTRA:
		if d.has(f2):
			s.set(f2, _ints_deep(d[f2]))
	return s


static func _plain(v: Variant) -> Variant:
	match typeof(v):
		TYPE_PACKED_INT64_ARRAY:
			return Array(v)
		TYPE_PACKED_STRING_ARRAY:
			return Array(v)
	return v


## JSON 读回来的数字是浮点，按整数还原（字典与数组逐层）。
static func _ints_deep(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v)
		TYPE_ARRAY:
			var out: Array = []
			for x: Variant in v:
				out.append(_ints_deep(x))
			return out
		TYPE_DICTIONARY:
			var o: Dictionary = {}
			for k: Variant in (v as Dictionary).keys():
				o[k] = _ints_deep(v[k])
			return o
	return v


func state_hash() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for f: String in FIELDS:
		var v: Variant = get(f)
		match typeof(v):
			TYPE_PACKED_INT64_ARRAY:
				parts.append(f + "=" + ",".join(Array(v).map(func(x: int) -> String: return str(x))))
			TYPE_PACKED_STRING_ARRAY:
				parts.append(f + "=" + "|".join(v))
			TYPE_ARRAY:
				parts.append(f + "=" + JSON.stringify(v, "", true))
			_:
				parts.append(f + "=" + str(v))
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("\n".join(parts).to_utf8_buffer())
	return ctx.finish().hex_encode()


func duplicate_state() -> JCState:
	return JCState.from_dict(to_dict())
