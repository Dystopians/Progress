# 16 外部世界设计记录（澄湾共和国）

> **本文件不是内容包文件，不参与 `content_hash`，载入器永远不读它。**
> 它是原 `content/scenarios/chengwan/world.json` 的归宿：那份文件自称 `schema_kind = "world_init"`，
> 而 `11_data_contract.md` §5 的类型集合里没有这个类型，§2 的文件布局里也没有这个文件；
> 按 §5.4，外部世界初值的唯一事实来源是 `content/scenarios/chengwan/scenario.json` 的 `world_init` 字段。
>
> 处理办法（不改契约、不改校验器、不删内容）：
> **数据留在 scenario.json（已经在了，逐字相等），设计规则与参数身份证迁到本文件。**
> 内容包里因此不再有一个既进不了载入器、又没有任何校验能证明其正确的 29 KB JSON。
>
> 记账纪律沿用计划书 §13 §14：全程 int64 定点；本文件不含任何平衡修正项或凭空补贴。
> **刻度：全文按裁定 R-SCALE-01 书写，1 U = 1 000 000 000 μU，基年价 1 000 000 000 μU/Q_s。**
> 实物（`_uqs`）、比率（`_ppm`）、人数、件数、季度一律不随货币刻度变化。

---

## 0 本记录改了什么

| # | 位置 | 原状 | 现状 | 性质 |
|---|---|---|---|---|
| 1 | 文件归宿 | `content/scenarios/chengwan/world.json`，`schema_kind = world_init` | 本文件；内容包中已删除该 JSON | 结构错误（`E_SCHEMA_HEADER` ×2、`E_CONTENT_LAYOUT` ×1） |
| 2 | `value_cards[cash_uu].source_ref` | 「`scenario.total_cash_uu = 80 U` 的分配」 | `scenario.json` 实为 **55 U**；本文件给出完整分解并已与各初值文件逐项核过 | **数值错误**，两处事实来源漂移 |
| 3 | `sustainability_budget.worst_case_inflow_zh` | 按「外债 16 U 全为 bullet、票息 11 000 ppm/季」估算，40 季回流约 7.04 U | 按 `government_init.json` 的**真实批次**重算：40 季回流 **17 960 500 000 μU** | **数值错误**，依赖的前提已被真实数据推翻 |
| 4 | `sustainability_budget.trajectory_check_zh` | 「每季净减约 324 000 μU，q=39 约 2 360 000 μU」 | 逐季重算：q=0..19 单调**上升**到 22 960 500 000 μU，q=20..39 单调下降到 **12 960 500 000 μU** | **数值错误** |
| 5 | 新增 | 无 | 最不利情形（q=0 用满 12 U 外部额度）的 row 现金下界 **3 206 000 000 μU** | 补齐缺失的核算 |
| 6 | 新增 | 无 | **120 季压测下出口会在 q≈65 断供**（原文件只核到 40 季） | 补齐缺失的核算 |
| 7 | `open_question_refs` | OQ-246..254 当作已登记编号引用 | 标注为**提议编号**；`13_open_questions.md` 现只到 OQ-245 | 悬空引用 |
| 8 | 全文刻度（本轮） | 正文与载荷里的 μU 数字仍是 1 U = 10⁶ μU 的旧刻度，与已迁移的 `scenario.json` 差 1000 倍 | 全部改为 R-SCALE-01 新刻度，并与 `scenario.json` / `government_init.json` / `population_init.json` / `cells_init.json` 的现值逐项对过 | **刻度错误**（裁定 R-SCALE-01 遗留的「字符串正文里的旧数字」） |
| 9 | 三处「先乘后除」公式（本轮） | `credit_used_uu * 1000000`、`qty_uqs * price`、`price * 1000000` 写成裸乘 | 改走 `mul_div_floor(a, b, c)` | **溢出缺陷**：新刻度下 `credit_used(≤4×10¹⁵) × 10⁶` 真的溢出 int64（R-SCALE-01 连带要求 1） |
| 10 | `external_credit.usage_rules_zh`（本轮） | 只说「存量外债不占用额度」 | 按**裁定 R-CREDIT-01** 显式写明「外部额度是增量额度」及其理由 | 裁定落点：R-CREDIT-01 要求此条必须显式写在原 `world.json` 与 `10_variable_dictionary.md` §8.4，前者的义务由本文件继承 |
| 11 | `tightening_price_rule.missing_dependency_zh`（本轮） | 「`param.market_rate_base_ppm` 在任何内容文件里都没有取值」 | `content/parameters/params_core.json` 已落地，该参数 = **10 000 ppm**，与 `world_init.sovereign_rate_ppm_per_q` 相等，这条一致性现在可被校验 | 陈述过期 |

**没有做的事**：没有改任何字段的取值口径，没有删掉任何规则、参数卡或反例条款，
没有为了让校验通过而放宽 `valid_range`，没有碰 `10/11/12/13/18` 号文件，也没有碰校验器。

---

## 1 归宿裁定

| 载荷 | 该归谁 | 现状 |
|---|---|---|
| `world_init` 的 7 个初值 | `scenario.json#world_init`（11 号 §5.4 已规定） | **已在位，且与本文件的只读副本逐字相等**（本轮重新逐字段比对过） |
| `export_demand.export_baseline_uqs_per_q` | 三份契约都没有给它字段归宿，而 `12_simulation_contract.md` §5.6 的出口需求行直接引用「基准出口量[s]」 | **契约硬伤**，见 §5 提议 OQ-246 |
| 6 张 `parameter_cards` | `content/parameters/params_core.json`（11 号 §2 规定的 `parameter_set`） | 该文件已落地（73 张卡），但**尚未收下这 6 张**；见 §3 |
| 结算规则（出口实现、进口双闸、外部额度定价、冲击落点） | `12_simulation_contract.md` | 本文件只登记，不自行实施 |
| 外部账户与科目 | `10_variable_dictionary.md` §2.2 / §8.4 | 已在位；本文件补的是它们的**用法约束** |
| 裁定 R-CREDIT-01 的「增量额度」表述 | 原 `world.json` + `10_variable_dictionary.md` §8.4 | 前者的义务由本文件 §4 `external_credit.usage_rules_zh` 第 1 条承接；后者仍需其负责人落地 |

> 一条纪律：`world_init_mirror` 是**只读副本**，不是第二份事实来源。
> 它与 `scenario.json#world_init` 不一致时，**永远以 scenario.json 为准，本文件改**，反向绝不允许。

> 为什么不是「把 world.json 登记进 §2」：`11_data_contract.md` §10.5 第 4 条写明该文件「需要单独裁定后再改 §2」，
> `18_rulings.md` 的「尚未裁定」一节又禁止实现者自行假定。在裁定作出之前，
> 把一个没有任何 `V-*` 校验表的新类型塞进布局，等于给内容包加 29 KB **无人能证明其正确**的数据——
> 这与 11 号文件开篇「任何不能被校验器证明账能对上的剧本一律拒绝加载」直接冲突。
> `scenario.json` 的 `_note_includes_world_json` 已独立得出同一结论。

---

## 2 会计复核（逐笔算过，不是估）

### 2.1 外部债务回流：按真实批次，不按假设

`government_init.json` 中 `holder == "row"` 的批次只有两笔，合计 16 000 000 000 μU（即 §05 的 50 U 债务里的 16 U）：

| bond_id | 面值 μU | q=0 期初余额 μU | 票息 ppm/季 | 到期 q | 摊还 |
|---|---|---|---|---|---|
| `bond.q-8_01` | 13 500 000 000 | 10 000 000 000 | 12 500 | 19 | `level_principal` |
| `bond.q-2_01` | 6 000 000 000 | 6 000 000 000 | 13 500 | 7 | `bullet` |

`level_principal` 的期数按 12 号 §2 02.4「发行时由 `split_largest_remainder(principal_initial, 等权重)` 预生成」还原：
期数 = `maturity_q − issue_q` = 27，每期 500 000 000 μU，付款落在 q = −7..19。
q=0 期初已付 7 期共 3 500 000 000 μU，余额 13 500 000 000 − 3 500 000 000 = **10 000 000 000 μU**，与文件登记值**精确相等**。
同一还原法用在 `bond.q-12_01`（invpool，面值 14 400 000 000、36 期 × 400 000 000、已付 11 期）同样精确对上，
两笔互证，说明这个期数口径就是剧本作者用的那个。

