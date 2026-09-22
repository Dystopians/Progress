## 政策时滞（docs/30 §4 类别 C）的独立验收测试。
##
## 本文件**只依据契约**编写，不参考 sim/policy/*.gd 的实现：
##   - docs/18 R-SCALE-01（1 U == 1e9 μU，P04 的全部货币数按新刻度）
##   - 计划书 §10（P04 卡片：4 U / 8 季 / 每季 0.5 U / 0.2+0.1+0.2 落点 / 运行费 0.02 U / 10 单位电力）
##   - docs/12 §2.1 02.1 资格链、02.2 预算预留
##   - docs/11 §5.12 V-PD-01..11
##   - docs/17 §4.8 / §4.21 的成员表、常量与签名
##   - docs/10 §14 INV-091/095/096/097/098/099/100/032/033/137/138
##   - docs/31 ADV-A01（≡ ADV-01）
##
## 分两部分：
##   A 段 直接读 `content/policies/*.json`，校验**内容包本身**是否满足目录级门槛
##        （T-U-C-00..03）。它不经过加载器，因此加载器写错时这段依然是可信的标尺。
##   B 段 用 JWSimState.allocate_all() 建夹具，直接驱动 JWPolicyEngine，
##        校验资格闸门、预算预留、时滞闸门、幂等台账与退出规则。
##
## 纪律：JWResult 的故障登记是静态的，跨测试方法残留；每个方法前后都要 clear_pending()。
extends JWTest

# ── 政策稠密下标（P01 == 0） ───────────────────────────────────────────────

const P01: int = 0
const P02: int = 1
const P03: int = 2
const P04: int = 3
const P05: int = 4
const P09: int = 8
const P10: int = 9
const P11: int = 10

## P09 夹具的补助费率（content/policies/policy_P09.json 的 subsidy_rate_ppm 默认值）
const P09_SUBSIDY_RATE_PPM: int = 300_000

## JSON 里读不出整数时的哨兵，绝不可能与任何合法值相等。
const BAD_INT: int = -999_999_999_999

## 内容包里三条支出落点的顺序（docs/17 §4.8：36 == 12×3，进口设备/国产材料/施工服务）。
const SPEND_LINE_N: int = 3

# ── 计划书 §10 的 P04 数值，按 R-SCALE-01 换算（1 U == 1e9 μU） ─────────────
#
# 这些字面量**故意写死**（docs/30 §4.4 的要求：不从内容包读，否则内容包写错时测试跟着错）。
# 每条都在下面的测试里同时与「由 JWUnits.U_SCALE 推出的值」对照，钉死刻度裁定。

## 总成本 4 U
const P04_ONE_OFF_UU: int = 4_000_000_000
## 计划 8 季
const P04_PLANNED_Q: int = 8
## 每季 0.5 U
const P04_PER_Q_UU: int = 500_000_000
## 每季 0.2 U 进口设备
const P04_LINE_IMPORT_UU: int = 200_000_000
## 每季 0.1 U 国产材料
const P04_LINE_MATERIAL_UU: int = 100_000_000
## 每季 0.2 U 施工服务
const P04_LINE_CONSTRUCTION_UU: int = 200_000_000
## 启用后每季运行费 0.02 U
const P04_OPEX_UU: int = 20_000_000
## 额外 10 单位可用电力服务 == 10 × Q_SCALE μQ_energy/季
const P04_CAPACITY_UQS: int = 10_000_000
## 开关一次性行政成本（docs/11 §5.12 == param.policy_toggle_cost_uu）
const P04_TOGGLE_COST_UU: int = 10_000_000
## 冷却期
const P04_COOLDOWN_Q: int = 4
## 生效时滞
const P04_LAG_Q: int = 1
## 投运时滞（INV-091 要求 ≥ 1）
const P04_COMMISSION_DELAY_Q: int = 1
## 退出赔偿比例
const P04_EXIT_COMPENSATION_PPM: int = 300_000
## 施工投入（μQ_services）与进口设备（μQ_manu），不随货币刻度变化
const P04_REQ_CONSTRUCTION_UQS: int = 3_200_000
const P04_REQ_EQUIPMENT_UQS: int = 1_600_000

# ── 计划书 §10 / docs/30 §4.2 的「最早反馈」窗口，下标 == 政策下标 ─────────
#
# 计划书对 P01/P02/P03 只写「1 季」，对其余写区间。区间的下界 == lag.min_feedback_q，
# 上界 == lag.max_feedback_q；只写单季的三项只约束下界。

const PLAN_MIN_FEEDBACK_Q: PackedInt64Array = [1, 1, 1, 4, 4, 6, 4, 6, 2, 2, 4, 2]
## −1 表示计划书未给上界（P01/P02/P03）
const PLAN_MAX_FEEDBACK_Q: PackedInt64Array = [-1, -1, -1, 8, 8, 12, 8, 10, 4, 4, 8, 6]

# ── 九项必填（docs/11 §5.12 / 计划书 §09） ─────────────────────────────────

const REQUIRED_FIELDS: PackedStringArray = [
	"problem_statement_zh", "legal_authority", "cost", "preconditions", "lag",
	"effect", "exit_rule", "political_reaction", "failure_paths",
]

# ── 夹具常量 ───────────────────────────────────────────────────────────────

## 奇数席位（V-POL-02）
const SEATS_TOTAL: int = 101
## 554 455 ppm ≥ 500 000，席位闸门通过
const SEATS_GOV_PASS: int = 56
## 99 009 ppm < 500 000，席位闸门不通过
const SEATS_GOV_SHORT: int = 10
## 夹具里的政府现金：远大于 P04 一季所需
const FIXTURE_GOV_CASH_UU: int = 100_000_000_000
## 夹具里每地区的施工槽位
const FIXTURE_SLOTS: int = 4
## 立项季：预算审查季（INV-127：q ≡ 3 (mod 4)）
const Q_ENACT: int = 3
## 关停季 == 立项季 + cooldown_q，冷却恰好走完
const Q_REPEAL: int = Q_ENACT + P04_COOLDOWN_Q
## 再立项季 == 关停季 + cooldown_q
const Q_REENACT: int = Q_REPEAL + P04_COOLDOWN_Q

## _seed_* 写入失败的累计计数：非 0 说明数组没有按契约长度分配。
var _seed_errors: int = 0


func before_each() -> void:
	JWResult.clear_pending()
	JWResult.set_step(0)
	_seed_errors = 0


func after_each() -> void:
	JWResult.clear_pending()


# ══════════════════════════════════════════════════════════════════════════
# A 段：内容包目录级门槛（T-U-C-00..03），直接读 JSON，不经加载器
# ══════════════════════════════════════════════════════════════════════════

## T-U-C-00 / V-PD-01 / V-PD-02 / INV-099：12 个政策齐全、ID 无缺无重、九项必填非空。
func test_u_policy_catalog_complete() -> void:
	var docs: Array = _load_all_policy_docs()
	eq_int(docs.size(), JWUnits.POLICY_N,
			"content/policies/ 必须恰有 12 个政策定义（V-PD-01，计划书 §09）")
	if docs.size() != JWUnits.POLICY_N:
		return
	var seen: Dictionary = {}
	var missing_fields: int = 0
	for p: int in JWUnits.POLICY_N:
		var d: Dictionary = docs[p]
		var want_id: String = "policy.P%02d" % (p + 1)
		eq_str(String(d.get("policy_id", "")), want_id,
				"第 %d 个文件的 policy_id 必须是 %s（V-PD-01 要求 ID 连续 P01..P12）" % [p, want_id])
		seen[want_id] = int(seen.get(want_id, 0)) + 1
		for f: String in REQUIRED_FIELDS:
			if not d.has(f) or _is_empty_value(d[f]):
				missing_fields += 1
				fail("%s 缺少或为空的必填字段 `%s`（V-PD-02 九项必填，计划书 §09「没有这些字段的政策不进入可玩菜单」）"
						% [want_id, f])
	eq_int(seen.size(), JWUnits.POLICY_N, "12 个 policy_id 必须互不重复（V-PD-01）")
	eq_int(missing_fields, 0, "九项必填字段的缺失计数必须为 0（V-PD-02）")


## T-U-C-01 / V-PD-03：成本字段自洽，且加载器不做归一化补偿。
func test_u_policy_cost_exact() -> void:
	var docs: Array = _load_all_policy_docs()
	eq_int(docs.size(), JWUnits.POLICY_N, "先要有 12 个政策文件才能校验成本（V-PD-01）")
	if docs.size() != JWUnits.POLICY_N:
		return
	for p: int in JWUnits.POLICY_N:
		var pid: String = _pid(docs, p)
		var cost: Dictionary = _sub(docs[p], "cost")
		var per_q: int = _as_int(cost.get("per_quarter_uu", BAD_INT))
		var planned: int = _as_int(cost.get("planned_quarters", BAD_INT))
		var one_off: int = _as_int(cost.get("one_off_uu", BAD_INT))
		eq_int(JWMath.mul(per_q, planned), one_off,
				"%s：per_quarter_uu × planned_quarters 必须精确等于 one_off_uu（V-PD-03，加载器不得归一化补偿）" % pid)
		var lines: Dictionary = _sub(cost, "spend_lines_uu_per_q")
		var line_sum: int = 0
		for k: Variant in lines.keys():
			if String(k).begins_with("_"):
				continue
			line_sum += _as_int(lines[k])
		eq_int(line_sum, per_q,
				"%s：Σ spend_lines_uu_per_q 必须精确等于 per_quarter_uu（V-PD-03）" % pid)


## T-U-C-02 / V-PD-10 / V-PD-11 / INV-091：效果落点必须在白名单内，且能力类只能落在 *_pending_*。
func test_u_effect_target_pending_only() -> void:
	var docs: Array = _load_all_policy_docs()
	eq_int(docs.size(), JWUnits.POLICY_N, "先要有 12 个政策文件才能校验落点（V-PD-01）")
	if docs.size() != JWUnits.POLICY_N:
		return
	var off_whitelist: int = 0
	var direct_active: int = 0
	for p: int in JWUnits.POLICY_N:
		var pid: String = _pid(docs, p)
		var target: String = String(_sub(docs[p], "effect").get("target", ""))
		var code: int = -1
		for i: int in JWPolicyDef.EFFECT_TARGETS.size():
			if JWPolicyDef.EFFECT_TARGETS[i] == target:
				code = i
				break
		if code < 0:
			off_whitelist += 1
			fail("%s 的 effect.target = \"%s\" 不在 docs/11 §5.12 的效果落点白名单内（V-PD-10）" % [pid, target])
		if target.find("_active_") >= 0:
			direct_active += 1
			fail("%s 的 effect.target 直接落在 *_active_* 上，绕过了「完工资产下一季才供能」（V-PD-11 / INV-091）" % pid)
	eq_int(off_whitelist, 0, "落点不在白名单的政策数必须为 0（V-PD-10）")
	eq_int(direct_active, 0, "落在 *_active_* 上的政策数必须为 0（V-PD-11 / INV-091）")


