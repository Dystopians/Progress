## 就业匹配、技能错配、失业统计、工资支付。
##
## employment_persons 的唯一持有者（cell 侧与 pubserv 侧），群组侧由 JWPopulation 保存同一事实的
## 另一个索引视图，两者逐（地区，技能）精确相等（INV-077，故意冗余，交叉校验）。
##
## 骨架依据：docs/17_api_skeleton.md §4.15；公式依据：docs/12 §3.2/§3.3/§3.4、§4.1/§4.2、§7.5/§7.7。
class_name JWLaborMarket
extends RefCounted

## 本块各数组所属子系统（与 STATE_ARRAY_IDS 等长）：cell_* 归 SUBSYS_CELL、pub_* 归 SUBSYS_PUBSERV。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_PUBSERV, JWUnits.SUBSYS_PUBSERV,
]

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
const STATE_ARRAY_IDS: PackedStringArray = [
	"state.cell.employment_persons",
	"state.pubserv.employment_persons",
	# R-PUBSTAFF-01：公共部门编制（在岗人数的补员上限），开局 == 剧本在岗人数。
	"state.pubserv.establishment_persons",
]

const STATE_SCALAR_IDS: PackedStringArray = []

const FLOW_ARRAY_IDS: PackedStringArray = [
	"flow.cell.hires_persons",
	"flow.cell.separations_persons",
	"flow.cell.wage_bill_uu",
	"flow.pubserv.wage_bill_uu",
]

const FLOW_SCALAR_IDS: PackedStringArray = []

# ── log.clamp 的字段码（本模块段：3000..3099） ────────────────────────────────
#
# 全项目尚无统一的 field_code 注册表（见本模块交付说明的 open_questions）。
# 这四个码只在本文件产生，取 3000 段以避免与价格（S07）与主观量（S08）的段冲突。

## 招工／裁员的摩擦夹逼（docs/12 §3.2 (b)）
const LOG_FIELD_HIRE_DELTA: int = 3001
## 地区同技能劳动力池的配给（docs/12 §3.2 (c)，闸一）
const LOG_FIELD_HIRE_POOL: int = 3002
## 工资资金闸把在岗人数压到 affordable_k（docs/12 §3.2 (d)，闸二）
const LOG_FIELD_HIRE_CASH: int = 3003
## 上游给出的负计划产量被截到 0（防御性，正常不应发生）
const LOG_FIELD_PLAN_NEGATIVE: int = 3004

## 账本 cause 码：本模块的过账全部来自结算规则本身，不来自政策／项目／事件／冲击。
## 全项目尚无 cause 码注册表，0 即「规则」（docs/10 §2.5 的来源操作码，待建表）。
const CAUSE_RULE: int = 0

## 非实物过账的 product 占位（docs/17 §4.10：无实物腿时 product 为 -1、qty 为 0）。
const NO_PRODUCT: int = -1

# ── 状态（S 类，进 state_hash） ────────────────────────────────────────────────

## state.cell.employment_persons[]，48（CELL × K），人。
## 写入者 S03（主要写入点）与 S07（仅流出配对，只允许出现在 release_for_outflow 内）。
var cell_employment: PackedInt64Array = PackedInt64Array()
## state.pubserv.employment_persons[]，12（PUBSERV × K），人。写入者 S03, S07。
var pub_employment: PackedInt64Array = PackedInt64Array()
## state.pubserv.establishment_persons[]，12（PUBSERV × K），人。R-PUBSTAFF-01：公共部门编制。
## 自然减员（死亡、退休、迁出，见 release_for_outflow）之后，S03 从本地区同技能的可用劳动力中
## 补员到编制为止（受同一招聘摩擦约束），优先于企业招聘——公共服务的在岗人数不再只减不增。
var pub_establishment: PackedInt64Array = PackedInt64Array()

# ── 流量（F 类，每季 S01 清零） ───────────────────────────────────────────────

## flow.cell.hires_persons[]，48，人。写入者 S03。
var f_hires: PackedInt64Array = PackedInt64Array()
## flow.cell.separations_persons[]，48，人。写入者 S03, S07。
var f_separations: PackedInt64Array = PackedInt64Array()
## flow.cell.wage_bill_uu[]，16，μU。写入者 S04。
var f_wage_bill: PackedInt64Array = PackedInt64Array()
## flow.pubserv.wage_bill_uu[]，4，μU。写入者 S04。
var f_pub_wage_bill: PackedInt64Array = PackedInt64Array()

# ── 派生与内部快照（不进 state_hash） ─────────────────────────────────────────

## derived.labor.unemployment_ppm，ppm。写入者 S03（反算，不是参数）。
var _unemployment_ppm: int = 0
## R-FIRMCASH-01 第 3 条（战役模式）：招聘上限按需求而不是只按现有人数计。编排器每季 S03 前写入，
## 不进状态（由 state.meta.mode 决定，逐季重算）。旧剧本为 false，行为逐位不变。
var hire_by_need: bool = false
## 空缺岗位数，人（S07 工资调整用）。写入者 S03。
var _vacancies_persons: int = 0
## 48，S03 入口快照（摩擦上限与 hires/separations 的基线）。
var _prev_employment: PackedInt64Array = PackedInt64Array()

# ── 预分配 scratch（docs/17 §1.4：热路径不新建对象） ──────────────────────────

## 48，本季目标在岗（§3.2 (a) 的 need_k）
var _need: PackedInt64Array = PackedInt64Array()
## 48，摩擦夹逼后的目标在岗（prev + clamp(need − prev, −max_fire, +max_hire)）
var _target: PackedInt64Array = PackedInt64Array()
## 48，闸一分得的净增员额（alloc_k）
var _alloc: PackedInt64Array = PackedInt64Array()
## 4，闸一按 cell 下标升序的权重／决胜键／输出
var _w_cell: PackedInt64Array = PackedInt64Array()
## R-LABOR-SHRINK-01：劳动力缩减时的强制离职缓冲（长 S+1：四个 cell + pubserv）与逐 cell 档的离职额。
var _w_force: PackedInt64Array = PackedInt64Array()
var _tb_force: PackedInt64Array = PackedInt64Array()
var _out_force: PackedInt64Array = PackedInt64Array()
var _forced_cut: PackedInt64Array = PackedInt64Array()
var _tb_cell: PackedInt64Array = PackedInt64Array()
var _out_cell: PackedInt64Array = PackedInt64Array()
## 3，闸二按技能档的权重／决胜键／输出
var _w_skill: PackedInt64Array = PackedInt64Array()
var _tb_skill: PackedInt64Array = PackedInt64Array()
var _out_skill: PackedInt64Array = PackedInt64Array()
## 5，§7.7 按就业槽位（4 部门 + pubserv）的权重／决胜键／输出
var _w_slot: PackedInt64Array = PackedInt64Array()
var _tb_slot: PackedInt64Array = PackedInt64Array()
var _out_slot: PackedInt64Array = PackedInt64Array()
## 36，本季公共部门应付工资（按群组下标），供 record_public_wage_paid 核对「实付不超应付」
var _pub_due_by_group: PackedInt64Array = PackedInt64Array()
## 12，清单行号 → 群组下标（record_public_wage_paid 接受行序数组时用）
var _pub_row_group: PackedInt64Array = PackedInt64Array()
## 本季公共工资清单行数
var _pub_row_count: int = 0
## 全国劳动力合计（compute_unemployment 缓存，供 unemployed_persons() 无参访问）
var _labor_force_total: int = 0
## 全国失业人数（compute_unemployment 缓存）
var _unemployed_total: int = 0