利息按 12 号 §2 02.3 逐批次 `mul_ppm(outstanding, coupon_ppm)`（内部走 `mul_div_floor`）：
两笔的每季利息增量都是整数（500 000 000 × 12 500 ppm = 6 250 000；6 000 000 000 × 13 500 ppm = 81 000 000），
`interest_remainder_ppmuu` 全程为 0，**长期不漂移**。

40 季（q=0..39）本国付给 `agent.row` 的债务履约合计：

```
利息   1 960 500 000 μU   （bond.q-8_01 的 1 312 500 000 + bond.q-2_01 的 648 000 000）
本金  16 000 000 000 μU   （10 000 000 000 + 6 000 000 000，两笔在 q=19 前全部结清）
合计  17 960 500 000 μU
```

其中 `bond.q-8_01` 的利息 = `0.0125 × Σ(k=0..19) (10 000 000 000 − k × 500 000 000)`
= `0.0125 × 105 000 000 000` = 1 312 500 000 μU；`bond.q-2_01` 的利息 = 81 000 000 × 8（q=0..7）= 648 000 000 μU。

### 2.2 row 现金 40 季轨迹（无冲击、无进口、无新增外债 = 对 row 最不利）

出口每季 500 000 μQ，基年价 1 000 000 000 μU/Q_s：
`value_uu = mul_div_floor(qty_uqs, price_uu_per_qs, Q_SCALE) = mul_div_floor(500 000, 1 000 000 000, 1 000 000) = 500 000 000 μU/季`。
（新刻度下 1 μQ_s 折 1 000 μU，不再像旧刻度那样「μQ_s 数值与 μU 数值相等」。）

| q | 回流 μU | 出口支出 μU | row 现金 μU |
|---|---|---|---|
| 起点 | — | — | 15 000 000 000 |
| 0 | 706 000 000 | 500 000 000 | 15 206 000 000 |
| 7 | 6 662 250 000 | 500 000 000 | 22 473 000 000 |
| 19 | 506 250 000 | 500 000 000 | **22 960 500 000**（峰值） |
| 20 | 0 | 500 000 000 | 22 460 500 000 |
| 39 | 0 | 500 000 000 | **12 960 500 000**（40 季最小值） |

对账：`15 000 000 000 + 17 960 500 000 − 20 000 000 000 = 12 960 500 000` ✔
**全程为正，40 季末仍有 12 960 500 000 μU，相当于 25.9 季的出口余量。**

### 2.3 最不利情形：q=0 一次用满外部额度

外债**认购**是 row 掏现金（`post(bond_issue, holder.cash → gov.cash)`），
所以「政府大举外借」对 row 现金是**先减后补**，是本表真正的下界所在。
取 q=0 一次发满 12 000 000 000 μU、票息取本规则下的下界 12 000 ppm/季
（= `param.market_rate_base_ppm` 10 000 + `param.external_spread_ppm_per_q` 2 000 + 使用率加价 0，
在 `[param.coupon_min_ppm 2 000, param.coupon_max_ppm 60 000]` 内）、bullet 且到期晚于 q=39：

```
q=0 : 15 000 000 000 − 12 000 000 000 + 706 000 000 − 500 000 000 = 3 206 000 000 μU   ← 全程最小值
q=7 :                                                              11 481 000 000 μU
q=39:                                                               6 576 500 000 μU
```

（q=1..39 每季多出新批次利息 `mul_ppm(12 000 000 000, 12 000) = 144 000 000 μU`，
39 季共 5 616 000 000 μU，正是 q=39 余额高于 §2.2 无新债情形的原因。）

**下界 3 206 000 000 μU > 0**，首版 40 季的出口规模在任何发债路径下都站得住。

### 2.4 120 季压力测试：出口会在 q≈65 断供

两笔外债在 q=19 前全部结清，此后若没有新的外债利息、也没有政府设备进口付款，
`agent.row` 只出不进，每季 −500 000 000 μU：

```
q=64 末：12 960 500 000 − 25 × 500 000 000 = 460 500 000 μU
q=65   ：现金不足，出口按现金截断为 460 500 000 μU（= 460 500 μQ，不足基准量 500 000 μQ）
q=66 起：出口 = 0
```

这不是崩溃，不违反任何不变量，但它正是计划书 §04「报告必须能解释」要避免的那种现象：
**指标塌了，而原因不在任何经济机制里。** 处理纪律（本文件不擅自实施，只登记）：

1. 截断必须写 `flow.cell.unmet_demand_uqs` 并给出可读原因，**不得静默归零**；
2. 不得用「给 row 补现金」这类后处理补丁绕过（计划书 §13）；
3. 真要在 120 季里保住出口，只有两条合规路线：开放经常性进口通路（提议 OQ-251，让本国付钱给 row），
   或先改 OQ-201 再调大 `world_init.cash_uu` 并同步改 `scenario.total_cash_uu`。
4. 提议 OQ-255 登记此事。

### 2.5 全经济现金 63.716 U 的分解（INV-018）

`scenario.json` 的 `total_cash_uu = 63 716 000 000`。裁定 R-REGION-01 把每个 cell 的开局现金补到「一季工资 + 中间投入」，
企业现金合计由 20 U 变为 28.716 U，全经济由 55 U 变为 63.716 U（其余四项不变）。按现有各文件初值：

| 主体 | 来源文件 | cash_uu |
|---|---|---|
| `agent.gov` | `government_init.json` | 2 000 000 000 |
| `agent.invpool` | `government_init.json` | 9 000 000 000 |
| `agent.row` | `scenario.json#world_init` | 15 000 000 000 |
| 36 个群组合计 | `population_init.json`（实测求和） | 9 000 000 000 |
| 16 个 cell 合计 | `cells_init.json`（实测求和，R-REGION-01） | 28 716 000 000 |
| 合计 | | 63 716 000 000 |

五项相加恰为 63 716 000 000 μU，`assert.cash_total` 的口径成立（`tests/scenario/content_load_test.gd` 的 `TOTAL_CASH_UU` 同步）。

顺带复核（与本文件的外部口径相关）：V-FIN-09 `Σ group.deposit_uu = 43 000 000 000`
`= invpool.cash 9 000 000 000 + invpool 持有债券 34 000 000 000`（8 + 7 + 10 + 9 U）✔

---

## 3 待采纳清单

| 谁 | 要做什么 | 依据 |
|---|---|---|
| `parameters/params_core.json` 的负责人 | 收下 §4 的 6 张 `parameter_cards`（`registry.json` 曾扫到它们，但那是审计产物，不是 `parameter_set`；world.json 删除后它们在内容包里已无归宿） | 11 号 §2、R-PARAM-01 |
| `parameters/registry.json` 的负责人 | 重跑 `tools/build_param_registry.py`：现行登记表里有 6 张卡的 `_origin_file` 指向已删除的 `scenarios/chengwan/world.json` | 11 号 §5.16 V-PR-02/03 |
| `12_simulation_contract.md` 的负责人 | §5.6 的「基准出口量[s]」需要一个契约字段归宿；本文件的 `export_baseline_uqs_per_q` 是候选取值 | 提议 OQ-246 |
| `10_variable_dictionary.md` 的负责人 | §8.4 落地 R-CREDIT-01 的「增量额度」表述（该裁定要求两处都写明，本文件只承接原 world.json 那一处） | R-CREDIT-01 |
| `13_open_questions.md` 的负责人 | 登记 OQ-246..255（现登记到 OQ-245 为止） | 13 号 §H |
| `sim/world/world_market.gd`、`tests/unit/world_shocks_test.gd`、`shocks/shock_S0*.json`、`events/E06` 的负责人 | 注释与 `source_ref` 里的「world.json `forbidden_zh` / `gate_a_quantity_zh` / `delivery_capacity_semantics_zh` / `identities_zh`」改指本文件 §4 的同名键（**规则名逐字保留，引用路径变了而已**） | 本次迁移 |

---

## 4 完整载荷（原 world.json 全文，已更正、已按 R-SCALE-01 换刻度）