## T-U-C-02 / V-PD-04 / INV-091：`lag.commission_delay_q >= 1` 的政策数必须是 12。
func test_u_commission_delay_at_least_one() -> void:
	var docs: Array = _load_all_policy_docs()
	eq_int(docs.size(), JWUnits.POLICY_N, "先要有 12 个政策文件才能校验投运时滞（V-PD-01）")
	if docs.size() != JWUnits.POLICY_N:
		return
	var ok_count: int = 0
	for p: int in JWUnits.POLICY_N:
		var delay: int = _as_int(_sub(docs[p], "lag").get("commission_delay_q", BAD_INT))
		if delay >= 1:
			ok_count += 1
		else:
			fail("%s 的 lag.commission_delay_q = %d，小于 1，等于允许完工当季投运（V-PD-04 / INV-091）"
					% [_pid(docs, p), delay])
	eq_int(ok_count, JWUnits.POLICY_N, "commission_delay_q >= 1 的政策数必须是 12（V-PD-04）")


## T-U-C-00 / V-PD-08 / INV-099：mechanism_ids 必须全部命中 JWPolicyDef.MECHANISM_IDS，
## 且条数不得超过 mechanism_mask 的位宽（docs/17 §4.8：注册表长度 12）。
func test_u_policy_mechanism_ids_registered() -> void:
	var docs: Array = _load_all_policy_docs()
	eq_int(docs.size(), JWUnits.POLICY_N, "先要有 12 个政策文件才能校验机制引用（V-PD-01）")
	if docs.size() != JWUnits.POLICY_N:
		return
	var unknown: int = 0
	var overflow: int = 0
	for p: int in JWUnits.POLICY_N:
		var pid: String = _pid(docs, p)
		var mechs: Array = _arr(docs[p], "mechanism_ids")
		check(mechs.size() > 0, "%s 的 mechanism_ids 不得为空（V-PD-08）" % pid)
		if mechs.size() > JWPolicyDef.MECHANISM_IDS.size():
			overflow += 1
			fail("%s 引用了 %d 个机制，超过机制注册表的 %d 位（docs/17 §4.8 mechanism_mask 是 12 位掩码）"
					% [pid, mechs.size(), JWPolicyDef.MECHANISM_IDS.size()])
		for m: Variant in mechs:
			var mid: String = String(m)
			if JWPolicyDef.mechanism_index(mid) < 0:
				unknown += 1
				fail("%s 引用了未注册的机制 \"%s\"；政策不能自带逻辑，只能引用 MechanismRegistry 已有机制（V-PD-08 / INV-099，计划书 §09 伪深度防线）"
						% [pid, mid])
	eq_int(unknown, 0, "mechanism_ids 中未注册的 mech.* 数必须为 0（V-PD-08 / INV-099）")
	eq_int(overflow, 0, "引用机制数超过注册表位宽的政策数必须为 0（docs/17 §4.8）")


## T-U-C-03：同一效果不得被复制成多个名字（计划书 §09「避免两种伪深度」）。
func test_u_policy_no_pseudo_depth() -> void:
	var docs: Array = _load_all_policy_docs()
	eq_int(docs.size(), JWUnits.POLICY_N, "先要有 12 个政策文件才能查重（V-PD-01）")
	if docs.size() != JWUnits.POLICY_N:
		return
	var keys: PackedStringArray = PackedStringArray()
	for p: int in JWUnits.POLICY_N:
		var mechs: Array = _arr(docs[p], "mechanism_ids")
		var names: PackedStringArray = PackedStringArray()
		for m: Variant in mechs:
			names.append(String(m))
		names.sort()
		keys.append("%s|%s" % [String(_sub(docs[p], "effect").get("target", "")), "+".join(names)])
	var dup_pairs: int = 0
	for a: int in JWUnits.POLICY_N:
		for b: int in range(a + 1, JWUnits.POLICY_N):
			if keys[a] == keys[b]:
				dup_pairs += 1
				fail("%s 与 %s 的机制集合与效果落点完全相同，属于同一效果的两个名字（T-U-C-03，计划书 §09）"
						% [_pid(docs, a), _pid(docs, b)])
	eq_int(dup_pairs, 0, "机制与落点完全相同的政策对数必须为 0（T-U-C-03）")


## docs/17 §4.8：param_min_ppm / param_max_ppm / param_default 长度 48 == 12 × 4，
## 因此每项政策的 player_params 不得超过 JWIds.POLICY_PARAM_STRIDE 项，否则运行期无处安放。
func test_u_player_params_fit_runtime_slots() -> void:
	var docs: Array = _load_all_policy_docs()
	eq_int(docs.size(), JWUnits.POLICY_N, "先要有 12 个政策文件才能校验参数槽位（V-PD-01）")
	if docs.size() != JWUnits.POLICY_N:
		return
	eq_int(JWUnits.POLICY_PARAM_N, JWMath.mul(JWUnits.POLICY_N, JWIds.POLICY_PARAM_STRIDE),
			"docs/17 §4.8：政策参数数组长度必须是 12 × 4 == 48")
	var overflow: int = 0
	for p: int in JWUnits.POLICY_N:
		var n: int = _arr(docs[p], "player_params").size()
		if n > JWIds.POLICY_PARAM_STRIDE:
			overflow += 1
			fail("%s 声明了 %d 个 player_params，超过每政策 %d 个的运行期槽位（docs/17 §4.8：params_ppm/params_uu 长度 48 == 12×4）"
					% [_pid(docs, p), n, JWIds.POLICY_PARAM_STRIDE])
	eq_int(overflow, 0, "player_params 超出 4 个槽位的政策数必须为 0（docs/17 §4.8）")


## V-PD-09：每个 player_params 项都要有 valid_range 与 default，且 default ∈ valid_range；
## default 必须是整数——params_ppm / params_uu 是 PackedInt64Array，装不下字符串（docs/17 §4.8）。
func test_u_player_param_range_and_default() -> void:
	var docs: Array = _load_all_policy_docs()
	eq_int(docs.size(), JWUnits.POLICY_N, "先要有 12 个政策文件才能校验参数区间（V-PD-01）")
	if docs.size() != JWUnits.POLICY_N:
		return
	var bad: int = 0
	for p: int in JWUnits.POLICY_N:
		var pid: String = _pid(docs, p)
		for item: Variant in _arr(docs[p], "player_params"):
			var pp: Dictionary = item as Dictionary
			var key: String = String(pp.get("key", "?"))
			var rng: Array = []
			if typeof(pp.get("valid_range")) == TYPE_ARRAY:
				rng = pp["valid_range"] as Array
			if rng.size() != 2:
				bad += 1
				fail("%s.%s 缺少形如 [min, max] 的 valid_range（V-PD-09）" % [pid, key])
				continue
			var lo: int = _as_int(rng[0])
			var hi: int = _as_int(rng[1])
			var dv: int = _as_int(pp.get("default", BAD_INT))
			if dv == BAD_INT:
				bad += 1
				fail("%s.%s 的 default 不是整数；params_ppm / params_uu 是 PackedInt64Array，无法承载非整数默认值（docs/17 §4.8 / V-PD-09）"
						% [pid, key])
				continue
			if lo > hi or dv < lo or dv > hi:
				bad += 1
				fail("%s.%s 的 default = %d 不在 valid_range [%d, %d] 内（V-PD-09）" % [pid, key, dv, lo, hi])
	eq_int(bad, 0, "player_params 的区间／默认值违规项数必须为 0（V-PD-09）")


## V-PD-06 / V-PD-07 / INV-099：failure_paths 非空、每条带 test_id；acceptance_tests 非空。
## 「写不出失败测试的政策，进不了内容包。」
func test_u_failure_paths_and_acceptance_tests_present() -> void:
	var docs: Array = _load_all_policy_docs()
	eq_int(docs.size(), JWUnits.POLICY_N, "先要有 12 个政策文件才能校验测试对（V-PD-01）")
	if docs.size() != JWUnits.POLICY_N:
		return
	var empty_failures: int = 0
	var bad_ids: int = 0
	for p: int in JWUnits.POLICY_N:
		var pid: String = _pid(docs, p)
		var fps: Array = _arr(docs[p], "failure_paths")
		if fps.is_empty():
			empty_failures += 1
			fail("%s 的 failure_paths 为空（V-PD-06：写不出失败测试的政策不进内容包）" % pid)
		for item: Variant in fps:
			var fp: Dictionary = item as Dictionary
			var tid: String = String(fp.get("test_id", ""))
			if not _is_test_id(tid):
				bad_ids += 1
				fail("%s 的 failure_path[%s] 的 test_id = \"%s\" 不是合法的测试矩阵 ID（V-PD-06：只能是 docs/30 的 T-* 或 docs/31 的 ADV-*）"
						% [pid, String(fp.get("code", "?")), tid])
		var ats: Array = _arr(docs[p], "acceptance_tests")
		check(ats.size() > 0, "%s 的 acceptance_tests 不得为空（V-PD-07）" % pid)
		for item2: Variant in ats:
			var at: String = String(item2)
			if not _is_test_id(at):
				bad_ids += 1
				fail("%s 的 acceptance_tests 含非法 ID \"%s\"（V-PD-07：只能是 docs/30 的 T-* 或 docs/31 的 ADV-*）"
						% [pid, at])
	eq_int(empty_failures, 0, "failure_paths 为空的政策数必须为 0（V-PD-06）")
	eq_int(bad_ids, 0, "非法 test_id 的条数必须为 0（V-PD-06/07）")


## 计划书 §10 的「最早反馈」列 / docs/30 §4.2 同名列：
## lag.min_feedback_q 与 lag.max_feedback_q 必须逐项对上，参数定稿不得改动这张表。
func test_u_feedback_window_matches_plan_section_10() -> void:
	var docs: Array = _load_all_policy_docs()
	eq_int(docs.size(), JWUnits.POLICY_N, "先要有 12 个政策文件才能校验反馈窗口（V-PD-01）")
	if docs.size() != JWUnits.POLICY_N:
		return
	for p: int in JWUnits.POLICY_N:
		var pid: String = _pid(docs, p)
		var lag: Dictionary = _sub(docs[p], "lag")
		var lo: int = _as_int(lag.get("min_feedback_q", BAD_INT))
		var hi: int = _as_int(lag.get("max_feedback_q", BAD_INT))
		eq_int(lo, PLAN_MIN_FEEDBACK_Q[p],
				"%s 的 lag.min_feedback_q 必须等于计划书 §10「最早反馈」列的下界（docs/30 §4.2 同表）" % pid)
		if PLAN_MAX_FEEDBACK_Q[p] >= 0:
			eq_int(hi, PLAN_MAX_FEEDBACK_Q[p],
					"%s 的 lag.max_feedback_q 必须等于计划书 §10「最早反馈」列的上界（docs/30 §4.2 同表）" % pid)
		ge_int(hi, lo, "%s 的反馈窗口必须满足 min <= max" % pid)
		ge_int(_as_int(lag.get("enact_to_effect_q", BAD_INT)), 1,
				"%s 的 lag.enact_to_effect_q 必须 >= 1；等于 0 就是「当季立刻生效」，时滞被跳过（INV-095/098）" % pid)