## S03 §3.2：招工与裁员（两道硬闸 + 摩擦）。employment 的第一个也是主要的写入点。
## 步骤：S03 §3.2
## 前置：output_plan 已由 JWSectorModel 算出；本季价格与工资率已固定
## 后置：employment_k <= min(need_k, prev + alloc_k, affordable_k)；
##       同步回写 JWPopulation.employed；hires/separations 写入
## 不变量：INV-076（Σ employed <= Σ labor_force）、INV-077（两侧口径相等）、
##          INV-078（不允许技能替代）、INV-079（工资有资金来源，首版不允许欠薪）、INV-003
## 失败：Σ employed > pool → Fault.EMPLOYMENT_OVERFLOW；
##       现金不足 → 缩减到 affordable_k 并写 log.clamp（业务性短缺，不是故障）
##
## 与契约的两处关系说明（实现者必读）：
## 1. §3.2 (d) 的 `employment_k = min(need_k, employment_k + alloc_k, affordable_k)` 里的 `need_k`
##    取的是 (b) 摩擦夹逼后的目标 `target_k = prev_k + delta_k`。若字面取未夹逼的 need_k，
##    则 (b) 的 `max_fire_k` 在任何输入下都不会生效（结果恒 <= need_k），整条裁员摩擦成为死代码。
##    本实现取 target_k，使 (b) 与 (d) 同时有效；三个上限仍是 min，闸二（资金）仍然最高优先。
## 2. 技能之间不做任何替代（INV-078）：need/alloc/affordable 全部逐档独立，
##    某档人不够只压低该档在岗人数，不允许用别的档顶上。
func hire_and_fire(output_plan_uqs: PackedInt64Array, io: JWIoTable, pricing: JWPricing,
		pop: JWPopulation, accounts: JWAccount, params: PackedInt64Array) -> int:
	if io == null or pricing == null or pop == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, 0)
	if cell_employment.size() != JWUnits.EMP_N or pub_employment.size() != JWUnits.PUBSERV_EMP_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				cell_employment.size(), JWUnits.EMP_N)
	if output_plan_uqs.size() != JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				output_plan_uqs.size(), JWUnits.CELL)
	if params.size() < JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	if pop.employed.size() != JWUnits.GROUP_EMP_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				pop.employed.size(), JWUnits.GROUP_EMP_N)
	if f_hires.size() != JWUnits.EMP_N or f_separations.size() != JWUnits.EMP_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				f_hires.size(), JWUnits.EMP_N)
	_ensure_scratch()

	var hiring_friction_ppm: int = params[JWUnits.Param.HIRING_FRICTION_PPM]
	var firing_friction_ppm: int = params[JWUnits.Param.FIRING_FRICTION_PPM]
	var wage_cash_share_ppm: int = params[JWUnits.Param.WAGE_CASH_SHARE_PPM]

	# ── 入口快照：摩擦上限与 hires/separations 的基线都用它，本季后续写入不得改变它 ──
	var e: int = 0
	while e < JWUnits.EMP_N:
		_prev_employment[e] = cell_employment[e]
		_alloc[e] = 0
		e += 1

	# ── (a) 目标在岗 need_k 与 (b) 摩擦上限 ───────────────────────────────────
	var cell: int = 0
	while cell < JWUnits.CELL:
		var plan_uqs: int = output_plan_uqs[cell]
		if plan_uqs < 0:
			# 上游缺陷的防御性处理：负计划产量不可能有意义的用工需求。
			# 显式截到 0 并登记，不静默吞掉。
			pricing.log_clamp(LOG_FIELD_PLAN_NEGATIVE, plan_uqs, 0, 0)
			plan_uqs = 0
		var k: int = 0
		while k < JWUnits.K:
			var idx: int = JWIds.idx_emp(cell, k)
			var coeff: int = io.labor_of(cell, k)
			var need_k: int = 0
			if coeff > 0:
				# rounding: ceil, reason=不得少算用工（docs/12 §3.2 (a)）
				# 单位：μQ_s × (人/Q_s) / 1e6(μQ_s/Q_s) = 人
				need_k = JWMath.ceil_div(JWMath.mul(plan_uqs, coeff), JWUnits.PPM)
			_need[idx] = need_k
			var prev_k: int = _prev_employment[idx]
			# 旧口径「上季人数 × 摩擦 + 1」在单元雇员归零后变成吸收态：每季只能多招 1 人，
			# 回到百万级要 145 季。战役模式改按需求与现有人数的较大者计。
			var hire_base_k: int = maxi(prev_k, need_k) if hire_by_need else prev_k
			var max_hire_k: int = JWMath.mul_ppm(hire_base_k, hiring_friction_ppm) + 1
			var max_fire_k: int = JWMath.mul_ppm(prev_k, firing_friction_ppm)
			var raw_delta: int = need_k - prev_k
			var delta_k: int = JWMath.clamp_i(raw_delta, -max_fire_k, max_hire_k)
			if delta_k != raw_delta:
				var bound: int = max_hire_k
				if raw_delta < 0:
					bound = -max_fire_k
				pricing.log_clamp(LOG_FIELD_HIRE_DELTA, raw_delta, delta_k, bound)
			_target[idx] = prev_k + delta_k
			k += 1
		cell += 1

	# ── (c) 闸一：地区同技能可用劳动力（INV-076） ─────────────────────────────
	# 同地区的 4 个 cell 与 pubserv 竞争同一个池子。pubserv 的本季净增员额恒为 0
	# （docs/12 §3 未给出 S03 改变公共部门编制的公式，见交付说明的 open_questions），
	# 其存量已经在 pool 的被减数里，因此不参与拆分也不会被别人挤掉。
	if _forced_cut.size() != JWUnits.EMP_N:
		_forced_cut.resize(JWUnits.EMP_N)
	_forced_cut.fill(0)
	var r: int = 0
	while r < JWUnits.R:
		var k2: int = 0
		while k2 < JWUnits.K:
			# R-LABOR-SHRINK-01：劳动年龄人口因死亡、老龄化缩减到在岗人数以下时，超出的在岗者离职
			# （按各 cell 与 pubserv 的现有人数最大余数法分摊，决胜键为 cell 下标、pubserv 最后）。
			# 此前没有这一步，长局里会在 INV-076 终检处触发 EMPLOYMENT_OVERFLOW（1600 季空跑第 548 季实测）。
			var over: int = _employed_region_skill(r, k2) - pop.labor_force_region_skill(r, k2)
			if over > 0:
				var rc_o: int = _separate_excess(r, k2, over)
				if rc_o != JWResult.OK:
					return rc_o
			var pool: int = pop.labor_force_region_skill(r, k2) - _employed_region_skill(r, k2)
			if pool < 0:
				# 入口就已超编（剧本或上一季的缺陷）。这里不倒扣既有在岗人数，
				# 留给本函数末尾的 INV-076 终检判 EMPLOYMENT_OVERFLOW。
				pool = 0
			# R-PUBSTAFF-01：公共部门补员到编制（受招聘摩擦约束），优先于企业。
			if pub_establishment.size() == JWUnits.PUBSERV_EMP_N:
				var pi: int = JWIds.idx_pubserv_emp(r, k2)
				var cur_p: int = pub_employment[pi]
				var want_p: int = pub_establishment[pi] - cur_p
				if want_p > 0 and pool > 0:
					want_p = mini(want_p, JWMath.mul_ppm(cur_p, hiring_friction_ppm) + 1)
					var hire_p: int = mini(want_p, pool)
					pub_employment[pi] = cur_p + hire_p
					pool -= hire_p
			var sum_pos: int = 0
			var s: int = 0
			while s < JWUnits.S:
				var idx2: int = JWIds.idx_emp(JWIds.idx_cell(r, s), k2)
				var pos: int = _target[idx2] - _prev_employment[idx2]
				if pos < 0:
					pos = 0
				_w_cell[s] = pos
				_tb_cell[s] = JWIds.idx_cell(r, s)
				sum_pos += pos
				s += 1
			var grant: int = mini(pool, sum_pos)
			# grant == sum_pos 时最大余数法逐项还原为权重本身（拆分是恒等的）；
			# grant < sum_pos 时按 cell 下标升序配给，禁止随机分配（docs/12 §3.2 (c)）。
			JWMath.split_lr_into(grant, _w_cell, _tb_cell, _out_cell)
			if JWMath._split_last_fault != 0:
				return JWMath._split_last_fault
			var s2: int = 0
			while s2 < JWUnits.S:
				_alloc[JWIds.idx_emp(JWIds.idx_cell(r, s2), k2)] = _out_cell[s2]
				s2 += 1
			if grant < sum_pos:
				pricing.log_clamp(LOG_FIELD_HIRE_POOL, sum_pos, grant, pool)
			k2 += 1
		r += 1

	# ── (d) 闸二：工资有资金来源（INV-079，首版不允许欠薪） ───────────────────
	#
	# 契约式（docs/12 §3.2 (d)）：
	#     budget_k     = split_largest_remainder(cash_for_wages, need_j × wage_j, 档下标)[k]
	#     affordable_k = idiv_floor(budget_k, wage_rate_k)
	# **不能直接调 split_lr_into 实现它**：该函数内部执行的乘法是 `mul(total, w_i)`，
	# 此处 total 是现金（μU，上界 AMOUNT_MAX = 4e15）、w_i 是工资总额（μU，1e8…1e17 量级），
	# 两个 μU 量相乘在新刻度下真的溢出 int64（裁定 R-SCALE-01 连带要求 1），
	# 于是整道资金闸在任何现实现金额上都会返回 INT_OVERFLOW（ADV-J01 把这一条钉死了）。
	# pay_wages() 的文档注释里已经就同一处陷阱做过同样的判断。
	#
	# 改为直接算 affordable_k，公式取的仍然是契约式本身，只是把中间的 μU 预算约掉：
	#     affordable_k = floor( floor(cash × need_k × wage_k / W) / wage_k )
	#                  = floor( cash × need_k × wage_k / (W × wage_k) )      （嵌套取整定理）
	#                  = floor( cash × need_k / W )，  W = Σ_j need_j × wage_j
	# 即 mul_div_floor(cash_for_wages, need_k, W) —— 先乘后除的唯一合法入口，中间量降到
	# 「现金 × 人数」量级。这是恒等变形，不是近似：wage_k 在分子分母里精确抵消。
	#
	# 与契约式唯一的差别是最大余数法的 μU 碎屑（整格 cell 合计 ≤ K−1 = 2 μU，
	# 这里只算配给上限、不过任何账，故不涉及 INV-003）。碎屑只会让 affordable_k **偏小**，
	# 即只可能少雇、不可能多雇，方向落在 INV-079「不允许欠薪」的安全一侧。
	# 要完全复原碎屑需要 (cash × w_k) mod W 的精确值，即 JWMath 侧的 128 位中间量，
	# 已登记为接口请求，不在本文件内另造一套拆分。
	var cell2: int = 0
	while cell2 < JWUnits.CELL:
		var cash_uu: int = accounts.cash_of(JWIds.agent_of_cell(cell2))
		if cash_uu < 0:
			cash_uu = 0
		var cash_for_wages: int = JWMath.mul_ppm(cash_uu, wage_cash_share_ppm)
		# W：本 cell 三档的期望工资支出合计（人 × μU/人/季 = μU）。
		# _w_skill / _tb_skill 仍按契约式的「权重 + 决胜键」填好：口径不变，
		# 一旦 JWMath 侧补上不溢出的拆分入口，这里换回 split_lr_into 即可，不必再改口径。
		var need_cost_total: int = 0
		var k3: int = 0
		while k3 < JWUnits.K:
			var w_k: int = JWMath.mul(_need[JWIds.idx_emp(cell2, k3)], pricing.wage_of(k3))
			_w_skill[k3] = w_k
			_tb_skill[k3] = k3
			need_cost_total += w_k
			k3 += 1
		var k4: int = 0
		while k4 < JWUnits.K:
			var idx3: int = JWIds.idx_emp(cell2, k4)
			var prev2: int = _prev_employment[idx3]
			var wage_rate_k: int = pricing.wage_of(k4)
			var affordable_k: int = _need[idx3]
			if wage_rate_k > 0:
				# W == 0（全档 need 为 0）与该档 need 为 0 时预算皆为 0 —— 不是故障，
				# 与 split_lr_into 在权重全 0 时「原额交回、out 全 0」的结果逐位一致。
				affordable_k = 0
				if need_cost_total > 0:
					# rounding: floor, reason=宁可少雇也不欠薪（docs/12 §3.2 (d)）
					affordable_k = JWMath.mul_div_floor(cash_for_wages, _need[idx3],
							need_cost_total)
			# wage_rate_k <= 0 属于内容错误（载入期校验工资落在 [wage_floor_uu, wage_ceil_uu]，
			# 下界为正）。这里不除零、不伪造预算，退化为「工资闸不起作用」。
			var want_k: int = mini(_target[idx3], prev2 + _alloc[idx3])
			var emp_k: int = mini(want_k, affordable_k)
			if emp_k < 0:
				emp_k = 0
			if affordable_k < want_k:
				pricing.log_clamp(LOG_FIELD_HIRE_CASH, want_k, emp_k, affordable_k)
			cell_employment[idx3] = emp_k
			f_hires[idx3] = maxi(0, emp_k - prev2)
			f_separations[idx3] = maxi(0, prev2 - emp_k) + _forced_cut[idx3]
			k4 += 1
		cell2 += 1

	# ── 回写群组侧（INV-077：同一事实的另一个索引视图） ───────────────────────
	# 群组已含地区与技能，因此 (r, working, k) 与 cell/pubserv 侧是一一对应，不需要再拆分。
	var r2: int = 0
	while r2 < JWUnits.R:
		var k5: int = 0
		while k5 < JWUnits.K:
			var g: int = JWIds.idx_group(r2, JWUnits.Age.WORKING, k5)
			var s3: int = 0
			while s3 < JWUnits.S:
				pop.employed[JWIds.idx_group_emp(g, s3)] = \
						cell_employment[JWIds.idx_emp(JWIds.idx_cell(r2, s3), k5)]
				s3 += 1
			pop.employed[JWIds.idx_group_emp(g, JWUnits.S)] = \
					pub_employment[JWIds.idx_pubserv_emp(r2, k5)]
			k5 += 1
		r2 += 1

	# ── 步末 INV-076：逐地区逐技能 Σ employed <= Σ labor_force ────────────────
	var r3: int = 0
	while r3 < JWUnits.R:
		var k6: int = 0
		while k6 < JWUnits.K:
			var employed_rk: int = _employed_region_skill(r3, k6)
			var force_rk: int = pop.labor_force_region_skill(r3, k6)
			if employed_rk > force_rk:
				return JWResult.raise_fault(JWResult.Fault.EMPLOYMENT_OVERFLOW,
						JWIds.idx_pubserv_emp(r3, k6), employed_rk - force_rk)
			k6 += 1
		r3 += 1
	return JWResult.OK


