## 库存恒等式 **与** 国内市场闭合。
##
## 两者合在一个文件里的理由：INV-047（期末 == 期初 + 生产 + 购入 − 售出 − 耗用 − 损耗）与
## INV-059（Σ 成交 + Σ 未满足 == Σ 需求，且卖方库存减少量 == Σ 成交）是同一笔账的两半；
## 分开放会让「卖方库存减少量等于成交量」这条断言变成跨文件约定。
##
## 骨架依据：docs/17_api_skeleton.md §4.17。依赖秩 6，只允许引用秩 ≤5。
class_name JWInventory
extends RefCounted

## §1.6 状态块协议：本块各数组所属子系统（与 STATE_ARRAY_IDS 等长）。
## inv_* 归 SUBSYS_CELL，pub_* 归 SUBSYS_PUBSERV；content.region.logistics_cost_ppm 归 SUBSYS_META。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_PUBSERV,
	JWUnits.SUBSYS_META,
]

## 稳定 ID 注册表：下标 == 数组序号；顺序是 schema 的一部分，重排即破坏性变更（INV-136）。
const STATE_ARRAY_IDS: PackedStringArray = [
	"state.cell.inventory_output_uqs",
	"state.cell.inventory_input_uqs",
	"state.pubserv.queue_persons",
	"content.region.logistics_cost_ppm",
]
const STATE_SCALAR_IDS: PackedStringArray = []

## 流量注册表。下标 4 的 `_internal.cell.spoilage_input_uqs` 在 docs/10 中尚无稳定 ID
## （docs/17 §4.17 的表里写作「—」），此处按内部流量登记，仍须每季 S01 清零。
const FLOW_ARRAY_IDS: PackedStringArray = [
	"flow.cell.consumed_input_uqs",
	"flow.cell.purchased_input_uqs",
	"flow.cell.sold_uqs",
	"flow.cell.spoilage_uqs",
	"_internal.cell.spoilage_input_uqs",
	"flow.cell.unmet_demand_uqs",
	"flow.cell.price_variance_uu",
	"flow.market.supply_uqs",
	"flow.market.demand_uqs",
	"flow.market.traded_uqs",
	"flow.market.unmet_demand_uqs",
	"flow.market.rationing_rule",
	"flow.market.inventory_target_uqs",
	"flow.pubserv.delivered_uqs",
	"flow.pubserv.intermediate_uu",
	"flow.cell.sold_direct_uqs",
	"flow.market.imported_uqs",
]
const FLOW_SCALAR_IDS: PackedStringArray = []

## 公共部门（pubserv 中间投入与政府采购）把预算换算成数量时的分产品结构（ppm，四项和恰为 1 000 000）。
##
## **临时取法，不是自创的经济规则**：docs/12 §5.6 对买方类 1/2 只写「按已预留预算换算成数量」，
## 没有给出分产品结构，而 `collect_demand` 的形参表里没有 `JWIoTable`（签名不得改），
## 拿不到 `io_coeff[j][services]`。本常量逐项取自剧本基年表
## `content/scenarios/chengwan/io_table.json` 的 `government_nonmarket_output.intermediate_by_product_uu`
## （400 / 1 300 / 900 / 1 600，合计 4 200，单位百万 μU），按最大余数法折成 ppm：
## 95 238 + 309 524 + 214 286 + 380 952 == 1 000 000（精确）。
## 正式做法应是内容字段 `content.pubserv.intermediate_share_ppm[4]`，已在 interface_requests 中登记。
const PUBSERV_INPUT_SHARE_PPM: PackedInt64Array = [95_238, 309_524, 214_286, 380_952]

## `gov.ration_mode` 的两个取值。**它不是 `JWUnits.Rationing` 枚举**，两者刻度不同：
## docs/12 §5.6 写「`gov.ration_mode == 1` 时的 proportional」，即开关是 0|1 的二值政策旗；
## 而 `Rationing` 是结果枚举 `none=0 / priority=1 / proportional=2`（`flow.market.rationing_rule`）。
## 拿开关去和结果枚举比（`ration_mode == Rationing.PROPORTIONAL`，即 == 2）会让
## 「切到全比例」这条政策永远打不开，且把 `rationing_rule` 记成 priority——同时破坏 INV-003 与 INV-061。
const RATION_MODE_PRIORITY: int = 0
const RATION_MODE_PROPORTIONAL: int = 1

## state.cell.inventory_output_uqs[] —— 长度 16，初值剧本，μQ_s。类 S，写入者 S05。
var inv_output: PackedInt64Array = PackedInt64Array()
## state.cell.inventory_input_uqs[] —— 长度 64（按 idx_inv），初值剧本，μQ_j。类 S，写入者 S05。
var inv_input: PackedInt64Array = PackedInt64Array()
## flow.cell.consumed_input_uqs[] —— 长度 64，初值 0，μQ_j。类 F，写入者 S05。
var f_consumed: PackedInt64Array = PackedInt64Array()
## flow.cell.purchased_input_uqs[] —— 长度 64，初值 0，μQ_j。类 F，写入者 S05。
var f_purchased: PackedInt64Array = PackedInt64Array()
## flow.cell.sold_uqs[] —— 长度 16，初值 0，μQ_s。类 F，写入者 S05。
var f_sold: PackedInt64Array = PackedInt64Array()
## flow.cell.spoilage_uqs[] —— 长度 16，初值 0，μQ_s。类 F，写入者 S05。
var f_spoilage_out: PackedInt64Array = PackedInt64Array()
## 内部流量：投入品损耗，长度 64，初值 0，μQ_j。类 F，写入者 S05（docs/10 尚无稳定 ID）。
var f_spoilage_in: PackedInt64Array = PackedInt64Array()
## flow.cell.unmet_demand_uqs[] —— 长度 16，初值 0，μQ_s。类 F，写入者 S05。
var f_unmet_demand: PackedInt64Array = PackedInt64Array()
## flow.cell.price_variance_uu[] —— 长度 16，初值 0，μU（可正可负）。类 F，写入者 S05。
var f_price_variance: PackedInt64Array = PackedInt64Array()
## flow.cell.sold_direct_uqs[] —— 16，μQ_s。不经市场撮合的直接售出（住房服务交租，R-HOUSING-01）。
## 进逐 cell 库存恒等式与下季 D_prev，不进「Σ售出 == Σ成交」的跨主体对账（那一条只对市场成交）。
var f_sold_direct: PackedInt64Array = PackedInt64Array()
## flow.market.imported_uqs[] —— MARKET_N，μQ_s。各（产品, 买方类）中由外部供货的成交量（R-IMPORT-01）。
## m_traded 含进口；跨主体对账为「Σ 国内卖方市场售出 + Σ 进口 == Σ 成交」。
var m_imported: PackedInt64Array = PackedInt64Array()
## R-INVEST-01：本季各 cell 的资本品需求量（μQ_s，下标 idx_inv(cell, s)）与资本品成交额（μU，按 cell）。
## 同季内由 add_capital_demand 写、成交后由 JWTurnRunner 读去记资本；与其它季内缓冲同寿命。
var _capital_demand: PackedInt64Array = PackedInt64Array()
## 本季已买到的资本品数量（μQ_s，下标 idx_inv(cell, s)），供第二轮补购算剩余需求。
var _capital_bought_qty: PackedInt64Array = PackedInt64Array()
## 配给给各（产品, 买方类）的计划成交量副本：第一轮执行会把 m_traded 改写成实际成交，第二轮需要原计划。
var _planned_copy: PackedInt64Array = PackedInt64Array()
var _cap_legs_acc: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
var _cap_legs_d: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
## R-IMPORT-01 季内缓冲：各产品进口份额与本季交付余额（collect_demand 缓存，ration 用——ration 的签名里没有 world）；
## 各（产品, 买方类）的进口计划量（ration 写，execute_trades 按请求量比例分给各买方实体）。
var _imp_share: PackedInt64Array = PackedInt64Array()
var _imp_room: PackedInt64Array = PackedInt64Array()
var _imp_plan: PackedInt64Array = PackedInt64Array()
## 正在执行的这一档（产品, 买方类）的进口计划与总计划量：_trade_one 的进口部分 = floor(请求 × 前者 / 后者)。
var _cur_imp_plan: int = 0
## R-ORDER-01：S03 由 JWSectorModel.plan_output 登记的投入品目标存量（μQ_j，下标 idx_inv）。
## 同季 S05 的「企业投入与补库」需求按它形成；未登记（单元测试直接调 collect_demand）时退回按本季实耗。
var _input_target: PackedInt64Array = PackedInt64Array()
var _input_target_armed: bool = false
var _cur_plan: int = 0
var f_capital_bought: PackedInt64Array = PackedInt64Array()
## flow.market.supply_uqs[] —— 长度 4，初值 0，μQ_s。类 F，写入者 S05。
var m_supply: PackedInt64Array = PackedInt64Array()
## flow.market.demand_uqs[] —— 长度 20（按 idx_market），初值 0，μQ_s。类 F，写入者 S05。
var m_demand: PackedInt64Array = PackedInt64Array()
## flow.market.traded_uqs[] —— 长度 20，初值 0，μQ_s。类 F，写入者 S05。
var m_traded: PackedInt64Array = PackedInt64Array()
## flow.market.unmet_demand_uqs[] —— 长度 20，初值 0，μQ_s。类 F，写入者 S05。
var m_unmet: PackedInt64Array = PackedInt64Array()
## flow.market.rationing_rule[] —— 长度 4，初值 0，枚举 JWUnits.Rationing。类 F，写入者 S05。
var m_rule: PackedInt64Array = PackedInt64Array()
## flow.market.inventory_target_uqs[] —— 长度 16，初值 0，μQ_s。类 F，写入者 S03。
var m_inv_target: PackedInt64Array = PackedInt64Array()
## flow.pubserv.delivered_uqs[] —— 长度 4，初值 0，μQ_services。类 F，写入者 S05。
var f_pub_delivered: PackedInt64Array = PackedInt64Array()
## flow.pubserv.intermediate_uu[] —— 长度 4，初值 0，μU。类 F，写入者 S05。
var f_pub_intermediate: PackedInt64Array = PackedInt64Array()
## state.pubserv.queue_persons[] —— 长度 12（按 idx_pubserv_queue），初值 0，人。类 S，写入者 S05。
var pub_queue: PackedInt64Array = PackedInt64Array()
## S05 入口快照（长度 16），供 INV-047 的库存恒等式检查；不进 state_hash。
var _inv_output_start: PackedInt64Array = PackedInt64Array()
## S05 入口快照（长度 64），供 INV-047 的库存恒等式检查；不进 state_hash。
var _inv_input_start: PackedInt64Array = PackedInt64Array()
## content.region.logistics_cost_ppm[] —— 长度 16，初值剧本，ppm。类 C，写入者 LOAD。
var logistics_cost_ppm: PackedInt64Array = PackedInt64Array()

# ── 内部缓冲（不进 schema、不进 state_hash；热路径禁止新建对象，全部构造期定长） ──
#
# 命名规律：`_w*` 权重、`_t*` 决胜键（恒为 0..n−1 的常量）、`_o*` 拆分结果，数字是长度。
# 它们是 JWMath.split_lr_into 的调用缓冲，不承载任何跨调用语义。

