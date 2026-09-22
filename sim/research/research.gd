## 研究与科技（docs/18 R-RESEARCH-01；docs/53 M2-1）。
##
## 三条纪律：
## ① **科技只解锁资格**：完成一项科技不改任何数值，只让某些建筑类型与生产方式变得可建、可改造（M2-2 起使用）。
##    经济后果全部来自玩家随后真的去建、去改造，以及由此改变的投入产出——不是科技本身发钱发产能。
## ② 研究点由已经发生的事实产生：本季实际交付的教育服务量、在业高技能人数。没有教育与人力，就没有研究。
## ③ 只有一个研究方向（focus）。没有方向时研究点照常累积进池子，不浪费也不加速。
##
## 战役剧本才启用（剧本 `research_rule`）；旧剧本 tech_count == 0、enabled == 0，本块恒为空转。
class_name JWResearch
extends RefCounted

# ── §1.6 状态块协议 ─────────────────────────────────────────────────────────

const STATE_ARRAY_IDS: PackedStringArray = [
	"state.research.status",
	"state.research.progress",
	"content.tech.cost",
	"content.tech.era_hint",
	"content.tech.prereq_mask",
	"content.tech.unlock_building_mask",
	"content.tech.unlock_method_mask",
	"content.tech.requires_building_mask",
]
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV,
	JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV,
]
const STATE_SCALAR_IDS: PackedStringArray = [
	"state.research.points_pool",
	"state.research.focus",
	"state.research.completed_mask",
	"content.tech.count",
	"content.research.enabled",
	"content.research.points_per_edu_ppm",
	"content.research.points_per_high_skill_ppm",
]
const STATE_SCALAR_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV,
	JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV,
]
const FLOW_SCALAR_IDS: PackedStringArray = ["flow.research.points_gained"]
const FLOW_SCALAR_SUBSYS: PackedInt64Array = [JWUnits.SUBSYS_GOV]
const FLOW_ARRAY_IDS: PackedStringArray = []
const FLOW_ARRAY_SUBSYS: PackedInt64Array = []

## 科技表容量（M3 的六个时代共 48 项，留余量；前置掩码是 int64 位图，上限 63）。
const CAP0: int = 64

## 科技状态：0 未解锁（前置未完成）、1 可研究、2 已完成。
const ST_LOCKED: int = 0
const ST_AVAILABLE: int = 1
const ST_DONE: int = 2

## 没有研究方向。
const NO_FOCUS: int = -1

# ── 状态 ───────────────────────────────────────────────────────────────────

## state.research.status[] —— 每项科技的状态。写入者 S07
var status: PackedInt64Array = PackedInt64Array()
## state.research.progress[] —— 每项科技已投入的研究点。写入者 S07
var progress: PackedInt64Array = PackedInt64Array()
## state.research.points_pool —— 尚未投入任何方向的研究点。写入者 S07
var points_pool: int = 0
## state.research.focus —— 当前研究方向（科技下标），NO_FOCUS 表示没有。写入者 S02（命令 13）
var focus: int = NO_FOCUS
## state.research.completed_mask —— 已完成科技的位图（第 i 位 == 科技 i）。写入者 S07
var completed_mask: int = 0

# ── 内容常量（content/technologies/*.json 与剧本 research_rule） ───────────

var tech_count: int = 0
var enabled: int = 0
var points_per_edu_ppm: int = 0
var points_per_high_skill_ppm: int = 0
var cost: PackedInt64Array = PackedInt64Array()
var era_hint: PackedInt64Array = PackedInt64Array()
var prereq_mask: PackedInt64Array = PackedInt64Array()
var unlock_building_mask: PackedInt64Array = PackedInt64Array()
var unlock_method_mask: PackedInt64Array = PackedInt64Array()
var requires_building_mask: PackedInt64Array = PackedInt64Array()

# ── 流量 ───────────────────────────────────────────────────────────────────

## flow.research.points_gained —— 本季新增研究点。写入者 S07
var f_points_gained: int = 0


func allocate() -> void:
	status = _zeros(CAP0)
	progress = _zeros(CAP0)
	cost = _zeros(CAP0)
	era_hint = _zeros(CAP0)
	prereq_mask = _zeros(CAP0)
	unlock_building_mask = _zeros(CAP0)
	unlock_method_mask = _zeros(CAP0)
	requires_building_mask = _zeros(CAP0)
	points_pool = 0
	focus = NO_FOCUS
	completed_mask = 0
	tech_count = 0
	enabled = 0
	points_per_edu_ppm = 0
	points_per_high_skill_ppm = 0
	f_points_gained = 0