```json
{
  "doc_kind": "external_world_design_record",
  "doc_version": 3,
  "scenario_ref": "scenario.chengwan",
  "label_zh": "澄湾共和国 · 外部世界账户配置",
  "reference_year": 0,
  "unit_scale_zh": "本载荷按裁定 R-SCALE-01 书写：1 U = 1 000 000 000 μU，基年价 BASE_PRICE = 1 000 000 000 μU/Q_s，Q_SCALE = PPM = 1 000 000，AMOUNT_MAX = 4×10¹⁵ μU。凡带 μU 的数字都是新刻度；μQ_s、ppm、人数、件数、季度不随货币刻度变化。",

  "contract_binding": {
    "authority_docs": [
      "docs/ref/plan_v1.0.txt §03 §07 §09(P08) §13 §14",
      "docs/10_variable_dictionary.md §2.1 §2.2 §8.4 §14.8",
      "docs/11_data_contract.md §5.4 §5.14 §5.15",
      "docs/12_simulation_contract.md §1.1(01.7) §2(02.6) §4(04.4) §5.5 §5.6 §6.8",
      "docs/18_rulings.md R-SCALE-01 R-CREDIT-01 R-PARAM-01 R-SCHEMA-01"
    ],
    "file_status_zh": "本载荷曾以 content/scenarios/chengwan/world.json 的形式放在内容包里，schema_kind 写成 world_init。11 号文件 §5 没有这个类型，§2 也没有这个文件，因此它既进不了载入器，也没有任何校验能证明它是对的（E_SCHEMA_HEADER ×2、E_CONTENT_LAYOUT ×1）。按 §5.4，world 初值的唯一事实来源是 scenario.json 的 world_init 字段，那里已经有一份逐字相等的值。裁定：数据留在 scenario.json，规则与参数身份证迁到 docs/16_external_world_design.md，内容包中删除该 JSON。这不是新增契约类型，也不是放宽校验：契约要新增 world_init 类型，必须先由 11 号文件 §2 与 §5 登记并给出 V-* 校验表。",
    "mirror_rule_zh": "world_init 的唯一事实来源是 scenario.json#world_init。下方 world_init_mirror 是只读副本，供人工与工具交叉复核；两者不一致时一律以 scenario.json 为准并修改本文件，绝不反向改写 scenario.json。",
    "simcore_read_scope_zh": "SimCore 不从本文件读取任何运行值，本文件也不进入 content_hash。它是设计契约、校准依据与跨文件一致性检查的输入。"
  },

  "monetary_regime": {
    "fx_regime": "fixed",
    "fx_rate_ppm": 1000000,
    "_note_fx_rate_ppm": "恒 1 000 000；任何写入都是 FAULT（INV-105）。",
    "player_can_set_fx": 0,
    "central_bank_modeled": 0,
    "commercial_banks_modeled": 0,
    "money_creation_modeled": 0,
    "foreign_currency_debt_modeled": 0,
    "valuation_change_modeled": 0,
    "declaration_zh": "首版固定汇率，玩家不得操纵汇率；不模拟央行与商业银行体系，不存在货币创造与存款派生。全经济现金总量恒定（INV-018），agent.row 是持有有限现金的显式账户主体，不是无限资金源。政府外债一律以本币记账，无外币债务与估值变动（计划书 §03 §07）。",
    "consequence_zh": "因为没有货币创造，外部约束只能由三样东西表达：交付能力（物量）、外部信用额度（可借量）、融资价格（票息）。不存在也不得引入任何『外汇充足』式的布尔标签。"
  },

  "world_init_mirror": {
    "source_of_truth": "content/scenarios/chengwan/scenario.json#world_init",
    "verified_identical_zh": "已逐字段比对（R-SCALE-01 迁移后重新比对一次），与 scenario.json#world_init 完全一致。",
    "fx_rate_ppm": 1000000,
    "export_demand_ppm": [1000000, 1000000, 1000000, 1000000],
    "import_price_ppm": [1000000, 1000000, 1000000, 1000000],
    "delivery_capacity_uqs": [400000, 2400000, 600000, 0],
    "credit_limit_uu": 12000000000,
    "_note_credit_limit_uu": "12 U",
    "sovereign_rate_ppm_per_q": 10000,
    "cash_uu": 15000000000,
    "_note_cash_uu": "15 U"
  },

  "external_accounts": {
    "holder_agent": "agent.row",
    "accounts": [
      { "account_code": "cash", "label_zh": "外部世界现金", "role_zh": "出口收入的付款来源；进口支出与对外还本付息的收款方。恒 ≥ 0（INV-016），因此它同时是出口规模的物理上限，见 sustainability_budget。" },
      { "account_code": "inv.agri", "label_zh": "外部农产品可交付量", "role_zh": "进口农产品的实物来源。" },
      { "account_code": "inv.manu", "label_zh": "外部制造品可交付量", "role_zh": "进口设备与中间制造品的实物来源。" },
      { "account_code": "inv.energy", "label_zh": "外部能源可交付量", "role_zh": "进口燃料与外购能源的实物来源。" },
      { "account_code": "bondhold", "label_zh": "外部持有的政府债券", "role_zh": "面值口径；derived.world.external_debt_uu 由 holder == row 的批次汇总（INV-107）。" },
      { "account_code": "recv", "label_zh": "对本国应收款", "role_zh": "与本国 pay 配对（INV-019）。" },
      { "account_code": "pay", "label_zh": "对本国应付款", "role_zh": "与本国 recv 配对。" }
    ],
    "row_physical_side_zh": "10 号文件 §2.2 允许 agent.row 持有 inv.<sector>，但没有任何文件给出它的初值，也没说库存恒等式 INV-047 是否适用于 row。首版取最保守可执行的做法：row 的实物侧不做库存恒等式对账，可交付量由 state.world.delivery_capacity_uqs 的每季上限唯一约束；这不等于承认 row 有无限存量，而是把物量约束集中在一个可被冲击写、可被测试断言的字段上。提议 OQ-249。",
    "lines": [
      { "line_id": "world.line.export_receipts", "label_zh": "出口收入", "direction": "inflow_to_domestic", "ledger_kind": 8, "flow_field": "flow.world.exports_uu", "qty_field": "flow.world.exports_uqs", "class_hint": "exp_class = X", "counterparty": "agent.row" },
      { "line_id": "world.line.import_spending", "label_zh": "进口支出", "direction": "outflow_to_row", "ledger_kind": 9, "flow_field": "flow.world.imports_uu", "qty_field": "flow.world.imports_uqs", "class_hint": "exp_class = M（负号）", "counterparty": "agent.row" },
      { "line_id": "world.line.external_borrowing", "label_zh": "政府外债新增借款", "direction": "inflow_to_domestic", "ledger_kind": 15, "flow_field": "flow.gov.new_borrowing_uu", "qty_field": "none", "class_hint": "三口径均为 none（INV-029）", "counterparty": "agent.row" },
      { "line_id": "world.line.external_interest", "label_zh": "对外利息", "direction": "outflow_to_row", "ledger_kind": 17, "flow_field": "flow.gov.interest_paid_uu", "qty_field": "none", "class_hint": "三口径均为 none", "counterparty": "agent.row" },
      { "line_id": "world.line.external_principal", "label_zh": "对外还本", "direction": "outflow_to_row", "ledger_kind": 16, "flow_field": "flow.gov.principal_paid_uu", "qty_field": "none", "class_hint": "三口径均为 none；还本不是 GDP", "counterparty": "agent.row" },
      { "line_id": "world.line.external_writeoff", "label_zh": "对外确认减记（债权人损失）", "direction": "loss_to_row", "ledger_kind": 28, "flow_field": "flow.gov.recognized_writeoffs_uu", "qty_field": "none", "class_hint": "三口径均为 none", "counterparty": "agent.row" }
    ],
    "identities_zh": [
      "state.world.current_account_uu += flow.world.exports_uu - flow.world.imports_uu - 对外利息 + 对外净借款（12 号 §6.8，INV-106）。",
      "derived.world.external_debt_uu == Σ(holder == row) bond.principal_outstanding_uu（INV-107）。",
      "derived.world.net_foreign_position_uu == -agent.row.nw（INV-110）。",
      "每一笔涉及外部的过账都必须以 agent.row 为对手方，不存在无对手方的对外收支（INV-026）。",
      "借款不是收入，还本不是 GDP，减记不是支出：ledger_kind 15/16/17/28 在生产法、支出法、收入法下全为 none（11 号 §5.3）。"
    ],
    "normal_year_writeoff_uu": 0,
    "_note_normal_year_writeoff_uu": "0 U。普通年份减记为零；只有 debt_restructure 命令才登记债权人损失（计划书 §07）。"
  },

  "export_demand": {
    "tradable": [1, 1, 1, 0],
    "_note_tradable": "按 10 号 §0.5 稠密下标 agri / manu / energy / services。与 scenario.json 的 delivery_capacity_uqs [400000, 2400000, 600000, 0] 严格一致：交付能力为 0 的部门，出口基准量必须为 0，否则会出现『配置了出口却被静默截成 0』这种既不违反不变量又不符合直觉的账。",
    "export_baseline_uqs_per_q": [100000, 350000, 50000, 0],
    "_note_export_baseline_uqs_per_q": "合计 500 000 μQ_s/季。新刻度下基年价 1 000 000 000 μU/Q_s，即 1 μQ_s 折 1 000 μU，故基年出口额为每季 500 000 000 μU、全年 2 000 000 000 μU，即基年 100 U（100 000 000 000 μU）名义 GDP 的 2%。该规模不是对现实开放度的估计，而是 sustainability_budget 里 agent.row 现金约束逼出来的上限。逐部门均不超过同部门交付能力（100000≤400000、350000≤2400000、50000≤600000、0≤0）。",
    "export_price_elasticity_ppm": [0, 0, 0, 0],
    "realizable_export_rule": {
      "step_01_zh": "potential_uqs[s] = mul_ppm(export_baseline_uqs_per_q[s], state.world.export_demand_ppm[s])　# 外部需求指数，由 shock.S01 在 S01 写入",
      "step_02_zh": "price_ppm[s] = mul_div_floor(state.price.sector_uu_per_qs[s], 1000000, content.price.base_uu_per_qs[s])　# rounding: floor, reason=不高估竞争力；新刻度下 price × 10⁶ 已接近 int64 上界，禁止裸乘（R-SCALE-01 连带要求 1）",
      "step_03_zh": "competitiveness_ppm[s] = clamp(1000000 - mul_ppm(param.export_price_elasticity_ppm[s], max(0, price_ppm[s] - 1000000)), 0, 1000000)",
      "step_04_zh": "desired_uqs[s] = mul_ppm(potential_uqs[s], competitiveness_ppm[s])　# rounding: floor, reason=不凭空多给订单",
      "step_05_zh": "demand_uqs[买方类 4][s] = min(desired_uqs[s], state.world.delivery_capacity_uqs[s])　# 即 12 号 §5.6 的出口需求行",
      "step_06_zh": "实际出口量由 §5.6 的两级配给决定，出口固定排在最后一档（OQ-238）；未成交部分记 flow.cell.unmet_demand_uqs，不得转为收入，也不得留待下季补记。",
      "step_07_zh": "成交价 = state.price.sector_uu_per_qs[s]（国内现价；固定汇率下即外部到岸价）。value_uu = mul_div_floor(qty_uqs, price_uu_per_qs, 1000000)（分母是 Q_SCALE，不是 PPM；QTY_MAX × PRICE_MAX = 2.5×10²¹ 真的溢出 int64，故必须走 mul_div_floor）。post(kind=8, agent.row.cash -> 卖方 cell.cash)；agent.row 现金不足时按现金截断并记未满足需求，绝不让 row 现金为负。",
      "v1_price_channel_zh": "首版 param.export_price_elasticity_ppm 全为 0，即出口量对价格无弹性，价格只通过成交价影响出口收入。原因：12 号 §5.6 的权威出口公式里没有价格项，擅自加入会改动已锁定的结算步。结构在此登记完整，启用必须先改 12 号文件。提议 OQ-247。"
    },
    "no_self_dealing_rules_zh": [
      "出口量不得超过本季实际可售供给经配给后的成交量；没有供给就没有出口，不存在先记收入后补货。",
      "export_baseline_uqs_per_q 是内容常量，运行期任何系统都不得写它；唯一可被改变的外部需求量是 state.world.export_demand_ppm，且只能由 shock.S01 写（INV-108）。",
      "delivery_capacity 与 port_capacity 都是上限，不是订单；提高上限本身不产生任何出口收入。",
      "policy.P08（港口与物流升级）只放宽上限，绝不得提高 export_demand_ppm 或 export_baseline_uqs_per_q——这是计划书 §09 P08『不能自造订单』的结构性执行点。",
      "任何政策、事件或冲击都不得直接写 flow.world.exports_uu／exports_uqs；它们只能是成交的结果。"
    ],
    "port_gate": {
      "status": "declared_not_active_in_v1",
      "intended_rule_zh": "Σ_s (flow.world.exports_uqs[s] + flow.world.imports_uqs[s]) ≤ Σ_r state.region.port_capacity_uqs_per_q[r]",
      "why_not_active_zh": "两处硬伤：(a) 12 号 §5.5 与 §5.6 的权威公式里根本没有 port_capacity 项；(b) 该求和跨部门相加 μQ_s，违反 10 号 §0.1『不可跨部门相加』，需要先定义一个中性的通行量单位。首版不启用，提议 OQ-248。",
      "consequence_if_unfixed_zh": "10 号文件 §7 已把 state.region.port_capacity_uqs_per_q 标注为『P08；INV-104』，但没有任何结算步读它。若不修复，policy.P08 的效果落点 state.region.port_capacity_pending_uqs_per_q 无人读取，P08 成为没有反馈链的空政策，违反计划书 §09『每项政策至少 1 条完整反馈链』。这是首版最需要先裁定的一条。"
    }
  },

  "import_supply": {
    "external_price_rule_zh": "external_price_uu_per_qs[s] = mul_ppm(content.price.base_uu_per_qs[s], state.world.import_price_ppm[s])　# rounding: floor, reason=少付优于凭空多付。基年 import_price_ppm 全为 1 000 000，故基年外部到岸价 == 基年价 == 1 000 000 000 μU/Q_s，基年名义即实际。",
    "external_price_uu_per_qs_init": [1000000000, 1000000000, 1000000000, 1000000000],
    "import_lead_time_q": [0, 0, 0, 0],
    "_note_import_lead_time_q": "首版一律 0 季：订货与到货同季，数量由交付能力上限截断，时滞效果由『交付能力不足导致分季到货』表达。计划书 §07 提到交付时滞，但 12 号 §5.5 的到货公式 delivered_uqs = min(本季已订量, 交付能力剩余) 没有时滞项；擅自加入会改变 P04『第 8 季交付齐全才可投运』的验收口径。提议 OQ-250。",
    "lines": [
      {
        "import_line_id": "world.import.equipment",
        "sector_ref": "sector.manu",
        "label_zh": "设备与中间制造品",
        "channel_status": "active_in_v1",
        "delivery_capacity_ref": "state.world.delivery_capacity_uqs[1]",
        "delivery_capacity_uqs_per_q": 2400000,
        "buyers_zh": "政府项目支出的 import_equipment 分项（12 号 §4 04.4，收款方 agent.row，同时增 flow.world.imports_uu/imports_uqs）；企业资本品购入中的进口部分（OQ-213，计入 M_cap）。",
        "scenario_note_zh": "海岬『设备依赖进口』的开局约束由这条线的每季 2 400 000 μQ_s 上限形成：P04 每季 200 000 μQ_s（= 200 000 000 μU）的设备进口、P08 的港口设备进口与企业投资共用这一个上限。"
      },
      {
        "import_line_id": "world.import.energy",
        "sector_ref": "sector.energy",
        "label_zh": "燃料与外购能源",
        "channel_status": "declared_no_sim_step_in_v1",
        "delivery_capacity_ref": "state.world.delivery_capacity_uqs[2]",
        "delivery_capacity_uqs_per_q": 600000,
        "buyers_zh": "计划书 §07 要求进口含能源，且 shock.S02 的主要杀伤面就是进口能源价格。但 12 号 §5.6 的买方类只有『居民／公共服务／政府采购／企业投入与补库／出口』五类，没有任何一条通路让外部产品进入国内供给。首版不自造结算步：保留价格与额度定义，燃料短缺仍按OQ-216 表现为能源 cell 的 bound_materials 收紧。提议 OQ-251。",
        "scenario_note_zh": "在该通路缺失期间，shock.S02 只能通过项目设备进口的价格影响财政，对能源供给没有传导；这是首版『进口能源价格冲击』威力被削弱的已知原因，不要用调大冲击强度去掩盖。"
      },
      {
        "import_line_id": "world.import.agri",
        "sector_ref": "sector.agri",
        "label_zh": "农产品",
        "channel_status": "declared_no_sim_step_in_v1",
        "delivery_capacity_ref": "state.world.delivery_capacity_uqs[0]",
        "delivery_capacity_uqs_per_q": 400000,
        "buyers_zh": "同 world.import.energy：额度已配置，结算步缺失。提议 OQ-251。",
        "scenario_note_zh": "该额度存在的意义是为『北原歉收时能否买粮』留出后续扩展空间，首版不实现，也不得用它给居民凭空补供给。"
      },
      {
        "import_line_id": "world.import.services",
        "sector_ref": "sector.services",
        "label_zh": "服务",
        "channel_status": "closed_in_v1",
        "delivery_capacity_ref": "state.world.delivery_capacity_uqs[3]",
        "delivery_capacity_uqs_per_q": 0,
        "buyers_zh": "首版服务不跨境交付，进出口均为 0。",
        "scenario_note_zh": "施工服务必须来自国内 cell.<r>.services，不得用进口绕开施工能力约束（计划书 §10 的 T-S-P04-PAY-NO-PROGRESS 依赖这一点）。"
      }
    ],
    "delivery_capacity_semantics_zh": "state.world.delivery_capacity_uqs 是唯一一个既被进口（INV-104、INV-089）又被出口（12 号 §5.6）引用的数组。首版按『两个方向各自独立受同一个上限约束、不共享额度池』执行，因为两处公式都写的是各自 min 而不是联合约束。是否拆成 import_delivery 与 export_absorption 两个数组，提议 OQ-246。"
  },

  "external_credit": {
    "base_credit_limit_uu": 12000000000,
    "_note_base_credit_limit_uu": "12 U；低于开局外债余额 16 U，外部融资在开局即为稀缺资源（取值与理由由 scenario.json 锁定，本文件只复述规则）。",
    "credit_used_init_uu": 0,
    "usage_rules_zh": [
      "【裁定 R-CREDIT-01】外部信用额度是**增量额度**：它约束的是本局**新增**的外部借款，开局存量外债**不占用**额度（credit_used_init_uu == 0 因此不是口径遗漏）。理由：存量外债的约束已经由还本付息的现金流表达了，再占一次额度是重复计算。本条按该裁定的要求显式写明，不得靠读者推断；10_variable_dictionary.md §8.4 需同样写明。",
      "额度只被一件事消耗：holder == row 的政府新发债。12 号 §2 02.6：external_capacity = credit_limit_uu - credit_used_uu；发行后 credit_used_uu += issue_external（INV-034）。",
      "额度不能直接买商品。进口是现金交易；额度通过限制政府能借到多少现金来间接约束进口，见 dual_constraint_rule。",
      "国内额度（state.gov.credit_limit_domestic_memo_uu，且再受 invpool 现金与 param.household_bond_appetite_ppm 约束）与外部额度是两条独立额度，任何一条用尽都不得由另一条顶替。",
      "增量额度的代价要说清楚：本局可新增外债 12 U 与历史 16 U 并存，外债总规模上限实为 28 U。若日后认为存量应占额度，必须同时调高额度，否则等于悄悄把外部通道砍掉。提议 OQ-252。",
      "冲击 S03 按 12 号 §1.1 01.7 缩放：credit_limit_uu = mul_ppm(base_credit_limit_uu, clamp(1000000 - eff_ppm[S03], 0, 1000000))。收紧只改上限，不追缴已借；若收紧后 credit_used > credit_limit，不得强制回收，只是 external_capacity 取 0。",
      "已借额度在还本时是否释放：首版不释放（param.external_credit_release_on_repayment == 0），照 12 号文件字面执行。代价是 120 季压测后期外部通道会单调顶死。提议 OQ-252。",
      "认购是 row 掏现金（post(kind=15, row.cash -> gov.cash)）。因此『用满外部额度』对 agent.row 现金是先减 12 000 000 000 μU 再按票息回流，是 sustainability_budget 的真正下界情形，见 max_drawdown_case。"
    ],
    "default_penalty_rule_zh": "对外债务档（debt_service）发生欠付时，S02 立即按 param.external_credit_default_penalty_ppm 永久调低基准额度：base_credit_limit_uu = mul_ppm(base_credit_limit_uu, 1000000 - 250000)，逐次累乘且不可恢复，并写 log.arrears。12 号 §2.2 只写『credit_limit 收紧』而没有给量，本条补齐该量。提议 OQ-253。",
    "tightening_price_rule": {
      "purpose_zh": "补齐 12 号 §2 02.6 公式里留空的『外部收紧冲击加成』。该项无名无值会让外部融资在收紧时只减量不涨价，与计划书 §07『用额度与融资价格模拟外部约束』直接冲突。",
      "formula_zh": "external_premium_ppm_per_q = param.external_spread_ppm_per_q + max(0, state.world.sovereign_rate_ppm_per_q - param.market_rate_base_ppm) + mul_ppm(param.external_utilization_premium_ppm, utilization_ppm)",
      "utilization_ppm_zh": "utilization_ppm = mul_div_floor(state.world.credit_used_uu, 1000000, max(state.world.credit_limit_uu, 1))　# rounding: floor, reason=不夸大已用比例。**必须走 mul_div_floor**：新刻度下 credit_used_uu 的契约上界 4×10¹⁵ 乘 10⁶ 得 4×10²¹，裸乘真的溢出 int64（R-SCALE-01 连带要求 1）。credit_limit 被冲击压到 0 时取分母 1，结果恒为额度上限档，不做除零。",
      "final_coupon_zh": "coupon_ppm_per_q = clamp(market_ppm + external_premium_ppm_per_q, param.coupon_min_ppm, param.coupon_max_ppm)；写入债券批次后永不重定价（计划书 §07『固定利率旧债不因新发利率变化而全部重定价』，INV-036）。基线取值：market 10 000 + spread 2 000 + 使用率加价 0 = 12 000 ppm/季，落在 [2 000, 60 000] 内。",
      "monotonicity_requirement_zh": "额度越紧（utilization 越高、credit_limit 越低、sovereign_rate 越高），新发外债票息必须单调不降。建议回归测试 T-S-EXT-CREDIT-PRICE 断言该单调性，并断言旧批次票息不变。",
      "dependency_status_zh": "本式引用的 param.market_rate_base_ppm 已在 content/parameters/params_core.json 落地，取值 10 000 ppm，与 world_init.sovereign_rate_ppm_per_q 相等——『无冲击时 S01 重算结果等于初值』这条一致性现在可被校验。两者必须一起改。"
    }
  },

  "dual_constraint_rule": {
    "statement_zh": "进口必须同时通过两道相互独立的闸门，任一不通过即减量或停摆。不存在任何靠标签绕开的路径（计划书 §07『不能仅靠外汇充足标签无限采购』）。",
    "gate_a_quantity_zh": "物量闸：flow.world.imports_uqs[s] ≤ state.world.delivery_capacity_uqs[s]（INV-104）；项目设备到货 delivered_uqs ≤ 本季交付能力剩余（INV-089）。超出部分不是欠货而是本季根本没到货，项目 status = suspended、suspension_reason = delivery，交付进度不推进。",
    "gate_b_finance_zh": "融资闸：进口以现金支付，买方现金不足即无法成交（INV-016）；政府补足现金的唯一外部途径是发外债，受 credit_limit_uu - credit_used_uu 约束（INV-034）。额度用尽 ⇒ 借不到 ⇒ 付不出 ⇒ 项目 suspension_reason = financing，已付部分不退。",
    "independence_zh": "两闸必须各自可单独失败：交付能力为 0 而额度充裕时停在 delivery；额度为 0 而交付能力充裕时停在 financing。任何把两者合成一个标量『外部可购买力』的实现都是错的，会让两条失败路径退化成一条。",
    "forbidden_zh": [
      "禁止设置任何『外汇充足』『储备充足』布尔标签并据以放行采购。",
      "禁止用外部信用额度直接抵扣进口货款；额度只能先变成债券本金、再变成国库现金、最后才变成付款。",
      "禁止在现金不足时向 agent.row 无限赊购：对外欠付必须逐笔登记 pay/recv 并进入 INV-019 对账，且计入支付优先级排序。",
      "禁止因为『本季进口没用满交付能力』而把剩余额度结转到下季；交付能力是每季独立上限。"
    ],
    "test_refs": ["test_s_import_cap", "T-S-P04-FAIL-DELIVERY", "T-S-P04-FAIL-FINANCING"]
  },

  "sustainability_budget": {
    "why_zh": "全经济现金总量恒定（INV-018），agent.row 是有限现金的主体。出口是 row 掏现金买货，因此基年出口规模的上限，实际由 row 初始现金加上本国支付给 row 的款项（对外还本付息、进口货款）决定。这是首版最容易被忽略的硬约束：出口定高了，row 现金会见底，出口被迫归零，而原因不在任何经济机制里，玩家无法解释——正是计划书 §04『报告必须能解释』要避免的情形。",
    "row_cash_init_uu": 15000000000,
    "_note_row_cash_init_uu": "15 U",
    "export_total_40q_uu": 20000000000,
    "_note_export_total_40q_uu": "20 U，即每季 500 000 000 μU × 40 季",
    "required_inflow_to_row_40q_uu": 5000000000,
    "_note_required_inflow_to_row_40q_uu": "5 U，即 40 季出口总额 20 000 000 000 μU 减 row 初始现金 15 000 000 000 μU；本国至少要向 row 支付这么多，否则 row 现金见底。",
    "basis_zh": "以下数字不是估算，是按 content/scenarios/chengwan/government_init.json 里 holder == row 的两笔真实批次逐季算出的：bond.q-8_01（面值 13500000000、q=0 期初余额 10000000000、票息 12500 ppm/季、level_principal、到期 q=19）与 bond.q-2_01（6000000000、票息 13500 ppm/季、bullet、到期 q=7）。level_principal 的期数按 12 号 §2 02.4 还原为 maturity_q - issue_q = 27 期 × 500000000 μU，q=0 期初已付 7 期，余额精确等于登记值；同一还原法在 invpool 的 bond.q-12_01 上同样精确对上，两笔互证。",
    "external_interest_40q_uu": 1960500000,
    "external_principal_40q_uu": 16000000000,
    "external_inflow_40q_uu": 17960500000,
    "_note_external_inflow_40q_uu": "利息 1960500000 + 本金 16000000000。两笔外债在 q=19 前全部结清。",
    "row_cash_peak_uu": 22960500000,
    "row_cash_peak_q": 19,
    "row_cash_min_40q_uu": 12960500000,
    "row_cash_min_40q_q": 39,
    "trajectory_check_zh": "无冲击、无进口、无新增外债（对 row 最不利）时：q=0..19 回流大于出口支出，row 现金由 15000000000 单调升到 22960500000 μU；q=20..39 只出不进，每季 -500000000，降到 12960500000 μU。对账：15000000000 + 17960500000 - 20000000000 = 12960500000，精确闭合。40 季全程为正，期末余量相当于 25.9 季出口。",
    "max_drawdown_case": {
      "assumption_zh": "q=0 政府一次用满外部额度 12000000000 μU（row 掏现金认购），新批次取本规则下的票息下界 12000 ppm/季（market 10000 + spread 2000 + 使用率加价 0）、bullet、到期晚于 q=39。这是 row 现金的真正下界情形。",
      "row_cash_min_uu": 3206000000,
      "row_cash_min_q": 0,
      "row_cash_end_40q_uu": 6576500000,
      "conclusion_zh": "下界 3206000000 μU > 0。首版 40 季的出口规模在任何发债路径下都站得住，不需要下调 export_baseline_uqs_per_q。新批次每季利息 mul_ppm(12000000000, 12000) = 144000000 μU，q=1..39 共 5616000000 μU，正是期末高于无新债情形的原因。"
    },
    "stress_120q_finding": {
      "status": "open",
      "row_cash_exhausted_q": 65,
      "finding_zh": "两笔外债在 q=19 前结清，此后若无新外债利息、也无政府设备进口付款，row 每季净减 500000000 μU：q=64 末余 460500000 μU，q=65 出口被现金截断为 460500000 μU（460500 μQ_s，不足基准量 500000 μQ_s），q=66 起出口为 0。这不是崩溃，也不违反任何不变量，但属于『指标塌了而原因不在任何机制里』，与计划书 §04 冲突。",
      "forbidden_fix_zh": "禁止用『给 row 补现金』『出口保底』之类的后处理补丁绕过（计划书 §13）。",
      "allowed_fix_zh": "只有两条合规路线：开放经常性进口通路（提议 OQ-251，让本国持续付钱给 row）；或先改 OQ-201 再调大 world_init.cash_uu 并同步改 scenario.total_cash_uu。在裁定前，120 季压测必须把截断写进 flow.cell.unmet_demand_uqs 并在报告中给出可读原因。",
      "open_question_ref": "提议 OQ-255"
    },
    "dependency_note_zh": "本表已按 government_init.json 的现行批次核对通过。若该文件的外债批次（票息、摊还方式、到期季、holder）发生变化，本表全部数字失效，必须重算；外债余额低于 16 U、或 40 季内提前还清且此后无其它回流时，还要同步下调 export_baseline_uqs_per_q。",
    "recommended_assertion": {
      "id": "assert.row_cash_nonneg",
      "at": "q_end:39",
      "expr": "min_q(0..39, agent.row.cash_uu)",
      "expect_ge": 0,
      "owner_file": "content/scenarios/chengwan/assertions.json",
      "note_zh": "本文件不写 assertions.json（由剧本负责人维护），此处只登记建议。11 号 §5.11 的表达式语言目前没有 min_q，也没有 expect_ge（只有 expect + tolerance），需要先扩表达式语言。提议 OQ-254。"
    },
    "scaling_rule_zh": "每新增 1 U/季 的经常性进口回流，出口基准可同步上调 1 U/季；每上调 1 U/季 出口而无对应回流，需要额外 40 U 的 row 初始现金。放宽 world_init.cash_uu 必须先改 OQ-201，并同时改 scenario.total_cash_uu，不能单方面在本文件里放宽。"
  },

  "shock_binding": {
    "writable_whitelist": [
      "state.world.export_demand_ppm",
      "state.world.import_price_ppm",
      "state.world.credit_limit_uu",
      "state.world.sovereign_rate_ppm_per_q",
      "state.world.delivery_capacity_uqs"
    ],
    "channels": [
      { "shock_id": "shock.S01", "channel": "export_demand", "target_field": "state.world.export_demand_ppm", "base_field": "world_init.export_demand_ppm", "clamp_range_ppm": [0, 3000000] },
      { "shock_id": "shock.S02", "channel": "import_price", "target_field": "state.world.import_price_ppm", "base_field": "world_init.import_price_ppm", "clamp_range_ppm": [100000, 5000000] },
      { "shock_id": "shock.S03", "channel": "external_credit", "target_field": "state.world.credit_limit_uu", "base_field": "external_credit.base_credit_limit_uu", "also_writes": "state.world.sovereign_rate_ppm_per_q", "clamp_range_ppm": [0, 100000] }
    ],
    "rules_zh": [
      "冲击只写上述白名单字段，绝不直接写国内账户、产能、库存或人口（INV-108、V-SH-04）。",
      "每次抽样写 log.rng 与 shock_log，含 draw_index / raw_u64 / mapped_value（计划书 §07『每次抽样写入日志』，V-SH-05）；存档重载不得重抽已确定的冲击（INV-109）。",
      "冲击强度与持续时间由 content/shocks/shock_S0*.json 配置；本文件只提供基准值与上下限，不复制冲击参数，避免出现第二处事实来源。",
      "shock.S01 的 target_weights_ppm 落在 services 上不会产生任何可观察后果，因为该部门出口基准与交付能力均为 0；冲击文件应把权重集中在 agri / manu / energy，否则会出现『抽到了冲击但什么也没发生』的不可解释现象。",
      "shock.S03 同时改额度与利率：额度按 (1 - eff) 缩放，利率按 param.rate_sensitivity_ppm 传导，二者共用同一次抽样，不得分别抽样。"
    ]
  },

  "value_cards": [
    {
      "field_ref": "world_init.fx_rate_ppm",
      "value": 1000000,
      "unit": "ppm",
      "source_type": "design_assumption",
      "source_ref": "计划书 §07「首版固定汇率」；10 号文件 §8.4 INV-105",
      "reference_year": 0,
      "definition": "本币对外部记账单位的固定汇率，1 000 000 ppm 表示 1:1。首版为常量，任何运行期写入都是程序缺陷。",
      "valid_range": [1000000, 1000000],
      "confidence": "high",
      "calibration_note": "永不校准。引入浮动汇率必须先引入外币债务与估值变动，属计划书 §18 方向 C 的后续工作，不在首版。"
    },
    {
      "field_ref": "world_init.export_demand_ppm",
      "value": [1000000, 1000000, 1000000, 1000000],
      "unit": "ppm",
      "source_type": "design_assumption",
      "source_ref": "scenario.json#world_init；计划书 §07「出口需求变化」",
      "reference_year": 0,
      "definition": "分部门外部需求指数。基年 1 000 000 表示外部需求恰好等于 export_baseline_uqs_per_q，此后只由 shock.S01 改写。valid_range 逐元素适用。",
      "valid_range": [0, 3000000],
      "confidence": "medium",
      "calibration_note": "基年必须恰为 1 000 000，否则基准出口量与基年出口额两处各写一遍、互相漂移。校准出口波动请改 shock.S01 的强度区间，不改本初值。"
    },
    {
      "field_ref": "world_init.import_price_ppm",
      "value": [1000000, 1000000, 1000000, 1000000],
      "unit": "ppm",
      "source_type": "design_assumption",
      "source_ref": "scenario.json#world_init；计划书 §07「进口能源／设备价格变化」",
      "reference_year": 0,
      "definition": "分部门外部价格指数，相对 content.price.base_uu_per_qs。基年 1 000 000 使外部到岸价与基年价相等。valid_range 逐元素适用。",
      "valid_range": [100000, 5000000],
      "confidence": "medium",
      "calibration_note": "基年偏离 1 000 000 会让 GDP 的进口项与基年价口径不一致，直接冲击 assert.base_year_gdp。只允许由 shock.S02 偏离。"
    },
    {
      "field_ref": "world_init.delivery_capacity_uqs",
      "value": [400000, 2400000, 600000, 0],
      "unit": "μQ_s/季",
      "source_type": "design_assumption",
      "source_ref": "scenario.json#world_init；10 号文件 §8.4；INV-104、INV-089",
      "reference_year": 0,
      "definition": "外部世界每季可交付／可吸纳的分部门物量上限。首版按方向各自独立适用同一上限：进口受它约束，出口也受它约束，两方向不共享额度池。services 为 0 表示不跨境。",
      "valid_range": [0, 100000000],
      "confidence": "low",
      "calibration_note": "实物量，不随 R-SCALE-01 改变。manu 的 2 400 000 μQ_s/季 必须同时容得下出口基准 350 000 与项目设备进口峰值（P04 为 200 000/季，P08 更高）与企业资本品进口。若 P08 规格超出，先改本值再改政策，不得在结算里放宽 INV-104。"
    },
    {
      "field_ref": "world_init.credit_limit_uu",
      "value": 12000000000,
      "unit": "μU",
      "source_type": "design_assumption",
      "source_ref": "scenario.json#world_init；OQ-201；计划书 §07「外部世界不能成为无限资金源」",
      "reference_year": 0,
      "definition": "本局政府可累计向外部借入的本金上限（12 U = 12 000 000 000 μU = 基年 GDP 100 000 000 000 μU 的 12%）。被 shock.S03 按比例调低，被对外欠付按 default_penalty_rule 永久调低。按裁定 R-CREDIT-01 它只约束新增借款。",
      "valid_range": [0, 100000000000],
      "confidence": "low",
      "calibration_note": "G1 的 40 季无命令基线跑完后检查 credit_used 轨迹：若从未触顶，说明外部约束没有咬合，应调低而不是调高；若第一年就触顶，先查赤字与国内额度的分担，再动本值。一次用满会让 agent.row 现金立刻少 12 000 000 000 μU，下界见 sustainability_budget.max_drawdown_case。"
    },
    {
      "field_ref": "world_init.sovereign_rate_ppm_per_q",
      "value": 10000,
      "unit": "ppm/季",
      "source_type": "design_assumption",
      "source_ref": "scenario.json#world_init；12 号文件 §1.1 01.7",
      "reference_year": 0,
      "definition": "当季主权融资基准利率（季度口径，10 000 ppm/季 ≈ 4%/年）。S01 每季按 param.market_rate_base_ppm 与 shock.S03 重算，本初值只在 q=0 的 S01 之前有效。",
      "valid_range": [0, 100000],
      "confidence": "low",
      "calibration_note": "本值必须与 param.market_rate_base_ppm 相等，使无冲击时 S01 的重算结果与初值一致；params_core.json 现取 10 000，两处已相等，这条一致性可被校验。两者必须一起改，否则存档载入瞬间的利率与第一季利率不一致，报告会出现无法解释的跳变。"
    },
    {
      "field_ref": "world_init.cash_uu",
      "value": 15000000000,
      "unit": "μU",
      "source_type": "design_assumption",
      "source_ref": "OQ-201 的示例取值（row = 15 U）；scenario.json 的 total_cash_uu = 63716000000 的分配（R-REGION-01）；INV-018",
      "reference_year": 0,
      "definition": "agent.row 的初始现金存量，是全经济现金总量的一部分。它同时是首版出口规模的真实上限来源（见 sustainability_budget）。",
      "valid_range": [0, 200000000000],
      "confidence": "low",
      "calibration_note": "63.716 U 的现行分解（R-REGION-01 之后，已逐文件求和核对）：gov 2000000000 + invpool 9000000000 + row 15000000000 + 36 群组 9000000000 + 16 个 cell 28716000000 = 63716000000 μU。调大本值等于放松外部吸纳约束，必须先改 OQ-201，再同步改 scenario.total_cash_uu 与 cells 的配额，最后重算出口基准与 row 现金轨迹。不得单方面在本文件放宽。"
    },
    {
      "field_ref": "export_demand.export_baseline_uqs_per_q",
      "value": [100000, 350000, 50000, 0],
      "unit": "μQ_s/季",
      "source_type": "design_assumption",
      "source_ref": "12 号文件 §5.6 出口需求行引用的「基准出口量[s]」（三份契约均无字段归宿，本文件补齐）；计划书 §05 基年 GDP 100 U",
      "reference_year": 0,
      "definition": "外部需求指数为 1 000 000 时，每季分部门的基准出口需求量。合计 500 000 μQ_s/季，按基年价折 500 000 000 μU/季 = 0.5 U/季 = 2 U/年 = 基年名义 GDP 的 2%。",
      "valid_range": [0, 2400000],
      "confidence": "low",
      "calibration_note": "该值由 sustainability_budget 的 row 现金约束反推得出，不是对现实贸易开放度的估计。按现行外债批次，40 季轨迹全程为正且下界 3206000000 μU（用满外部额度情形），本值无需下调；但 120 季压测下 row 现金在 q≈65 见底（stress_120q_finding）。上调之前必须先满足两件事之一：开放经常性进口通路（提议 OQ-251），或调大 row 初始现金（OQ-201）。每次上调都要重跑 row 现金轨迹。"
    },
    {
      "field_ref": "export_demand.tradable",
      "value": [1, 1, 1, 0],
      "unit": "dimensionless",
      "source_type": "derived",
      "source_ref": "由 world_init.delivery_capacity_uqs 推出",
      "reference_year": 0,
      "definition": "部门是否存在跨境通路。1 表示该部门的进出口在结构上可能发生。",
      "valid_range": [0, 1],
      "confidence": "high",
      "calibration_note": "派生值，必须与交付能力保持一致；不一致说明有一个部门被配置了出口却永远成交为 0。",
      "derivation_expr": "tradable[s] == (delivery_capacity_uqs[s] > 0 ? 1 : 0)"
    },
    {
      "field_ref": "import_supply.external_price_uu_per_qs_init",
      "value": [1000000000, 1000000000, 1000000000, 1000000000],
      "unit": "μU/Q_s",
      "source_type": "derived",
      "source_ref": "content.price.base_uu_per_qs × world_init.import_price_ppm",
      "reference_year": 0,
      "definition": "基年外部到岸价。固定汇率下不做汇率换算，故与基年价 BASE_PRICE = 1 000 000 000 μU/Q_s 相等。",
      "valid_range": [100000000, 5000000000],
      "confidence": "high",
      "calibration_note": "派生值，不单独配置；改 import_price_ppm 即改它。valid_range 是 base_uu_per_qs 乘 import_price_ppm 的区间 [100000, 5000000] 得来，随 R-SCALE-01 一并 ×1000；它是外部到岸价，不受国内价格闸 PRICE_MIN/PRICE_MAX（4×10⁸ / 2.5×10⁹）约束。若两处不一致，以 import_price_ppm 为准并报错。",
      "derivation_expr": "external_price_uu_per_qs[s] == mul_ppm(base_uu_per_qs[s], import_price_ppm[s])"
    },
    {
      "field_ref": "external_credit.credit_used_init_uu",
      "value": 0,
      "unit": "μU",
      "source_type": "design_assumption",
      "source_ref": "10 号文件 §8.4 state.world.credit_used_uu 初值 0；裁定 R-CREDIT-01",
      "reference_year": 0,
      "definition": "开局已用外部额度。取 0 表示开局存量外债是历史遗留，不占用本局新增额度——这是裁定 R-CREDIT-01 的『增量额度』口径，不是口径遗漏。",
      "valid_range": [0, 0],
      "confidence": "medium",
      "calibration_note": "若改为『存量外债占用额度』，必须同时把 credit_limit_uu 调高同等金额，否则等于悄悄把外部融资空间砍成负数。与提议 OQ-252 一并裁定。"
    }
  ],

  "parameter_cards": [
    {
      "parameter_id": "param.export_price_elasticity_ppm",
      "value": [0, 0, 0, 0],
      "unit": "ppm",
      "source_type": "design_assumption",
      "source_ref": "计划书 §07「出口需求变化」；12 号文件 §5.6 出口需求行",
      "reference_year": 0,
      "definition": "国内现价每高出基年价 1 ppm，可实现出口量下降的比例（ppm）。首版为 0，即出口量对价格无弹性，价格只影响出口收入。valid_range 逐元素适用。",
      "valid_range": [0, 2000000],
      "confidence": "low",
      "calibration_note": "启用前必须先在 12 号文件 §5.6 的出口需求行加入 competitiveness_ppm 项（提议 OQ-247）。启用后做三档敏感性：若外部冲击的传导幅度相差一个量级，说明结论只依赖这一个脆弱参数，应先收紧区间再谈校准。"
    },
    {
      "parameter_id": "param.external_spread_ppm_per_q",
      "value": 2000,
      "unit": "ppm/季",
      "source_type": "design_assumption",
      "source_ref": "计划书 §07「用额度与融资价格模拟外部约束」；12 号文件 §2 02.6 留空的「外部收紧冲击加成」",
      "reference_year": 0,
      "definition": "holder == row 的新发债相对同期国内市场利率的结构性利差（2 000 ppm/季 ≈ 0.8%/年）。与冲击加成、额度使用率加价相加后统一 clamp。比率参数，不随 R-SCALE-01 改变。",
      "valid_range": [0, 20000],
      "confidence": "low",
      "calibration_note": "检验方式：无冲击基线下外债票息应稳定高于同期内债票息且差额恒定。若玩家在任何情况下都优先借外债，说明利差过低。"
    },
    {
      "parameter_id": "param.external_utilization_premium_ppm",
      "value": 6000,
      "unit": "ppm/季",
      "source_type": "design_assumption",
      "source_ref": "计划书 §07「外部融资收紧」；本文件 external_credit.tightening_price_rule",
      "reference_year": 0,
      "definition": "外部额度使用率为 100% 时叠加到新发外债票息上的最大加价（6 000 ppm/季 ≈ 2.4%/年），按使用率线性折算。",
      "valid_range": [0, 40000],
      "confidence": "low",
      "calibration_note": "检验方式：连续借外债时票息必须单调上升（T-S-EXT-CREDIT-PRICE）。若额度快用完时融资成本几乎没变，『额度收紧』就只剩数量约束、失去价格信号，应调高该值而不是缩小额度。"
    },
    {
      "parameter_id": "param.external_credit_default_penalty_ppm",
      "value": 250000,
      "unit": "ppm",
      "source_type": "design_assumption",
      "source_ref": "12 号文件 §2.2「debt_service 推迟 ⇒ credit_limit 收紧」（未给量）",
      "reference_year": 0,
      "definition": "发生对外债务欠付时，基准外部信用额度被永久调低的比例（25%）。逐次累乘，不可恢复。",
      "valid_range": [0, 1000000],
      "confidence": "low",
      "calibration_note": "检验方式：恶意玩家用例「借新还旧是否永远没有成本」（计划书 §17）。若连续违约后仍能持续融资，说明该值过低；应先调高它，而不是在结算里加一条硬性禁止。"
    },
    {
      "parameter_id": "param.import_lead_time_q",
      "value": [0, 0, 0, 0],
      "unit": "季",
      "source_type": "design_assumption",
      "source_ref": "计划书 §07「进口还受交付能力与外部信用额度约束」；12 号文件 §5.5 到货公式",
      "reference_year": 0,
      "definition": "下单到到货的时滞。首版一律 0：到货量当季由交付能力截断，时滞效果由交付能力不足分季表达。valid_range 逐元素适用。",
      "valid_range": [0, 4],
      "confidence": "low",
      "calibration_note": "启用非零值会直接改变 P04「第 8 季交付齐全才可投运」的验收口径（计划书 §10），必须同时改 12 号 §5.5 与 P04 的验收测试。先做提议 OQ-250 的裁定再动本值。"
    },
    {
      "parameter_id": "param.external_credit_release_on_repayment",
      "value": 0,
      "unit": "dimensionless",
      "source_type": "design_assumption",
      "source_ref": "12 号文件 §2 02.6（只写 credit_used_uu 增加，未写任何释放路径）；裁定 R-CREDIT-01",
      "reference_year": 0,
      "definition": "还本时是否把已用外部额度释放回可用额度。0 = 不释放（额度是本局累计发行上限），1 = 释放（额度是余额上限）。与 R-CREDIT-01 的『增量额度』口径一致：额度管的是新增发行的累计量。",
      "valid_range": [0, 1],
      "confidence": "low",
      "calibration_note": "检验方式：120 季压力测试中观察 credit_used 是否在中后期单调顶死、外部通道彻底失效。若失效，先在提议 OQ-252 裁定改为 1，再改 12 号文件，最后改本值并补一条会因放宽而失败的回归测试。"
    }
  ],

  "notes_zh": "数字为测试起点，不是现实国家数据，也不是已经跑出的结果。本文件不含任何平衡修正项、凭空补贴或后处理补丁（计划书 §13）；外部世界的每一笔收支都必须以 agent.row 为对手方（INV-026），外部世界的每一次放宽都必须先改待决问题登记、再改契约、最后才改数据。"
}
```