## 不可库存产出（storable == 0）的当期可供余量，长度 16，μQ_s。
##
## 它不是库存：能源与服务不入库存（INV-049），产出只在本季存在。放在这里有两个用处：
## (a) 让 §5.6 的卖方可售量对可库存与不可库存两类走同一条取数路径；
## (b) 让 INV-047 对这两类也能写成同一条恒等式（见 check_stock_identity 的推导）。
var _direct_avail: PackedInt64Array = PackedInt64Array()
## collect_demand 时刻各 cell 的可售量快照（长度 16），供未满足需求按卖方摊回 f_unmet_demand。
var _supply_by_cell: PackedInt64Array = PackedInt64Array()
## 能源 cell 在电网配完生产用电之后、可在当季市场出售的剩余电力（μQ_energy）。
## JWSectorModel.settle_energy 写，市场成交扣减；与其它季内缓冲同寿命。电力不入库存：季末未售部分作废。
var _energy_market_avail: PackedInt64Array = PackedInt64Array()
## 居民分组分产品消费预算，长度 144（按 idx_group_prod），μU。
var _group_budget: PackedInt64Array = PackedInt64Array()
## 居民分组分产品需求量，长度 144，μQ_s。
var _group_demand: PackedInt64Array = PackedInt64Array()
## 居民分组分产品已成交金额，长度 144，μU（预算减它即被迫储蓄）。
var _group_spent: PackedInt64Array = PackedInt64Array()
## 企业投入与补库需求，长度 64（按 idx_inv），μQ_j。
var _firm_demand: PackedInt64Array = PackedInt64Array()
## 公共服务中间投入需求，长度 16（按 idx_cell(r, s) 的布局复用：r × 4 + 产品），μQ_s。
var _pub_demand: PackedInt64Array = PackedInt64Array()
## 政府采购需求，长度 4（按产品），μQ_s。
var _gov_demand: PackedInt64Array = PackedInt64Array()
## 出口需求，长度 4（按产品），μQ_s。
var _export_demand: PackedInt64Array = PackedInt64Array()
## 政府采购成交额按地区的归属权重缓冲，长度 4，μU。
var _gov_value_by_region: PackedInt64Array = PackedInt64Array()

## 拆分缓冲：长度 3（服务种类）。
var _w3: PackedInt64Array = PackedInt64Array()
var _t3: PackedInt64Array = PackedInt64Array()
var _o3: PackedInt64Array = PackedInt64Array()
## 拆分缓冲：长度 4（地区 / 部门）。
var _w4: PackedInt64Array = PackedInt64Array()
var _t4: PackedInt64Array = PackedInt64Array()
var _o4: PackedInt64Array = PackedInt64Array()
## 按部门拆分的缓冲（长 S）。R-SCENARIO-02：此前与按地区拆分共用 _w4/_t4/_o4，4 区时 R == S 恰好不出错。
var _wS: PackedInt64Array = PackedInt64Array()
var _tS: PackedInt64Array = PackedInt64Array()
var _oS: PackedInt64Array = PackedInt64Array()
## 拆分缓冲：长度 5（买方类）。
var _w5: PackedInt64Array = PackedInt64Array()
var _t5: PackedInt64Array = PackedInt64Array()
var _o5: PackedInt64Array = PackedInt64Array()
## 拆分缓冲：长度 9（一个地区内的 9 个群组）。
var _w9: PackedInt64Array = PackedInt64Array()
var _t9: PackedInt64Array = PackedInt64Array()
var _o9: PackedInt64Array = PackedInt64Array()
## 拆分缓冲：长度 16（cell）。
var _w16: PackedInt64Array = PackedInt64Array()
var _t16: PackedInt64Array = PackedInt64Array()
var _o16: PackedInt64Array = PackedInt64Array()
## 拆分缓冲：长度 36（群组）。
var _w36: PackedInt64Array = PackedInt64Array()
var _t36: PackedInt64Array = PackedInt64Array()
var _o36: PackedInt64Array = PackedInt64Array()

## 私有助手登记的故障码（0 == 无故障）。助手的返回值是数量，不能兼做故障通道。
var _fault: int = 0

# ── 私有助手 ───────────────────────────────────────────────────────────────

## 把 a 填成 0, 1, 2, …（最大余数法的决胜键：下标升序，恒定不变）。
func _fill_iota(a: PackedInt64Array) -> void:
	for i: int in a.size():
		a[i] = i


## 登记一次故障：写入 _fault（只记第一次）并转给全局故障登记点。
func _raise(code: int, a: int, b: int) -> int:
	if _fault == 0:
		_fault = code
	return JWResult.raise_fault(code, a, b)


## 一笔成交的付款额（μU）。INV-062：`floor(量 × 价 / 1e6)`，跨区再乘 `1e6 + logistics`。
## 两处缩放都走 mul_div_floor：新刻度下 `qty × price` 与 `value × ppm` 都能真的溢出 int64（R-SCALE-01）。
func _trade_value(qty_uqs: int, price: int, logistics_ppm: int) -> int:
	# rounding: floor, reason=INV-062，付款额按 floor 取整，少收优于凭空多收
	var v: int = JWMath.mul_div_floor(qty_uqs, price, JWUnits.Q_SCALE)
	if logistics_ppm > 0:
		# rounding: floor, reason=跨区加成同样只取整一次（M1）
		v = JWMath.mul_ppm(v, JWUnits.PPM + logistics_ppm)
	return v


## 在买方现金约束下能成交的最大数量（μQ_s）。**没有任何路径可以产生凭空的货**（docs/12 §5.9）。
##
## 取法：先把现金反折成不含物流的金额上界 `A = floor(cash × 1e6 / (1e6 + L))`，
## 再折成数量 `q = floor(A × 1e6 / price)`。
## 由 `q × price ≤ A × 1e6` 得 `v1 = floor(q × price / 1e6) ≤ A`，
## 再由 `A × (1e6 + L) ≤ cash × 1e6` 得 `floor(v1 × (1e6+L) / 1e6) ≤ cash`——一次算出即成立，不需要迭代收敛。
func _affordable_qty(qty_uqs: int, price: int, logistics_ppm: int, cash_uu: int) -> int:
	if qty_uqs <= 0 or price <= 0:
		return 0
	if cash_uu <= 0:
		return 0
	if _trade_value(qty_uqs, price, logistics_ppm) <= cash_uu:
		return qty_uqs
	var budget: int = cash_uu
	if logistics_ppm > 0:
		# rounding: floor, reason=剥掉物流加成后的可付金额上界，取 floor 保证不超付
		budget = JWMath.mul_div_floor(cash_uu, JWUnits.PPM, JWUnits.PPM + logistics_ppm)
	# rounding: floor, reason=金额折数量一律 floor（docs/10 §0.10「买方能买多少」不得多算）
	var q: int = JWMath.mul_div_floor(budget, JWUnits.Q_SCALE, price)
	if q > qty_uqs:
		q = qty_uqs
	if q < 0:
		return 0
	return q


## 卖方 cell 的当期可售量：库存 + 不可库存产出的当期余量（两者互斥，恒有一个为 0）。
func _avail_of(cell: int) -> int:
	# 能源 cell 的 _direct_avail 装着全部产量（含已经电网配给、已付款的部分），市场只能卖配给后的剩余。
	if JWIds.sector_of_cell(cell) == JWUnits.Sector.ENERGY:
		return mini(_direct_avail[cell], _energy_market_avail[cell])
	return inv_output[cell] + _direct_avail[cell]