## 计划书 §10「投入与工期」行 + docs/18 R-SCALE-01：总成本 4 U、8 季、每季 0.5 U。
## 三个数互相锁死，并同时用 JWUnits.U_SCALE 复算一遍，钉死 1 U == 1e9 μU。
func test_u_p04_cost_matches_plan_section_10() -> void:
	var d: Dictionary = _load_policy_doc(P04)
	eq_str(String(d.get("policy_id", "")), "policy.P04", "本测试针对 P04 电网可靠性升级")
	var cost: Dictionary = _sub(d, "cost")
	eq_int(JWUnits.U_SCALE, 1_000_000_000, "docs/18 R-SCALE-01：1 U == 1e9 μU（不是 1e6）")
	eq_int(_as_int(cost.get("one_off_uu", BAD_INT)), P04_ONE_OFF_UU,
			"计划书 §10：P04 总成本 4 U == 4 × U_SCALE μU")
	eq_int(P04_ONE_OFF_UU, JWMath.mul(4, JWUnits.U_SCALE),
			"字面量 4_000_000_000 必须等于 4 × U_SCALE，否则刻度裁定 R-SCALE-01 没有落到测试里")
	eq_int(_as_int(cost.get("planned_quarters", BAD_INT)), P04_PLANNED_Q,
			"计划书 §10：P04 计划 8 季")
	eq_int(_as_int(cost.get("per_quarter_uu", BAD_INT)), P04_PER_Q_UU,
			"计划书 §10：P04 每季 0.5 U == U_SCALE / 2 μU")
	eq_int(P04_PER_Q_UU, JWMath.floor_div(JWUnits.U_SCALE, 2),
			"字面量 500_000_000 必须等于 0.5 U（U_SCALE / 2）")
	eq_int(JWMath.mul(P04_PER_Q_UU, P04_PLANNED_Q), P04_ONE_OFF_UU,
			"计划书 §10：每季 0.5 U × 8 季必须精确等于总成本 4 U（V-PD-03）")
	eq_int(_as_int(cost.get("required_construction_uqs", BAD_INT)), P04_REQ_CONSTRUCTION_UQS,
			"P04 的施工投入 3 200 000 μQ_services 不随货币刻度变化（docs/18 R-SCALE-01 第 3 条）")
	eq_int(_as_int(cost.get("required_equipment_uqs", BAD_INT)), P04_REQ_EQUIPMENT_UQS,
			"P04 的进口设备 1 600 000 μQ_manu 不随货币刻度变化（docs/18 R-SCALE-01 第 3 条）")


## 计划书 §10「支出落点」行：每季 0.2 U 进口设备 + 0.1 U 国产材料 + 0.2 U 施工服务，各有收款方。
func test_u_p04_spend_lines_match_plan_section_10() -> void:
	var d: Dictionary = _load_policy_doc(P04)
	var lines: Dictionary = _sub(_sub(d, "cost"), "spend_lines_uu_per_q")
	eq_int(_as_int(lines.get("import_equipment", BAD_INT)), P04_LINE_IMPORT_UU,
			"计划书 §10：P04 每季进口设备 0.2 U == U_SCALE / 5 μU")
	eq_int(_as_int(lines.get("domestic_material", BAD_INT)), P04_LINE_MATERIAL_UU,
			"计划书 §10：P04 每季国产材料 0.1 U == U_SCALE / 10 μU")
	eq_int(_as_int(lines.get("construction_service", BAD_INT)), P04_LINE_CONSTRUCTION_UU,
			"计划书 §10：P04 每季施工服务 0.2 U == U_SCALE / 5 μU")
	eq_int(P04_LINE_IMPORT_UU, JWMath.floor_div(JWUnits.U_SCALE, 5), "0.2 U 的新刻度换算")
	eq_int(P04_LINE_MATERIAL_UU, JWMath.floor_div(JWUnits.U_SCALE, 10), "0.1 U 的新刻度换算")
	eq_int(P04_LINE_IMPORT_UU + P04_LINE_MATERIAL_UU + P04_LINE_CONSTRUCTION_UU, P04_PER_Q_UU,
			"计划书 §10：三条支出落点之和必须精确等于每季 0.5 U（V-PD-03，加载器不得补偿）")
	eq_int(JWMath.mul(P04_LINE_IMPORT_UU + P04_LINE_MATERIAL_UU + P04_LINE_CONSTRUCTION_UU,
			P04_PLANNED_Q), P04_ONE_OFF_UU,
			"8 季逐季分项累计必须精确等于 4 U（docs/30 T-S-P04-CHAIN 断言 ①②）")


## 计划书 §10「运行费」与「容量效果」行：每季 0.02 U；额外 10 单位可用电力服务。
func test_u_p04_opex_and_capacity_match_plan_section_10() -> void:
	var d: Dictionary = _load_policy_doc(P04)
	eq_int(_as_int(_sub(d, "cost").get("opex_per_q_uu", BAD_INT)), P04_OPEX_UU,
			"计划书 §10：P04 启用后每季运行费 0.02 U == U_SCALE / 50 μU（docs/30 T-S-P04-CHAIN 断言 ⑥）")
	eq_int(P04_OPEX_UU, JWMath.floor_div(JWUnits.U_SCALE, 50), "0.02 U 的新刻度换算")
	var eff: Dictionary = _sub(d, "effect")
	eq_int(_as_int(eff.get("capacity_delta_uqs_per_q", BAD_INT)), P04_CAPACITY_UQS,
			"计划书 §10：额外 10 单位可用电力服务 == 10 × Q_SCALE μQ_energy/季（docs/30 T-S-P04-CHAIN 断言 ④）")
	eq_int(P04_CAPACITY_UQS, JWMath.mul(10, JWUnits.Q_SCALE),
			"实物量刻度 Q_SCALE 不随 R-SCALE-01 变化（docs/18 R-SCALE-01 常量表）")
	eq_str(String(eff.get("target", "")), "state.region.grid_capacity_pending_uqs_per_q",
			"计划书 §10：新增容量下一季才投入使用，落点只能是 *_pending_*（V-PD-11 / INV-091）")


## 计划书 §10「退出处理」行 + INV-098：已交付资产保留、赔偿按剩余合同规则、开关有冷却与成本。
func test_u_p04_exit_and_toggle_rule() -> void:
	var d: Dictionary = _load_policy_doc(P04)
	var ex: Dictionary = _sub(d, "exit_rule")
	eq_str(String(ex.get("delivered_assets", "")), "retain",
			"计划书 §10：P04 已交付资产保留（docs/30 T-S-P<nn>-OFF 断言 ③）")
	eq_str(String(ex.get("unfinished_work", "")), "register_residual",
			"计划书 §10：未完工工程登记残值")
	eq_str(String(ex.get("compensation_rule", "")), "remaining_contract_ppm",
			"计划书 §10：合同赔偿按剩余合同规则结算")
	eq_int(_as_int(ex.get("compensation_ppm", BAD_INT)), P04_EXIT_COMPENSATION_PPM,
			"docs/11 §5.12 的 P04 夹具值：exit_rule.compensation_ppm == 300 000")
	eq_int(_as_int(d.get("cooldown_q", BAD_INT)), P04_COOLDOWN_Q,
			"docs/11 §5.12 的 P04 夹具值：cooldown_q == 4（INV-098 冷却期）")
	eq_int(_as_int(d.get("toggle_cost_uu", BAD_INT)), P04_TOGGLE_COST_UU,
			"docs/11 §5.12：toggle_cost_uu == param.policy_toggle_cost_uu == 0.01 U（INV-098「每次开关有真实成本」）")
	eq_int(P04_TOGGLE_COST_UU, JWMath.floor_div(JWUnits.U_SCALE, 100), "0.01 U 的新刻度换算")
	var lag: Dictionary = _sub(d, "lag")
	eq_int(_as_int(lag.get("enact_to_effect_q", BAD_INT)), P04_LAG_Q,
			"docs/11 §5.12 的 P04 夹具值：lag.enact_to_effect_q == 1")
	eq_int(_as_int(lag.get("commission_delay_q", BAD_INT)), P04_COMMISSION_DELAY_Q,
			"docs/11 §5.12 的 P04 夹具值：lag.commission_delay_q == 1（INV-091）")


## 计划书 §10「失败路径」行 / docs/30 §4.4：P04 恰有五条失败路径，一条不少。
func test_u_p04_failure_paths_are_the_five_of_plan_section_10() -> void:
	var d: Dictionary = _load_policy_doc(P04)
	var want: PackedStringArray = ["financing", "delivery", "congestion", "fuel", "no_demand"]
	var got: PackedStringArray = PackedStringArray()
	for item: Variant in _arr(d, "failure_paths"):
		got.append(String((item as Dictionary).get("code", "")))
	eq_int(got.size(), want.size(),
			"计划书 §10：P04 的失败路径恰有 5 条（融资中断／设备延迟／施工队列拥堵／燃料不足／没有需求）")
	for code: String in want:
		check(got.has(code),
				"P04 缺少计划书 §10 点名的失败路径 \"%s\"（V-PD-06：每条失败路径都要有可运行的测试）" % code)


# ══════════════════════════════════════════════════════════════════════════
# B 段：JWPolicyEngine 的闸门、预留、时滞、幂等与退出
# ══════════════════════════════════════════════════════════════════════════

## docs/17 §4.21 成员表：状态数组长度与初值（enacted_q / effective_from_q / exit_pending_q 初值 −1）。
func test_u_policy_state_arrays_allocated_with_contract_initials() -> void:
	var st: JWSimState = _new_state()
	var pe: JWPolicyEngine = st.policy
	eq_int(pe.enabled.size(), JWUnits.POLICY_N, "state.policy.enabled 长度必须是 12（docs/17 §4.21）")
	eq_int(pe.params_ppm.size(), JWUnits.POLICY_PARAM_N, "state.policy.params_ppm 长度必须是 48")
	eq_int(pe.params_uu.size(), JWUnits.POLICY_PARAM_N, "state.policy.params_uu 长度必须是 48")
	eq_int(pe.pending_params.size(), JWUnits.POLICY_PARAM_N, "state.policy.pending_params 长度必须是 48")
	eq_int(pe.claim_key.size(), JWPolicyEngine.CLAIM_CAP, "claim_ledger 的键数组长度必须是 CLAIM_CAP")
	eq_int(pe.claim_amount.size(), JWPolicyEngine.CLAIM_CAP, "claim_ledger 的金额数组长度必须是 CLAIM_CAP")
	if pe.enabled.size() != JWUnits.POLICY_N:
		return
	for p: int in JWUnits.POLICY_N:
		eq_int(pe.enabled[p], 0, "政策 %d 的 enabled 初值必须是 0（docs/17 §4.21）" % p)
		eq_int(pe.enacted_q[p], -1, "政策 %d 的 enacted_q 初值必须是 −1（未通过）" % p)
		eq_int(pe.effective_from_q[p], -1, "政策 %d 的 effective_from_q 初值必须是 −1" % p)
		eq_int(pe.exit_pending_q[p], -1, "政策 %d 的 exit_pending_q 初值必须是 −1" % p)
		eq_int(pe.toggle_count[p], 0, "政策 %d 的 toggle_count 初值必须是 0" % p)
		eq_int(pe.cooldown_until_q[p], 0, "政策 %d 的 cooldown_until_q 初值必须是 0" % p)
		eq_int(pe.budget_committed[p], 0, "政策 %d 的 budget_committed 初值必须是 0" % p)
		eq_int(pe.budget_spent[p], 0, "政策 %d 的 budget_spent 初值必须是 0" % p)


## INV-095（唯一实现点）：enabled == 0 时，12 项政策一律零效应。
## 这是 docs/30 「未满足前置条件不得发放效果」在效应闸门上的最小形式。
func test_u_is_effective_false_when_disabled_for_all_twelve() -> void:
	var st: JWSimState = _new_state()
	var pe: JWPolicyEngine = st.policy
	for p: int in JWUnits.POLICY_N:
		check_false(pe.is_effective(p, 0),
				"政策 %d 未启用（enabled == 0）时 is_effective 必须为假（INV-095）" % p)
		check_false(pe.is_effective(p, 39),
				"政策 %d 未启用时，推进到第 39 季 is_effective 仍必须为假（INV-095）" % p)