## R-LABOR-SHRINK-01：从 (r, k) 的在岗者中移出 over 人（cell 与 pubserv 按现有人数分摊）。
func _separate_excess(r: int, k: int, over: int) -> int:
	var n: int = JWUnits.S + 1
	if _w_force.size() != n:
		_w_force.resize(n)
		_tb_force.resize(n)
		_out_force.resize(n)
	for s: int in JWUnits.S:
		_w_force[s] = cell_employment[JWIds.idx_emp(JWIds.idx_cell(r, s), k)]
		_tb_force[s] = s
	var pi: int = JWIds.idx_pubserv_emp(r, k)
	_w_force[JWUnits.S] = pub_employment[pi]
	_tb_force[JWUnits.S] = JWUnits.S
	JWMath.split_lr_into(over, _w_force, _tb_force, _out_force)
	if JWMath._split_last_fault != 0:
		return JWMath._split_last_fault
	for s2: int in JWUnits.S:
		var idx: int = JWIds.idx_emp(JWIds.idx_cell(r, s2), k)
		var cut: int = mini(_out_force[s2], cell_employment[idx])
		cell_employment[idx] -= cut
		_prev_employment[idx] -= cut
		_forced_cut[idx] += cut
	pub_employment[pi] -= mini(_out_force[JWUnits.S], pub_employment[pi])
	return JWResult.OK