## R-HOUSING-01：住房服务直接售出（交租）。从服务 cell 的当季可售量中取走 qty 并记为售出。
## 步骤：S05（市场开市之前，由 JWTurnRunner._pay_rents 调用）
## 前置：cell 是服务部门 cell；qty <= _avail_of(cell)（调用方先用 avail_for_direct_sale 取上限）
## 后置：卖方可售量减少 qty，f_sold 同步增加（INV-047 / INV-059 的卖方侧仍精确成立）
## 不变量：INV-047（库存恒等式：售出含住房服务）
## 失败：越界 / 超量 → Fault
func sell_direct(cell: int, qty_uqs: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL or qty_uqs < 0:
		return _raise(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, qty_uqs)
	if qty_uqs > _avail_of(cell):
		return _raise(JWResult.Fault.NEGATIVE_INVENTORY, cell, qty_uqs - _avail_of(cell))
	if qty_uqs == 0:
		return JWResult.OK
	_take_from_seller(cell, qty_uqs)
	f_sold_direct[cell] = f_sold_direct[cell] + qty_uqs
	return JWResult.OK


## 某 cell 当季可直接售出的量（只读）。
func avail_for_direct_sale(cell: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		return 0
	return _avail_of(cell)


## 能源 cell 在电网配给后可售的剩余电力（S05 §5.2 之后由 JWSectorModel 写入）。
func set_energy_market_avail(cell: int, qty_uqs: int) -> void:
	if cell < 0 or cell >= _energy_market_avail.size() or qty_uqs < 0:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, qty_uqs)
		return
	_energy_market_avail[cell] = qty_uqs


## 从卖方扣减已成交的实物：先扣库存，再扣当期不可库存余量。
## 卖方库存减少量精确等于 Σ traded（INV-059）由本函数与 f_sold 的同步累加保证。
func _take_from_seller(cell: int, qty_uqs: int) -> void:
	if JWIds.sector_of_cell(cell) == JWUnits.Sector.ENERGY:
		_energy_market_avail[cell] = maxi(0, _energy_market_avail[cell] - qty_uqs)
	var from_inv: int = qty_uqs
	if from_inv > inv_output[cell]:
		from_inv = inv_output[cell]
	inv_output[cell] = inv_output[cell] - from_inv
	var rest: int = qty_uqs - from_inv
	if rest > 0:
		_direct_avail[cell] = _direct_avail[cell] - rest


## R-IMPORT-01：向外部（agent.row）购买 qty_req（μQ_s），外部按进口价供货。
## 步骤：S05 §5.6（_trade_one 内，先于国内卖方）
## 前置：qty_req 已按交付能力余额封顶；买方类不是出口或中央政府采购
## 后置：买方现金 → row 现金（资本品走四腿）；world.record_import 登记进口流量（M）；
##       买方侧入账与国内采购相同（居民消费 / 公服中间消耗 / 投入入库与价差 / 资本品）；m_imported 累计
## 不变量：INV-104（进口 ≤ 交付能力，且受买方现金约束）、INV-115（进口在支出法中以 M 同额抵减）
## 失败：过账被拒 → 该笔不成交（返回 0），不透支、不静默改账
func _trade_import(s: int, buyer_class: int, buyer_agent: int, buyer_region: int,
		buyer_entity: int, qty_req: int, kind: int, pop: JWPopulation, world: JWWorldMarket,
		ledger: JWLedger, accounts: JWAccount) -> int:
	# rounding: floor, reason=进口价 = 基价 × 进口价格乘数（world.import_price_ppm，受冲击）
	var imp_price: int = JWMath.mul_ppm(JWUnits.BASE_PRICE, world.import_price(s))
	if imp_price <= 0:
		return 0
	var cash: int = accounts.cash_of(buyer_agent)
	if buyer_class == JWUnits.BuyerClass.HOUSEHOLD:
		# INV-063：居民以分产品预算余额为准（同国内成交）。
		var rem: int = _group_budget[JWIds.idx_group_prod(buyer_entity, s)] \
				- _group_spent[JWIds.idx_group_prod(buyer_entity, s)]
		if rem < cash:
			cash = rem
	var q: int = _affordable_qty(qty_req, imp_price, 0, cash)
	if q <= 0:
		return 0
	var value: int = _trade_value(q, imp_price, 0)
	if value <= 0:
		return 0
	var row_cash: int = JWIds.idx_account(JWIds.AGENT_ROW, JWIds.ACC_CASH)
	var prc: int = JWResult.OK
	if buyer_class == JWUnits.BuyerClass.FIRM_CAPITAL:
		# 四腿同国内资本品：外部现金 +V（第 0 腿承载 I 类分类）、买方现金 −V、买方资本 +V、外部净值 −V。
		_cap_legs_acc[0] = row_cash
		_cap_legs_acc[1] = JWIds.idx_account(buyer_agent, JWIds.ACC_CASH)
		_cap_legs_acc[2] = JWIds.idx_account(buyer_agent, JWIds.ACC_CAPITAL)
		_cap_legs_acc[3] = JWIds.idx_account(JWIds.AGENT_ROW, JWIds.ACC_NW)
		_cap_legs_d[0] = value
		_cap_legs_d[1] = -value
		_cap_legs_d[2] = value
		_cap_legs_d[3] = -value
		prc = ledger.post_multi(kind, _cap_legs_acc, _cap_legs_d, q, s, 0, buyer_entity)
	else:
		prc = ledger.post(kind, JWIds.idx_account(buyer_agent, JWIds.ACC_CASH), row_cash,
				value, q, s, 0, buyer_entity)
	if prc != JWResult.OK:
		return 0
	# 数量已按交付余额封顶，record_import 不应再截短；截短说明两处口径不一致，按故障处理。
	var before: int = world.f_imports_uqs[s]
	var rc_i: int = world.record_import(s, q, value)
	if rc_i != JWResult.OK:
		_raise(rc_i, s, q)
		return 0
	if world.f_imports_uqs[s] - before != q:
		_raise(JWResult.Fault.STOCK_IDENTITY, s, q - (world.f_imports_uqs[s] - before))
		return 0
	var mi: int = JWIds.idx_market(s, buyer_class)
	m_imported[mi] = m_imported[mi] + q
	if buyer_class == JWUnits.BuyerClass.HOUSEHOLD:
		var gp: int = JWIds.idx_group_prod(buyer_entity, s)
		_group_spent[gp] = _group_spent[gp] + value
		pop.record_consumption(buyer_entity, s, value, q)
	elif buyer_class == JWUnits.BuyerClass.PUBSERV:
		f_pub_intermediate[buyer_region] = f_pub_intermediate[buyer_region] + value
	elif buyer_class == JWUnits.BuyerClass.FIRM_INPUT:
		var ii: int = JWIds.idx_inv(buyer_entity, s)
		inv_input[ii] = inv_input[ii] + q
		f_purchased[ii] = f_purchased[ii] + q
		var at_base: int = JWMath.mul_div_floor(q, JWUnits.BASE_PRICE, JWUnits.Q_SCALE)
		f_price_variance[buyer_entity] = f_price_variance[buyer_entity] + (at_base - value)
	elif buyer_class == JWUnits.BuyerClass.FIRM_CAPITAL:
		f_capital_bought[buyer_entity] = JWMath.check_amount(f_capital_bought[buyer_entity] + value)
		var ci: int = JWIds.idx_inv(buyer_entity, s)
		_capital_bought_qty[ci] = _capital_bought_qty[ci] + q
	return q


## 一个买方实体对某产品的成交执行：按各卖方 cell 的可售量拆分，逐笔过账并回写实物。
##
## 返回实际成交量（μQ_s，可能小于 qty_req —— 现金不足或过账被拒时缩减，差额由调用方记未满足需求）。
## 故障经 _fault 通道登记，不混进返回值。
func _trade_one(s: int, buyer_class: int, buyer_agent: int, buyer_region: int, buyer_entity: int,
		qty_req: int, price: int, kind: int, pop: JWPopulation, world: JWWorldMarket,
		ledger: JWLedger, accounts: JWAccount) -> int:
	if qty_req <= 0:
		return 0
	# R-IMPORT-01：本档进口计划按请求量比例分到本买方实体，先向外部购买。
	# 进口部分无论成交与否都不转向国内卖方：国内可供量已按「国内需求」配给给各档，
	# 把买不起的进口改成国内采购会挤占后面各档的配额；缺口记未满足需求。
	var done_imp: int = 0
	if _cur_imp_plan > 0 and _cur_plan > 0 and world != null:
		# rounding: floor, reason=按比例分进口计划，Σ 各实体 ≤ 本档计划
		var imp_req: int = mini(JWMath.mul_div_floor(qty_req, _cur_imp_plan, _cur_plan), qty_req)
		imp_req = mini(imp_req, world.delivery_remaining(s))
		if imp_req > 0:
			done_imp = _trade_import(s, buyer_class, buyer_agent, buyer_region, buyer_entity,
					imp_req, kind, pop, world, ledger, accounts)
			if _fault != 0:
				return done_imp
			qty_req -= imp_req
			if qty_req <= 0:
				return done_imp
	var total_avail: int = 0
	for r: int in JWUnits.R:
		var av: int = _avail_of(JWIds.idx_cell(r, s))
		_w4[r] = av
		total_avail += av
	if total_avail <= 0:
		return done_imp
	var want: int = qty_req
	if want > total_avail:
		want = total_avail
	var rc: int = JWMath.split_lr_into(want, _w4, _t4, _o4)
	if JWMath._split_last_fault != 0:
		_raise(rc, s, buyer_class)
		return done_imp
	var done: int = 0
	for r: int in JWUnits.R:
		var qty: int = _o4[r]
		if qty <= 0:
			continue
		var seller_cell: int = JWIds.idx_cell(r, s)
		var seller_agent: int = JWIds.agent_of_cell(seller_cell)
		if seller_agent == buyer_agent:
			# 自产自用不经市场：post() 的前置是两端不同（INV-015）。差额留给未满足需求，不静默成交。
			continue
		# buyer_region < 0 表示「没有国内收货地」（出口与中央政府采购），不加区间物流成本。
		var logistics: int = 0
		if buyer_region >= 0 and r != buyer_region:
			logistics = logistics_cost_ppm[JWIds.idx_od(r, buyer_region)]
		var cash: int = accounts.cash_of(buyer_agent)
		if buyer_class == JWUnits.BuyerClass.HOUSEHOLD:
			# INV-063：居民本季可花的钱以 consumption_budget_into 给出的分产品预算为准，
			# 而不是账上现金——否则跨区物流加成会把支出顶出预算之外，把「被迫储蓄」吃掉。
			var rem: int = _group_budget[JWIds.idx_group_prod(buyer_entity, s)] \
					- _group_spent[JWIds.idx_group_prod(buyer_entity, s)]
			if rem < cash:
				cash = rem
		var qty_eff: int = _affordable_qty(qty, price, logistics, cash)
		if qty_eff <= 0:
			continue
		var value: int = _trade_value(qty_eff, price, logistics)
		if value <= 0:
			continue
		var prc: int = JWResult.OK
		if buyer_class == JWUnits.BuyerClass.FIRM_CAPITAL:
			# R-INVEST-01：四腿——卖方现金 +V（第 0 腿，承载 I 类分类与数量）、买方现金 −V、
			# 买方资本 +V、卖方净值 −V（权益增记负）。买方现金换资本、净值不变；卖方收入进净值。
			_cap_legs_acc[0] = JWIds.idx_account(seller_agent, JWIds.ACC_CASH)
			_cap_legs_acc[1] = JWIds.idx_account(buyer_agent, JWIds.ACC_CASH)
			_cap_legs_acc[2] = JWIds.idx_account(buyer_agent, JWIds.ACC_CAPITAL)
			_cap_legs_acc[3] = JWIds.idx_account(seller_agent, JWIds.ACC_NW)
			_cap_legs_d[0] = value
			_cap_legs_d[1] = -value
			_cap_legs_d[2] = value
			_cap_legs_d[3] = -value
			prc = ledger.post_multi(kind, _cap_legs_acc, _cap_legs_d, qty_eff, s, 0, buyer_entity)
		else:
			prc = ledger.post(kind, JWIds.idx_account(buyer_agent, JWIds.ACC_CASH),
					JWIds.idx_account(seller_agent, JWIds.ACC_CASH), value, qty_eff, s, 0, buyer_entity)
		if prc != JWResult.OK:
			# 过账被拒（现金不足等）：**不动任何实物**，该笔转未满足需求。禁止静默改账。
			continue
		_take_from_seller(seller_cell, qty_eff)
		f_sold[seller_cell] = f_sold[seller_cell] + qty_eff
		done += qty_eff
		# 买方侧的账：入库方按基年价计值并记价差（docs/10 §2.3、INV-119），不入库方不产生价差。
		if buyer_class == JWUnits.BuyerClass.HOUSEHOLD:
			var gp: int = JWIds.idx_group_prod(buyer_entity, s)
			_group_spent[gp] = _group_spent[gp] + value
			pop.record_consumption(buyer_entity, s, value, qty_eff)
		elif buyer_class == JWUnits.BuyerClass.PUBSERV:
			f_pub_intermediate[buyer_region] = f_pub_intermediate[buyer_region] + value
		elif buyer_class == JWUnits.BuyerClass.GOV_PROCUREMENT:
			# 中央采购没有收货地区，先按**卖方**地区记账，成交完再按各地区服务容量归属到 pubserv。
			_gov_value_by_region[r] = _gov_value_by_region[r] + value
		elif buyer_class == JWUnits.BuyerClass.FIRM_INPUT:
			var ii: int = JWIds.idx_inv(buyer_entity, s)
			inv_input[ii] = inv_input[ii] + qty_eff
			f_purchased[ii] = f_purchased[ii] + qty_eff
			# 价差 = at_base(qty) − 实付（docs/10 §2.3、INV-119）。R-SCALE-01 之后基价 1e9 μU/Q ≠ Q_SCALE 1e6，
			# μQ 与 μU 不再数值相等，必须显式按基价折算；旧写法 (qty − value) 让价差恒约等于 −实付额。
			var at_base: int = JWMath.mul_div_floor(qty_eff, JWUnits.BASE_PRICE, JWUnits.Q_SCALE)
			f_price_variance[buyer_entity] = f_price_variance[buyer_entity] + (at_base - value)
		elif buyer_class == JWUnits.BuyerClass.EXPORT:
			world.record_export(s, qty_eff, value)
		elif buyer_class == JWUnits.BuyerClass.FIRM_CAPITAL:
			f_capital_bought[buyer_entity] = JWMath.check_amount(f_capital_bought[buyer_entity] + value)
			var ci: int = JWIds.idx_inv(buyer_entity, s)
			_capital_bought_qty[ci] = _capital_bought_qty[ci] + qty_eff
	return done + done_imp

# ── 方法 ───────────────────────────────────────────────────────────────────

## S03 §3.1：登记本季目标库存（由 JWSectorModel 在制定计划时调用）。
## 步骤：S03 §3.1
## 前置：storable == 0 的部门目标恒为 0
## 后置：m_inv_target[cell] >= 0
## 不变量：INV-049（不可库存部门期末库存恒为 0）
## 失败：无
func set_inventory_target(cell: int, target_uqs: int) -> void:
	if cell < 0 or cell >= JWUnits.CELL:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
		return
	# 不可库存部门的目标由调用方保证为 0（storable 在 JWIoTable，本函数签名里没有它）；
	# 这里只兜住「负目标」这一条：负的目标库存没有任何业务含义，会让 §5.6 的补库需求变成负数。
	var v: int = target_uqs
	if v < 0:
		v = 0
	m_inv_target[cell] = JWMath.check_qty(v)


## R-ORDER-01：登记某 cell 对投入品 j 的目标存量（下标 idx_inv(cell, j)）。
## 步骤：S03 §3.1（JWSectorModel.plan_output 调用）
## 前置：qty >= 0
## 后置：_input_target[idx] = qty；本季 collect_demand 按它形成投入品补库需求
## 不变量：INV-050（本季购入供下季使用）
## 失败：越界 / 负量 → INDEX_OUT_OF_RANGE
func set_input_target(idx: int, qty_uqs: int) -> void:
	if idx < 0 or idx >= _input_target.size() or qty_uqs < 0:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, idx, qty_uqs)
		return
	_input_target[idx] = JWMath.check_qty(qty_uqs)
	_input_target_armed = true


## S05 入口：快照期初库存，供步末的库存恒等式检查。
## 步骤：S05 §5.1 开始
## 前置：phase == S05
## 后置：_inv_*_start 与当前库存逐位相同
## 不变量：INV-047
## 失败：无
func begin_production() -> void:
	for i: int in JWUnits.CELL:
		_inv_output_start[i] = inv_output[i]
	for i: int in JWUnits.INV_N:
		_inv_input_start[i] = inv_input[i]