## INV-095 / docs/30 T-S-P<nn>-CHAIN 断言 ①②：
## q < effective_from_q 期间零效应；q == effective_from_q 当季首次生效，且此后一直生效。
func test_u_is_effective_respects_effective_from_q() -> void:
	var st: JWSimState = _new_state()
	var pe: JWPolicyEngine = st.policy
	var eff_q: int = 5
	for p: int in JWUnits.POLICY_N:
		_seed_int(pe, "enabled", p, 1)
		_seed_int(pe, "effective_from_q", p, eff_q)
		_seed_int(pe, "enacted_q", p, eff_q - 1)
	eq_int(_seed_errors, 0, "夹具写入失败说明 state.policy.* 没有按契约长度分配（docs/17 §4.21）")
	for p: int in JWUnits.POLICY_N:
		check_false(pe.is_effective(p, eff_q - 1),
				"政策 %d：q = %d < effective_from_q = %d，必须零效应（INV-095，时滞不得跳过）"
						% [p, eff_q - 1, eff_q])
		check(pe.is_effective(p, eff_q),
				"政策 %d：q == effective_from_q = %d 当季必须开始生效（docs/30 T-S-P<nn>-CHAIN 断言 ②）"
						% [p, eff_q])
		check(pe.is_effective(p, eff_q + 3),
				"政策 %d：生效后不得自行失效（INV-095）" % p)


## INV-095：`effective_param_ppm` 在未生效时**恒返回 0**，生效后返回登记参数原值。
func test_u_effective_param_zero_before_effective() -> void:
	var st: JWSimState = _new_state()
	var pe: JWPolicyEngine = st.policy
	var slot: int = JWIds.idx_policy_param(P01, 0)
	_seed_int(pe, "params_ppm", slot, 250_000)
	_seed_int(pe, "enabled", P01, 1)
	_seed_int(pe, "effective_from_q", P01, 4)
	eq_int(_seed_errors, 0, "夹具写入失败说明 state.policy.* 没有按契约长度分配")
	eq_int(pe.effective_param_ppm(P01, 0, 3), 0,
			"q = 3 < effective_from_q = 4 时 effective_param_ppm 必须恒为 0（INV-095）")
	eq_int(pe.effective_param_ppm(P01, 0, 4), 250_000,
			"q == effective_from_q 时必须返回登记参数原值 250 000 ppm（INV-095 的另一半）")
	_seed_int(pe, "enabled", P01, 0)
	eq_int(pe.effective_param_ppm(P01, 0, 9), 0,
			"关停后（enabled == 0）即使 q 已过生效季，参数也必须归零（INV-095 / 退出规则断言 ①）")