## S03 §3.4：失业率（反算，不是参数）。
## 步骤：S03 §3.4
## 前置：hire_and_fire 已完成
## 后置：_unemployment_ppm = floor(unemployed × 1e6 / max(labor_force, 1))；q=0 时必须落在 [79500, 80500]
## 不变量：INV-075（分母是劳动力）、INV-143（剧本 schema 中不存在失业率输入字段）
## 失败：unemployed < 0 → Fault.EMPLOYMENT_OVERFLOW
func compute_unemployment(pop: JWPopulation) -> int:
	if pop == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, 0)
	if cell_employment.size() != JWUnits.EMP_N or pub_employment.size() != JWUnits.PUBSERV_EMP_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				cell_employment.size(), JWUnits.EMP_N)
	_ensure_scratch()

	var labor_force_total: int = 0
	var g: int = 0
	while g < JWUnits.GROUP:
		labor_force_total += pop.labor_force(g)
		g += 1
	# 就业口径取本类持有的权威两份（cell 侧 + pubserv 侧）；它与群组侧的一致性
	# 由 check_employment_views() 单独交叉校验（INV-077），不在这里互相担保。
	var employed_total: int = JWMath.sum(cell_employment) + JWMath.sum(pub_employment)
	var unemployed_total: int = labor_force_total - employed_total
	if unemployed_total < 0:
		return JWResult.raise_fault(JWResult.Fault.EMPLOYMENT_OVERFLOW,
				employed_total, labor_force_total)
	_labor_force_total = labor_force_total
	_unemployed_total = unemployed_total
	# rounding: floor, reason=docs/12 §3.4；先乘后除一律走 mul_div_floor（裁定 R-SCALE-01）
	_unemployment_ppm = JWMath.mul_div_floor(unemployed_total, JWUnits.PPM,
			maxi(labor_force_total, 1))

	# 空缺岗位数：目标在岗减去实际在岗的未填补部分（S07 §7.3 工资调整与 §7.5 cap_jobs 的输入）。
	var vacancies: int = 0
	var e: int = 0
	while e < JWUnits.EMP_N:
		vacancies += maxi(0, _need[e] - cell_employment[e])
		e += 1
	_vacancies_persons = vacancies
	return JWResult.OK


## 失业率读数（derived.labor.unemployment_ppm）。
## 步骤：S03 末及其后
## 前置：compute_unemployment 已完成
## 后置：不改状态
## 不变量：INV-075、INV-143
## 失败：无
func unemployment_ppm() -> int:
	return _unemployment_ppm