## 载入后重建季初快照（内容开局与读档共用；与 begin_production 的快照语义一致）。
## 步骤：LOAD（JWSimState.finalize_load 调用，早于 check_all_p0）
## 前置：库存与本季流量已由 set_state_array 写入；output_actual_uqs 是 JWSectorModel 已载入的本季实际产出
## 后置：可库存 cell：_inv_output_start = 期末 − 产出 + 售出 + 损耗，_direct_avail = 0；
##        不可库存 cell：_inv_output_start = 0，_direct_avail = 产出 − 售出 − 损耗（本季未售而作废的量）；
##        投入品：_inv_input_start = 期末 − 购入 + 耗用 + 损耗
## 不变量：INV-047 的逐 cell 恒等式在载入后按构造成立；以下仍是**真检查**，反推不替它们背书——
##          反推出的期初与作废量不得为负（否则存档里售出多于可售）、INV-049 不可库存部门库存恒为 0、
##          以及 check_stock_identity 里 Σ售出 == Σ成交、成交 + 未满足 == 需求 这两条跨主体对账
## 失败：INDEX_OUT_OF_RANGE / NEGATIVE_INVENTORY / ENERGY_STORED
##
## 为什么是反推：三个缓冲都是季内私有中间量，不在状态块协议里。内容开局时流量全 0，反推即「期初 = 当前」；
## 读档时存档带有上季全部流量，反推结果与原进程 S05 入口快照逐位相同。
func rebase_after_load(output_actual_uqs: PackedInt64Array, io: JWIoTable) -> int:
	if output_actual_uqs.size() != JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				output_actual_uqs.size(), JWUnits.CELL)
	if io == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	for cell: int in JWUnits.CELL:
		var net: int = output_actual_uqs[cell] - f_sold[cell] - f_sold_direct[cell] - f_spoilage_out[cell]
		if io.is_storable(JWIds.sector_of_cell(cell)):
			_direct_avail[cell] = 0
			var start: int = inv_output[cell] - net
			if start < 0:
				return JWResult.raise_fault(JWResult.Fault.NEGATIVE_INVENTORY, cell, start)
			_inv_output_start[cell] = start
		else:
			if inv_output[cell] != 0:
				return JWResult.raise_fault(JWResult.Fault.ENERGY_STORED, cell, inv_output[cell])
			if net < 0:
				return JWResult.raise_fault(JWResult.Fault.NEGATIVE_INVENTORY, cell, net)
			_inv_output_start[cell] = 0
			_direct_avail[cell] = net
	for idx: int in JWUnits.INV_N:
		var start_in: int = inv_input[idx] - f_purchased[idx] + f_consumed[idx] + f_spoilage_in[idx]
		if start_in < 0:
			return JWResult.raise_fault(JWResult.Fault.NEGATIVE_INVENTORY, idx, start_in)
		_inv_input_start[idx] = start_in
	return JWResult.OK

## S05 §5.4：从 q_actual 反算并扣减投入品（ceil，保证不透支）。
## 步骤：S05 §5.4
## 前置：q_actual <= floor(avail × 1e6 / a)（由 §5.3 的 bound_materials 保证）
## 后置：inv_input 减少 use；f_consumed 增加 use；inv_input >= 0
## 不变量：INV-046（整数引理 T-U-CEIL-SAFE）、INV-047、INV-048、INV-050（只用期初库存）
## 失败：use > avail → Fault.NEGATIVE_INVENTORY（说明 q_actual 推导有误），终止保留现场
func consume_inputs(cell: int, q_actual_uqs: int, io: JWIoTable) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
	if io == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, cell, 0)
	if q_actual_uqs < 0:
		# 负产量会把「扣减」变成「凭空入库」。不夹逼、不吞掉，直接暴露 q_actual 的推导缺陷。
		return JWResult.raise_fault(JWResult.Fault.NEGATIVE_INVENTORY, cell, q_actual_uqs)
	if q_actual_uqs == 0:
		return JWResult.OK
	var s: int = JWIds.sector_of_cell(cell)
	# 固定顺序 agri → manu → services，**不含 energy**：电力当期使用、不入库存（§5.2/INV-051）。
	for j: int in JWUnits.S:
		if j == JWUnits.Sector.ENERGY:
			continue
		var a: int = io.input_of(cell, j)
		if a == 0:
			# 零系数跳过，不做除零，也不用 max(a,1) 代替（INV-044）。
			continue
		# rounding: ceil, reason=docs/12 §5.4「不少耗料」。
		# ceil(q×a/1e6) == −floor(−q×a/1e6)，经 mul_div_floor 走，避免 q×a 的中间溢出（R-SCALE-01）。
		var use: int = -JWMath.mul_div_floor(-q_actual_uqs, a, JWUnits.Q_SCALE)
		if use <= 0:
			continue
		var idx: int = JWIds.idx_inv(cell, j)
		var avail: int = inv_input[idx]
		if use > avail:
			# 整数引理 T-U-CEIL-SAFE 说这不可能发生；真发生了就是 §5.3 的 bound_materials 算错了。
			return JWResult.raise_fault(JWResult.Fault.NEGATIVE_INVENTORY, idx, use - avail)
		inv_input[idx] = avail - use
		f_consumed[idx] = f_consumed[idx] + use
	return JWResult.OK


## S05 §5.4：成品入库（storable == 1）或直接进当期供给（storable == 0）。
## 步骤：S05 §5.4
## 前置：q_actual >= 0
## 后置：storable == 1 → inv_output += q_actual；storable == 0 → 期末库存恒为 0
## 不变量：INV-049（energy 与 services 期末库存恒为 0）、INV-047
## 失败：不可库存部门被写入库存 → Fault.ENERGY_STORED
##
## 调用约定：`q_actual_uqs` 必须与 `flow.cell.output_actual_uqs[cell]` 逐位相同——
## check_stock_identity 用后者做「生产」项，两者不一致会让 INV-047 报出与病因无关的残差。
## 能源 cell 也照此传入**全部产量**（自用与作废在 §5.2 内部净出，不进本类的任何账）。
func store_output(cell: int, q_actual_uqs: int, io: JWIoTable) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
	if io == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, cell, 0)
	if q_actual_uqs < 0:
		return JWResult.raise_fault(JWResult.Fault.NEGATIVE_INVENTORY, cell, q_actual_uqs)
	var s: int = JWIds.sector_of_cell(cell)
	if io.is_storable(s):
		inv_output[cell] = JWMath.check_qty(inv_output[cell] + q_actual_uqs)
		return JWResult.OK
	# 不可库存：期末库存恒为 0（INV-049）。库存里已有东西说明别处越权写了库存，立刻暴露。
	if inv_output[cell] != 0:
		return JWResult.raise_fault(JWResult.Fault.ENERGY_STORED, cell, inv_output[cell])
	# 产出进入当期供给。能源同样登记在这里（供 INV-047 的恒等式配平），
	# 但它不进市场可售量：电力已在 §5.2 分配完毕（docs/12 §5.6 的 supply 公式）。
	_direct_avail[cell] = JWMath.check_qty(_direct_avail[cell] + q_actual_uqs)
	return JWResult.OK


## S05 §5.6：形成 5 类买方的需求（先全部算完再统一配给，避免先到先得的顺序依赖）。
## 步骤：S05 §5.6
## 前置：居民预算由 JWPopulation 提供；公共服务与政府采购按已预留预算换算；
##       出口按 world.export_demand 与 delivery_capacity 取小
## 后置：m_demand 被填满，买方类顺序固定 0..4
## 不变量：INV-059、INV-063
## 失败：无
func collect_demand(pop: JWPopulation, capital: JWCapital, treasury: JWTreasury,
		world: JWWorldMarket, pricing: JWPricing, accounts: JWAccount,
		params: PackedInt64Array) -> int:
	if pop == null or capital == null or treasury == null or world == null \
			or pricing == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	_fault = 0
	m_demand.fill(0)
	_group_demand.fill(0)
	_firm_demand.fill(0)
	# 资本品需求与成交在本季由 add_capital_demand / execute_trades 重新累计，开市前清零。
	_capital_demand.fill(0)
	f_capital_bought.fill(0)
	_capital_bought_qty.fill(0)
	_pub_demand.fill(0)
	_gov_demand.fill(0)
	_export_demand.fill(0)
	# R-IMPORT-01：缓存本季进口份额与交付余额（S05 入口已重置），供 ration() 划分进口计划。
	for s0: int in JWUnits.S:
		# R-TRADE-PRICE-01：国内越贵，越多需求转向进口（份额仍封顶在 1e6）。
		_imp_share[s0] = world.import_share_ppm[s0] if s0 < world.import_share_ppm.size() else 0
		_imp_share[s0] = mini(JWMath.mul_ppm(_imp_share[s0], world.import_attractiveness_ppm),
				JWUnits.PPM)
		_imp_room[s0] = world.delivery_remaining(s0)

	# ── 可售供给（docs/12 §5.6）────────────────────────────────────────────
	# supply[s] = Σ_r (期初成品库存 + 本季产量) −（services 的施工份额）−（energy 全部）。
	# 可库存部门的「期初 + 本季产量」此刻已经全在 inv_output 里（store_output 已入库）；
	# 不可库存部门在 _direct_avail 里。energy 恒为 0：电力已在 §5.2 分配完。
	for s: int in JWUnits.S:
		var sup: int = 0
		for r: int in JWUnits.R:
			var cell: int = JWIds.idx_cell(r, s)
			var av: int = _avail_of(cell)
			_supply_by_cell[cell] = av
			# 电力：只有电网配给后的剩余进入市场（_avail_of 已按此截取），卖给居民与出口。
			sup += av
		m_supply[s] = sup

	# ── 买方类 0：居民（INV-063，不能花未收到的钱）────────────────────────
	var rc: int = pop.consumption_budget_into(_group_budget, accounts, params)
	if rc != JWResult.OK:
		return rc
	for g: int in JWUnits.GROUP:
		for s: int in JWUnits.S:
			var gp: int = JWIds.idx_group_prod(g, s)
			var budget: int = _group_budget[gp]
			if budget <= 0:
				continue
			var price: int = pricing.price_of(s)
			if price <= 0:
				continue
			# rounding: floor, reason=docs/12 §5.6，预算折数量一律 floor
			var q: int = JWMath.mul_div_floor(budget, JWUnits.Q_SCALE, price)
			_group_demand[gp] = q
			var mi: int = JWIds.idx_market(s, JWUnits.BuyerClass.HOUSEHOLD)
			m_demand[mi] = m_demand[mi] + q

	# ── 买方类 1：公共服务中间投入（上限由 S04 的运行费拨付决定，INV-102）──
	for r: int in JWUnits.R:
		var opex: int = 0
		for k: int in JWUnits.SERVICE_KIND:
			opex += treasury.f_pay_opex[JWIds.idx_opex(r, k)]
		if opex <= 0:
			continue
		for s: int in JWUnits.S:
			_wS[s] = PUBSERV_INPUT_SHARE_PPM[s]
		rc = JWMath.split_lr_into(opex, _wS, _tS, _oS)
		if JWMath._split_last_fault != 0:
			return _raise(rc, r, opex)
		for s: int in JWUnits.S:
			var price: int = pricing.price_of(s)
			if price <= 0 or _oS[s] <= 0:
				continue
			# rounding: floor, reason=预算折数量一律 floor
			var q: int = JWMath.mul_div_floor(_oS[s], JWUnits.Q_SCALE, price)
			_pub_demand[JWIds.idx_cell(r, s)] = q
			var mi: int = JWIds.idx_market(s, JWUnits.BuyerClass.PUBSERV)
			m_demand[mi] = m_demand[mi] + q

	# ── 买方类 2：政府采购（已预留预算换算成数量）──────────────────────────
	# 这笔钱的去向是 pubserv 的中间投入（docs/12 §2.2 第 6 档与 §6.3：政府最终消费 == Σ pubserv 产出），
	# 因此与买方类 1 共用同一张分产品结构表，只是资金来源不同（采购档 vs 运行费档）。
	# R-PROCURE-01：预算 = S04 核定的本季采购额（f_pay_procurement 是 S05 末登记的实付，开市时恒为 0）。
	var gov_budget: int = treasury.f_procure_budget
	var gov_cash: int = accounts.cash_of(JWIds.AGENT_GOV)
	if gov_budget > gov_cash:
		gov_budget = gov_cash
	if gov_budget > 0:
		for s: int in JWUnits.S:
			_wS[s] = PUBSERV_INPUT_SHARE_PPM[s]
		rc = JWMath.split_lr_into(gov_budget, _wS, _tS, _oS)
		if JWMath._split_last_fault != 0:
			return _raise(rc, JWIds.AGENT_GOV, gov_budget)
		for s: int in JWUnits.S:
			var price: int = pricing.price_of(s)
			if price <= 0 or _oS[s] <= 0:
				continue
			# rounding: floor, reason=预算折数量一律 floor
			var q: int = JWMath.mul_div_floor(_oS[s], JWUnits.Q_SCALE, price)
			_gov_demand[s] = q
			var mi: int = JWIds.idx_market(s, JWUnits.BuyerClass.GOV_PROCUREMENT)
			m_demand[mi] = m_demand[mi] + q

	# ── 买方类 3：企业投入与补库（max(0, 目标 − 现有)，受 cell.cash 约束）──
	#
	# 目标存量的取法（R-ORDER-01）：S03 由 JWSectorModel.plan_output 按「下季预期产量 × io 系数 ×
	# (1 + param.inventory_target_ppm)」登记（set_input_target）。本季买进的投入品供下季生产（INV-050），
	# 按本季实耗补货会在计划回升时系统性缺料。未登记时（单元测试直接调本函数）退回旧口径：
	# `本季实耗 × (1 + param.inventory_target_ppm)`。
	var target_ppm: int = params[JWUnits.Param.INVENTORY_TARGET_PPM]
	for cell: int in JWUnits.CELL:
		var need_value: int = 0
		for j: int in JWUnits.S:
			_wS[j] = 0
			var idx: int = JWIds.idx_inv(cell, j)
			var target: int = 0
			if _input_target_armed:
				# R-ORDER-01：按 S03 登记的下季目标存量补库。
				target = _input_target[idx]
			else:
				var used: int = f_consumed[idx]
				if used <= 0:
					continue
				target = used + JWMath.mul_ppm(used, target_ppm)
			var need: int = target - inv_input[idx]
			if need <= 0:
				continue
			var price: int = pricing.price_of(j)
			if price <= 0:
				continue
			_firm_demand[idx] = need
			var v: int = _trade_value(need, price, 0)
			_wS[j] = v
			need_value += v
		if need_value <= 0:
			continue
		# 补货需求按**全额**登记，不在此处按即时现金封顶：此刻企业刚付完工资与电费、本季销售收入尚未到账，
		# 按即时现金封顶会让制造业 cell 系统性地只补回实耗的零头，下季即被材料约束压产（基年螺旋收缩的起点）。
		# 计划书 §06「企业有经营现金，先负担工资和投入」——现金在季内循环。可负担量改由成交时的
		# _trade_one 按当时现金核定（企业投入类排在居民、公服、政采之后成交，届时这三类的货款已到账）。
		# 付不起的部分照常转未满足需求（INV-064），不透支。
		var cash: int = JWUnits.AMOUNT_MAX
		if need_value > cash:
			# 现金不够就按各产品需求金额比例缩减，**不是先到先得**（顺序依赖会让重放不可复现）。
			rc = JWMath.split_lr_into(cash, _wS, _tS, _oS)
			if JWMath._split_last_fault != 0:
				return _raise(rc, cell, cash)
			for j: int in JWUnits.S:
				var idx2: int = JWIds.idx_inv(cell, j)
				if _firm_demand[idx2] <= 0:
					continue
				var price2: int = pricing.price_of(j)
				if price2 <= 0:
					_firm_demand[idx2] = 0
					continue
				# rounding: floor, reason=预算折数量一律 floor
				_firm_demand[idx2] = JWMath.mul_div_floor(_oS[j], JWUnits.Q_SCALE, price2)
		for j: int in JWUnits.S:
			var idx3: int = JWIds.idx_inv(cell, j)
			var q3: int = _firm_demand[idx3]
			if q3 <= 0:
				continue
			var mi: int = JWIds.idx_market(j, JWUnits.BuyerClass.FIRM_INPUT)
			m_demand[mi] = m_demand[mi] + q3

	# ── 买方类 4：出口（基准出口量 × 外部需求，受交付能力封顶）──────────────
	for s: int in JWUnits.S:
		var base_q: int = 0
		if s < world.base_export_uqs.size():
			base_q = world.base_export_uqs[s]
		if base_q <= 0:
			continue
		# 有效外部需求（伙伴通道 × 相对价格）由 world 统一给出，与 record_export 的上限同源。
		var want: int = JWMath.mul_ppm(base_q, world.export_demand_with_partners(s))
		var cap: int = world.delivery_remaining(s)
		if want > cap:
			want = cap
		if want <= 0:
			continue
		_export_demand[s] = want
		var mi: int = JWIds.idx_market(s, JWUnits.BuyerClass.EXPORT)
		m_demand[mi] = m_demand[mi] + want
	return _fault


