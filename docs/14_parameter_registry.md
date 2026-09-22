# 14 参数登记表（生成物，勿手改）

> 本文件由 `tools/build_param_registry.py` 扫描 `content` 下全部 JSON 生成，对应计划书 §14「每个参数都带一张身份证」与`docs/11_data_contract.md` §5.15 `ParameterCard`。
> 任何手工修改都会在下次生成时被覆盖：**改参数请改来源文件**。
> 工具只报告、不修正；它不含任何模拟逻辑（计划书 §12「Python 只用于离线分析」）。

## 0 证据状态仪表盘

计划书 §14「本版本的证据状态」：**尚未完成数据下载与现实样本拟合**。下表是这句话的机器版本——它诚实地显示这个模型此刻建立在多少作者假设之上。

| source_type | 含义 | 卡片数 | 占比 | |
|---|---|---:|---:|---|
| `design_assumption` | 设计假设（作者拍板，待校准） | 91 | 94.7917% | `██████████████████████··` |
| `derived` | 派生计算（须给 derivation_expr） | 5 | 5.2083% | `█·······················` |

**V-PC-04 闸门（首版 `observed` 必须为 0）**：✅ 通过，observed = 0。

**一句话读数**：96 张身份证中有 96 张（100.0000%）没有任何外部证据支撑，只有作者假设与由假设派生的计算。这不是缺陷，是首版的**真实状态**；它决定了本版结论只能用于机制验证，不能用于现实预测。

### 置信度分布

| confidence | 卡片数 | 占比 | |
|---|---:|---:|---|
| `low` | 81 | 84.3750% | `████████████████████····` |
| `medium` | 12 | 12.5000% | `███·····················` |
| `high` | 3 | 3.1250% | `························` |

## 1 校验结果

- 扫描文件：37（跳过 1）
- 参数身份证：96
- 近似卡（带卡片字段但无 `parameter_id`，未进登记表）：4
- **ERROR：0**（按契约应拒绝加载）
- WARN：26（不阻断加载，但应在 G0 关闭前清掉）

### 1.1 问题汇总

| 检查码 | 级别 | 契约错误码 | 条目数 | 检查内容 |
|---|---|---|---:|---|
| PR-017 | WARN | `E_UNIT_MISMATCH` | 1 | ID 后缀与单位一致（§0.2） |
| PR-018 | WARN | `E_UNIT_MISMATCH` | 21 | 单位拼写在两份契约间统一 |
| PR-024 | WARN | `E_PARAM_CARD` | 4 | 近似卡：有卡片字段但无 parameter_id |

### 1.2 逐条明细