## 失业人数（劳动力减在岗）。
## 步骤：S03 末及其后
## 前置：compute_unemployment 已完成
## 后置：不改状态
## 不变量：INV-075, INV-076
## 失败：无
func unemployed_persons() -> int:
	return _unemployed_total


## 空缺岗位数（S07 工资调整的输入）。
## 步骤：S03 末、S07 §7.3
## 前置：compute_unemployment 已完成
## 后置：不改状态
## 不变量：INV-076
## 失败：无
func vacancies_persons() -> int:
	return _vacancies_persons


## S04 §4.1：企业付工资（工资先于消费）。
## 步骤：S04 §4.1
## 前置：wage_bill[i] <= cell.cash（由 S03 闸二保证）
## 后置：按各组在该 cell 的在岗人数用 split_lr 拆分并逐组 post(kind=WAGE_PAYMENT)；
##       Σ 各组工资收入 == Σ 各 cell 工资总额
## 不变量：INV-079、INV-003、INV-015、INV-016
## 失败：现金不足 → Fault.WAGE_UNFUNDED（说明 S03 有缺陷；不在 S04 补救、不裁员）
##
## 为什么这里不调 split_lr_into：该 cell 的每个技能档恰好对应唯一一个群组 (r, working, k)，
## 其应得额就是 employment_k × wage_k，三档之和按定义精确等于 wage_bill —— 拆分权重
## 就是被拆的金额本身，最大余数法在此是恒等映射。而 split_lr_into 的入口溢出判据
## 是 total × w_i，此处两者都是 μU 量级（各约 1e9…1e10），相乘会触发一次**假的**
## INT_OVERFLOW。直接按定义式逐组过账既精确又不引入这个伪故障，并在末尾逐 cell 复核和相等。
func pay_wages(pricing: JWPricing, pop: JWPopulation, ledger: JWLedger, accounts: JWAccount) -> int:
	if pricing == null or pop == null or ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, 0)
	if cell_employment.size() != JWUnits.EMP_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				cell_employment.size(), JWUnits.EMP_N)
	if pop.f_wage_income.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				pop.f_wage_income.size(), JWUnits.GROUP)
	if f_wage_bill.size() != JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				f_wage_bill.size(), JWUnits.CELL)

	var cell: int = 0
	while cell < JWUnits.CELL:
		var wage_bill: int = 0
		var k: int = 0
		while k < JWUnits.K:
			# 单位：人 × μU/人/季 = μU
			wage_bill += JWMath.mul(cell_employment[JWIds.idx_emp(cell, k)], pricing.wage_of(k))
			k += 1
		JWMath.check_amount(wage_bill)
		f_wage_bill[cell] = wage_bill
		if wage_bill == 0:
			cell += 1
			continue
		var payer_agent: int = JWIds.agent_of_cell(cell)
		var cash_uu: int = accounts.cash_of(payer_agent)
		if wage_bill > cash_uu:
			# S03 闸二保证过这一条；走到这里说明 S03 有缺陷。
			# 按契约不在本步补救、不裁员、不部分支付。
			return JWResult.raise_fault(JWResult.Fault.WAGE_UNFUNDED, cell, wage_bill - cash_uu)
		var region: int = JWIds.region_of_cell(cell)
		var paid_sum: int = 0
		var k2: int = 0
		while k2 < JWUnits.K:
			var amount: int = JWMath.mul(cell_employment[JWIds.idx_emp(cell, k2)],
					pricing.wage_of(k2))
			if amount <= 0:
				k2 += 1
				continue
			var g: int = JWIds.idx_group(region, JWUnits.Age.WORKING, k2)
			var rc: int = ledger.post(JWUnits.Kind.WAGE_PAYMENT,
					JWIds.idx_account(payer_agent, JWIds.ACC_CASH),
					JWIds.idx_account(JWIds.agent_of_group(g), JWIds.ACC_CASH),
					amount, 0, NO_PRODUCT, CAUSE_RULE, cell)
			if rc != JWResult.OK:
				return rc
			pop.f_wage_income[g] += amount
			paid_sum += amount
			k2 += 1
		if paid_sum != wage_bill:
			return JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, wage_bill, paid_sum)
		cell += 1
	return JWResult.OK


## S04 §4.2：公共部门工资的应付额清单（收款方 = 群组主体）。
## 不直接调 JWTreasury（同秩，§3.2）：由 JWTurnRunner 取清单 → treasury.pay_line() → 回写实付。
## 步骤：S04 §4.2 的 public_wages 档
## 前置：pub_employment 与 wage 已定
## 后置：out_payee_agent 与 out_due 等长且逐项对应；返回清单长度
## 不变量：INV-101（非市场产出按成本计价的工资腿）、INV-079
## 失败：无
##
## 行序：按 (地区, 技能) 下标升序，只登记应付额为正的行（收款方 ID 也随之升序，
## 正是 treasury.pay_line 要求的「按收款方 ID 升序拆分」次序）。
func public_wage_due_into(out_payee_agent: PackedInt64Array, out_due: PackedInt64Array,
		pricing: JWPricing, pop: JWPopulation) -> int:
	if pricing == null or pop == null:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, 0)
		return 0
	if out_payee_agent.size() != out_due.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				out_payee_agent.size(), out_due.size())
		return 0
	if pub_employment.size() != JWUnits.PUBSERV_EMP_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				pub_employment.size(), JWUnits.PUBSERV_EMP_N)
		return 0
	_ensure_scratch()
	var g0: int = 0
	while g0 < JWUnits.GROUP:
		_pub_due_by_group[g0] = 0
		g0 += 1
	_pub_row_count = 0

	var rows: int = 0
	var r: int = 0
	while r < JWUnits.R:
		var k: int = 0
		while k < JWUnits.K:
			# 单位：人 × μU/人/季 = μU
			var due: int = JWMath.mul(pub_employment[JWIds.idx_pubserv_emp(r, k)],
					pricing.wage_of(k))
			if due <= 0:
				k += 1
				continue
			if rows >= out_due.size():
				JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, rows, out_due.size())
				return rows
			var g: int = JWIds.idx_group(r, JWUnits.Age.WORKING, k)
			JWMath.check_amount(due)
			out_payee_agent[rows] = JWIds.agent_of_group(g)
			out_due[rows] = due
			_pub_row_group[rows] = g
			_pub_due_by_group[g] = due
			rows += 1
			k += 1
		r += 1
	_pub_row_count = rows
	return rows