## R-INVEST-01：登记企业资本品需求（买方类 FIRM_CAPITAL）。
## 步骤：S05 §5.6（collect_demand 之后、ration 之前）
## 前置：invest_intent_uu 是 JWSectorModel 在 S03 算出的投资意愿（μU，按 cell）；split_ppm Σ == 1e6
## 后置：_capital_demand[idx_inv(cell, s)] = 意愿按构成拆到产品后按现价折成数量；m_demand 同步累加
## 不变量：INV-003（金额拆分和恒等）、INV-059（需求逐格登记）
## 失败：长度不符 → INDEX_OUT_OF_RANGE
func add_capital_demand(invest_intent_uu: PackedInt64Array, split_ppm: PackedInt64Array,
		pricing: JWPricing) -> int:
	if invest_intent_uu.size() != JWUnits.CELL or split_ppm.size() != JWUnits.S or pricing == null:
		return _raise(JWResult.Fault.INDEX_OUT_OF_RANGE, invest_intent_uu.size(), JWUnits.CELL)
	for cell: int in JWUnits.CELL:
		var want_uu: int = invest_intent_uu[cell]
		if want_uu <= 0:
			continue
		var rc: int = JWMath.split_lr_into(want_uu, split_ppm, _tS, _oS)
		if JWMath._split_last_fault != 0:
			return _raise(rc, cell, want_uu)
		if rc != 0:
			# 构成全 0（内容未给资本品构成）：不发明分配规则，本 cell 不产生资本品需求。
			continue
		for s: int in JWUnits.S:
			var v: int = _oS[s]
			var price: int = pricing.price_of(s)
			if v <= 0 or price <= 0:
				continue
			# rounding: floor, reason=按现价折数量只取整一次，少买优于凭空多买
			var qty: int = JWMath.mul_div_floor(v, JWUnits.Q_SCALE, price)
			if qty <= 0:
				continue
			_capital_demand[JWIds.idx_inv(cell, s)] = qty
			var mi: int = JWIds.idx_market(s, JWUnits.BuyerClass.FIRM_CAPITAL)
			m_demand[mi] = m_demand[mi] + qty
	return _fault


## R-IMPORT-01：划出产品 s 各买方类的进口计划（写 _imp_plan）。
## 进口计划 = floor(需求 × 进口份额)；出口与中央政府采购不进口；
## 总量超过本季交付余额时按各类计划量以最大余数法压到余额（每类不超过原计划）。
func _plan_imports(s: int) -> int:
	var total: int = 0
	for b: int in JWUnits.BUYER_CLASS_N:
		var mi: int = JWIds.idx_market(s, b)
		var i_b: int = 0
		if _imp_share[s] > 0 and m_demand[mi] > 0 and b != JWUnits.BuyerClass.EXPORT \
				and b != JWUnits.BuyerClass.GOV_PROCUREMENT:
			# rounding: floor, reason=进口计划只取整一次，少进口优于凭空多进口
			i_b = JWMath.mul_ppm(m_demand[mi], _imp_share[s])
		_imp_plan[mi] = i_b
		_w5[b] = i_b
		total += i_b
	var room: int = _imp_room[s]
	if total <= room:
		return JWResult.OK
	if room <= 0:
		for b0: int in JWUnits.BUYER_CLASS_N:
			_imp_plan[JWIds.idx_market(s, b0)] = 0
		return JWResult.OK
	var rc: int = JWMath.split_lr_into(room, _w5, _t5, _o5)
	if JWMath._split_last_fault != 0:
		return _raise(rc, s, room)
	for b1: int in JWUnits.BUYER_CLASS_N:
		var mi1: int = JWIds.idx_market(s, b1)
		_imp_plan[mi1] = mini(_o5[b1], _imp_plan[mi1])
	return JWResult.OK


## S05 §5.6：两级配给（公开优先级 + 档内按需求量比例），两级都完全确定。
## 步骤：S05 §5.6
## 前置：m_supply 与 m_demand 已算完；rationing_priority 来自内容配置
## 后置：Σ alloc == min(可供, Σ 需求)，alloc_i <= requested_i；m_rule 记录实际走的路径
## 不变量：INV-060（配给精确）、INV-061（rationing_rule 与实际路径一致）、INV-003
## 失败：拆分和不等 → Fault.SPLIT_MISMATCH
##
## `rng` 形参不被使用，也**不允许**被使用：两级配给都是完全确定的（docs/12 §5.6「禁止随机分配」）。
## 它留在签名里是为了让「这里没有抽样」成为一条可被静态核对的事实，而不是一句注释。
## 优先级档次取 docs/13 OQ-238 的裁定：`居民 > 公共服务 > 政府采购 > 企业投入 > 出口`，
## 即买方类下标升序（内容包目前没有 `rationing_priority` 字段，见 open_questions）。
@warning_ignore("unused_parameter")
func ration(ration_mode: int, rng: JWRngStreams) -> int:
	_fault = 0
	# 政策旗的定义域是 0|1（docs/12 §5.6）。越界值不得被静默当成优先级配给：
	# 那会让一个坏掉的政策位表现为「政策没生效」，而不是一次可被看见的故障。
	if ration_mode != RATION_MODE_PRIORITY and ration_mode != RATION_MODE_PROPORTIONAL:
		return _raise(JWResult.Fault.INDEX_OUT_OF_RANGE,
				ration_mode, RATION_MODE_PROPORTIONAL)
	for s: int in JWUnits.S:
		var supply: int = m_supply[s]
		if supply < 0:
			return _raise(JWResult.Fault.NEGATIVE_INVENTORY, s, supply)
		# R-IMPORT-01：先划出各买方类的进口计划，国内可供量只对余下的「国内需求」配给。
		var rc_imp: int = _plan_imports(s)
		if rc_imp != JWResult.OK:
			return rc_imp
		var total_demand: int = 0
		for b: int in JWUnits.BUYER_CLASS_N:
			var d: int = m_demand[JWIds.idx_market(s, b)]
			if d < 0:
				return _raise(JWResult.Fault.SPLIT_MISMATCH, JWIds.idx_market(s, b), d)
			_w5[b] = d - _imp_plan[JWIds.idx_market(s, b)]
			total_demand += _w5[b]
		if total_demand <= supply:
			# 供给充足：全额成交，规则记 none（INV-061）。
			m_rule[s] = JWUnits.Rationing.NONE
			for b: int in JWUnits.BUYER_CLASS_N:
				var mi_n: int = JWIds.idx_market(s, b)
				m_traded[mi_n] = _w5[b] + _imp_plan[mi_n]
				m_unmet[mi_n] = m_demand[mi_n] - m_traded[mi_n]
			continue
		if ration_mode == RATION_MODE_PROPORTIONAL:
			# 全比例配给（gov.ration_mode == 1）：一次最大余数法，Σ alloc 精确等于 supply。
			# 权重就是各买方类的需求量（§5.6 第二级「档内按需求量比例」，INV-003）；
			# 决胜键 _t5 是恒定的买方类下标升序，故结果与调用顺序无关（无 rng 参与）。
			var rc: int = JWMath.split_lr_into(supply, _w5, _t5, _o5)
			if JWMath._split_last_fault != 0:
				return _raise(rc, s, supply)
			m_rule[s] = JWUnits.Rationing.PROPORTIONAL
		else:
			# 公开优先级：逐档满足，后面的吃剩余。档内只有一个买方类，无需第二级拆分。
			var remaining: int = supply
			for b: int in JWUnits.BUYER_CLASS_N:
				var take: int = _w5[b]
				if take > remaining:
					take = remaining
				_o5[b] = take
				remaining -= take
			m_rule[s] = JWUnits.Rationing.PRIORITY
		var assigned: int = 0
		for b: int in JWUnits.BUYER_CLASS_N:
			var alloc: int = _o5[b]
			if alloc > _w5[b]:
				# alloc_i <= requested_i 是 INV-060 的后半条，越界即拆分逻辑坏了。
				return _raise(JWResult.Fault.SPLIT_MISMATCH, JWIds.idx_market(s, b), alloc)
			var mi_r: int = JWIds.idx_market(s, b)
			m_traded[mi_r] = alloc + _imp_plan[mi_r]
			m_unmet[mi_r] = m_demand[mi_r] - m_traded[mi_r]
			assigned += alloc
		if assigned != supply:
			return _raise(JWResult.Fault.SPLIT_MISMATCH, s, assigned - supply)
	return _fault