---

## 5 待决问题（**提议编号，尚未在 `13_open_questions.md` 登记**）

`13_open_questions.md` 现登记到 **OQ-245** 为止。下列编号是本设计记录**提议**占用的，
按 13 号 §H「编号一经登记不得复用」的纪律，**必须由该文件的负责人正式登记后才算数**；
在登记之前，本文件与内容包中对它们的引用都只是提议，不是已裁定的取法。

| 提议编号 | 问题 |
|---|---|
| OQ-246 | `12_simulation_contract.md` §5.6 引用的「基准出口量[s]」在三份契约里没有字段归宿；同时 `delivery_capacity_uqs` 一个数组同时承担进口交付与出口吸纳两种语义，是否该拆成两个 |
| OQ-247 | 出口的价格弹性通道：§5.6 的出口公式里没有价格项，`param.export_price_elasticity_ppm` 无处可用 |
| OQ-248 | 港口通行能力是否约束外贸量。不裁定则 `policy.P08` 的效果落点无人读取，成为没有反馈链的空政策 |
| OQ-249 | `agent.row` 的实物库存是否参与库存恒等式 INV-047 |
| OQ-250 | 进口交付时滞：计划书 §07 有，12 号 §5.5 的到货公式没有 |
| OQ-251 | 经常性进口供给缺少结算步：能源与农产品的额度已配置，但 §5.6 的买方类里没有任何通路让外部产品进入国内供给 |
| OQ-252 | 外部额度：R-CREDIT-01 已裁定存量外债不占用额度；尚未裁定的是「还本是否释放额度」，以及外债总规模上限实为 28 U 是否可接受 |
| OQ-253 | 对外违约导致的额度收紧量（12 号 §2.2 只写「收紧」没给量） |
| OQ-254 | `assertions` 的表达式语言缺 `min_q` 与 `expect_ge`，无法表达「row 现金全程非负」 |
| OQ-255 | 120 季压测下 `agent.row` 现金在 q≈65 见底导致出口断供，成因不在任何经济机制里（见 §2.4） |
| OQ-256 | **本轮新增**：`world.json` 被移出内容包后，`11_data_contract.md` §10.5 第 4 条所说的「world.json 是否进 §2」仍未裁定。若将来裁定「要进」，必须同时给出 `world_init` 类型的 `V-*` 校验表，否则等于把无人校验的数据接进载入器 |

另有一条**不属于本文件、但在核对中撞到**的问题，留给对应负责人：

- `world.json` 删除后，它曾提供的 6 张 `param.*` 身份证在内容包里没有归宿。
  按 R-PARAM-01「只有 `param.*` 建正式卡片」，这 6 个参数**必须**有卡；
  在 `params_core.json` 收下它们之前，内容包对这几个参数是无卡状态（见 §3 第一行）。

---

*本文件是设计记录，不是内容包文件。载入器不读它，`content_hash` 不含它。*