## S04 §4.2：回写实际支付结果（不足部分已由 treasury 登记 arrears）。
## 步骤：S04 §4.2
## 前置：paid_by_group 来自 treasury.pay_line 的拆分结果
## 后置：flow.pubserv.wage_bill_uu 与 flow.group.wage_income_uu 同步写入
## 不变量：INV-079、INV-101、INV-030
## 失败：Σ paid > Σ due → Fault.LEDGER_IMBALANCE
##
## 接受两种等价形态（行数上限 12 < 36，两者不会混淆）：
##   size == JWUnits.GROUP        —— 按群组下标对齐（与形参名一致）
##   size == 上一次清单的行数     —— 按 public_wage_due_into 的行序对齐
func record_public_wage_paid(paid_by_group: PackedInt64Array, pop: JWPopulation) -> int:
	if pop == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, 0)
	if pop.f_wage_income.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				pop.f_wage_income.size(), JWUnits.GROUP)
	if f_pub_wage_bill.size() != JWUnits.PUBSERV:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				f_pub_wage_bill.size(), JWUnits.PUBSERV)
	_ensure_scratch()
	var n: int = paid_by_group.size()
	var by_group: bool = n == JWUnits.GROUP
	if not by_group and n != _pub_row_count:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, n, _pub_row_count)

	var i: int = 0
	while i < n:
		var paid: int = paid_by_group[i]
		var g: int = i
		if not by_group:
			g = _pub_row_group[i]
		if paid == 0:
			i += 1
			continue
		if paid < 0:
			return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, g, paid)
		if paid > _pub_due_by_group[g]:
			# 实付超应付：treasury 的拆分越界，属于恒等式破裂。
			return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, g,
					paid - _pub_due_by_group[g])
		f_pub_wage_bill[JWIds.region_of_group(g)] += paid
		pop.f_wage_income[g] += paid
		i += 1
	return JWResult.OK


## S07 §7.7：人口流出带走的就业扣减。S07 对 employment 的写只允许出现在本函数内。
## 步骤：S07 §7.7
## 前置：outflow 来自 JWPopulation.outflow_persons_into()
## 后置：Σ 扣减 == employed_share（按各 cell/pubserv 在该组在岗人数用 split_lr 拆分）；
##       结果回写 JWPopulation.apply_employment_cut()
## 不变量：INV-080（减少量精确等于人口流出带走的就业人数）、INV-077、INV-003
## 失败：和不相等 → Fault.EMPLOYMENT_OVERFLOW
##
## 群组侧的回写由 JWTurnRunner 在本函数之后调 pop.apply_employment_cut(out_cut_by_group_slot)
## 完成（docs/17 §5 的 S07 第 8 步把三步写成一条链）。本函数**不**自己调它，
## 否则群组侧会被扣两次。
func release_for_outflow(outflow_persons: PackedInt64Array, pop: JWPopulation,
		out_cut_by_group_slot: PackedInt64Array) -> int:
	if pop == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, 0)
	if outflow_persons.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				outflow_persons.size(), JWUnits.GROUP)
	if out_cut_by_group_slot.size() != JWUnits.GROUP_EMP_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				out_cut_by_group_slot.size(), JWUnits.GROUP_EMP_N)
	if pop._population_prev.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				pop._population_prev.size(), JWUnits.GROUP)
	if cell_employment.size() != JWUnits.EMP_N or pub_employment.size() != JWUnits.PUBSERV_EMP_N \
			or f_separations.size() != JWUnits.EMP_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				cell_employment.size(), JWUnits.EMP_N)
	_ensure_scratch()
	var z: int = 0
	while z < JWUnits.GROUP_EMP_N:
		out_cut_by_group_slot[z] = 0
		z += 1

	var g: int = 0
	while g < JWUnits.GROUP:
		var outflow: int = outflow_persons[g]
		if outflow <= 0:
			g += 1
			continue
		if JWIds.age_of_group(g) != JWUnits.Age.WORKING:
			# 非劳动年龄组不可能在岗（participation_ppm 恒 0），无就业可扣。
			g += 1
			continue
		var r: int = JWIds.region_of_group(g)
		var k: int = JWIds.skill_of_group(g)
		var employed_g: int = 0
		var s: int = 0
		while s < JWUnits.S:
			var n: int = cell_employment[JWIds.idx_emp(JWIds.idx_cell(r, s), k)]
			_w_slot[s] = n
			_tb_slot[s] = s
			employed_g += n
			s += 1
		var n_pub: int = pub_employment[JWIds.idx_pubserv_emp(r, k)]
		_w_slot[JWUnits.S] = n_pub
		_tb_slot[JWUnits.S] = JWUnits.S
		employed_g += n_pub
		if employed_g <= 0:
			g += 1
			continue
		var pop_prev: int = maxi(pop._population_prev[g], 1)
		# rounding: floor, reason=docs/12 §7.7；先乘后除走 mul_div_floor（裁定 R-SCALE-01）
		var employed_share: int = JWMath.mul_div_floor(outflow, employed_g, pop_prev)
		if employed_share > employed_g:
			# 流出人数超过了上季人口，说明人口侧的流出登记有缺陷。
			return JWResult.raise_fault(JWResult.Fault.EMPLOYMENT_OVERFLOW, g, employed_share)
		if employed_share <= 0:
			g += 1
			continue
		JWMath.split_lr_into(employed_share, _w_slot, _tb_slot, _out_slot)
		if JWMath._split_last_fault != 0:
			return JWMath._split_last_fault
		var cut_sum: int = 0
		var s2: int = 0
		while s2 < JWUnits.S:
			var cut: int = _out_slot[s2]
			if cut > 0:
				var idx: int = JWIds.idx_emp(JWIds.idx_cell(r, s2), k)
				cell_employment[idx] -= cut
				f_separations[idx] += cut
			out_cut_by_group_slot[JWIds.idx_group_emp(g, s2)] = cut
			cut_sum += cut
			s2 += 1
		var cut_pub: int = _out_slot[JWUnits.S]
		if cut_pub > 0:
			pub_employment[JWIds.idx_pubserv_emp(r, k)] -= cut_pub
		out_cut_by_group_slot[JWIds.idx_group_emp(g, JWUnits.S)] = cut_pub
		cut_sum += cut_pub
		if cut_sum != employed_share:
			return JWResult.raise_fault(JWResult.Fault.EMPLOYMENT_OVERFLOW, g,
					cut_sum - employed_share)
		g += 1
	return JWResult.OK


## 只读访问器：某 cell 某技能的在岗人数。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-077
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func employment(cell: int, k: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL or k < 0 or k >= JWUnits.K:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, k)
		return 0
	var idx: int = JWIds.idx_emp(cell, k)
	if idx >= cell_employment.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, idx, cell_employment.size())
		return 0
	return cell_employment[idx]