## S05 §5.6：成交过账（金额与实物各自双边入账；跨区加物流成本；入库方产生价差）。
## 步骤：S05 §5.6
## 前置：ration() 已完成
## 后置：卖方库存减少量精确等于 Σ traded；买方若入库则按基年价计值并记 price_variance；
##       未成交的居民预算留作现金（被迫储蓄）并记 unmet_consumption
## 不变量：INV-059、INV-062、INV-064、INV-015、INV-016、INV-119（价差逐笔可追溯）
## 失败：买方现金不足 → 成交量缩减并记未满足需求（**没有任何路径可以产生凭空的货**）
func execute_trades(pop: JWPopulation, capital: JWCapital, treasury: JWTreasury,
		world: JWWorldMarket, pricing: JWPricing, ledger: JWLedger,
		accounts: JWAccount) -> int:
	if pop == null or capital == null or treasury == null or world == null \
			or pricing == null or ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	_fault = 0
	_group_spent.fill(0)
	_gov_value_by_region.fill(0)
	# 遍历顺序固定：**买方类升序** × 产品升序 × 买方实体升序 × 卖方地区升序（INV-008）。
	# 买方类在外：docs/12 §5.1 第 7 步「居民消费 → 公共服务采购 → 政府采购 → 企业投入与补库 → 出口」。
	# 原实现是产品在外，农产品的企业投入交易排在制成品卖给居民之前，制造业买投入时尚未收到本季货款，
	# 系统性地买不起投入。配给量已由 ration() 逐（产品, 买方类）定死，改变执行次序只改变季内现金到账的先后。
	for mi0: int in JWUnits.MARKET_N:
		_planned_copy[mi0] = m_traded[mi0]
	for b: int in JWUnits.BUYER_CLASS_N:
		for s: int in JWUnits.S:
			var price: int = pricing.price_of(s)
			if price <= 0:
				continue
			var mi: int = JWIds.idx_market(s, b)
			var planned: int = m_traded[mi]
			if planned <= 0:
				m_traded[mi] = 0
				m_unmet[mi] = m_demand[mi]
				continue
			var done: int = 0
			_cur_imp_plan = _imp_plan[mi]
			_cur_plan = planned
			if b == JWUnits.BuyerClass.HOUSEHOLD:
				# 先把本档成交量按各组需求量拆到 36 个组，再逐组对四个卖方拆分。
				for g: int in JWUnits.GROUP:
					_w36[g] = _group_demand[JWIds.idx_group_prod(g, s)]
				var rc: int = JWMath.split_lr_into(planned, _w36, _t36, _o36)
				if JWMath._split_last_fault != 0:
					return _raise(rc, mi, planned)
				for g: int in JWUnits.GROUP:
					if _o36[g] <= 0:
						continue
					done += _trade_one(s, b, JWIds.agent_of_group(g), JWIds.region_of_group(g),
							g, _o36[g], price, JWUnits.Kind.HOUSEHOLD_CONSUMPTION,
							pop, world, ledger, accounts)
			elif b == JWUnits.BuyerClass.PUBSERV:
				for r: int in JWUnits.R:
					_w4[r] = _pub_demand[JWIds.idx_cell(r, s)]
				var rc2: int = JWMath.split_lr_into(planned, _w4, _t4, _o4)
				if JWMath._split_last_fault != 0:
					return _raise(rc2, mi, planned)
				# 公共服务没有自有现金，付款由 gov 执行（docs/10 §2.1）；货进 pubserv 的中间消耗。
				for r: int in JWUnits.R:
					if _o4[r] <= 0:
						continue
					done += _trade_one(s, b, JWIds.AGENT_GOV, r, r, _o4[r], price,
							JWUnits.Kind.GOV_PROCUREMENT, pop, world, ledger, accounts)
			elif b == JWUnits.BuyerClass.GOV_PROCUREMENT:
				# 中央采购是单一买方（agent.gov），无收货地区，故不加物流成本（buyer_region = −1）。
				done = _trade_one(s, b, JWIds.AGENT_GOV, -1, JWIds.AGENT_GOV,
						planned, price, JWUnits.Kind.GOV_PROCUREMENT, pop, world, ledger, accounts)
			elif b == JWUnits.BuyerClass.FIRM_INPUT:
				for cell: int in JWUnits.CELL:
					_w16[cell] = _firm_demand[JWIds.idx_inv(cell, s)]
				var rc3: int = JWMath.split_lr_into(planned, _w16, _t16, _o16)
				if JWMath._split_last_fault != 0:
					return _raise(rc3, mi, planned)
				for cell: int in JWUnits.CELL:
					if _o16[cell] <= 0:
						continue
					done += _trade_one(s, b, JWIds.agent_of_cell(cell),
							JWIds.region_of_cell(cell), cell, _o16[cell], price,
							JWUnits.Kind.INTERMEDIATE_PURCHASE, pop, world, ledger, accounts)
			elif b == JWUnits.BuyerClass.EXPORT:
				# 出口：对手方是 agent.row。交货地视同卖方所在地区，不加区内物流成本。
				done = _trade_one(s, b, JWIds.AGENT_ROW, -1, s, planned, price,
						JWUnits.Kind.EXPORT, pop, world, ledger, accounts)
			elif b == JWUnits.BuyerClass.FIRM_CAPITAL:
				# R-INVEST-01：资本品购买。先按各 cell 需求量拆本档成交量，再逐 cell 对卖方拆分。
				for cell_k: int in JWUnits.CELL:
					_w16[cell_k] = _capital_demand[JWIds.idx_inv(cell_k, s)]
				var rc5: int = JWMath.split_lr_into(planned, _w16, _t16, _o16)
				if JWMath._split_last_fault != 0:
					return _raise(rc5, mi, planned)
				for cell_k: int in JWUnits.CELL:
					if _o16[cell_k] <= 0:
						continue
					done += _trade_one(s, b, JWIds.agent_of_cell(cell_k),
							JWIds.region_of_cell(cell_k), cell_k, _o16[cell_k], price,
							JWUnits.Kind.CAPITAL_PURCHASE, pop, world, ledger, accounts)
			if _fault != 0:
				return _fault
			if done > planned:
				return _raise(JWResult.Fault.DOUBLE_ALLOCATION, mi, done - planned)
			# 缩减掉的量（现金不足、自产自用、过账被拒）一律转未满足需求：
			# Σ 成交 + Σ 未满足 == Σ 需求 逐格精确成立（INV-059/INV-064）。
			m_traded[mi] = done
			m_unmet[mi] = m_demand[mi] - done
	# 第二轮：企业投入与资本品在拿到本季**全部**货款（含出口与其它企业的采购）之后，
	# 按 ration() 为该类预留而第一轮因现金不足未成交的量再试一次。计划书 §06「企业有经营现金，
	# 先负担工资和投入」——现金在季内循环；不引入赊账。上限仍是配给给该类的计划量，优先级不变。
	var second: PackedInt64Array = PackedInt64Array([JWUnits.BuyerClass.FIRM_INPUT,
			JWUnits.BuyerClass.FIRM_CAPITAL])
	for b2: int in second:
		for s2: int in JWUnits.S:
			var price2: int = pricing.price_of(s2)
			if price2 <= 0:
				continue
			var mi2: int = JWIds.idx_market(s2, b2)
			var room: int = _planned_copy[mi2] - m_traded[mi2]
			if room <= 0:
				continue
			var resid_sum: int = 0
			for cell2: int in JWUnits.CELL:
				var ii: int = JWIds.idx_inv(cell2, s2)
				var want2: int = 0
				if b2 == JWUnits.BuyerClass.FIRM_INPUT:
					want2 = _firm_demand[ii] - f_purchased[ii]
				else:
					want2 = _capital_demand[ii] - _capital_bought_qty[ii]
				if want2 < 0:
					want2 = 0
				_w16[cell2] = want2
				resid_sum += want2
			if resid_sum <= 0:
				continue
			var take: int = mini(room, resid_sum)
			_cur_imp_plan = maxi(0, _imp_plan[mi2] - m_imported[mi2])
			_cur_plan = room
			var rc6: int = JWMath.split_lr_into(take, _w16, _t16, _o16)
			if JWMath._split_last_fault != 0:
				return _raise(rc6, mi2, take)
			var kind2: int = JWUnits.Kind.INTERMEDIATE_PURCHASE
			if b2 == JWUnits.BuyerClass.FIRM_CAPITAL:
				kind2 = JWUnits.Kind.CAPITAL_PURCHASE
			var done2: int = 0
			for cell3: int in JWUnits.CELL:
				if _o16[cell3] <= 0:
					continue
				done2 += _trade_one(s2, b2, JWIds.agent_of_cell(cell3),
						JWIds.region_of_cell(cell3), cell3, _o16[cell3], price2,
						kind2, pop, world, ledger, accounts)
			if _fault != 0:
				return _fault
			if done2 > room:
				return _raise(JWResult.Fault.DOUBLE_ALLOCATION, mi2, done2 - room)
			m_traded[mi2] = m_traded[mi2] + done2
			m_unmet[mi2] = m_demand[mi2] - m_traded[mi2]
	_cur_imp_plan = 0
	_cur_plan = 0
	# 政府采购的货最终进 pubserv 的中间消耗；按各地区服务容量归属（无容量则不归属）。
	var gov_total: int = 0
	for r: int in JWUnits.R:
		gov_total += _gov_value_by_region[r]
	if gov_total > 0:
		var wsum: int = 0
		for r: int in JWUnits.R:
			var capr: int = capital.pubserv_capacity(r)
			_w4[r] = capr
			wsum += capr
		if wsum > 0:
			var rc4: int = JWMath.split_lr_into(gov_total, _w4, _t4, _o4)
			if JWMath._split_last_fault != 0:
				return _raise(rc4, JWIds.AGENT_GOV, gov_total)
			for r: int in JWUnits.R:
				f_pub_intermediate[r] = f_pub_intermediate[r] + _o4[r]
	# 未成交的居民预算留作现金（被迫储蓄），显式登记，不允许静默消失（INV-064）。
	for g: int in JWUnits.GROUP:
		var left: int = 0
		for s: int in JWUnits.S:
			var gp: int = JWIds.idx_group_prod(g, s)
			left += _group_budget[gp] - _group_spent[gp]
		if left > 0:
			pop.record_unmet_consumption(g, left)
	# 未满足需求按卖方摊回 cell（S03 §3.1 的 D_prev 用的是「成交 + 未满足」的 cell 口径）。
	for s: int in JWUnits.S:
		var unmet_s: int = 0
		for b: int in JWUnits.BUYER_CLASS_N:
			unmet_s += m_unmet[JWIds.idx_market(s, b)]
		if unmet_s <= 0:
			continue
		var wsum2: int = 0
		for r: int in JWUnits.R:
			var w: int = _supply_by_cell[JWIds.idx_cell(r, s)]
			_w4[r] = w
			wsum2 += w
		if wsum2 == 0:
			# 本部门整季一件也没产出：未满足需求没有「按产量摊回」的依据，均摊到四个 cell。
			for r: int in JWUnits.R:
				_w4[r] = 1
		var rc5: int = JWMath.split_lr_into(unmet_s, _w4, _t4, _o4)
		if JWMath._split_last_fault != 0:
			return _raise(rc5, s, unmet_s)
		for r: int in JWUnits.R:
			var c: int = JWIds.idx_cell(r, s)
			f_unmet_demand[c] = f_unmet_demand[c] + _o4[r]
	return _fault


