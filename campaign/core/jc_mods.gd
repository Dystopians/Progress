## v2 修正汇总（docs/57 §8—§10）：科技、政令、地标、事件带来的加成统一成「目标 + 范围 → 数值」。
## 数值以「百分之一个百分点」存（+20% 存 2000）；点数类（民心、国望、关系）同样 ×100。
##
## 模拟核心认得的目标（数值含义）：
##   land_tax_eff / salt_tax_eff / customs_eff / tax_eff        征收率 ±%
##   hidden_growth（±%）、hidden_cut（每季追回隐田的百分点）       隐田
##   admin_eff / edu_eff / health_eff / relief_eff / irrigation_eff  设施效果 ±%
##   admin_cost / construction_cost / workshop_cost（±%）          成本
##   invest_prop / invest_workshop（±%）                          民间投资意愿
##   sea_trade_cap / land_trade_cap / commerce_cap（±%）            能力
##   export_price / import_price（±%，范围：all / sea / partner:<id>:<商品>） 贸易价格
##   relation（点，范围：伙伴）、relation_all（点）                 关系
##   farm_yield（±%，范围：地区或空）、workshop_labor（±%）          生产
##   logistics_cut / logistics_cut_all（百分点）                    物流
##   research_speed / research_foreign（±%）、literacy_rate（±%）   研究与识字
##   support（点，范围：阶层或 all）、unrest（±%，范围：阶层、地区或 all）、prestige（点）
##   mortality（±%）、disaster_cut（±%）、migration（±%）、skill_up（±%）
##   flags：granary_ops、relief、title_sales、reclaim、income_tax、pension、price_stability
##   interest_rate（±%）、tariff（±%）、price_level（%）、ships_output（±%）、electricity_bonus（±%）
##   forest_regrow / coal_shift / pollution_cut（±%）
class_name JCMods
extends RefCounted

var totals: Dictionary = {}


func rebuild(st: JCState, ct: JCContent) -> void:
	totals.clear()
	for t: int in ct.t_n:
		if st.t_done[t] == 1:
			for m: Dictionary in ct.t_effects[t]:
				_add(m, 1_000_000)
	for d: int in ct.decrees.size():
		var dd: Dictionary = ct.decrees[d]
		var lvl: int = st.d_level[d]
		var effs: Array = dd.get("effects", [])
		var kind: String = String(dd.get("kind", "toggle"))
		var pick: int = -1
		if kind == "level":
			pick = lvl
		elif lvl > 0:
			pick = 0
		if pick >= 0 and pick < effs.size():
			for m2: Dictionary in effs[pick]:
				_add(m2, 1_000_000)
	for l: int in ct.landmarks.size():
		var ls: int = st.l_state[l]
		if ls < 2:
			continue
		var ld: Dictionary = ct.landmarks[l]
		var scale: int = _eraband_scale(st, ld)
		var key: String = "effects_full" if ls == 2 else "effects_lite"
		for m3: Dictionary in ld.get(key, []):
			_add(m3, scale)
	for i: int in st.tm_target.size():
		_add_raw(st.tm_target[i], st.tm_scope[i], st.tm_value[i])


## 带时代标签的地标加成：本国进入 eraband+2 时代后 40 季内线性归零（docs/57 §10）。
func _eraband_scale(st: JCState, ld: Dictionary) -> int:
	var band: int = int(ld.get("eraband", 0))
	if band <= 0:
		return 1_000_000
	var fade_era: int = band + 2
	if st.era < fade_era or fade_era >= st.era_q.size():
		return 1_000_000
	var since: int = st.q - st.era_q[fade_era]
	return maxi(0, 1_000_000 - since * 25_000)


func _add(m: Dictionary, scale_ppm: int) -> void:
	var v: int = int(round(float(m.get("value", 0)) * 100.0))
	v = JCMath.muldiv(v, scale_ppm, 1_000_000)
	_add_raw(String(m.get("target", "")), String(m.get("scope", "")), v)


func _add_raw(target: String, scope: String, v: int) -> void:
	var k: String = target + "|" + scope
	totals[k] = int(totals.get(k, 0)) + v


## 某目标的总值（全局 + 指定范围），单位：百分之一。
func sum(target: String, scope: String = "") -> int:
	var v: int = int(totals.get(target + "|", 0))
	if scope != "":
		v += int(totals.get(target + "|" + scope, 0))
	return v


## 只取某个范围的值（不含全局部分）；scope 为空串时只取全局部分。
func scoped(target: String, scope: String) -> int:
	return int(totals.get(target + "|" + scope, 0))


## 百分比修正换成 ppm 乘数：1 + sum/10000（下限 0）。
func mult_ppm(target: String, scope: String = "") -> int:
	return maxi(0, 1_000_000 + sum(target, scope) * 100)


## 百分比修正换成 ppm 增量：sum/10000 × 1e6。
func delta_ppm(target: String, scope: String = "") -> int:
	return sum(target, scope) * 100


func flag(target: String) -> bool:
	return sum(target) > 0


## 列出某目标的全部来源（给界面解释用）：[{scope, value}]
func breakdown(target: String) -> Array:
	var out: Array = []
	for k: Variant in totals.keys():
		var s: String = String(k)
		if s.begins_with(target + "|"):
			out.append({"scope": s.substr(target.length() + 1), "value": int(totals[k])})
	return out