## docs/12 §2.1 02.1 + INV-098：通过后 effective_from_q == q + lag、toggle_count += 1、
## cooldown_until_q == q + cooldown_q。
func test_u_try_enact_sets_lag_cooldown_toggle() -> void:
	var st: JWSimState = _new_state()
	_seed_p04(st)
	eq_int(_seed_errors, 0, "P04 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	var q: int = Q_ENACT
	var rc: int = _enact_p04(st, q)
	eq_int(rc, JWResult.OK,
			"前置条件全部满足时 P04 立项必须被接受（docs/12 §2.1 资格链；返回码见 JWResult.Reject）")
	eq_int(st.policy.enacted_q[P04], q, "docs/12 §2.1：通过后 enacted_q == 本季 q")
	eq_int(st.policy.effective_from_q[P04], q + P04_LAG_Q,
			"docs/12 §2.1：effective_from_q == q + lag.enact_to_effect_q（时滞只能向前，INV-098）")
	eq_int(st.policy.toggle_count[P04], 1, "docs/12 §2.1：通过一次 toggle_count += 1（INV-098）")
	eq_int(st.policy.cooldown_until_q[P04], q + P04_COOLDOWN_Q,
			"docs/12 §2.1：cooldown_until_q == q + policy_def.cooldown_q（INV-098）")
	check_false(st.policy.is_effective(P04, q),
			"立项当季不得生效——时滞 1 季（INV-095，docs/30 T-S-P04-CHAIN 断言 ①）")
	check(st.policy.is_effective(P04, q + P04_LAG_Q),
			"下一季必须开始生效（docs/30 T-S-P04-CHAIN 断言 ②）")


## docs/12 §2.2 + INV-032 / INV-033 / INV-096：预留占用可用额度而非现金；
## 承诺登记的是全部季的合同额（one_off_uu），且不产生任何现金移动。
func test_u_try_enact_reserves_budget_and_commits() -> void:
	var st: JWSimState = _new_state()
	_seed_p04(st)
	eq_int(_seed_errors, 0, "P04 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	var cash_before: int = st.accounts.cash_of(JWIds.AGENT_GOV)
	var committed_before: int = st.treasury.committed_memo
	var rc: int = _enact_p04(st, Q_ENACT)
	eq_int(rc, JWResult.OK, "P04 立项必须被接受，才能检验预留与承诺（docs/12 §2.2）")
	eq_int(cash_before - st.accounts.cash_of(JWIds.AGENT_GOV), P04_TOGGLE_COST_UU,
			"docs/12 §2.2：预留不产生任何现金移动，本季政府现金的唯一减少项是那笔一次性开关成本 0.01 U（INV-098）")
	eq_int(st.treasury.reserved_memo, P04_PER_Q_UU,
			"docs/12 §2.2：reserved_memo += cost.per_quarter_uu == 0.5 U（预留是本季的，不是全程的）")
	eq_int(st.treasury.committed_memo - committed_before, P04_ONE_OFF_UU,
			"docs/12 §2.2：committed_memo += cost.one_off_uu == 4 U（未来全部季承诺，INV-032）")
	eq_int(st.policy.budget_committed[P04], P04_ONE_OFF_UU,
			"docs/12 §2.2：policy.budget_committed_uu += cost.one_off_uu == 4 U")
	le_int(st.policy.budget_spent[P04], st.policy.budget_committed[P04],
			"INV-096：budget_spent 永远不得超过 budget_committed")
	eq_int(st.policy.budget_spent[P04], 0,
			"预留不是支付：立项当季 budget_spent 必须仍为 0（docs/12 §2.2「真正的付款在 S04」）")


## docs/30 T-S-P<nn>-GATE 断言 ①②⑤ + INV-137 / INV-100：
## 权限位未取得 ⇒ REJECT(E_AUTHORITY)，状态哈希逐位不变，且 blocked_reason != none。
func test_u_reject_authority_leaves_state_hash_unchanged() -> void:
	var st: JWSimState = _new_state()
	_seed_p04(st)
	st.politics.legal_authority_mask = 0
	eq_int(_seed_errors, 0, "P04 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	_ctx(st, Q_ENACT)
	var hash_before: String = st.state_hash()
	var rc: int = _enact_p04(st, Q_ENACT)
	eq_int(rc, JWResult.Reject.AUTHORITY,
			"权限位未取得时必须精确返回 E_AUTHORITY（docs/12 §2.1 资格链第 1 步；docs/30 GATE 断言 ①）")
	eq_str(st.state_hash(), hash_before,
			"INV-137：命令被拒时状态哈希必须逐位不变（docs/30 GATE 断言 ②）")
	eq_int(st.policy.enabled[P04], 0, "被拒的政策不得被置为已启用（docs/30 GATE 断言 ⑤）")
	eq_int(st.policy.toggle_count[P04], 0, "被拒的命令不得消耗 toggle_count（INV-098）")
	var reason: int = st.policy.blocked_reason(P04)
	ne_int(reason, JWUnits.BlockedReason.NONE,
			"INV-100：enabled == 0 且玩家可见时 blocked_reason 必须不是 none")
	eq_int(reason, JWUnits.BlockedReason.AUTHORITY,
			"权限缺失的 blocked_reason 必须是 AUTHORITY，玩家才知道差在哪（INV-100）")


## docs/30 T-S-P<nn>-GATE + docs/12 §2.1 第 1 步：席位占比不足 ⇒ REJECT(E_SEATS_SHORT)，状态不变。
func test_u_reject_seats_short_is_pure() -> void:
	var st: JWSimState = _new_state()
	_seed_p04(st)
	st.politics.seats_gov = SEATS_GOV_SHORT
	eq_int(_seed_errors, 0, "P04 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	eq_int(JWMath.mul_div_floor(SEATS_GOV_SHORT, JWUnits.PPM, SEATS_TOTAL), 99_009,
			"席位占比按 mul_div_floor(seats_gov, 1e6, seats_total) 计算：10/101 == 99 009 ppm")
	_ctx(st, Q_ENACT)
	var hash_before: String = st.state_hash()
	var rc: int = _enact_p04(st, Q_ENACT)
	eq_int(rc, JWResult.Reject.SEATS_SHORT,
			"99 009 ppm < min_seats_ppm 500 000 时必须精确返回 E_SEATS_SHORT（docs/12 §2.1）")
	eq_str(st.state_hash(), hash_before, "INV-137：被拒命令不得改动任何状态")
	eq_int(st.policy.enabled[P04], 0, "席位不足时政策不得生效（docs/30 GATE 断言 ④⑤）")


## docs/30 T-S-P<nn>-GATE + docs/12 §2.1 第 1 步：集团否决 ⇒ REJECT(E_BLOC_VETO)。
func test_u_reject_bloc_veto_is_pure() -> void:
	var st: JWSimState = _new_state()
	_seed_p04(st)
	# P04 需要 bloc.business 不否决；把它的立场压到否决阈值以下。
	var stance: PackedInt64Array = PackedInt64Array()
	stance.resize(JWUnits.STANCE_N)
	stance.fill(600_000)
	stance[JWIds.idx_stance(JWUnits.Bloc.BUSINESS, P04)] = -1_000_000
	st.policy.set_bloc_stance_view(stance)
	eq_int(_seed_errors, 0, "P04 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	_ctx(st, Q_ENACT)
	var hash_before: String = st.state_hash()
	var rc: int = _enact_p04(st, Q_ENACT)
	eq_int(rc, JWResult.Reject.BLOC_VETO,
			"requires_bloc_mask 命中的集团强烈反对时必须精确返回 E_BLOC_VETO（docs/12 §2.1）")
	eq_str(st.state_hash(), hash_before, "INV-137：被拒命令不得改动任何状态")


## docs/30 T-S-P<nn>-GATE + docs/12 §2.2：现金不足（funding_source == cash）⇒ REJECT(E_BUDGET_INSUFFICIENT)。
func test_u_reject_budget_insufficient_is_pure() -> void:
	var st: JWSimState = _new_state()
	_seed_p04(st)
	_seed_int(st.accounts, "balance", JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH), 0)
	eq_int(_seed_errors, 0, "夹具写入失败说明 account.balance 没有按 900 分配")
	eq_int(st.accounts.cash_of(JWIds.AGENT_GOV), 0, "夹具：政府现金已清零")
	_ctx(st, Q_ENACT)
	var hash_before: String = st.state_hash()
	var rc: int = _enact_p04(st, Q_ENACT)
	eq_int(rc, JWResult.Reject.BUDGET_INSUFFICIENT,
			"need(0.5 U) > avail(0) 且资金来源为现金时必须精确返回 E_BUDGET_INSUFFICIENT（docs/12 §2.2）")
	eq_str(st.state_hash(), hash_before,
			"INV-137 / docs/12 §2.2：预留失败时**不写任何资金行**，状态哈希必须不变")
	eq_int(st.treasury.reserved_memo, 0, "被拒时不得留下半截预留（INV-033）")
	eq_int(st.policy.budget_committed[P04], 0, "被拒时不得留下半截承诺（INV-032）")


## docs/30 T-S-P<nn>-GATE + docs/12 §2.1 第 4 步 / INV-094：无施工槽位 ⇒ REJECT(E_NO_SLOT)。
func test_u_reject_no_slot_is_pure() -> void:
	var st: JWSimState = _new_state()
	_seed_p04(st)
	for r: int in JWUnits.R:
		_seed_int(st.capital, "construction_slots", r, 0)
	eq_int(_seed_errors, 0, "夹具写入失败说明 state.region.construction_slots_total 没有按 4 分配")
	_ctx(st, Q_ENACT)
	var hash_before: String = st.state_hash()
	var rc: int = _enact_p04(st, Q_ENACT)
	eq_int(rc, JWResult.Reject.NO_SLOT,
			"施工槽位为 0 时必须精确返回 E_NO_SLOT（docs/12 §2.1 第 4 步，INV-094）")
	eq_str(st.state_hash(), hash_before, "INV-137：被拒命令不得改动任何状态")
	eq_int(st.policy.blocked_reason(P04), JWUnits.BlockedReason.QUEUE,
			"槽位不足时 blocked_reason 必须是 QUEUE，玩家才知道要先腾出队列（INV-100）")


## INV-098：冷却期内的**关停**同样必须 REJECT(E_POLICY_COOLDOWN)，
## 否则「开一季关一季」可以绕过冷却，docs/31 ADV-A01 的开关刷成本攻击就成立了。
func test_u_cooldown_blocks_repeal() -> void:
	var st: JWSimState = _new_state()
	_seed_p04(st)
	eq_int(_seed_errors, 0, "P04 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	eq_int(_enact_p04(st, Q_ENACT), JWResult.OK, "第一次立项必须被接受")
	eq_int(st.policy.cooldown_until_q[P04], Q_ENACT + P04_COOLDOWN_Q,
			"冷却截止季 == 立项季 3 + cooldown_q 4 == 7（INV-098）")
	var toggles_before: int = st.policy.toggle_count[P04]
	_ctx(st, Q_ENACT + 2)
	var hash_before: String = st.state_hash()
	var rc: int = _repeal_p04(st, Q_ENACT + 2)
	rejects(rc, JWResult.OK, "冷却期内（q = 5 < cooldown_until_q = 7）的关停必须被拒（INV-098）")
	eq_int(rc, JWResult.Reject.POLICY_COOLDOWN,
			"冷却期内关停的拒绝码必须精确是 E_POLICY_COOLDOWN（docs/17 §4.21 try_repeal 失败码）")
	eq_int(st.policy.toggle_count[P04], toggles_before,
			"被拒的开关不得计入 toggle_count，否则冷却可以被刷（INV-098）")
	eq_int(st.policy.enabled[P04], 1, "被拒的关停不得把政策关掉")
	eq_str(st.state_hash(), hash_before, "INV-137：被拒命令不得改动任何状态")


## INV-098 / INV-137：已经通过的政策不得被重复立项，且重复命令必须是纯的。
func test_u_double_enact_rejected_and_pure() -> void:
	var st: JWSimState = _new_state()
	_seed_p04(st)
	eq_int(_seed_errors, 0, "P04 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	eq_int(_enact_p04(st, Q_ENACT), JWResult.OK, "第一次立项必须被接受")
	var committed_before: int = st.policy.budget_committed[P04]
	var toggles_before: int = st.policy.toggle_count[P04]
	_ctx(st, Q_REPEAL)
	var hash_before: String = st.state_hash()
	var rc: int = _enact_p04(st, Q_REPEAL)
	rejects(rc, JWResult.OK, "已生效的政策再次立项必须被拒（否则承诺会被重复登记一次）")
	eq_int(rc, JWResult.Reject.ALREADY_ENACTED,
			"重复立项的拒绝码必须精确是 E_ALREADY_ENACTED（docs/11 §7 的 E_* 表）")
	eq_int(st.policy.budget_committed[P04], committed_before,
			"被拒的重复立项不得再加一次 budget_committed（INV-032/096：承诺不得凭空翻倍）")
	eq_int(st.policy.toggle_count[P04], toggles_before, "被拒的命令不得计入 toggle_count（INV-098）")
	eq_str(st.state_hash(), hash_before, "INV-137：被拒命令不得改动任何状态")


## docs/30 T-S-P<nn>-GATE「预算审查窗口未到」+ docs/12 §2.8 / INV-127：
## `requires_budget_review == 1` 的政策在窗口关闭时必须 REJECT(E_PRECONDITION)，且状态不变。
func test_u_reject_budget_review_window_closed() -> void:
	var st: JWSimState = _new_state()
	_seed_p04(st)
	eq_int(_seed_errors, 0, "P04 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	_ctx(st, Q_ENACT)
	st.politics.f_budget_review_due = 0
	var hash_before: String = st.state_hash()
	var rc: int = st.policy.try_enact(P04, st.policy_defs, st.politics, st.treasury,
			st.projects, st.capital, st.ledger, st.accounts, Q_ENACT, st.params)
	eq_int(rc, JWResult.Reject.PRECONDITION,
			"预算审查窗口未到时必须精确返回 E_PRECONDITION（docs/30 GATE 的前置清单；docs/12 §2.8）")
	eq_str(st.state_hash(), hash_before, "INV-137：被拒命令不得改动任何状态")
	eq_int(st.policy.blocked_reason(P04), JWUnits.BlockedReason.PRECONDITION,
			"窗口未到的 blocked_reason 必须是 PRECONDITION（INV-100）")
	eq_int(st.treasury.committed_memo, 0, "被拒时不得留下半截承诺（INV-032）")


## INV-098：`effective_from_q` 单调不回溯——关停再开启只能往后排，不能把生效季写回历史。
## 这是 ADV-A01「反复开关补发历史季」攻击的结构性防线。
func test_u_effective_from_q_never_moves_backward() -> void:
	var st: JWSimState = _new_state()
	_seed_p04(st)
	eq_int(_seed_errors, 0, "P04 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	eq_int(_enact_p04(st, Q_ENACT), JWResult.OK, "第一次立项必须被接受")
	var first_eff: int = st.policy.effective_from_q[P04]
	eq_int(first_eff, Q_ENACT + P04_LAG_Q, "第一次生效季 == 3 + lag 1 == 4")
	eq_int(_repeal_p04(st, Q_REPEAL), JWResult.OK,
			"冷却期满（q = 7）后关停必须被接受（docs/30 T-S-P<nn>-OFF）")
	var rc: int = _enact_p04(st, Q_REENACT)
	eq_int(rc, JWResult.OK, "再次冷却期满（q = 11）后重新开启必须被接受")
	ge_int(st.policy.effective_from_q[P04], first_eff,
			"INV-098：effective_from_q 单调不回溯；写回历史季等于给玩家补发关闭期间的效果")
	eq_int(st.policy.effective_from_q[P04], Q_REENACT + P04_LAG_Q,
			"重新开启的生效季 == 重新开启季 11 + lag 1 == 12（INV-098，docs/31 ADV-A01）")
	ge_int(st.policy.toggle_count[P04], 3,
			"开启 + 关停 + 再开启 == 3 次开关，每次都必须计数并收一次行政成本（INV-098）")


## INV-100：任何未启用且玩家可见的政策都必须有非 none 的 blocked_reason，
## 否则政策页无法告诉玩家「为什么不能执行」。
func test_u_blocked_reason_not_none_when_disabled() -> void:
	var st: JWSimState = _new_state()
	_seed_all_defs(st)
	st.politics.legal_authority_mask = 0
	eq_int(_seed_errors, 0, "政策定义夹具写入失败说明 content.policy.* 长度不符合 docs/17 §4.8")
	st.policy.refresh_blocked_reasons(st.policy_defs, st.politics, st.treasury, st.projects,
			st.capital, st.accounts, 0, st.params)
	for p: int in JWUnits.POLICY_N:
		eq_int(st.policy.enabled[p], 0, "政策 %d 在夹具里应为未启用" % p)
		ne_int(st.policy.blocked_reason(p), JWUnits.BlockedReason.NONE,
				"政策 %d 未启用且权限全无时 blocked_reason 不得是 none（INV-100）" % p)
		in_range_int(st.policy.blocked_reason(p), JWUnits.BlockedReason.NONE,
				JWUnits.BlockedReason.EXITED,
				"政策 %d 的 blocked_reason 必须落在 docs/10 登记的枚举范围内（INV-100）" % p)


## V-PD-09 / INV-138：越界参数必须 REJECT(E_PARAM_RANGE)，且 params 逐位不变。
func test_u_apply_pending_params_range_gate() -> void:
	var st: JWSimState = _new_state()
	_seed_p04(st)
	eq_int(_seed_errors, 0, "P04 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	var slot: int = JWIds.idx_policy_param(P04, 1)
	var before: int = st.policy.params_ppm[slot]
	# P04 的 scale_ppm 合法区间 [250 000, 2 000 000]；写一个超出上界的值。
	_seed_int(st.policy, "pending_params", slot, 3_000_000)
	eq_int(_seed_errors, 0, "夹具写入失败说明 state.policy.pending_params 没有按 48 分配")
	var rc: int = st.policy.apply_pending_params(P04, st.policy_defs, 0)
	eq_int(rc, JWResult.Reject.PARAM_RANGE,
			"scale_ppm = 3 000 000 超出 valid_range [250 000, 2 000 000]，必须返回 E_PARAM_RANGE（V-PD-09）")
	eq_int(st.policy.params_ppm[slot], before,
			"越界参数被拒时 params_ppm 必须逐位不变，不得夹到边界后悄悄落地（INV-138 / INV-137）")
	# 合法值必须能落地，否则闸门等于把所有参数都堵死。
	_seed_int(st.policy, "pending_params", slot, 1_500_000)
	eq_int(st.policy.apply_pending_params(P04, st.policy_defs, 0), JWResult.OK,
			"区间内的参数必须能落地（V-PD-09 只拒越界，不拒合法值）")
	eq_int(st.policy.params_ppm[slot], 1_500_000, "合法参数落地后 params_ppm 必须等于提交值")


## INV-091 / V-PD-11 / V-PD-04：效果只能写 *_pending_*，`grid_capacity_active` 当季增量必须是 0；
## 且**项目类政策的效果不在本函数落地**。
##
## 后一半是契约逼出来的，不是实现方便：P04 的 10 × Q_SCALE μQ_energy 由项目队列在**完工那一季**
## 写进 `grid_capacity_pending`（docs/12 §7.1「目标数组的 *_pending_* += capacity_effect_uqs_per_q」；
## 该值由 S02 入队时从 `effect_magnitude` 抄进 `state.project.capacity_effect_uqs_per_q`，docs/10）。
## apply_effects 若在生效季再落一次，docs/30 的三条 P0 断言同时不成立——
## `T-S-P04-PAY-NO-PROGRESS`（施工进度恒 0 ⇒ `grid_capacity_pending` 增量 `== 0`）、
## `T-S-P04-NO-EARLY-COMMISSION`（交付未齐 ⇒ 增量 `== 0`）、`T-S-D-07` ⑤（取消 ⇒ 增量 `== 0`），
## 三者里的 P04 都是「已立项、已过生效季」的，而 `T-S-P04-CHAIN` ④⑤ 的 10 000 000 会变成 20 000 000。
##
## 所以本测试分两段：① 项目类在本函数零效应；② 同样的落点与量级换成非项目类政策时，
## 必须在落点季（`effective_from_q + commission_delay_q`，V-PD-04 / docs/30 T-U-C-02）
## 恰好落一次 pending，且 active 不动。
func test_u_apply_effects_writes_pending_not_active() -> void:
	var st: JWSimState = _new_state()
	_seed_p04(st)
	eq_int(_seed_errors, 0, "P04 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	var r: int = JWUnits.Region.HAIJIA
	var active_before: int = st.capital.grid_capacity[r]
	var pending_before: int = st.capital.grid_pending[r]
	_seed_int(st.policy, "enabled", P04, 1)
	_seed_int(st.policy, "effective_from_q", P04, 1)
	st.policy.set_region_mask(P04, 1 << r)
	# ① 项目类：生效季及其后若干季，本函数一律零效应——产能只能由完工那一刻写入。
	for q: int in [1, 2, 3, 4]:
		eq_int(st.policy.apply_effects(st.policy_defs, st.capital, st.treasury, st.politics,
				st.pop, q), JWResult.OK, "生效后的效果落地调用必须成功返回（q = %d）" % q)
		eq_int(st.capital.grid_pending[r] - pending_before, 0,
				"q = %d：项目类政策 P04 的产能只能由项目完工写入，apply_effects 再落一次就是凭空翻倍（docs/12 §7.1；docs/30 T-S-P04-PAY-NO-PROGRESS / T-S-P04-NO-EARLY-COMMISSION / T-S-D-07 ⑤）" % q)
		eq_int(st.capital.grid_capacity[r] - active_before, 0,
				"q = %d：grid_capacity_active 在任何情况下都不得被 apply_effects 写（INV-091 / V-PD-11）" % q)
	# ② 非项目类、同一落点同一量级：落点季恰好落一次 pending，active 不动。
	_seed_int(st.policy_defs, "kind", P04, JWPolicyDef.POLICY_KIND_CAPACITY)
	eq_int(_seed_errors, 0, "夹具写入失败说明 content.policy.kind 长度不符合 docs/17 §4.8")
	var landing_q: int = 1 + P04_COMMISSION_DELAY_Q
	eq_int(st.policy.apply_effects(st.policy_defs, st.capital, st.treasury, st.politics,
			st.pop, landing_q - 1), JWResult.OK, "落点季之前的调用必须成功返回")
	eq_int(st.capital.grid_pending[r] - pending_before, 0,
			"q = %d < effective_from_q + commission_delay_q：投运时滞未走完，pending 增量必须是 0（V-PD-04 / docs/30 T-U-C-02：政策不得绕过投运时滞）" % (landing_q - 1))
	eq_int(st.policy.apply_effects(st.policy_defs, st.capital, st.treasury, st.politics,
			st.pop, landing_q), JWResult.OK, "落点季的效果落地必须成功")
	eq_int(st.capital.grid_pending[r] - pending_before, P04_CAPACITY_UQS,
			"非项目类政策必须在落点季把 10 × Q_SCALE μQ_energy 写进 grid_capacity_pending（docs/17 §4.21 后置）")
	eq_int(st.capital.grid_capacity[r] - active_before, 0,
			"同一季 grid_capacity_active 的增量必须是 0——投运要等下一季 S01（INV-091 / V-PD-11）")
	eq_int(st.policy.apply_effects(st.policy_defs, st.capital, st.treasury, st.politics,
			st.pop, landing_q + 1), JWResult.OK, "落点季之后的调用必须成功返回")
	eq_int(st.capital.grid_pending[r] - pending_before, P04_CAPACITY_UQS,
			"存量性效果只能落一次：落点季之后再调 apply_effects，pending 的累计增量必须保持不变（否则 40 季发 40 倍）")


## INV-091 / V-PD-11 / docs/17 §4.21 apply_effects 后置：
## 能力类政策（P10 形状：落点 `state.pubserv.capacity_pending_uqs_per_q`）的效果由本函数直接落地，
## 不经项目队列。生效季必须写 pending，且 active 当季增量为 0。
func test_u_apply_effects_capacity_policy_writes_pending() -> void:
	var st: JWSimState = _new_state()
	var d: JWPolicyDef = st.policy_defs
	var delta: int = 500_000
	_seed_int(d, "kind", P10, JWPolicyDef.POLICY_KIND_CAPACITY)
	_seed_int(d, "lag_enact_to_effect_q", P10, 1)
	_seed_int(d, "commission_delay_q", P10, 1)
	_seed_int(d, "effect_target", P10, JWPolicyDef.TARGET_PUBSERV_CAPACITY_PENDING)
	_seed_int(d, "effect_magnitude", P10, delta)
	for j: int in JWIds.POLICY_PARAM_STRIDE:
		_seed_param(d, P10, j, 0, 2_000_000, JWUnits.PPM)
		_seed_int(st.policy, "params_ppm", JWIds.idx_policy_param(P10, j), JWUnits.PPM)
	_seed_int(st.policy, "enabled", P10, 1)
	_seed_int(st.policy, "enacted_q", P10, 0)
	_seed_int(st.policy, "effective_from_q", P10, 1)
	st.policy.set_region_mask(P10, 1 << JWUnits.Region.HAIJIA)
	eq_int(_seed_errors, 0, "P10 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	var r: int = JWUnits.Region.HAIJIA
	var pend_before: int = st.capital.pub_capacity_pending[r]
	var active_before: int = st.capital.pub_capacity_active[r]
	eq_int(st.policy.apply_effects(d, st.capital, st.treasury, st.politics, st.pop, 2),
			JWResult.OK, "生效季的效果落地必须成功")
	eq_int(st.capital.pub_capacity_pending[r] - pend_before, delta,
			"docs/17 §4.21：apply_effects 必须按 effect_target 调 JWCapital.add_pending 写入 effect_magnitude")
	eq_int(st.capital.pub_capacity_active[r] - active_before, 0,
			"同一季 capacity_active 增量必须是 0——投运要等下一季 S01（INV-091 / V-PD-11）")


## INV-095：未到生效季时，效果落点的累计变化必须精确为 0（docs/30 T-S-P<nn>-CHAIN 断言 ①）。
func test_u_apply_effects_zero_before_effective() -> void:
	var st: JWSimState = _new_state()
	_seed_p04(st)
	eq_int(_seed_errors, 0, "P04 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	var r: int = JWUnits.Region.HAIJIA
	var pending_before: int = st.capital.grid_pending[r]
	_seed_int(st.policy, "enabled", P04, 1)
	_seed_int(st.policy, "effective_from_q", P04, 4)
	st.policy.set_region_mask(P04, 1 << r)
	for q: int in 4:
		st.policy.apply_effects(st.policy_defs, st.capital, st.treasury, st.politics, st.pop, q)
		eq_int(st.capital.grid_pending[r] - pending_before, 0,
				"q = %d < effective_from_q = 4：效果落点的累计变化必须精确为 0（INV-095）" % q)
	# 未启用的政策同样零效应，即使 q 已越过生效季。
	_seed_int(st.policy, "enabled", P04, 0)
	st.policy.apply_effects(st.policy_defs, st.capital, st.treasury, st.politics, st.pop, 9)
	eq_int(st.capital.grid_pending[r] - pending_before, 0,
			"enabled == 0 时即使 q >= effective_from_q 也必须零效应（INV-095）")


## docs/30 T-S-P09-FAIL-NOINVEST + docs/17 §4.21：
## 补助的前置是「上季已发生的实际投资」，不是「政策已开启」。
func test_u_pay_subsidy_requires_prior_investment() -> void:
	var st: JWSimState = _new_state()
	_seed_p09(st)
	eq_int(_seed_errors, 0, "P09 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	var cell: int = JWIds.idx_cell(JWUnits.Region.HAIJIA, JWUnits.Sector.MANU)
	var cash_before: int = _cell_cash(st, cell)
	var rc: int = st.policy.pay_subsidy(P09, cell, 100_000_000, 7, 0, st.policy_defs,
			st.treasury, st.ledger, st.accounts, 3)
	rejects(rc, JWResult.OK,
			"上季实际投资为 0 时申领必须被拒（docs/30 T-S-P09-FAIL-NOINVEST：政策开启不等于有合格投资）")
	eq_int(_cell_cash(st, cell) - cash_before, 0,
			"无合格投资时企业现金增量必须精确为 0（INV-113：补助不得凭空发放）")
	eq_int(st.policy.claim_count(), 0, "无合格投资时不得在台账里留下任何一行（INV-097）")
	eq_int(st.policy.budget_spent[P09], 0, "无合格投资时 budget_spent 不得增加（INV-096）")


## INV-097 / docs/31 ADV-A01：同一 claim_key 至多付一次。
## claim_key = hash(policy_id, beneficiary_cell, q, qualifying_event_id)。
func test_u_pay_subsidy_idempotent_on_same_claim_key() -> void:
	var st: JWSimState = _new_state()
	_seed_p09(st)
	eq_int(_seed_errors, 0, "P09 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	var cell: int = JWIds.idx_cell(JWUnits.Region.HAIJIA, JWUnits.Sector.MANU)
	var invest: int = 1_000_000_000
	var want: int = JWMath.mul_ppm(invest, P09_SUBSIDY_RATE_PPM)
	eq_int(want, 300_000_000, "复算基准：合格投资 1 U × 补助费率 30% == 0.3 U")
	var c0: int = _cell_cash(st, cell)
	eq_int(st.policy.pay_subsidy(P09, cell, want, 7, invest, st.policy_defs,
			st.treasury, st.ledger, st.accounts, 3), JWResult.OK,
			"有合格投资、额度充足时第一次申领必须被接受（否则这条测试等于没测，docs/31 ADV-A01 第 3 点）")
	var c1: int = _cell_cash(st, cell)
	eq_int(c1 - c0, want,
			"第一次申领的实发额必须精确等于 mul_ppm(合格投资, 费率)（INV-002：先乘后除一次取整）")
	eq_int(st.policy.claim_count(), 1, "第一次申领必须在台账里恰好留下 1 行（INV-097）")
	var rc2: int = st.policy.pay_subsidy(P09, cell, want, 7, invest, st.policy_defs,
			st.treasury, st.ledger, st.accounts, 3)
	rejects(rc2, JWResult.OK,
			"同一 (policy, cell, q, qualifying_event_id) 的二次申领必须被挡下（INV-097 / ADV-01）")
	eq_int(_cell_cash(st, cell) - c1, 0,
			"重复申领的实发额必须精确为 0——白拿第二份就是 ADV-01 的攻击目标（INV-097）")
	eq_int(st.policy.claim_count(), 1,
			"重复申领不得新增台账行；同键至多一条（INV-097）")
	var c2: int = _cell_cash(st, cell)
	eq_int(st.policy.pay_subsidy(P09, cell, want, 8, invest, st.policy_defs,
			st.treasury, st.ledger, st.accounts, 3), JWResult.OK,
			"不同 qualifying_event_id 是不同的合格事件，必须能各领一次（否则幂等键把合法申领也吞了）")
	eq_int(_cell_cash(st, cell) - c2, want,
			"另一笔合格事件的实发额同样等于 mul_ppm(合格投资, 费率)")
	eq_int(st.policy.claim_count(), 2, "两个不同的 claim_key 必须各占一行（INV-097）")


## INV-097 / INV-098 / docs/31 ADV-A01：
## 台账只增不减；关停再开启不补发关闭期间的历史季。
func test_u_pay_subsidy_no_backpay_after_reenable() -> void:
	var st: JWSimState = _new_state()
	_seed_p09(st)
	eq_int(_seed_errors, 0, "P09 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	var cell: int = JWIds.idx_cell(JWUnits.Region.HAIJIA, JWUnits.Sector.MANU)
	var invest: int = 1_000_000_000
	var want: int = JWMath.mul_ppm(invest, P09_SUBSIDY_RATE_PPM)
	var c0: int = _cell_cash(st, cell)
	eq_int(st.policy.pay_subsidy(P09, cell, want, 7, invest, st.policy_defs,
			st.treasury, st.ledger, st.accounts, 3), JWResult.OK, "开启期间的申领必须被接受")
	eq_int(_cell_cash(st, cell) - c0, want, "开启期间的申领必须真的发放")
	var rows_before: int = st.policy.claim_count()
	var c1: int = _cell_cash(st, cell)
	# 关停：关闭期间（q = 4）发生的合格投资不得排队等待补发。
	_seed_int(st.policy, "enabled", P09, 0)
	st.policy.pay_subsidy(P09, cell, want, 9, invest, st.policy_defs, st.treasury,
			st.ledger, st.accounts, 4)
	eq_int(_cell_cash(st, cell) - c1, 0, "政策关停期间的实发额必须精确为 0（INV-095）")
	# 重新开启后，关闭期间的 claim_key 永久作废，不排队、不补发。
	_seed_int(st.policy, "enabled", P09, 1)
	_seed_int(st.policy, "effective_from_q", P09, 5)
	var c2: int = _cell_cash(st, cell)
	st.policy.pay_subsidy(P09, cell, want, 9, invest, st.policy_defs, st.treasury,
			st.ledger, st.accounts, 4)
	eq_int(_cell_cash(st, cell) - c2, 0,
			"重新开启后不得补发关闭期间（q = 4）的历史季；这正是 ADV-01 的攻击面（INV-097/098）")
	ge_int(st.policy.claim_count(), rows_before,
			"claim_ledger 只增不减：政策退出也不清零（docs/17 §4.21 `_claim_count` 只增不减）")


## docs/30 T-S-P<nn>-OFF 断言 ①②④⑤：
## 关停当季起效应归零；已发生的支出不回退；一次性行政成本恰扣 1 次；toggle_count += 1。
func test_u_repeal_zeroes_effect_but_keeps_spend() -> void:
	var st: JWSimState = _new_state()
	_seed_p04(st)
	eq_int(_seed_errors, 0, "P04 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	eq_int(_enact_p04(st, Q_ENACT), JWResult.OK, "先要立项成功，才能检验退出规则")
	# 模拟 S04 已经付过两季款（退出规则不得让这两季的钱回到国库）。
	_seed_int(st.policy, "budget_spent", P04, JWMath.mul(P04_PER_Q_UU, 2))
	eq_int(_seed_errors, 0, "夹具写入失败说明 state.policy.budget_spent_uu 没有按 12 分配")
	var spent_before: int = st.policy.budget_spent[P04]
	var toggles_before: int = st.policy.toggle_count[P04]
	var q_off: int = Q_REPEAL
	var rc: int = _repeal_p04(st, q_off)
	eq_int(rc, JWResult.OK, "冷却期满后关停必须被接受（docs/30 T-S-P<nn>-OFF）")
	eq_int(st.policy.enabled[P04], 0, "关停后 enabled 必须是 0")
	check_false(st.policy.is_effective(P04, q_off),
			"关停当季起效应函数必须返回零效应（docs/30 T-S-P<nn>-OFF 断言 ①）")
	check_false(st.policy.is_effective(P04, q_off + 3),
			"关停后第 3 季仍必须零效应（docs/30 T-S-P<nn>-OFF 断言 ①，4 次精确等于 0 中的一次）")
	eq_int(st.policy.budget_spent[P04], spent_before,
			"docs/30 T-S-P<nn>-OFF 断言 ②：已发生的支出 paid_uu 不回退——关停不能退钱（INV-093/098）")
	eq_int(st.policy.toggle_count[P04] - toggles_before, 1,
			"docs/30 T-S-P<nn>-OFF 断言 ⑤：toggle_count 增量恰为 1（INV-098）")
	eq_int(st.policy.cooldown_until_q[P04], q_off + P04_COOLDOWN_Q,
			"关停同样刷新冷却截止季（7 + 4 == 11），防止开关刷成本（INV-098）")


## docs/30 T-S-P<nn>-OFF 断言 ③ + 计划书 §10「退出处理」：
## `exit_rule.delivered_assets == retain` ⇒ 关停不减少已交付资产。
func test_u_repeal_retains_delivered_capacity() -> void:
	var st: JWSimState = _new_state()
	_seed_p04(st)
	eq_int(_seed_errors, 0, "P04 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	var r: int = JWUnits.Region.HAIJIA
	# 夹具：项目已投运，10 单位电力容量已在 active 上。
	_seed_int(st.capital, "grid_capacity", r, P04_CAPACITY_UQS)
	eq_int(_seed_errors, 0, "夹具写入失败说明 state.region.grid_capacity_uqs_per_q 没有按 4 分配")
	eq_int(_enact_p04(st, Q_ENACT), JWResult.OK, "先要立项成功，才能检验退出规则")
	var active_before: int = st.capital.grid_capacity[r]
	var pending_before: int = st.capital.grid_pending[r]
	eq_int(_repeal_p04(st, Q_REPEAL), JWResult.OK, "冷却期满后关停必须被接受")
	eq_int(st.capital.grid_capacity[r], active_before,
			"计划书 §10「已交付资产保留」：关停不得删除已投运的电网容量（docs/30 T-S-P<nn>-OFF 断言 ③）")
	eq_int(st.capital.grid_pending[r], pending_before,
			"关停不得回收 pending 上的容量；未完工部分走残值登记，不是抹掉（INV-091/093）")


## docs/30 T-S-P<nn>-OFF 断言 ⑥ + INV-098：关停后冷却期内的再开启必须 REJECT(E_POLICY_COOLDOWN)。
func test_u_repeal_then_reenact_within_cooldown_rejected() -> void:
	var st: JWSimState = _new_state()
	_seed_p04(st)
	eq_int(_seed_errors, 0, "P04 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	eq_int(_enact_p04(st, Q_ENACT), JWResult.OK, "先要立项成功")
	var q_off: int = Q_REPEAL
	eq_int(_repeal_p04(st, q_off), JWResult.OK, "冷却期满后关停必须被接受")
	_ctx(st, q_off + 1)
	var hash_before: String = st.state_hash()
	var rc: int = _enact_p04(st, q_off + 1)
	eq_int(rc, JWResult.Reject.POLICY_COOLDOWN,
			"关停后冷却期内（q = 8 < cooldown_until_q = 11）的再开启必须返回 E_POLICY_COOLDOWN（docs/30 OFF 断言 ⑥）")
	eq_str(st.state_hash(), hash_before, "INV-137：被拒的再开启命令不得改动任何状态")
	eq_int(st.policy.enabled[P04], 0, "被拒后政策必须仍是关停状态")


## INV-096：`budget_spent <= budget_committed` 在任何路径下都成立；
## 超预留必须走重新审核，而不是让支出悄悄越过承诺。
func test_u_budget_spent_never_exceeds_committed() -> void:
	var st: JWSimState = _new_state()
	_seed_p09(st)
	eq_int(_seed_errors, 0, "P09 夹具写入失败说明 content.policy.* 数组长度不符合 docs/17 §4.8")
	# 夹具：本政策只承诺了一季的量，却连续申领四季。
	_seed_int(st.policy, "budget_committed", P09, 200_000_000)
	eq_int(_seed_errors, 0, "夹具写入失败说明 state.policy.budget_committed_uu 没有按 12 分配")
	var cell: int = JWIds.idx_cell(JWUnits.Region.HAIJIA, JWUnits.Sector.MANU)
	for i: int in 4:
		st.policy.pay_subsidy(P09, cell, 150_000_000, 100 + i, 1_000_000_000, st.policy_defs,
				st.treasury, st.ledger, st.accounts, 3)
		le_int(st.policy.budget_spent[P09], st.policy.budget_committed[P09],
				"第 %d 次申领后 budget_spent 仍必须 <= budget_committed（INV-096）" % i)


## INV-095 / docs/30 §4.2 P03 行：法定转移在政策未生效时应付额必须全为 0，
## 且**不得靠少算人数装作没人符合资格**（docs/17 §4.21 transfer_due_into 后置条件）。
func test_u_transfer_due_zero_before_effective() -> void:
	var st: JWSimState = _new_state()
	_seed_all_defs(st)
	eq_int(_seed_errors, 0, "政策定义夹具写入失败说明 content.policy.* 长度不符合 docs/17 §4.8")
	var payee: PackedInt64Array = PackedInt64Array()
	payee.resize(JWUnits.GROUP)
	var due: PackedInt64Array = PackedInt64Array()
	due.resize(JWUnits.GROUP)
	due.fill(-1)
	var rc: int = st.policy.transfer_due_into(payee, due, st.pop, st.labor, st.policy_defs,
			0, st.params)
	eq_int(rc, JWResult.OK, "transfer_due_into 在政策未生效时也必须正常返回（它不是故障路径）")
	var total: int = JWMath.sum(due)
	eq_int(total, 0, "P03 未生效（enabled == 0）时 36 组应付额之和必须精确为 0（INV-095）")
	for g: int in JWUnits.GROUP:
		eq_int(due[g], 0, "第 %d 组的应付额必须被显式写为 0，而不是留着调用方的旧值（INV-095）" % g)


# ══════════════════════════════════════════════════════════════════════════
# 夹具与辅助
# ══════════════════════════════════════════════════════════════════════════

## 建一个已分配、权限齐备、现金与槽位充足的状态根。
##
## 注意 `JWSimState.allocate_all()` 用 `JWLedger.new()` 构造账本，**没有把 JWAccount 传进去**，
## 于是 `post()` 全程 PHASE_VIOLATION。这里显式重建并回填 `_blocks`，
## 让政策的开关成本与补助能够真的过账（已在 open_questions 登记）。
func _new_state() -> JWSimState:
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	st.ledger = JWLedger.new(st.accounts)
	st.ledger.allocate()
	st._blocks[JWSimState.BLK_LEDGER] = st.ledger
	st.politics.seats_total = SEATS_TOTAL
	st.politics.seats_gov = SEATS_GOV_PASS
	st.politics.legal_authority_mask = -1
	st.politics.admin_capacity_ppm = JWUnits.PPM
	st.politics.next_budget_review_q = 3
	st.treasury.credit_limit_domestic = FIXTURE_GOV_CASH_UU
	var stance: PackedInt64Array = PackedInt64Array()
	stance.resize(JWUnits.STANCE_N)
	stance.fill(600_000)
	st.policy.set_bloc_stance_view(stance)
	for r: int in JWUnits.R:
		_seed_int(st.capital, "construction_slots", r, FIXTURE_SLOTS)
	_seed_int(st.accounts, "balance", JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH),
			FIXTURE_GOV_CASH_UU)
	_seed_int(st, "params", JWUnits.Param.POLICY_TOGGLE_COST_UU, P04_TOGGLE_COST_UU)
	_ctx(st, 0)
	return st


## 把状态根摆到 S02 的结算上下文（命令受理就在 S02），并打开预算审查窗口。
##
## `requires_budget_review == 1` 的政策要求 `flow.politics.budget_review_due == 1`
## （docs/12 §2.8，INV-127：q ≡ 3 (mod 4) 时由 S02 置位）。夹具默认把窗口开着，
## 「窗口未到」由 test_u_reject_budget_review_window_closed 单独检验。
func _ctx(st: JWSimState, q: int) -> void:
	st.q = q
	st.phase = JWUnits.Phase.S02
	st.ledger.set_context(q, JWUnits.Phase.S02)
	st.politics.f_budget_review_due = 1
	JWResult.set_step(JWUnits.Phase.S02)


## 把 P04 的契约夹具值（计划书 §10 × 1e9）写进 content.policy.*。
func _seed_p04(st: JWSimState) -> void:
	var d: JWPolicyDef = st.policy_defs
	_seed_int(d, "kind", P04, JWPolicyDef.POLICY_KIND_PROJECT)
	_seed_int(d, "authority_bit", P04, 2)
	_seed_int(d, "min_seats_ppm", P04, 500_000)
	_seed_int(d, "requires_bloc_mask", P04, 1 << JWUnits.Bloc.BUSINESS)
	_seed_int(d, "requires_budget_review", P04, 1)
	_seed_int(d, "cost_one_off_uu", P04, P04_ONE_OFF_UU)
	_seed_int(d, "cost_per_quarter_uu", P04, P04_PER_Q_UU)
	_seed_int(d, "planned_quarters", P04, P04_PLANNED_Q)
	_seed_int(d, "spend_line_uu", P04 * SPEND_LINE_N + 0, P04_LINE_IMPORT_UU)
	_seed_int(d, "spend_line_uu", P04 * SPEND_LINE_N + 1, P04_LINE_MATERIAL_UU)
	_seed_int(d, "spend_line_uu", P04 * SPEND_LINE_N + 2, P04_LINE_CONSTRUCTION_UU)
	_seed_int(d, "opex_per_q_uu", P04, P04_OPEX_UU)
	_seed_int(d, "required_construction_uqs", P04, P04_REQ_CONSTRUCTION_UQS)
	_seed_int(d, "required_equipment_uqs", P04, P04_REQ_EQUIPMENT_UQS)
	_seed_int(d, "lag_enact_to_effect_q", P04, P04_LAG_Q)
	_seed_int(d, "commission_delay_q", P04, P04_COMMISSION_DELAY_Q)
	_seed_int(d, "effect_kind", P04, 0)
	_seed_int(d, "effect_target", P04, JWPolicyDef.TARGET_REGION_GRID_PENDING)
	_seed_int(d, "effect_magnitude", P04, P04_CAPACITY_UQS)
	_seed_int(d, "cooldown_q", P04, P04_COOLDOWN_Q)
	_seed_int(d, "toggle_cost_uu", P04, P04_TOGGLE_COST_UU)
	_seed_int(d, "exit_compensation_ppm", P04, P04_EXIT_COMPENSATION_PPM)
	# 三个玩家参数：region_mask / scale_ppm / funding_source（0 == cash）
	_seed_param(d, P04, 0, 1, 15, 1 << JWUnits.Region.HAIJIA)
	_seed_param(d, P04, 1, 250_000, 2_000_000, JWUnits.PPM)
	_seed_param(d, P04, 2, 0, 2, 0)
	_seed_param(d, P04, 3, 0, 0, 0)
	_seed_int(st.policy, "params_ppm", JWIds.idx_policy_param(P04, 0),
			1 << JWUnits.Region.HAIJIA)
	_seed_int(st.policy, "params_ppm", JWIds.idx_policy_param(P04, 1), JWUnits.PPM)
	_seed_int(st.policy, "pending_params", JWIds.idx_policy_param(P04, 0),
			1 << JWUnits.Region.HAIJIA)
	_seed_int(st.policy, "pending_params", JWIds.idx_policy_param(P04, 1), JWUnits.PPM)
	st.policy.set_region_mask(P04, 1 << JWUnits.Region.HAIJIA)


## P09（设备投资补助）的最小夹具：已生效、有预算、费率 30%。
func _seed_p09(st: JWSimState) -> void:
	var d: JWPolicyDef = st.policy_defs
	_seed_int(d, "kind", P09, JWPolicyDef.POLICY_KIND_SUBSIDY)
	_seed_int(d, "authority_bit", P09, 1)
	_seed_int(d, "min_seats_ppm", P09, 500_000)
	_seed_int(d, "cost_one_off_uu", P09, 2_400_000_000)
	_seed_int(d, "cost_per_quarter_uu", P09, 200_000_000)
	_seed_int(d, "planned_quarters", P09, 12)
	_seed_int(d, "spend_line_uu", P09 * SPEND_LINE_N + 0, 190_000_000)
	_seed_int(d, "spend_line_uu", P09 * SPEND_LINE_N + 1, 10_000_000)
	_seed_int(d, "opex_per_q_uu", P09, 10_000_000)
	_seed_int(d, "lag_enact_to_effect_q", P09, 1)
	_seed_int(d, "commission_delay_q", P09, 1)
	_seed_int(d, "effect_target", P09, JWPolicyDef.TARGET_POLICY_PARAMS_PPM)
	_seed_int(d, "effect_magnitude", P09, 300_000)
	_seed_int(d, "cooldown_q", P09, 4)
	_seed_int(d, "toggle_cost_uu", P09, P04_TOGGLE_COST_UU)
	for j: int in JWIds.POLICY_PARAM_STRIDE:
		_seed_param(d, P09, j, 0, 2_000_000, P09_SUBSIDY_RATE_PPM)
		# 四个槽位写同一个费率：无论实现读的是哪个槽，发放额都等于 mul_ppm(投资, 30%)，
		# 这样断言复算的是**规则**，而不是「实现恰好读了哪个下标」。
		_seed_int(st.policy, "params_ppm", JWIds.idx_policy_param(P09, j),
				P09_SUBSIDY_RATE_PPM)
	st.policy.set_region_mask(P09, JWPolicyEngine.REGION_MASK_ALL)
	_seed_int(st.policy, "enabled", P09, 1)
	_seed_int(st.policy, "enacted_q", P09, 0)
	_seed_int(st.policy, "effective_from_q", P09, 1)
	_seed_int(st.policy, "budget_committed", P09, 2_400_000_000)


## 给 12 项政策都填上最小可判定的定义（只为让 blocked_reason / transfer_due 有 defs 可读）。
func _seed_all_defs(st: JWSimState) -> void:
	var d: JWPolicyDef = st.policy_defs
	for p: int in JWUnits.POLICY_N:
		_seed_int(d, "authority_bit", p, p % 4)
		_seed_int(d, "min_seats_ppm", p, 500_000)
		_seed_int(d, "cost_one_off_uu", p, 1_000_000_000)
		_seed_int(d, "cost_per_quarter_uu", p, 250_000_000)
		_seed_int(d, "planned_quarters", p, 4)
		_seed_int(d, "lag_enact_to_effect_q", p, 1)
		_seed_int(d, "commission_delay_q", p, 1)
		_seed_int(d, "cooldown_q", p, 4)
		_seed_int(d, "toggle_cost_uu", p, P04_TOGGLE_COST_UU)
		for j: int in JWIds.POLICY_PARAM_STRIDE:
			_seed_param(d, p, j, 0, JWUnits.PPM, 0)


func _seed_param(d: JWPolicyDef, p: int, j: int, lo: int, hi: int, dv: int) -> void:
	var idx: int = JWIds.idx_policy_param(p, j)
	_seed_int(d, "param_min_ppm", idx, lo)
	_seed_int(d, "param_max_ppm", idx, hi)
	_seed_int(d, "param_default", idx, dv)


## 以「读出整条数组 → 改一位 → 写回」的方式写夹具，避免依赖属性链的索引赋值语义。
## 越界即计入 _seed_errors，由测试断言它为 0——数组长度不对不能被静默吞掉。
func _seed_int(owner: Object, prop: String, idx: int, value: int) -> void:
	var a: PackedInt64Array = owner.get(prop)
	if idx < 0 or idx >= a.size():
		_seed_errors += 1
		return
	a[idx] = value
	owner.set(prop, a)


## 提交一次 P04 立项命令。
## 末位形参 `params` 是**全局数值参数表 param.\***（长度 JWUnits.PARAM_N），
## 不是玩家参数——玩家参数走 `state.policy.params_*` 与 `pending_params`。
func _enact_p04(st: JWSimState, q: int) -> int:
	_ctx(st, q)
	return st.policy.try_enact(P04, st.policy_defs, st.politics, st.treasury, st.projects,
			st.capital, st.ledger, st.accounts, q, st.params)


## 提交一次 P04 关停命令。
func _repeal_p04(st: JWSimState, q: int) -> int:
	_ctx(st, q)
	return st.policy.try_repeal(P04, st.policy_defs, st.treasury, st.ledger, st.accounts, q)


# ── 内容包读取（不经加载器） ───────────────────────────────────────────────

func _load_all_policy_docs() -> Array:
	var out: Array = []
	for p: int in JWUnits.POLICY_N:
		var d: Dictionary = _load_policy_doc(p)
		if d.is_empty():
			return []
		out.append(d)
	return out


func _load_policy_doc(p: int) -> Dictionary:
	var path: String = "res://content/policies/policy_P%02d.json" % (p + 1)
	if not FileAccess.file_exists(path):
		fail("找不到政策定义文件 %s（V-PD-01：12 个政策文件齐全）" % path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		fail("%s 不是合法的 JSON 对象（E_FILE_FORMAT）" % path)
		return {}
	return parsed as Dictionary


## 合法的测试矩阵 ID 命名空间：docs/30 的 `T-*` 与 docs/31 的 `ADV-*`
## （docs/30 §4.2 的 P05 行直接把 `ADV-03` 当作失败链 ID 使用）。
func _is_test_id(id: String) -> bool:
	return id.begins_with("T-") or id.begins_with("ADV-")


## 某个 cell 主体的现金余额（补助的实发额只能从这里读，不能信返回值）。
func _cell_cash(st: JWSimState, cell: int) -> int:
	return st.accounts.cash_of(JWIds.agent_of_cell(cell))


func _pid(docs: Array, p: int) -> String:
	return String((docs[p] as Dictionary).get("policy_id", "policy.P%02d?" % (p + 1)))


func _sub(d: Dictionary, key: String) -> Dictionary:
	var v: Variant = d.get(key)
	if typeof(v) == TYPE_DICTIONARY:
		return v as Dictionary
	return {}


func _arr(d: Dictionary, key: String) -> Array:
	var v: Variant = d.get(key)
	if typeof(v) == TYPE_ARRAY:
		return v as Array
	return []


## JSON 的数字在 Godot 里解析成双精度；契约里的数都远小于 2^53，转整数是精确的。
## 非数字一律返回 BAD_INT，让断言把问题显示成「不等于期望值」而不是悄悄变成 0。
func _as_int(v: Variant) -> int:
	var t: int = typeof(v)
	if t == TYPE_INT:
		return int(v)
	if t == TYPE_FLOAT:
		return int(v)
	return BAD_INT


func _is_empty_value(v: Variant) -> bool:
	var t: int = typeof(v)
	if t == TYPE_NIL:
		return true
	if t == TYPE_STRING:
		return String(v).strip_edges() == ""
	if t == TYPE_ARRAY:
		return (v as Array).is_empty()
	if t == TYPE_DICTIONARY:
		return (v as Dictionary).is_empty()
	return false