## S05 §5.7：公共服务交付与排队。
## 步骤：S05 §5.7
## 前置：availability_ppm 是上季 S07 的结果（本季只读）
## 后置：delivered <= mul_ppm(capacity_active, availability_ppm)；
##       未获服务人数按各组需求用最大余数法摊回 queue_persons
## 不变量：INV-103、INV-102（**不得降 capacity_active、不得删资产**）
## 失败：无（交付不足是业务结果）
##
## 需求口径：`content.base_delivered_service[]`（108 == 群组 × 服务种类，μQ）。
## 它是剧本登记的各组服务需求量；本函数只读它，不写 capital 的任何字段（INV-102）。
func deliver_public_services(capital: JWCapital, pop: JWPopulation) -> int:
	if capital == null or pop == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	_fault = 0
	for r: int in JWUnits.R:
		# 1) 本地区各服务种类的需求（按组求和）。
		var need_total: int = 0
		for k: int in JWUnits.SERVICE_KIND:
			var nk: int = 0
			for a: int in JWUnits.A:
				for sk: int in JWUnits.K:
					var g: int = JWIds.idx_group(r, a, sk)
					nk += pop.base_delivered_service[JWIds.idx_group_svc(g, k)]
			_w3[k] = nk
			need_total += nk
		# 2) 可交付量：容量 × 可用率（INV-103 的上界），与需求取小。
		var funded: int = JWMath.mul_ppm(capital.pubserv_capacity(r), capital.availability(r))
		var delivered: int = funded
		if delivered > need_total:
			delivered = need_total
		if delivered < 0:
			delivered = 0
		f_pub_delivered[r] = delivered
		if need_total <= 0:
			for k: int in JWUnits.SERVICE_KIND:
				pub_queue[JWIds.idx_pubserv_queue(r, k)] = 0
			continue
		# 3) 交付量按各服务种类的需求比例分配（最大余数法，种类下标决胜）。
		var rc: int = JWMath.split_lr_into(delivered, _w3, _t3, _o3)
		if JWMath._split_last_fault != 0:
			return _raise(rc, r, delivered)
		# 4) 未获服务人数：按各组需求把「未满足比例」摊回人头（最大余数法，组下标决胜）。
		for k: int in JWUnits.SERVICE_KIND:
			var need_k: int = _w3[k]
			var unmet_k: int = need_k - _o3[k]
			var qi: int = JWIds.idx_pubserv_queue(r, k)
			if need_k <= 0 or unmet_k <= 0:
				pub_queue[qi] = 0
				continue
			var persons: int = 0
			var slot: int = 0
			for a: int in JWUnits.A:
				for sk: int in JWUnits.K:
					var g: int = JWIds.idx_group(r, a, sk)
					_w9[slot] = pop.base_delivered_service[JWIds.idx_group_svc(g, k)]
					persons += pop.population[g]
					slot += 1
			# rounding: floor, reason=排队人数宁可少报也不虚报（docs/10 §0.10）
			var unserved: int = JWMath.mul_div_floor(persons, unmet_k, need_k)
			var rc2: int = JWMath.split_lr_into(unserved, _w9, _t9, _o9)
			if JWMath._split_last_fault != 0:
				return _raise(rc2, qi, unserved)
			var back: int = 0
			for i: int in _o9.size():
				back += _o9[i]
			pub_queue[qi] = back
	return _fault


## S05 §5.8：损耗与期末库存结转。
## 步骤：S05 §5.8
## 前置：全部交易已完成
## 后置：spoilage 显式登记并计入中间消耗；库存 >= 0
## 不变量：INV-053（不允许用「盘点差异」吸收）、INV-048
## 失败：库存为负 → Fault.NEGATIVE_INVENTORY
func apply_spoilage(io: JWIoTable) -> int:
	if io == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	for cell: int in JWUnits.CELL:
		var s: int = JWIds.sector_of_cell(cell)
		var stock: int = inv_output[cell]
		if stock < 0:
			return JWResult.raise_fault(JWResult.Fault.NEGATIVE_INVENTORY, cell, stock)
		if stock > 0:
			# rounding: floor, reason=损耗按 floor，少毁优于多毁；余数留在库存里，不做盘点差异
			var loss: int = JWMath.mul_ppm(stock, io.spoilage(s))
			if loss < 0 or loss > stock:
				return JWResult.raise_fault(JWResult.Fault.NEGATIVE_INVENTORY, cell, stock - loss)
			inv_output[cell] = stock - loss
			f_spoilage_out[cell] = f_spoilage_out[cell] + loss
		for j: int in JWUnits.S:
			var idx: int = JWIds.idx_inv(cell, j)
			var st: int = inv_input[idx]
			if st < 0:
				return JWResult.raise_fault(JWResult.Fault.NEGATIVE_INVENTORY, idx, st)
			if st == 0:
				continue
			# 损耗率是产品的属性：投入品 j 用 j 自己的 spoilage_ppm。
			var loss2: int = JWMath.mul_ppm(st, io.spoilage(j))
			if loss2 < 0 or loss2 > st:
				return JWResult.raise_fault(JWResult.Fault.NEGATIVE_INVENTORY, idx, st - loss2)
			inv_input[idx] = st - loss2
			f_spoilage_in[idx] = f_spoilage_in[idx] + loss2
	return JWResult.OK


## S05 末：逐 cell 逐品种的库存恒等式检查。
## 步骤：S05 §5.8 末
## 前置：begin_production() 已在本步入口调用
## 后置：不改状态
## 不变量：INV-047（期末 == 期初 + 生产 + 购入 − 售出 − 生产耗用 − 损耗）、INV-059
## 失败：Fault.STOCK_IDENTITY，detail_a = idx_inv，detail_b = 残差
##
## 成品侧写成一条对可库存与不可库存都成立的式子：
##   `inv_output + _direct_avail == 期初 + 生产 − 售出 − 损耗`
## 可库存部门 `_direct_avail == 0`，退化成契约原式；
## 不可库存部门 `inv_output == 期初 == 损耗 == 0`，`_direct_avail` 正是「本季未售出而作废的产出」，
## 于是 INV-049（期末库存恒为 0）与 INV-047 用同一条断言一起被检查，而不是给能源与服务开一个豁免口子。
func check_stock_identity(output_actual_uqs: PackedInt64Array) -> int:
	if output_actual_uqs.size() != JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				output_actual_uqs.size(), JWUnits.CELL)
	for cell: int in JWUnits.CELL:
		var lhs: int = inv_output[cell] + _direct_avail[cell]
		var rhs: int = _inv_output_start[cell] + output_actual_uqs[cell] \
				- f_sold[cell] - f_sold_direct[cell] - f_spoilage_out[cell]
		if lhs != rhs:
			return JWResult.raise_fault(JWResult.Fault.STOCK_IDENTITY, cell, lhs - rhs)
		if inv_output[cell] < 0:
			return JWResult.raise_fault(JWResult.Fault.NEGATIVE_INVENTORY, cell, inv_output[cell])
		for j: int in JWUnits.S:
			var idx: int = JWIds.idx_inv(cell, j)
			var l2: int = inv_input[idx]
			var r2: int = _inv_input_start[idx] + f_purchased[idx] - f_consumed[idx] \
					- f_spoilage_in[idx]
			if l2 != r2:
				return JWResult.raise_fault(JWResult.Fault.STOCK_IDENTITY, idx, l2 - r2)
			if l2 < 0:
				return JWResult.raise_fault(JWResult.Fault.NEGATIVE_INVENTORY, idx, l2)
	# INV-059 的另一半：卖方库存减少量（== Σ f_sold）与市场成交量逐部门相等。
	for s: int in JWUnits.S:
		var sold: int = 0
		for r: int in JWUnits.R:
			sold += f_sold[JWIds.idx_cell(r, s)]
		var traded: int = 0
		for b: int in JWUnits.BUYER_CLASS_N:
			traded += m_traded[JWIds.idx_market(s, b)]
			# R-IMPORT-01：成交里由外部供货的部分不经国内卖方库存。
			sold += m_imported[JWIds.idx_market(s, b)]
		if sold != traded:
			return JWResult.raise_fault(JWResult.Fault.STOCK_IDENTITY, s, sold - traded)
		var demand: int = 0
		var unmet: int = 0
		for b: int in JWUnits.BUYER_CLASS_N:
			demand += m_demand[JWIds.idx_market(s, b)]
			unmet += m_unmet[JWIds.idx_market(s, b)]
		if traded + unmet != demand:
			return JWResult.raise_fault(JWResult.Fault.STOCK_IDENTITY, s,
					traded + unmet - demand)
	return JWResult.OK


