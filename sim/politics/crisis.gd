## 战役模式的国家延续：政府更替与危机状态机（docs/18 R-REGIME-01、R-CRISIS-01；docs/53 M1-6/M1-7）。
##
## 旧剧本（单届）不启用：选举、不信任、财政重组失败照旧直接终局。
## 战役剧本启用后：
## - 选举按剧本的选举周期举行；落选与连续不信任都只**更替政府**，国家延续。新政府继承全部债务、
##   承诺、在建项目与政策；预算审查计数重开，各组支持度回到基年水平（「新政府的蜜月」），
##   程序信任与未来预期不动（它们属于国家与社会，不属于某一届政府）。
## - 危机状态机四轨（财政 / 供给 / 合法性 / 战争），各自取值 0 无、1 预警、2 危机、3 最后补救窗口。
##   M1 实现财政与合法性两轨；供给与战争两轨在 M3 补齐，届时本表不改形状。
##   只有「最后补救窗口」届满、触发条件仍然成立，才以国家级结局终局（用户决定 U-8：很少终局，多是代价）。
##
## 依赖秩与其他状态块相同。
class_name JWCrisis
extends RefCounted

const TRACK_FISCAL: int = 0
const TRACK_SUPPLY: int = 1
const TRACK_LEGITIMACY: int = 2
const TRACK_WAR: int = 3
const TRACK_N: int = 4

const STAGE_NONE: int = 0
const STAGE_WARNING: int = 1
const STAGE_CRISIS: int = 2
const STAGE_FINAL: int = 3

# ── §1.6 状态块协议 ─────────────────────────────────────────────────────────

const STATE_ARRAY_IDS: PackedStringArray = [
	"state.crisis.stage",
	"state.crisis.since_q",
]
const STATE_ARRAY_SUBSYS: PackedInt64Array = [JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS]
const STATE_SCALAR_IDS: PackedStringArray = [
	"state.politics.gov_changes",
	"state.politics.last_gov_change_q",
	"content.crisis.enabled",
	"content.politics.election_period_q",
	"content.crisis.final_window_q",
	"content.crisis.legit_warn_ppm",
	"content.crisis.legit_crisis_ppm",
	"content.crisis.legit_final_ppm",
]
const STATE_SCALAR_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS,
	JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS,
]
const FLOW_ARRAY_IDS: PackedStringArray = []
const FLOW_ARRAY_SUBSYS: PackedInt64Array = []
const FLOW_SCALAR_IDS: PackedStringArray = []
const FLOW_SCALAR_SUBSYS: PackedInt64Array = []

# ── 状态 ───────────────────────────────────────────────────────────────────

## state.crisis.stage[4] —— 各轨当前级别。写入者 S08
var stage: PackedInt64Array = PackedInt64Array()
## state.crisis.since_q[4] —— 进入当前级别的季（未进入过为 −1）。写入者 S08
var since_q: PackedInt64Array = PackedInt64Array()
## state.politics.gov_changes —— 开局以来的政府更替次数。写入者 S08
var gov_changes: int = 0
## state.politics.last_gov_change_q —— 最近一次更替的季（没有为 −1）。写入者 S08
var last_gov_change_q: int = -1

# ── 内容常量（剧本 politics_init.crisis_rule） ─────────────────────────────

var enabled: int = 0
var election_period_q: int = 0
var final_window_q: int = 0
var legit_warn_ppm: int = 0
var legit_crisis_ppm: int = 0
var legit_final_ppm: int = 0


func allocate() -> void:
	stage = PackedInt64Array()
	stage.resize(TRACK_N)
	stage.fill(STAGE_NONE)
	since_q = PackedInt64Array()
	since_q.resize(TRACK_N)
	since_q.fill(-1)
	gov_changes = 0
	last_gov_change_q = -1


# ── 规则 ───────────────────────────────────────────────────────────────────

## 一条轨道本季的目标级别 → 实际级别：升级即时（可以跳级），降级每季只降一级（恢复慢于恶化）。
## 返回 true 表示最后补救窗口已届满且条件仍在（调用方据此终局）。
func step_track(track: int, target: int, q: int) -> bool:
	var cur: int = stage[track]
	if target > cur:
		stage[track] = target
		since_q[track] = q
	elif target < cur:
		stage[track] = cur - 1
		since_q[track] = q
	return stage[track] == STAGE_FINAL and target == STAGE_FINAL and final_window_q > 0 \
			and q - since_q[track] >= final_window_q


## 财政轨的目标级别（全部取自既有指标；阈值用既有参数，不另立一套）。
## 1 预警：预算审查失败过、或欠付超过审查上限；2 危机：付不出第 1 档、或审查连败到「失去执政资格」；
## 3 最后补救窗口：连续付不出第 1 档达到违约宽限期（旧剧本在这一点直接终局）。
static func fiscal_target(review_fail_streak: int, fail_to_lost: int, arrears_uu: int,
		arrears_limit_uu: int, default_streak_q: int, grace_q: int) -> int:
	if grace_q > 0 and default_streak_q >= grace_q:
		return STAGE_FINAL
	if default_streak_q >= 1 or (fail_to_lost > 0 and review_fail_streak >= fail_to_lost):
		return STAGE_CRISIS
	if review_fail_streak >= 1 or arrears_uu > arrears_limit_uu:
		return STAGE_WARNING
	return STAGE_NONE


## 合法性轨的目标级别：全国程序信任（选民口径加权）低于三档门槛。
func legitimacy_target(trust_national_ppm: int) -> int:
	if trust_national_ppm < legit_final_ppm:
		return STAGE_FINAL
	if trust_national_ppm < legit_crisis_ppm:
		return STAGE_CRISIS
	if trust_national_ppm < legit_warn_ppm:
		return STAGE_WARNING
	return STAGE_NONE


func note_gov_change(q: int) -> void:
	gov_changes += 1
	last_gov_change_q = q


# ── §1.6 状态块协议 ─────────────────────────────────────────────────────────

func state_array(i: int) -> PackedInt64Array:
	if i == 0:
		return stage
	if i == 1:
		return since_q
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


func set_state_array(i: int, v: PackedInt64Array) -> int:
	if v.size() != TRACK_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(), TRACK_N)
	if i == 0:
		stage = v.duplicate()
	elif i == 1:
		since_q = v.duplicate()
	else:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return JWResult.OK


func state_scalar(i: int) -> int:
	match i:
		0: return gov_changes
		1: return last_gov_change_q
		2: return enabled
		3: return election_period_q
		4: return final_window_q
		5: return legit_warn_ppm
		6: return legit_crisis_ppm
		7: return legit_final_ppm
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


func set_state_scalar(i: int, v: int) -> int:
	match i:
		0: gov_changes = v
		1: last_gov_change_q = v
		2: enabled = v
		3: election_period_q = v
		4: final_window_q = v
		5: legit_warn_ppm = v
		6: legit_crisis_ppm = v
		7: legit_final_ppm = v
		_:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return JWResult.OK


func flow_array(i: int) -> PackedInt64Array:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, 0)
	return PackedInt64Array()


func flow_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, 0)
	return 0


func reset_flows() -> void:
	pass


func flow_abs_sum() -> int:
	return 0