| 级别 | 检查码 | parameter_id | 位置 | 说明 |
|---|---|---|---|---|
| WARN | PR-017 | `param.pension_uu_per_elder_q` | `parameters/params_core.json/cards/74` | ID 后缀 `_q` 按 10 号文件 §0.2 应配 q 或 季，实得 'μU/人/季'。名字与单位不一致时，两处迟早有一处是错的。 |
| WARN | PR-018 | `param.bond_batch_cap` | `parameters/params_core.json/cards/6` | `unit` = '批' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.commitment_horizon_q` | `parameters/params_core.json/cards/7` | `unit` = '季' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.default_grace_q` | `parameters/params_core.json/cards/11` | `unit` = '季' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.edu_pipeline_slots` | `parameters/params_core.json/cards/14` | `unit` = '季' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.log_capacity_rows` | `parameters/params_core.json/cards/28` | `unit` = '行' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.max_defer_count` | `parameters/params_core.json/cards/88` | `unit` = '次' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.max_defer_quarters` | `parameters/params_core.json/cards/89` | `unit` = '季' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.no_confidence_q` | `parameters/params_core.json/cards/42` | `unit` = '季' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.pension_uu_per_elder_q` | `parameters/params_core.json/cards/74` | `unit` = 'μU/人/季' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.persons_per_housing_unit` | `parameters/params_core.json/cards/46` | `unit` = '人/套' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.price_clamp_budget_count` | `parameters/params_core.json/cards/49` | `unit` = '次' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.proc_transparency_decay_q` | `parameters/params_core.json/cards/95` | `unit` = '季' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.proc_transparency_ramp_q` | `parameters/params_core.json/cards/85` | `unit` = '季' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.rng_salt` | `parameters/params_core.json/cards/56` | `unit` = 'int64' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.rule_issue_tenor_q` | `parameters/params_core.json/cards/75` | `unit` = '季' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.student_teacher_ratio` | `parameters/params_core.json/cards/57` | `unit` = '人' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.training_lag_q` | `parameters/params_core.json/cards/62` | `unit` = '季' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.trust_streak_cap_q` | `parameters/params_core.json/cards/65` | `unit` = '季' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.wage_ceil_uu` | `parameters/params_core.json/cards/68` | `unit` = 'μU/人/季' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.wage_floor_uu` | `parameters/params_core.json/cards/69` | `unit` = 'μU/人/季' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-018 | `param.write_guard_sample_q` | `parameters/params_core.json/cards/72` | `unit` = '季' 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。两处拼写不统一时，单位一致性无法被机器完全证明。 |
| WARN | PR-024 | `-` | `policies/policy_P09.json/player_params/0` | 该对象带有身份证字段却无 `parameter_id`（key = region_mask，容器 `player_params`），未进登记表。若它本应是 param.* 参数，请补 `parameter_id`；若它是内容数据或玩家杠杆，请确认契约 §5.15「内容数据不建卡」的分界线仍然成立。 |
| WARN | PR-024 | `-` | `policies/policy_P09.json/player_params/1` | 该对象带有身份证字段却无 `parameter_id`（key = min_investment_ratio_ppm，容器 `player_params`），未进登记表。若它本应是 param.* 参数，请补 `parameter_id`；若它是内容数据或玩家杠杆，请确认契约 §5.15「内容数据不建卡」的分界线仍然成立。 |
| WARN | PR-024 | `-` | `policies/policy_P09.json/player_params/2` | 该对象带有身份证字段却无 `parameter_id`（key = subsidy_rate_ppm，容器 `player_params`），未进登记表。若它本应是 param.* 参数，请补 `parameter_id`；若它是内容数据或玩家杠杆，请确认契约 §5.15「内容数据不建卡」的分界线仍然成立。 |
| WARN | PR-024 | `-` | `policies/policy_P09.json/player_params/3` | 该对象带有身份证字段却无 `parameter_id`（key = cap_per_cell_per_q_uu，容器 `player_params`），未进登记表。若它本应是 param.* 参数，请补 `parameter_id`；若它是内容数据或玩家杠杆，请确认契约 §5.15「内容数据不建卡」的分界线仍然成立。 |

## 2 契约「首版必备参数最小集」覆盖

契约点名的首版必备参数 72 项，已建卡 72 项，**未建卡 0 项**。

✅ 最小集已全部建卡。

## 3 参数登记全表

按 `parameter_id` 升序。`value` 为整数或整数数组；单位见 `10_variable_dictionary.md` §0.1。

| parameter_id | value | unit | source_type | conf. | valid_range | 定义 | 来源文件 |
|---|---:|---|---|---|---|---|---|
| `param.amount_max_uu` | 4000000000000000 | μU | design_assumption | high | [4000000000000000, 4000000000000000] | 单笔金额与任一金额型状态字段的绝对值硬上限。超过即登记 INT_OVERFLOW 并拒绝结算，不做饱和截断。等于 4 … | `parameters/params_core.json` |
| `param.bloc_care_gain_ppm` | 300000 | ppm | design_assumption | low | [0, 1000000] | 集团所关心的指标每变化 1 000 000 ppm，其立场（stance）随之变化的传导系数。 | `parameters/params_core.json` |
| `param.bloc_org_inertia_ppm` | 700000 | ppm | design_assumption | low | [0, 1000000] | 集团组织力的惯性权重：org_power_t = mul_ppm(本值, org_power_{t−1}) + 规模项… | `parameters/params_core.json` |
| `param.bloc_resource_ref_uu` | 2000000000 | μU | design_assumption | low | [100000000, 100000000000] | 集团可动员资源折算成组织力时的参照额，等于 2 U。资源项 = mul_ppm(min(可动员资源, 本值) 相对本值… | `parameters/params_core.json` |
| `param.bloc_w_resource_ppm` | 100000 | ppm | design_assumption | low | [0, 1000000] | 集团组织力中「可动员资源相对 param.bloc_resource_ref_uu」的权重。 | `parameters/params_core.json` |
| `param.bloc_w_size_ppm` | 200000 | ppm | design_assumption | low | [0, 1000000] | 集团组织力中「成员规模相对全国劳动年龄人口」的权重。注意 bloc_affiliation_ppm 允许 Σ > 1 … | `parameters/params_core.json` |
| `param.bond_batch_cap` | 512 | 批 | design_assumption | medium | [64, 4096] | 债券台账可同时持有的批次数上限。每季至多新增两批（国内 + 外部），首版 40 季用不满；上限存在的目的是给 bond… | `parameters/params_core.json` |
| `param.commitment_horizon_q` | 16 | 季 | design_assumption | low | [4, 40] | 承诺表的滚动窗口长度（16 季）。超过本值的历史承诺不再计入信任的兑现率统计。 | `parameters/params_core.json` |
| `param.construction_share_cap_ppm` | 300000 | ppm | design_assumption | low | [0, 1000000] | 服务部门单季产出中可被项目施工占用的比例上限。它是上限，不是应当无条件扣除的固定份额。 | `parameters/params_core.json` |
| `param.coupon_max_ppm` | 60000 | ppm | design_assumption | low | [20000, 200000] | 新发债券季度票息的上限（6%/季，约 26%/年）。触顶即表示市场已不愿按价格出清，此后只能靠额度约束或违约路径处理。 | `parameters/params_core.json` |
| `param.coupon_min_ppm` | 2000 | ppm | design_assumption | low | [0, 20000] | 新发债券季度票息的下限（0.2%/季）。防止在极低偿债率下算出零息或负息。 | `parameters/params_core.json` |
| `param.default_grace_q` | 2 | 季 | design_assumption | low | [0, 8] | 政府无法足额偿付本息后，进入违约判定前的宽限季数。宽限期内欠付计入 gov.arrears_uu，不立即触发重组。 | `parameters/params_core.json` |
| `param.defer_fee_ppm_per_q` | 15000 | ppm | design_assumption | low | [0, 100000] | 延期赔偿率：每延期 1 季，按剩余合同额的该比例向承包方支付停工赔偿（人员、设备闲置），于延期当季一次付清，现金不足转… | `parameters/params_core.json` |
| `param.demand_smooth_ppm` | 400000 | ppm | design_assumption | low | [0, 1000000] | 计划产量对滞后需求的平滑权重：E_t = mul_ppm(本值, 实际需求_{t−1}) + mul_ppm(1e6 … | `parameters/params_core.json` |
| `param.dissave_ppm` | 80000 | ppm | design_assumption | low | [0, 200000] | 居民单季可动用的存量资产比例（5%）：消费预算 = mul_ppm(可支配收入, param.mpc_ppm) + m… | `parameters/params_core.json` |
| `param.edu_pipeline_slots` | 8 | 季 | design_assumption | low | [1, 16] | 培训队列可同时容纳的在训季数（队列深度）。超出即新批次排队等待，不是静默丢弃。 | `parameters/params_core.json` |
| `param.emission_decay_ppm` | 30000 | ppm | design_assumption | low | [0, 200000] | 排放存量的季度自然衰减率（3%）。季末先衰减再累加当季排放。 | `parameters/params_core.json` |
| `param.engel_weight_ppm` | [229573, 357738, 40181, 372… | ppm | design_assumption | medium | [0, 1000000] | 居民消费预算在四部门之间的分配权重，下标按 docs/10 §0.5 的稠密下标（0 agri / 1 manu / … | `parameters/params_core.json` |
| `param.env_exposure_gain_ppm` | 200000 | ppm | design_assumption | low | [0, 1000000] | 从排放存量折算到人口环境暴露指数的增益系数。暴露指数再经 param.migration_w_env_ppm 进入迁移… | `parameters/params_core.json` |
| `param.expectation_inertia_ppm` | 700000 | ppm | design_assumption | low | [0, 1000000] | 预期指数的惯性权重：expectation_t = mul_ppm(本值, expectation_{t−1}) + … | `parameters/params_core.json` |
| `param.firing_friction_ppm` | 60000 | ppm | design_assumption | low | [0, 300000] | 单季裁减人数占本 cell 现有在岗人数的比例上限（6%）。 | `parameters/params_core.json` |
| `param.gap_cap_ppm` | 500000 | ppm | design_assumption | low | [100000, 1000000] | 计入调价的供需缺口上限。实际缺口先 clamp 到 ±本值再进调价式，防止一次极端短缺把价格一步顶到 PRICE_MA… | `parameters/params_core.json` |
| `param.hiring_friction_ppm` | 100000 | ppm | design_assumption | low | [0, 300000] | 单季新增雇佣人数占本 cell 现有在岗人数的比例上限（10%）。 | `parameters/params_core.json` |
| `param.household_bond_appetite_ppm` | 600000 | ppm | design_assumption | low | [0, 1000000] | 投资池（agent.invpool）现金中单次可动用于认购新发国债的比例上限（60%）。 | `parameters/params_core.json` |
| `param.inventory_target_ppm` | 500000 | ppm | design_assumption | low | [0, 2000000] | 目标库存覆盖比例：目标期末库存 = mul_ppm(本季预期需求, 本值)。500 000 = 半个季度的需求量。只对… | `parameters/params_core.json` |
| `param.invest_propensity_ppm` | 200000 | ppm | design_assumption | low | [0, 1000000] | 企业留存现金中用于资本购置（kind=7 CAPITAL_PURCHASE）的比例（20%）。购置金额折算成产能要经 … | `parameters/params_core.json` |
| `param.io_table_set` | 548881274887433 | dimensionless | design_assumption | low | [0, 9007199254740992] | IOTable 整表技术系数的集合级身份证（V-PC-07）。IO 系数是内容数据，按裁定 R-PARAM-01 不逐… | `parameters/params_core.json` |
| `param.living_weight_house_ppm` | 250000 | ppm | design_assumption | low | [0, 1000000] | 生活指数中住房负担项的权重（25%）。收入项权重是残差式 w_income_ppm = 1 000 000 − liv… | `parameters/params_core.json` |
| `param.living_weight_service_ppm` | 250000 | ppm | design_assumption | low | [0, 1000000] | 生活指数中公共服务可及性项的权重（25%）。 | `parameters/params_core.json` |
| `param.log_capacity_rows` | 8192 | 行 | design_assumption | medium | [1024, 65536] | 单季日志（log.*）的预分配行数。热路径不得扩容；超出即登记一条溢出并丢弃后续行——丢弃必须可见，不得静默。 | `parameters/params_core.json` |
| `param.maintenance_backlog_gain_ppm` | 200000 | ppm | design_assumption | low | [0, 1000000] | 单季维护支出缺口转化为维护欠账的比例（20%）。欠账是存量，以 ppm 表示相对名义维护需求的倍数。 | `parameters/params_core.json` |
| `param.maintenance_backlog_max_ppm` | 400000 | ppm | design_assumption | low | [0, 1000000] | 维护欠账存量的上限（相对名义维护需求的 40%）。封顶存在的目的是让「已经烂到底」有明确定义，而不是让欠账无限增长后任… | `parameters/params_core.json` |
| `param.maintenance_backlog_recover_ppm` | 100000 | ppm | design_assumption | low | [0, 1000000] | 单季超额维护支出用于清偿维护欠账的比例（10%）。 | `parameters/params_core.json` |
| `param.market_rate_base_ppm` | 10000 | ppm | design_assumption | medium | [0, 100000] | 无风险基准季度利率（1%/季，约 4%/年）。新发债票息 = 本值 + 偿债率斜率项 + 外部利差项，再按 coupo… | `parameters/params_core.json` |
| `param.market_rate_slope_ppm` | 5000 | ppm | design_assumption | low | [0, 200000] | 偿债率（debt service ratio）每上升 1 000 000 ppm 所带来的票息加成系数：票息 = pa… | `parameters/params_core.json` |
| `param.max_defer_count` | 2 | 次 | design_assumption | medium | [0, 4] | 同一项目合同允许的延期次数上限（命令 6）。超出即以前置条件不满足拒绝，状态不变。 | `parameters/params_core.json` |
| `param.max_defer_quarters` | 8 | 季 | design_assumption | medium | [0, 16] | 同一项目各次延期的季数之和上限。单次季数的形状上界是承诺表滚动窗口 16 季（JWCommands.DEFER_QUA… | `parameters/params_core.json` |
| `param.migration_max_share_ppm` | 20000 | ppm | design_assumption | low | [0, 100000] | 单季迁出人数占来源群组人口的比例上限（2%），逐 (region, age, skill) 群组生效。 | `parameters/params_core.json` |
| `param.migration_threshold_ppm` | 120000 | ppm | design_assumption | low | [0, 1000000] | 触发迁移所需的地区间综合吸引力差距下限（12%）。差距小于本值时不产生任何迁移流，存在的目的是避免每季都有微小人口来回… | `parameters/params_core.json` |
| `param.migration_w_env_ppm` | 300000 | ppm | design_assumption | low | [0, 1000000] | 迁移推力中「本地环境暴露指数」的权重。 | `parameters/params_core.json` |
| `param.migration_w_house_ppm` | 700000 | ppm | design_assumption | low | [0, 1000000] | 迁移推力中「本地住房紧张（占用率与租金负担）」的权重。 | `parameters/params_core.json` |
| `param.migration_w_job_ppm` | 300000 | ppm | design_assumption | low | [0, 1000000] | 迁移拉力中「目的地空缺岗位相对本地失业」的权重。 | `parameters/params_core.json` |
| `param.migration_w_service_ppm` | 200000 | ppm | design_assumption | low | [0, 1000000] | 迁移拉力中「目的地公共服务可及性优势」的权重。 | `parameters/params_core.json` |
| `param.migration_w_wage_ppm` | 500000 | ppm | design_assumption | low | [0, 1000000] | 迁移拉力中「目的地工资率相对来源地的优势」的权重。 | `parameters/params_core.json` |
| `param.mpc_ppm` | 850000 | ppm | design_assumption | low | [0, 1000000] | 边际消费倾向：当期可支配收入中用于消费的比例（75%），其余进存款。 | `parameters/params_core.json` |
| `param.no_confidence_q` | 2 | 季 | design_assumption | low | [0, 8] | 失去留任资格（席位过半丧失或授权目标失守）后，触发终局判定前的宽限季数。 | `parameters/params_core.json` |
| `param.opex_recover_ppm` | 50000 | ppm | design_assumption | low | [0, 1000000] | 公共服务单元恢复足额拨付后，有效容量每季回升的比例（5%/季），上限是名义容量。 | `parameters/params_core.json` |
| `param.opex_starve_decay_ppm` | 150000 | ppm | design_assumption | low | [0, 1000000] | 公共服务单元在运营费未足额拨付的季度里，有效容量相对上季的衰减比例（15%/季）。 | `parameters/params_core.json` |
| `param.p09_eligible_sector_mask` | 6 | dimensionless | design_assumption | low | [1, 15] | 设备投资补助的合格部门位掩码，位序 0 agri / 1 manu / 2 energy / 3 services。值… | `parameters/params_core.json` |
| `param.p11_capacity_decay_ppm` | 15000 | ppm | design_assumption | low | [1000, 100000] | 运行费完全欠拨（shortfall == 1 000 000）或政策退出后，征收能力每季下降的 ppm 绝对值；按 s… | `parameters/params_core.json` |
| `param.p11_capacity_floor_ppm` | 760000 | ppm | derived | medium | [0, 1000000] | 断供或退出时征收能力的回落下限，等于剧本基年征收能力：本政策最坏只能退回实施前的水平，不会让国家比没做过这件事更差。 | `parameters/params_core.json` |
| `param.p11_capacity_recover_ppm` | 5000 | ppm | design_assumption | low | [500, 50000] | 运行费恢复足额拨款后，征收能力每季回升的 ppm 绝对值；上限为建成水平 state.gov.tax_capacity… | `parameters/params_core.json` |
| `param.p11_region_base_share_ppm` | [180000, 330000, 340000, 15… | ppm | design_assumption | low | [0, 1000000] | 各地区占全国可征税基的份额，下标 beiyuan / zhongzhou / haijia / xiling；regi… | `parameters/params_core.json` |
| `param.p11_staff_gain_full_ppm` | 60000 | ppm | design_assumption | low | [0, 200000] | 人员投入满编（staffing_scale_ppm == 1 000 000）时征收能力乘数的可达增量上限（ppm 绝… | `parameters/params_core.json` |
| `param.p11_system_gain_full_ppm` | 60000 | ppm | design_assumption | low | [0, 200000] | 信息系统达到设计规模（system_scale_ppm == 1 000 000）时征收能力乘数的可达增量上限（ppm… | `parameters/params_core.json` |
| `param.p11_tax_capacity_ceiling_ppm` | 920000 | ppm | design_assumption | low | [800000, 990000] | 征收能力乘数的硬上限。不存在 100% 征收；越过上限的增量被夹逼为 0。 | `parameters/params_core.json` |
| `param.payout_ratio_ppm` | 1000000 | ppm | design_assumption | low | [0, 1000000] | 企业税后利润中分配给居民（财产性收入，kind=18 PROPERTY_INCOME）的比例（30%），其余留存为营运… | `parameters/params_core.json` |
| `param.pension_uu_per_elder_q` | 240 | μU/人/季 | design_assumption | low | [0, 5000] | 基本养老金（R-PENSION-01）：每位老年人口每季领取的定额，作为法定转移的常设部分，与 P03 失业救济同档（… | `parameters/params_core.json` |
| `param.persons_per_housing_unit` | 3 | 人/套 | design_assumption | low | [1, 10] | 每套住房的标准居住人数。用于把地区住房存量折算成可容纳人口，进而算住房紧张度与迁移推力。 | `parameters/params_core.json` |
| `param.policy_toggle_cost_uu` | 10000000 | μU | design_assumption | low | [0, 1000000000] | 任一政策开启或关闭一次的一次性行政成本（0.01 U）。从政府现金扣除，按 kind=26 POLICY_TOGGLE… | `parameters/params_core.json` |
| `param.price_ceil_ppm` | 2500000 | ppm | design_assumption | medium | [1000000, 10000000] | 价格相对基年价 BASE_PRICE 的上限比率。绝对上限 PRICE_MAX = mul_ppm(BASE_PRIC… | `parameters/params_core.json` |
| `param.price_clamp_budget_count` | 240 | 次 | design_assumption | low | [0, 10000] | 120 季压力测试中允许出现的价格夹逼（触及 PRICE_MIN / PRICE_MAX 或 price_step_m… | `parameters/params_core.json` |
| `param.price_cover_gain_ppm` | 100000 | ppm | design_assumption | low | [0, 1000000] | 价格对库存覆盖率偏离目标的响应系数：调价式中来自库存项的部分 = mul_ppm(目标覆盖率 − 实际覆盖率, 本值)… | `parameters/params_core.json` |
| `param.price_floor_ppm` | 400000 | ppm | design_assumption | medium | [100000, 1000000] | 价格相对基年价 BASE_PRICE 的下限比率。绝对下限 PRICE_MIN = mul_ppm(BASE_PRIC… | `parameters/params_core.json` |
| `param.price_gap_gain_ppm` | 200000 | ppm | design_assumption | low | [0, 1000000] | 价格对当期供需缺口的响应系数：调价式中来自缺口项的部分 = mul_ppm(gap_ppm, 本值)。 | `parameters/params_core.json` |
| `param.price_step_max_ppm` | 30000 | ppm | design_assumption | low | [5000, 100000] | 单季价格相对上季的最大变动幅度（±3%），上下行对称：先算目标价，再按本值截断。 | `parameters/params_core.json` |
| `param.proc_review_uu_per_opex_ppm` | 20000000 | ppm | design_assumption | low | [1000000, 60000000] | 每 1 μU 到位运行费可覆盖的受审支出额（倍数，20 000 000 == 20 倍）：review_capacit… | `parameters/params_core.json` |
| `param.proc_transparency_appeal_load_ppm` | 24000 | ppm | design_assumption | low | [0, 500000] | 申诉受理范围带来的额外负荷系数：负荷第二项 = mul_ppm_2(本值, appeal_scope_ppm, cov… | `parameters/params_core.json` |
| `param.proc_transparency_decay_ppm` | 40000 | ppm | design_assumption | low | [0, 300000] | 采购透明撤回后回落期内每季按当前行政能力计提的回落比例：delta = −mul_ppm(本值, admin_capa… | `parameters/params_core.json` |
| `param.proc_transparency_decay_q` | 4 | 季 | design_assumption | low | [0, 12] | 采购透明撤回后行政能力回落的持续季数（从撤回季起算）。期满后该通道完全静默。 | `parameters/params_core.json` |
| `param.proc_transparency_gain_ppm` | 200000 | ppm | design_assumption | low | [0, 1000000] | 有效审核强度转化为行政执行能力的增益系数：gain = mul_ppm(本值, effective_audit_ppm… | `parameters/params_core.json` |
| `param.proc_transparency_load_ppm` | 20000 | ppm | design_assumption | low | [0, 500000] | 披露覆盖率带来的流程负荷系数：负荷第一项 = mul_ppm(本值, coverage_ppm)。 | `parameters/params_core.json` |
| `param.proc_transparency_ramp_q` | 3 | 季 | design_assumption | low | [1, 8] | 审核与申诉流程从开张到满负荷的基础季数；ramp_q_total = 本值 + idiv_floor(appeal_s… | `parameters/params_core.json` |
| `param.proc_transparency_step_max_ppm` | 40000 | ppm | design_assumption | low | [5000, 200000] | 行政执行能力每季净变动的绝对值上限（夹逼写 log.clamp）。 | `parameters/params_core.json` |
| `param.procurement_disclosure_ref_uu` | 500000000 | μU | design_assumption | low | [100000000, 2000000000] | 逐笔披露门槛的参照单笔对外支出额：门槛 = mul_ppm(本值, disclosure_threshold_ppm)。 | `parameters/params_core.json` |
| `param.pubserv_fee_ppm` | 170000 | ppm | design_assumption | medium | [0, 1000000] | 公共服务收费率（R-FEE-01）：各群组每获得 1 μQ 公共服务，缴纳基年单价（1 000 μU/μQ）的本比例。… | `parameters/params_core.json` |
| `param.qty_max_uqs` | 1000000000000 | μQ_s | design_assumption | high | [1000000000000, 1000000000000] | 单笔实物数量与任一数量型状态字段的绝对值硬上限，等于 1 000 000 Q_s。同时是「该约束不适用」的哨兵值 JW… | `parameters/params_core.json` |
| `param.rate_sensitivity_ppm` | 100000 | ppm | design_assumption | low | [0, 1000000] | 外部融资收紧冲击（shock.S03 通道）每 1 000 000 ppm 的强度，传导到主权利率利差的系数。 | `parameters/params_core.json` |
| `param.rng_salt` | [8566354709439740, 16970375… | int64 | derived | high | [1, 9007199254740992] | 六条独立随机流的盐值，按 JWUnits.RngStream 的枚举顺序排列（0 SHOCK / 1 EVENT / … | `parameters/params_core.json` |
| `param.rule_issue_tenor_q` | 32 | 季 | derived | medium | [4, 63] | 规则发行（S02 付本息前的预融资、到期本金续发、S04 各支付线的短缺融资）新批次的期限：到期季 = 发行季 + 本… | `parameters/params_core.json` |
| `param.student_teacher_ratio` | 25 | 人 | design_assumption | low | [5, 60] | 教育类公共服务单元中每一名教职人员对应的在学人数。用于把教育容量折算成人力需求。 | `parameters/params_core.json` |
| `param.support_weight_ppm` | [500000, 250000, 250000] | ppm | design_assumption | low | [0, 1000000] | 支持度合成中生活指数、预期、信任三项**变化量**的权重，按 [生活, 预期, 信任] 排列，三项合计精确为 1 00… | `parameters/params_core.json` |
| `param.tax_base_rate_ppm` | 250000 | ppm | design_assumption | low | [0, 1000000] | 税基侵蚀的参照平均税率（15%）。平均税率低于本值时不产生任何侵蚀，等于给「温和税制」一个免罚区。 | `parameters/params_core.json` |
| `param.tax_evasion_slope_ppm` | 1350000 | ppm | design_assumption | low | [0, 3000000] | 平均税率每高出 param.tax_base_rate_ppm 一个单位所侵蚀的税基比例系数：税基侵蚀 = mul_p… | `parameters/params_core.json` |
| `param.tax_recovery_ppm` | 50000 | ppm | design_assumption | low | [0, 1000000] | 应收欠税存量每季被追回的比例（5%）。追回额计入当季财政收入，存量相应减少。 | `parameters/params_core.json` |
| `param.training_lag_q` | 4 | 季 | design_assumption | low | [1, 12] | 一批受训者从入训到技能档位提升所需的季数。期间计入在训队列，不计入对应技能档的劳动供给。 | `parameters/params_core.json` |
| `param.trust_drop_ppm` | 80000 | ppm | design_assumption | low | [0, 1000000] | 一次失信（承诺未兑现）带来的信任下降幅度（8%）。 | `parameters/params_core.json` |
| `param.trust_recover_ppm` | 20000 | ppm | design_assumption | low | [0, 1000000] | 一季兑现承诺带来的信任恢复幅度（2%），受 param.trust_streak_cap_q 的连击上限约束。 | `parameters/params_core.json` |
| `param.trust_streak_cap_q` | 8 | 季 | design_assumption | low | [1, 40] | 连续兑现计入信任恢复的季数上限（8 季）。超过本值的连击不再增加单季恢复量，防止长期守约后信任免疫一切冲击。 | `parameters/params_core.json` |
| `param.uu_to_construction_uqs_ppm` | 1000 | ppm | design_assumption | low | [1, 1000000] | 把施工服务的金额折算成施工数量的换算率：施工量_μQ_services = mul_ppm(金额_μU, 本值)。基年… | `parameters/params_core.json` |
| `param.wage_cash_share_ppm` | 800000 | ppm | design_assumption | low | [0, 1000000] | 企业单季可动用于支付工资的营运现金比例上限（80%）。剩余部分留作中间投入与资本支出，防止企业把现金全部付成工资后无法… | `parameters/params_core.json` |
| `param.wage_ceil_uu` | 22220 | μU/人/季 | derived | low | [2223, 222200] | 工资率的硬上限，单位是每人每季的 μU。与 param.wage_floor_uu 成对，必须严格大于它。 | `parameters/params_core.json` |
| `param.wage_floor_uu` | 405 | μU/人/季 | derived | low | [1, 810] | 工资率的硬下限，单位是每人每季的 μU。作用于逐 (cell, skill) 的工资率，先于 step_max 生效。 | `parameters/params_core.json` |
| `param.wage_gain_ppm` | 150000 | ppm | design_assumption | low | [0, 1000000] | 工资率对劳动供需缺口的响应系数：Δwage_ppm = mul_ppm(劳动缺口_ppm, 本值)，再按 param.… | `parameters/params_core.json` |
| `param.wage_step_max_ppm` | 20000 | ppm | design_assumption | low | [0, 200000] | 单季工资率相对上季的最大变动幅度（±2%），上下行对称。 | `parameters/params_core.json` |
| `param.write_guard_sample_q` | 8 | 季 | design_assumption | medium | [1, 40] | 发布构建中重计算型不变量（INV-014 派生一致性等）的抽样周期：每 8 季全量复算一次。调试构建逐季复算，不受本值… | `parameters/params_core.json` |

## 4 卡片分布与扫描范围

| 来源文件 | 卡片数 |
|---|---:|
| `parameters/params_core.json` | 96 |

<details><summary>已扫描文件（37）</summary>

- `events/event_E01.json`
- `events/event_E02.json`
- `events/event_E03.json`
- `events/event_E04.json`
- `events/event_E05.json`
- `events/event_E06.json`
- `events/event_E07.json`
- `events/event_E08.json`
- `events/event_E09.json`
- `events/event_E10.json`
- `events/event_E11.json`
- `events/event_E12.json`
- `parameters/params_core.json`
- `policies/policy_P01.json`
- `policies/policy_P02.json`
- `policies/policy_P03.json`
- `policies/policy_P04.json`
- `policies/policy_P05.json`
- `policies/policy_P06.json`
- `policies/policy_P07.json`
- `policies/policy_P08.json`
- `policies/policy_P09.json`
- `policies/policy_P10.json`
- `policies/policy_P11.json`
- `policies/policy_P12.json`
- `scenarios/chengwan/assertions.json`
- `scenarios/chengwan/cells_init.json`
- `scenarios/chengwan/government_init.json`
- `scenarios/chengwan/io_table.json`
- `scenarios/chengwan/politics_init.json`
- `scenarios/chengwan/population_init.json`
- `scenarios/chengwan/pubserv_init.json`
- `scenarios/chengwan/regions.json`
- `scenarios/chengwan/scenario.json`
- `shocks/shock_S01.json`
- `shocks/shock_S02.json`
- `shocks/shock_S03.json`

</details>

**已跳过**：
- `parameters/registry.json（本工具自身的生成物，排除以避免自指重复登记）`

---

*本文件为生成物。校准纪律见计划书 §14，待决问题见 `docs/13_open_questions.md`。*