static func _zeros(n: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(n)
	a.fill(0)
	return a


# ── 规则 ───────────────────────────────────────────────────────────────────

## 本季研究点：教育交付量 × 系数 + 在业高技能人数 × 系数。
## 步骤：S07
## 前置：edu_delivered_uqs 是本季实际交付的教育服务量；high_skill_employed 是在业高技能人数
## 后置：不改状态（纯函数）
func points_of(edu_delivered_uqs: int, high_skill_employed: int) -> int:
	if enabled == 0:
		return 0
	# rounding: floor, reason=两项各取整一次，少给优于多给
	var a: int = JWMath.mul_ppm(maxi(0, edu_delivered_uqs), points_per_edu_ppm)
	var b: int = JWMath.mul_ppm(maxi(0, high_skill_employed), points_per_high_skill_ppm)
	return a + b


## 某项科技是否可研究（前置全部完成且自己未完成）。
func is_available(t: int) -> bool:
	if t < 0 or t >= tech_count:
		return false
	if (completed_mask >> t) & 1 == 1:
		return false
	return prereq_mask[t] & ~completed_mask == 0


## S02：设定研究方向（命令 13）。返回 JWResult.OK 或 Reject 码。
func set_focus(t: int) -> int:
	if enabled == 0 or tech_count == 0:
		return JWResult.Reject.PRECONDITION
	if t == NO_FOCUS:
		focus = NO_FOCUS
		return JWResult.OK
	if t < 0 or t >= tech_count:
		return JWResult.Reject.NOT_FOUND
	if not is_available(t):
		return JWResult.Reject.PRECONDITION
	focus = t
	return JWResult.OK


## S07：本季研究推进。新增点先进池子；有方向时池子整体投入该方向；
## 达到成本即完成（余数留在池子里，不浪费），并把后继科技从「未解锁」改为「可研究」。
## 步骤：S07
## 前置：points >= 0
## 后置：progress / status / completed_mask / points_pool / focus 按规则更新
## 不变量：R-RESEARCH-01（完成科技不改任何数值，只改状态与解锁位）
func advance_research(points: int) -> int:
	if enabled == 0 or tech_count == 0:
		f_points_gained = 0
		return JWResult.OK
	if points < 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, points, 0)
	f_points_gained = points
	points_pool = JWMath.check_amount(points_pool + points)
	if focus != NO_FOCUS:
		if not is_available(focus):
			# 前置被别的路径改动（读档、迁移）后方向可能失效：清掉方向，点数留在池子里。
			focus = NO_FOCUS
		else:
			progress[focus] = progress[focus] + points_pool
			points_pool = 0
			if progress[focus] >= cost[focus]:
				points_pool = progress[focus] - cost[focus]
				progress[focus] = cost[focus]
				status[focus] = ST_DONE
				completed_mask = completed_mask | (1 << focus)
				focus = NO_FOCUS
	_refresh_status()
	return JWResult.OK


## 按 completed_mask 刷新各项状态（已完成保持完成；前置齐备的变成可研究）。
func _refresh_status() -> void:
	for t: int in tech_count:
		if (completed_mask >> t) & 1 == 1:
			status[t] = ST_DONE
		elif prereq_mask[t] & ~completed_mask == 0:
			status[t] = ST_AVAILABLE
		else:
			status[t] = ST_LOCKED


## 已解锁的建筑类型位图（M2-2 起由建筑模块查询）。
func unlocked_building_mask() -> int:
	var m: int = 0
	for t: int in tech_count:
		if (completed_mask >> t) & 1 == 1:
			m = m | unlock_building_mask[t]
	return m


## 已解锁的生产方式位图（M2-2 起由建筑模块查询）。
func unlocked_method_mask() -> int:
	var m: int = 0
	for t: int in tech_count:
		if (completed_mask >> t) & 1 == 1:
			m = m | unlock_method_mask[t]
	return m


# ── §1.6 状态块协议 ─────────────────────────────────────────────────────────

func state_array(i: int) -> PackedInt64Array:
	match i:
		0: return status
		1: return progress
		2: return cost
		3: return era_hint
		4: return prereq_mask
		5: return unlock_building_mask
		6: return unlock_method_mask
		7: return requires_building_mask
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	if v.size() != CAP0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(), CAP0)
	var d: PackedInt64Array = v.duplicate()
	match i:
		0: status = d
		1: progress = d
		2: cost = d
		3: era_hint = d
		4: prereq_mask = d
		5: unlock_building_mask = d
		6: unlock_method_mask = d
		7: requires_building_mask = d
	return JWResult.OK


func state_scalar(i: int) -> int:
	match i:
		0: return points_pool
		1: return focus
		2: return completed_mask
		3: return tech_count
		4: return enabled
		5: return points_per_edu_ppm
		6: return points_per_high_skill_ppm
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


func set_state_scalar(i: int, v: int) -> int:
	match i:
		0: points_pool = v
		1: focus = v
		2: completed_mask = v
		3: tech_count = v
		4: enabled = v
		5: points_per_edu_ppm = v
		6: points_per_high_skill_ppm = v
		_:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return JWResult.OK


func flow_array(i: int) -> PackedInt64Array:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, 0)
	return PackedInt64Array()


func flow_scalar(i: int) -> int:
	if i == 0:
		return f_points_gained
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
	return 0


func set_flow_scalar(i: int, v: int) -> int:
	if i != 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
	f_points_gained = v
	return JWResult.OK


func reset_flows() -> void:
	f_points_gained = 0


func flow_abs_sum() -> int:
	return JWMath.absi(f_points_gained)