## 只读访问器：某地区公共服务部门某技能的在岗人数。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-077
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func pubserv_employment(r: int, k: int) -> int:
	if r < 0 or r >= JWUnits.R or k < 0 or k >= JWUnits.K:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, r, k)
		return 0
	var idx: int = JWIds.idx_pubserv_emp(r, k)
	if idx >= pub_employment.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, idx, pub_employment.size())
		return 0
	return pub_employment[idx]


## 地区工资指数（迁移的工资拉力输入）。
## 步骤：S07 §7.5
## 前置：本季工资率已固定；下标合法
## 后置：不改状态
## 不变量：INV-077
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
##
## 单位是 **μU/人/季**（docs/12 §7.5 的注释行：「该地区在岗人员的平均季度工资，
## 按 cell 在岗人数加权，向下取整」），不是 ppm —— §7.5 的 wage_adv_ppm 自己再做一次
## 相对差的 ppm 归一化。骨架注释里的「（ppm）」与契约冲突，按 docs/12 优先。
func region_wage_index(pricing: JWPricing, r: int) -> int:
	if pricing == null:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, 0)
		return 0
	if r < 0 or r >= JWUnits.R:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, r, JWUnits.R)
		return 0
	if cell_employment.size() != JWUnits.EMP_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				cell_employment.size(), JWUnits.EMP_N)
		return 0
	var total_wage: int = 0
	var headcount: int = 0
	var s: int = 0
	while s < JWUnits.S:
		var k: int = 0
		while k < JWUnits.K:
			var n: int = cell_employment[JWIds.idx_emp(JWIds.idx_cell(r, s), k)]
			headcount += n
			total_wage += JWMath.mul(n, pricing.wage_of(k))
			k += 1
		s += 1
	if headcount <= 0:
		return 0
	# rounding: floor, reason=docs/12 §7.5 明示向下取整
	return JWMath.floor_div(total_wage, headcount)


## 载入期与 S03 末的两侧口径交叉校验。
## 步骤：LOAD、S03 末
## 前置：两侧数组都已填充
## 后置：不改状态
## 不变量：INV-077、INV-151（故意冗余的交叉校验）
## 失败：Load.EMPLOY_MISMATCH（载入期）/ Fault.EMPLOYMENT_OVERFLOW（运行期）
##
## 返回运行期故障码 Fault.EMPLOYMENT_OVERFLOW；载入期调用方（JWContentLoader）
## 把非 0 映射为 Load.EMPLOY_MISMATCH —— 本函数不知道自己处在哪个阶段，也不该知道。
## 校验逐（地区，技能）逐槽位进行（比契约要求的汇总相等更强），并要求非劳动年龄组
## 的在岗人数恒为 0（它们的 participation_ppm 必须是 0，见 INV-074/075）。
func check_employment_views(pop: JWPopulation) -> int:
	if pop == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, 0)
	if pop.employed.size() != JWUnits.GROUP_EMP_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				pop.employed.size(), JWUnits.GROUP_EMP_N)
	if cell_employment.size() != JWUnits.EMP_N or pub_employment.size() != JWUnits.PUBSERV_EMP_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				cell_employment.size(), JWUnits.EMP_N)
	var r: int = 0
	while r < JWUnits.R:
		var k: int = 0
		while k < JWUnits.K:
			var g_work: int = JWIds.idx_group(r, JWUnits.Age.WORKING, k)
			var s: int = 0
			while s < JWUnits.S:
				var mine: int = cell_employment[JWIds.idx_emp(JWIds.idx_cell(r, s), k)]
				var theirs: int = pop.employed[JWIds.idx_group_emp(g_work, s)]
				if mine != theirs:
					return JWResult.raise_fault(JWResult.Fault.EMPLOYMENT_OVERFLOW,
							JWIds.idx_group_emp(g_work, s), mine - theirs)
				s += 1
			var mine_pub: int = pub_employment[JWIds.idx_pubserv_emp(r, k)]
			var theirs_pub: int = pop.employed[JWIds.idx_group_emp(g_work, JWUnits.S)]
			if mine_pub != theirs_pub:
				return JWResult.raise_fault(JWResult.Fault.EMPLOYMENT_OVERFLOW,
						JWIds.idx_group_emp(g_work, JWUnits.S), mine_pub - theirs_pub)
			var a: int = 0
			while a < JWUnits.A:
				if a != JWUnits.Age.WORKING:
					var g_other: int = JWIds.idx_group(r, a, k)
					var slot: int = 0
					while slot <= JWUnits.S:
						var v: int = pop.employed[JWIds.idx_group_emp(g_other, slot)]
						if v != 0:
							return JWResult.raise_fault(JWResult.Fault.EMPLOYMENT_OVERFLOW,
									JWIds.idx_group_emp(g_other, slot), v)
						slot += 1
				a += 1
			k += 1
		r += 1
	return JWResult.OK


# ── 内部工具 ─────────────────────────────────────────────────────────────────

## 某（地区，技能）当前在岗人数合计（4 个 cell + pubserv），本类两份权威数组的汇总。
func _employed_region_skill(r: int, k: int) -> int:
	var total: int = pub_employment[JWIds.idx_pubserv_emp(r, k)]
	var s: int = 0
	while s < JWUnits.S:
		total += cell_employment[JWIds.idx_emp(JWIds.idx_cell(r, s), k)]
		s += 1
	return total


## O(1) 长度自检：scratch 长度已对即立刻返回，不分配（docs/17 §1.4）。
## allocate() 正常会一次性把它们拉到位；这里兜住「未经 allocate 直接调用」的路径。
func _ensure_scratch() -> void:
	if _need.size() == JWUnits.EMP_N and _target.size() == JWUnits.EMP_N \
			and _alloc.size() == JWUnits.EMP_N and _prev_employment.size() == JWUnits.EMP_N \
			and _w_cell.size() == JWUnits.S and _w_skill.size() == JWUnits.K \
			and _w_slot.size() == JWUnits.S + 1 \
			and _pub_due_by_group.size() == JWUnits.GROUP \
			and _pub_row_group.size() == JWUnits.PUBSERV_EMP_N:
		return
	_alloc_scratch()


## scratch 的一次性定长化。
func _alloc_scratch() -> void:
	_prev_employment.resize(JWUnits.EMP_N)
	_need.resize(JWUnits.EMP_N)
	_target.resize(JWUnits.EMP_N)
	_alloc.resize(JWUnits.EMP_N)
	_w_cell.resize(JWUnits.S)
	_tb_cell.resize(JWUnits.S)
	_out_cell.resize(JWUnits.S)
	_w_skill.resize(JWUnits.K)
	_tb_skill.resize(JWUnits.K)
	_out_skill.resize(JWUnits.K)
	_w_slot.resize(JWUnits.S + 1)
	_tb_slot.resize(JWUnits.S + 1)
	_out_slot.resize(JWUnits.S + 1)
	_pub_due_by_group.resize(JWUnits.GROUP)
	_pub_row_group.resize(JWUnits.PUBSERV_EMP_N)