## S06 §6.2：成品库存变动（数量口径），供增加值与实际 GDP 计算。
## 步骤：S06 §6.2
## 前置：S05 已完成
## 后置：不改状态
## 不变量：INV-111、INV-117
## 失败：无
func d_inventory_output(cell: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
		return 0
	return inv_output[cell] - _inv_output_start[cell]


## S06 §6.2：投入品库存变动（数量口径，按 cell 汇总）。
## 步骤：S06 §6.2
## 前置：S05 已完成
## 后置：不改状态
## 不变量：INV-111、INV-117
## 失败：无
func d_inventory_input(cell: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
		return 0
	var acc: int = 0
	for j: int in JWUnits.S:
		var idx: int = JWIds.idx_inv(cell, j)
		acc += inv_input[idx] - _inv_input_start[idx]
	return acc


## S06 §6.2：本季耗用投入品合计（数量口径）。
## 步骤：S06 §6.2
## 前置：S05 已完成
## 后置：不改状态
## 不变量：INV-111
## 失败：无
func used_total(cell: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
		return 0
	var acc: int = 0
	for j: int in JWUnits.S:
		acc += f_consumed[JWIds.idx_inv(cell, j)]
	return acc


## S06 §6.2：本季成品损耗（数量口径）。
## 步骤：S06 §6.2
## 前置：S05 已完成
## 后置：不改状态
## 不变量：INV-053
## 失败：无
func spoilage_out(cell: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
		return 0
	return f_spoilage_out[cell]


## S06 §6.2：本季投入品损耗合计（数量口径）。
## 步骤：S06 §6.2
## 前置：S05 已完成
## 后置：不改状态
## 不变量：INV-053
## 失败：无
func spoilage_in_total(cell: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
		return 0
	var acc: int = 0
	for j: int in JWUnits.S:
		acc += f_spoilage_in[JWIds.idx_inv(cell, j)]
	return acc


## S06 §6.6：本季价差（μU，可正可负），进经营结果。
## 步骤：S06 §6.6
## 前置：S05 已完成
## 后置：不改状态
## 不变量：INV-119（价差逐笔可追溯）
## 失败：无
func price_variance(cell: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
		return 0
	return f_price_variance[cell]


## S06 §6.6：全国价差合计（μU），供总量对账。
## 步骤：S06 §6.6
## 前置：S05 已完成
## 后置：不改状态
## 不变量：INV-119
## 失败：无
## R-POWER-01：登记一笔不经市场撮合的入账价差（电网配电）。与市场购投入的价差同一口径：at_base(qty) − 实付。
## 步骤：S05 §5.2
## 前置：cell 合法
## 后置：f_price_variance[cell] += delta
## 不变量：INV-119
## 失败：越界 → INDEX_OUT_OF_RANGE
func add_price_variance(cell: int, delta: int) -> void:
	if cell < 0 or cell >= f_price_variance.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, f_price_variance.size())
		return
	f_price_variance[cell] = JWMath.check_amount(f_price_variance[cell] + delta)


func price_variance_total() -> int:
	return JWMath.sum(f_price_variance)


## §1.6 状态块协议：LOAD 期一次性 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：尚未 allocate
## 后置：inv_output/f_sold/… 长度 CELL，inv_input/f_consumed/… 长度 INV_N，
##       m_demand/m_traded/m_unmet 长度 MARKET_N，pub_queue 长度 PUBSERV_QUEUE_N
## 不变量：INV-136
## 失败：无
func allocate() -> void:
	inv_output.resize(JWUnits.CELL)
	inv_input.resize(JWUnits.INV_N)
	f_consumed.resize(JWUnits.INV_N)
	f_purchased.resize(JWUnits.INV_N)
	f_sold.resize(JWUnits.CELL)
	f_spoilage_out.resize(JWUnits.CELL)
	f_spoilage_in.resize(JWUnits.INV_N)
	f_unmet_demand.resize(JWUnits.CELL)
	f_price_variance.resize(JWUnits.CELL)
	f_sold_direct.resize(JWUnits.CELL)
	f_sold_direct.fill(0)
	m_imported.resize(JWUnits.MARKET_N)
	m_imported.fill(0)
	_imp_share.resize(JWUnits.S)
	_imp_share.fill(0)
	_imp_room.resize(JWUnits.S)
	_imp_room.fill(0)
	_imp_plan.resize(JWUnits.MARKET_N)
	_imp_plan.fill(0)
	_input_target.resize(JWUnits.INV_N)
	_input_target.fill(0)
	_capital_demand.resize(JWUnits.INV_N)
	_capital_demand.fill(0)
	_capital_bought_qty.resize(JWUnits.INV_N)
	_capital_bought_qty.fill(0)
	_planned_copy.resize(JWUnits.MARKET_N)
	_planned_copy.fill(0)
	f_capital_bought.resize(JWUnits.CELL)
	f_capital_bought.fill(0)
	m_supply.resize(JWUnits.S)
	m_demand.resize(JWUnits.MARKET_N)
	m_traded.resize(JWUnits.MARKET_N)
	m_unmet.resize(JWUnits.MARKET_N)
	m_rule.resize(JWUnits.S)
	m_inv_target.resize(JWUnits.CELL)
	f_pub_delivered.resize(JWUnits.PUBSERV)
	f_pub_intermediate.resize(JWUnits.PUBSERV)
	pub_queue.resize(JWUnits.PUBSERV_QUEUE_N)
	_inv_output_start.resize(JWUnits.CELL)
	_inv_input_start.resize(JWUnits.INV_N)
	logistics_cost_ppm.resize(JWUnits.OD_N)
	inv_output.fill(0)
	inv_input.fill(0)
	m_rule.fill(0)
	pub_queue.fill(0)
	_inv_output_start.fill(0)
	_inv_input_start.fill(0)
	logistics_cost_ppm.fill(0)
	# 内部缓冲：构造期一次性定长化，此后长度不变（热路径不分配）。
	_direct_avail.resize(JWUnits.CELL)
	_supply_by_cell.resize(JWUnits.CELL)
	_energy_market_avail.resize(JWUnits.CELL)
	_energy_market_avail.fill(0)
	_group_budget.resize(JWUnits.GROUP_PROD_N)
	_group_demand.resize(JWUnits.GROUP_PROD_N)
	_group_spent.resize(JWUnits.GROUP_PROD_N)
	_firm_demand.resize(JWUnits.INV_N)
	_pub_demand.resize(JWUnits.CELL)
	_gov_demand.resize(JWUnits.S)
	_export_demand.resize(JWUnits.S)
	_gov_value_by_region.resize(JWUnits.R)
	_w3.resize(JWUnits.SERVICE_KIND)
	_t3.resize(JWUnits.SERVICE_KIND)
	_o3.resize(JWUnits.SERVICE_KIND)
	_w4.resize(JWUnits.R)
	_t4.resize(JWUnits.R)
	_o4.resize(JWUnits.R)
	_wS.resize(JWUnits.S)
	_tS.resize(JWUnits.S)
	_oS.resize(JWUnits.S)
	_w5.resize(JWUnits.BUYER_CLASS_N)
	_t5.resize(JWUnits.BUYER_CLASS_N)
	_o5.resize(JWUnits.BUYER_CLASS_N)
	_w9.resize(JWUnits.A * JWUnits.K)
	_t9.resize(JWUnits.A * JWUnits.K)
	_o9.resize(JWUnits.A * JWUnits.K)
	_w16.resize(JWUnits.CELL)
	_t16.resize(JWUnits.CELL)
	_o16.resize(JWUnits.CELL)
	_w36.resize(JWUnits.GROUP)
	_t36.resize(JWUnits.GROUP)
	_o36.resize(JWUnits.GROUP)
	_fill_iota(_t3)
	_fill_iota(_t4)
	_fill_iota(_tS)
	_fill_iota(_t5)
	_fill_iota(_t9)
	_fill_iota(_t16)
	_fill_iota(_t36)
	reset_flows()


## §1.6 状态块协议：只读取用（返回引用，调用方不得写）。
## 步骤：LOAD / 哈希 / 存档
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func state_array(i: int) -> PackedInt64Array:
	if i == 0:
		return inv_output
	if i == 1:
		return inv_input
	if i == 2:
		return pub_queue
	if i == 3:
		return logistics_cost_ppm
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：仅 LOAD / MIG（静态检查：调用点必须在 systems/content_loader.gd 或 systems/saves.gd）。
## 步骤：LOAD / MIG
## 前置：allocate() 已调用；v 长度与契约一致
## 后置：对应数组逐位等于 v
## 不变量：INV-136、INV-049（不可库存部门初始库存必须为 0）
## 失败：越界或长度不符 → INDEX_OUT_OF_RANGE / Load.SCHEMA_HEADER
func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i,
				STATE_ARRAY_IDS.size())
	var target: PackedInt64Array = state_array(i)
	if v.size() != target.size():
		return JWResult.Load.SCHEMA_HEADER
	if i == 0:
		for cell: int in JWUnits.CELL:
			if v[cell] < 0:
				return JWResult.Load.RANGE
			var s: int = JWIds.sector_of_cell(cell)
			# INV-049：energy 与 services 的成品库存初值必须为 0（docs/10 §4.5 的 storable 约定）。
			if (s == JWUnits.Sector.ENERGY or s == JWUnits.Sector.SERVICES) and v[cell] != 0:
				return JWResult.Load.ENERGY_INVENTORY
		inv_output = v.duplicate()
		return JWResult.OK
	if i == 1:
		for k: int in JWUnits.INV_N:
			if v[k] < 0:
				return JWResult.Load.RANGE
		inv_input = v.duplicate()
		return JWResult.OK
	if i == 2:
		for k: int in JWUnits.PUBSERV_QUEUE_N:
			if v[k] < 0:
				return JWResult.Load.RANGE
		pub_queue = v.duplicate()
		return JWResult.OK
	for k: int in JWUnits.OD_N:
		if v[k] < 0 or v[k] > JWUnits.PPM:
			return JWResult.Load.RANGE
	logistics_cost_ppm = v.duplicate()
	return JWResult.OK


## §1.6 状态块协议：本类无标量状态，恒返回 0。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：INV-136
## 失败：无
@warning_ignore("unused_parameter")
func state_scalar(i: int) -> int:
	return 0


## §1.6 状态块协议：本类无标量状态，恒返回 OK 且不做任何事。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：INV-136
## 失败：无
@warning_ignore("unused_parameter")
func set_state_scalar(i: int, v: int) -> int:
	return JWResult.OK


## §1.6 状态块协议：读流量数组（只读取用）。
## 步骤：诊断 / 报告
## 前置：i ∈ [0, FLOW_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-010
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func flow_array(i: int) -> PackedInt64Array:
	if i == 0:
		return f_consumed
	if i == 1:
		return f_purchased
	if i == 2:
		return f_sold
	if i == 3:
		return f_spoilage_out
	if i == 4:
		return f_spoilage_in
	if i == 5:
		return f_unmet_demand
	if i == 6:
		return f_price_variance
	if i == 7:
		return m_supply
	if i == 8:
		return m_demand
	if i == 9:
		return m_traded
	if i == 10:
		return m_unmet
	if i == 11:
		return m_rule
	if i == 12:
		return m_inv_target
	if i == 13:
		return f_pub_delivered
	if i == 14:
		return f_pub_intermediate
	if i == 15:
		return f_sold_direct
	if i == 16:
		return m_imported
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：本类无标量流量，恒返回 0。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：INV-010
## 失败：无
@warning_ignore("unused_parameter")
func flow_scalar(i: int) -> int:
	return 0


## §1.6 状态块协议：仅 S01；全部 FLOW_* 归零。
## 步骤：S01 §01.3
## 前置：phase == S01
## 后置：十五个流量数组全 0
## 不变量：INV-010
## 失败：无
func reset_flows() -> void:
	f_consumed.fill(0)
	f_purchased.fill(0)
	f_sold.fill(0)
	f_spoilage_out.fill(0)
	f_spoilage_in.fill(0)
	f_unmet_demand.fill(0)
	f_price_variance.fill(0)
	m_supply.fill(0)
	m_demand.fill(0)
	m_traded.fill(0)
	m_unmet.fill(0)
	m_rule.fill(0)
	m_inv_target.fill(0)
	f_pub_delivered.fill(0)
	f_pub_intermediate.fill(0)
	# 内部缓冲与流量同寿命：它们承载本季的中间量，跨季残留会让 INV-047 的残差指向上一季。
	_direct_avail.fill(0)
	_supply_by_cell.fill(0)
	_energy_market_avail.fill(0)
	_group_budget.fill(0)
	_group_demand.fill(0)
	_group_spent.fill(0)
	_firm_demand.fill(0)
	# 直接售出是 S05 交租写入、跨季供 D_prev 与读档反推使用的流量，只在 S01 清零。
	f_sold_direct.fill(0)
	m_imported.fill(0)
	_imp_share.fill(0)
	_imp_room.fill(0)
	_imp_plan.fill(0)
	_cur_imp_plan = 0
	_cur_plan = 0
	_input_target.fill(0)
	_input_target_armed = false
	_pub_demand.fill(0)
	_gov_demand.fill(0)
	_export_demand.fill(0)
	_gov_value_by_region.fill(0)
	_fault = 0


## §1.6 状态块协议：S01 清零后的自检，非 0 即 FLOW_NOT_RESET。
## 步骤：S01 §01.3 末
## 前置：reset_flows() 已调用
## 后置：不改状态
## 不变量：INV-010
## 失败：无
func flow_abs_sum() -> int:
	var acc: int = 0
	for i: int in FLOW_ARRAY_IDS.size():
		acc += JWMath.sum_abs(flow_array(i))
	return acc


## §1.6 状态块协议：读档时写回流量数组（R-SAVE-01，由 tools/gen_flow_setters.py 按 flow_array 逐项对称生成）。
## 步骤：LOAD（JWSaves 经 JWSimState 调用）
## 前置：v 的长度与本块当前分配的长度一致（长度是 schema 的一部分，INV-136）
## 后置：对应成员被整体替换
## 不变量：INV-133（读档后与原进程逐位相同）
## 失败：下标越界或长度不符 → INDEX_OUT_OF_RANGE
func set_flow_array(i: int, v: PackedInt64Array) -> int:
	if i == 0:
		if v.size() != f_consumed.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_consumed = v.duplicate()
		return JWResult.OK
	if i == 1:
		if v.size() != f_purchased.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_purchased = v.duplicate()
		return JWResult.OK
	if i == 2:
		if v.size() != f_sold.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_sold = v.duplicate()
		return JWResult.OK
	if i == 3:
		if v.size() != f_spoilage_out.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_spoilage_out = v.duplicate()
		return JWResult.OK
	if i == 4:
		if v.size() != f_spoilage_in.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_spoilage_in = v.duplicate()
		return JWResult.OK
	if i == 5:
		if v.size() != f_unmet_demand.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_unmet_demand = v.duplicate()
		return JWResult.OK
	if i == 6:
		if v.size() != f_price_variance.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_price_variance = v.duplicate()
		return JWResult.OK
	if i == 7:
		if v.size() != m_supply.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		m_supply = v.duplicate()
		return JWResult.OK
	if i == 8:
		if v.size() != m_demand.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		m_demand = v.duplicate()
		return JWResult.OK
	if i == 9:
		if v.size() != m_traded.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		m_traded = v.duplicate()
		return JWResult.OK
	if i == 10:
		if v.size() != m_unmet.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		m_unmet = v.duplicate()
		return JWResult.OK
	if i == 11:
		if v.size() != m_rule.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		m_rule = v.duplicate()
		return JWResult.OK
	if i == 12:
		if v.size() != m_inv_target.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		m_inv_target = v.duplicate()
		return JWResult.OK
	if i == 13:
		if v.size() != f_pub_delivered.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_pub_delivered = v.duplicate()
		return JWResult.OK
	if i == 14:
		if v.size() != f_pub_intermediate.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_pub_intermediate = v.duplicate()
		return JWResult.OK
	if i == 15:
		if v.size() != f_sold_direct.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_sold_direct = v.duplicate()
		return JWResult.OK
	if i == 16:
		if v.size() != m_imported.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		m_imported = v.duplicate()
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