# ── §1.6 状态块协议（cell_* 归 SUBSYS_CELL，pub_* 归 SUBSYS_PUBSERV） ─────────

## LOAD 期一次性把本块各数组 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：尚未分配；只允许 JWContentLoader / JWSaves 调用
## 后置：全部数组长度等于契约长度，内容为 0；此后不再 resize
## 不变量：INV-136（数组顺序与长度是 schema 的一部分）
## 失败：无（长度不符在载入校验处报 Load.UNIT_MISMATCH）
func allocate() -> void:
	cell_employment.resize(JWUnits.EMP_N)
	cell_employment.fill(0)
	pub_employment.resize(JWUnits.PUBSERV_EMP_N)
	pub_employment.fill(0)
	pub_establishment.resize(JWUnits.PUBSERV_EMP_N)
	pub_establishment.fill(0)
	f_hires.resize(JWUnits.EMP_N)
	f_hires.fill(0)
	f_separations.resize(JWUnits.EMP_N)
	f_separations.fill(0)
	f_wage_bill.resize(JWUnits.CELL)
	f_wage_bill.fill(0)
	f_pub_wage_bill.resize(JWUnits.PUBSERV)
	f_pub_wage_bill.fill(0)
	_alloc_scratch()
	_prev_employment.fill(0)
	_need.fill(0)
	_target.fill(0)
	_alloc.fill(0)
	_pub_due_by_group.fill(0)
	_pub_row_group.fill(0)
	_pub_row_count = 0
	_unemployment_ppm = 0
	_vacancies_persons = 0
	_labor_force_total = 0
	_unemployed_total = 0


## 只读取用某个状态数组（返回引用，调用方不得写）。
## 步骤：LOAD、哈希、存档
## 前置：0 <= i < STATE_ARRAY_IDS.size()
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回空数组
func state_array(i: int) -> PackedInt64Array:
	if i == 0:
		return cell_employment
	if i == 1:
		return pub_employment
	if i == 2:
		return pub_establishment
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## 写入某个状态数组（仅 LOAD / MIG）。
## 步骤：LOAD、MIG
## 前置：调用点位于 systems/content_loader.gd 或 systems/saves.gd；长度与契约一致
## 后置：对应成员被整体替换
## 不变量：INV-136
## 失败：越界或长度不符 → 返回非 0 故障码
func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i == 0:
		if v.size() != JWUnits.EMP_N:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
					v.size(), JWUnits.EMP_N)
		cell_employment = v
		return JWResult.OK
	if i == 1:
		if v.size() != JWUnits.PUBSERV_EMP_N:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
					v.size(), JWUnits.PUBSERV_EMP_N)
		pub_employment = v
		return JWResult.OK
	if i == 2:
		if v.size() != JWUnits.PUBSERV_EMP_N:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
					v.size(), JWUnits.PUBSERV_EMP_N)
		pub_establishment = v
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())


## 读取某个状态标量（本类无状态标量，恒返回 0）。
## 步骤：LOAD、哈希、存档
## 前置：0 <= i < STATE_SCALAR_IDS.size()
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func state_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


## 写入某个状态标量（仅 LOAD / MIG；本类无状态标量）。
## 步骤：LOAD、MIG
## 前置：调用点位于 systems/content_loader.gd 或 systems/saves.gd
## 后置：无
## 不变量：INV-136
## 失败：任意下标都越界 → 返回非 0 故障码
func set_state_scalar(i: int, v: int) -> int:
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v)


## 只读取用某个流量数组。
## 步骤：哈希、诊断
## 前置：0 <= i < FLOW_ARRAY_IDS.size()
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回空数组
func flow_array(i: int) -> PackedInt64Array:
	if i == 0:
		return f_hires
	if i == 1:
		return f_separations
	if i == 2:
		return f_wage_bill
	if i == 3:
		return f_pub_wage_bill
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
	return PackedInt64Array()


## 读取某个流量标量（本类无流量标量，恒返回 0）。
## 步骤：哈希、诊断
## 前置：0 <= i < FLOW_SCALAR_IDS.size()
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func flow_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
	return 0


## 仅 S01：把全部 FLOW_* 归零。
## 步骤：S01 §01.3
## 前置：调用点位于 systems/turn_runner.gd 的 _step_s01 内
## 后置：全部流量数组逐位为 0
## 不变量：INV-013（流量每季清零）
## 失败：无（清零失败由 flow_abs_sum() 在其后检出）
func reset_flows() -> void:
	f_hires.fill(0)
	f_separations.fill(0)
	f_wage_bill.fill(0)
	f_pub_wage_bill.fill(0)
	# 公共工资清单是本季 S04 的一次性台账，跨季不得残留
	# （否则上季的应付额会给本季的实付额放行）。
	if _pub_due_by_group.size() == JWUnits.GROUP:
		_pub_due_by_group.fill(0)
	_pub_row_count = 0


## S01 清零后的自检，非 0 即 FLOW_NOT_RESET。
## 步骤：S01 §01.3 末
## 前置：reset_flows() 刚刚执行
## 后置：不改状态
## 不变量：INV-013
## 失败：返回非 0 由调用方判为 Fault.FLOW_NOT_RESET
func flow_abs_sum() -> int:
	var total: int = JWMath.sum_abs(f_hires)
	total += JWMath.sum_abs(f_separations)
	total += JWMath.sum_abs(f_wage_bill)
	total += JWMath.sum_abs(f_pub_wage_bill)
	return total


## §1.6 状态块协议：读档时写回流量数组（R-SAVE-01，由 tools/gen_flow_setters.py 按 flow_array 逐项对称生成）。
## 步骤：LOAD（JWSaves 经 JWSimState 调用）
## 前置：v 的长度与本块当前分配的长度一致（长度是 schema 的一部分，INV-136）
## 后置：对应成员被整体替换
## 不变量：INV-133（读档后与原进程逐位相同）
## 失败：下标越界或长度不符 → INDEX_OUT_OF_RANGE
func set_flow_array(i: int, v: PackedInt64Array) -> int:
	if i == 0:
		if v.size() != f_hires.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_hires = v.duplicate()
		return JWResult.OK
	if i == 1:
		if v.size() != f_separations.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_separations = v.duplicate()
		return JWResult.OK
	if i == 2:
		if v.size() != f_wage_bill.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_wage_bill = v.duplicate()
		return JWResult.OK
	if i == 3:
		if v.size() != f_pub_wage_bill.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_pub_wage_bill = v.duplicate()
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
