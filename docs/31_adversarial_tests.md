# 31 恶意玩家测试目录（对抗性验收套件）

> 权威需求来源：`docs/ref/plan_v1.0.txt` §17「必须加入的恶意玩家测试」、§13「禁止后处理补丁」、
> §16「人工评审重点」。本文件把计划书点名的六条展开为 **60 条可实现、可执行、可判定**的对抗性测试。
>
> 术语、单位、不变量编号沿用 `10_variable_dictionary.md`（INV-001..INV-152）、
> `11_data_contract.md`（命令、错误码 `E_*`、账本 `kind` 码、存档协议）、
> `12_simulation_contract.md`（S01–S08 八步结算、三种失败语义）。
> 本文件**不新定义**变量、不新定义单位、不新定义 INV 编号；凡需要新规则之处，一律写在
> 「失败诊断」里并汇总到 §13「本目录暴露的规则缺口」，由 `13_open_questions.md` 的维护者裁定。

---

## 0 本目录的立场

### 0.1 威胁模型（写清楚，免得测错东西）

| 在范围内 | 不在范围内 |
|---|---|
| 玩家**只用合法命令**（`11_data_contract.md` §6.1 的 12 种 `kind`）但以病态顺序、病态参数、病态频率使用 | 玩家用十六进制编辑器改自己的存档后要求游戏「认账」 |
| 玩家利用取整、边界、时序、幂等缺失制造**无来源的钱、货、人、进度、支持率** | 反作弊、反修改器、加密存档（计划书 §18：单机离线，`11_data_contract.md` §6.8 明确不防作弊） |
| 玩家用存档往返（save-scumming）改变**已经确定**的随机结果 | 玩家用存档往返改变**尚未抽样**的未来（这是合法玩法，不是漏洞） |
| 内容包（剧本 / 政策 / 事件 / 冲击 / 参数卡）本身写错，导致守恒被绕过 | 引擎与操作系统层面的攻击 |

**存档篡改类测试（H 族）测的不是「防住了改档」，而是「改档之后系统不会假装账是平的」**：
要么当场拒绝载入（`E_SAVE_CORRUPT`），要么进只读检视模式，**绝不静默继续并把错账带进第 30 季**。

### 0.2 唯一的裁决标准

任何一条测试的期望行为只能落在三类之一（`12_simulation_contract.md` §0.6）：

| 语义 | 含义 | 状态后果 | 本目录的记法 |
|---|---|---|---|
| `REJECT(E_xxx)` | 命令不合法 | **完全不变**，`state_hash` 逐位相同 | 记作 `⟹ REJECT(E_xxx)` |
| `ARREARS` | 钱／货／人／槽位不够 | 变，但账自洽：欠付、延期、取消、配给、未满足 | 记作 `⟹ ARREARS(...)` |
| `FAULT` | 恒等式破裂 | 结算中止，导出故障包 | 记作 `⟹ 测试期望永不发生` |

**禁止出现的第四类**：静默改账。包括但不限于——悄悄把现金补到 0 以上、季末「平衡修正」、
把未满足需求当作已满足、把负库存抹成 0、把重复发放的补助从别处扣回来、把无法解释的差额塞进残差项。
**凡本目录中出现「不得静默改账」字样，等价于断言「该季 `log.*` 中存在一条可追溯条目解释了这次变化」（INV-139）。**

### 0.3 与计划书点名六条的对应

计划书 §17 点名六条，`12_simulation_contract.md` §11 已把它们登记为 `ADV-01..ADV-06`。
本目录保留这六个编号作为**别名**，主编号改用分族编号，避免与扩充部分冲突：

| 计划书原文 | `12_simulation_contract.md` 编号 | 本目录主编号 |
|---|---|---|
| 反复开关补助是否重复领钱？ | `ADV-01` | `ADV-A01` |
| 借新还旧是否永远没有成本？ | `ADV-02` | `ADV-C01` |
| 没有教师时培训是否照样完成？ | `ADV-03` | `ADV-E03` |
| 所有工人迁到同一区域是否仍享受无限住房？ | `ADV-04` | `ADV-E01` |
| 提高税率后税收是否绕过实际税基？ | `ADV-05` | `ADV-A04` |
| 存档重载能否重抽已确定事件？ | `ADV-06` | `ADV-H01` |

这六条是**门槛级**（G3 之前必须全绿）；其余 54 条是 G5 之前必须全绿。分级见 §12.3。

### 0.4 强制开发纪律：先写会失败的版本

沿用 `12_simulation_contract.md` §11 的要求，并对本目录全体适用：

> 每条测试**必须先提交一个会红的版本**——即先用一个故意去掉防线的构建（`--adv-disable=<防线名>`，
> 只在测试构建中存在的编译期开关）跑一遍，确认测试确实会失败；再打开防线跑绿。
> `tests/tools/adv_negative_control.gd` 自动执行这一步：对每条 `ADV-*` 读取其 `guards:` 元数据，
> 逐个关闭并要求测试变红。**任一条在防线关闭时仍然绿 ⇒ CI 失败**（说明这条测试什么也没测到）。

```gdscript
# 每个 tests/scenario/test_s_adv_*.gd 文件头部必须有的元数据块（静态检查 check_adv_meta.gd）
# adv_id:     ADV-A01
# alias:      ADV-01
# family:     arbitrage
# invariants: INV-095, INV-097, INV-098
# guards:     claim_idempotency, policy_cooldown, effective_from_monotonic
# gate:       G3
```

缺少任一字段、或 `invariants:` 中引用了注册表里不存在的编号、或 `guards:` 中的开关在构建里不存在
⇒ 构建失败。这保证 §12.2 的覆盖矩阵可以机器生成，不靠人工维护。

---

## 1 测试夹具（所有断言依赖的公共 API）

所有对抗测试位于 `tests/scenario/`，前缀 `test_s_adv_`，共用夹具 `tests/scenario/adv_fixture.gd`。
夹具属于测试层，不受 SimCore 的「零 Dictionary / 零 String」限制，但**不得拥有任何写状态的能力**：
它只能通过 `submit()` 递交命令、通过 `advance()` 推进季度、通过只读视图读状态。

```gdscript
class_name AdvFixture extends RefCounted

# ---- 启动 ----
func boot(scenario_id: String = "scenario.chengwan",
          root_seed: int = 1,
          param_overrides: Dictionary = {}) -> void
        # param_overrides 只能覆写 ParameterCard 中 valid_range 内的值；越界即测试自身失败
        # 覆写会生成一个临时 paramset 并计入 content_hash，因此不会污染正式内容包

# ---- 命令 ----
func submit(kind: String, args: Dictionary) -> int          # 返回 command_id；不推进季度
func expect_reject(kind: String, args: Dictionary, code: String) -> void
        # 断言：返回 accepted == 0 且 reject_code == code 且 state_hash 与提交前逐位相同（INV-137）
func advance(n: int = 1) -> void                            # 推进 n 季；逐季全量 P0 不变量；任一 FAULT 即测试失败

# ---- 只读视图 ----
func q() -> int
func state_hash() -> PackedByteArray
func scalar(path: String) -> int                            # 例 scalar("state.gov.cash_uu")
func arr(path: String, idx: int) -> int
func derived(path: String) -> int

# ---- 账本与日志查询（全部按 11_data_contract.md §5.3 的 kind 码）----
func led_sum(kind_code: int, q_from: int, q_to: int) -> int                 # 闭区间，μU
func led_sum_by(kind_code: int, agent_id: String, q_from: int, q_to: int) -> int
func led_rows(kind_code: int, q: int) -> Array                              # 逐行，用于唯一性断言
func arrears_of(class_code: String) -> int                                  # 8 档支出类别
func rejections(q: int) -> Array                                            # log.rejections
func rng_log(stream: String, q: int) -> Array                               # log.rng
func clamp_count() -> int
func binding_code(cell_id: String) -> String                                # plan/capacity/labor/energy/materials

# ---- 存档 ----
func save(slot: String) -> void
func load(slot: String) -> int                              # 返回 0 或 E_* 错误码
func tamper(slot: String, json_pointer: String, value) -> void      # 仅测试可用，直接改磁盘文件
func rehash(slot: String) -> void                           # 改档后重算并写回 manifest.state_hash（H03 专用）

# ---- 全局守恒快照（每条测试收尾必调）----
func assert_conservation() -> void
        # INV-017 Σ Δcash == 0
        # INV-018 全经济现金总量 == scenario.total_cash_uu
        # INV-019 Σ recv == Σ pay
        # INV-020 逐主体资产负债恒等式
        # INV-021 Δnw 被本季损益完全解释
        # INV-024 INV-025 存款与债券持有对账
        # INV-071 人口守恒
```

**夹具的硬约束**：`AdvFixture` 内不存在任何形如 `set_*` 的状态写接口（`tamper` 只碰磁盘上的存档文件，
不碰内存状态）。`check_writers.gd` 把 `tests/` 纳入扫描：测试代码中出现对 `state.*` 的赋值即构建失败。
**理由：计划书 §16 的人工评审重点第四条——「是否在测试中偷偷补入资源」。这条纪律必须是机器强制的。**

---

## 2 A 族：套利与重复计数（补助 / 退税 / 转移支付）

### `ADV-A01` 反复开关补助重复领钱 〔≡ 计划书点名 ①，别名 ADV-01〕

- **攻击叙述**：「P09 设备投资补助按合格投资发钱。那我第 1 季开启领一次，第 2 季关闭，第 3 季再开启——
  重新开启时系统大概会把『这期间发生过的合格投资』重新算一遍补上。反复二十次，白拿二十次。」
- **操作序列**
  1. `boot()`，`param_overrides = {"param.subsidy_rate_ppm": 300000}`（30%，valid_range 内的上限附近）。
  2. q=0：`policy_enact{policy_id:"policy.P09", funding_source:"cash"}`；`advance(1)`。
  3. q=1：`policy_repeal{policy_id:"policy.P09"}`；`advance(1)`。
  4. 重复步骤 2–3 交替共 20 次（覆盖 q=0..19），每次都记录 `submit` 的返回与 `reject_code`。
  5. q=20..39：保持开启，`advance(20)`，让全部在途申领结清。
- **被攻击的不变量**：INV-097（`claim_key = hash(policy_id, beneficiary_id, q, qualifying_event_id)` 同键至多付一次）、
  INV-098（冷却 + `toggle_count` + 一次性行政成本 + `effective_from_q` 单调不回溯）、INV-095（未生效返回零效应）、INV-113（补助不进 GDP）。
- **期望行为**
  - 冷却期内的开关命令 `⟹ REJECT(E_POLICY_COOLDOWN)`，且状态哈希不变。
  - 每次成功开关产生一笔 `kind=26 policy_toggle_cost`，**开关本身是有成本的**。
  - 重新开启**不补发**关闭期间的任何合格投资；关闭期间发生的投资其 `claim_key` 永久作废，不排队等待。
  - 同一 `qualifying_event_id` 二次申领 `⟹ ARREARS` 之外的第四种都不允许：直接不生成第二条 claim，计入 `duplicate_claim_blocked`。
- **断言**

```gdscript
func test_adv_a01() -> void:
    # 1) 发放总额恰好等于合格投资 × 费率，一分不多
    var paid: int = f.led_sum(12, 0, 39)                       # kind 12 = subsidy
    var expect: int = 0
    for e in f.qualifying_investments(0, 39):                  # 只读视图，按 claim_key 去重后的合格事件
        expect += IntMath.mul_ppm(e.amount_uu, f.scalar("param.subsidy_rate_ppm"))
    assert_eq(paid, expect)                                    # 容差 0

    # 2) 每个 claim_key 在整局中至多出现一次
    var keys: Dictionary = {}
    for qq in range(0, 40):
        for row in f.led_rows(12, qq):
            assert_false(keys.has(row.claim_key), "重复申领: %s" % row.claim_key)
            keys[row.claim_key] = true

    # 3) 防线确实被触发过（否则这条测试等于没测）
    assert_gt(f.scalar("state.policy.P09.duplicate_claim_blocked_count"), 0)
    assert_gt(f.scalar("state.policy.P09.toggle_count"), 0)
    assert_gt(f.led_sum(26, 0, 39), 0)                         # 开关行政成本真的收了

    # 4) 冷却确实拒绝过，且拒绝是纯的
    assert_gt(f.rejections_with_code("E_POLICY_COOLDOWN").size(), 0)

    # 5) 补助没有进 GDP
    assert_eq(f.derived("derived.gdp.subsidy_contribution_uu"), 0)   # 该派生量按 INV-113 恒为 0
    f.assert_conservation()
```

- **失败诊断**
  - 发放总额 > 合格投资对应额 ⇒ **缺 INV-097 的幂等键**，或 `claim_key` 里漏了 `qualifying_event_id`（只用 `q` 会让同季多笔投资互相覆盖，只用 `policy_id+beneficiary` 会让跨季重复）。
  - 重新开启后出现「补发」条目 ⇒ **缺 INV-098 的 `effective_from_q` 单调不回溯**：政策生效季被写成了 `min(历史开启季)`。
  - `toggle_count == 0` 或行政成本为 0 ⇒ **缺「开关有成本」规则**，开关变成免费动作，整个冷却设计失去意义。
  - GDP 随补助上升 ⇒ **缺 INV-113**：补助被当成了最终产出（计划书 §06「政府给企业的补助本身不再额外算一遍最终产出」）。

### `ADV-A02` 同一笔投资拆成多笔骗取多份补助

- **攻击叙述**：「幂等键里有 `qualifying_event_id`？那我把一笔 1 U 的设备投资拆成 100 笔 0.01 U，
  每笔各有各的 event_id，各领一份补助。补助有下限门槛的话，我就拆到刚好压线。」
- **操作序列**
  1. `boot()`；q=0 启用 P09。
  2. 构造剧本夹具：`manu` 部门在 q=1 分 100 笔提交资本品购入（`kind=7 capital_purchase`），总额与对照组的单笔 1 U 相等。
  3. 对照组 `boot()` 同种子，q=1 单笔 1 U 购入。
  4. 两组各 `advance(4)`，比较补助总额。
- **被攻击的不变量**：INV-003（拆分后 Σ 分项 == 原额）、INV-097、INV-002（一切除法走 `idiv_floor` 且有 `# rounding:` 注释）。
- **期望行为**：两组补助总额之差 `|Δ| ≤ 99 μU`（纯取整残差上界，= 拆分笔数 − 1），
  **且该残差必须逐笔写入 `log.rounding`，不得产生任何债权债务**（INV-005）。若政策设有最低申领门槛，
  低于门槛的申领 `⟹ REJECT(E_PRECONDITION)` 而不是被静默吞掉。
- **断言**

```gdscript
    var split_paid: int = f_split.led_sum(12, 0, 4)
    var whole_paid: int = f_whole.led_sum(12, 0, 4)
    assert_le(absi(split_paid - whole_paid), 99)               # 取整残差上界，与笔数同阶
    assert_eq(f_split.scalar("state.gov.rounding_residual_uu"),
              f_split.log_rounding_sum(0, 4))                  # INV-005：残差被逐条解释
    assert_ge(split_paid, 0)
    f_split.assert_conservation()
```

- **失败诊断**：差额随拆分笔数线性放大且远超 μU 量级 ⇒ **缺「补助按季按受益人合并计基数」规则**：
  正确写法是先对同一 `(policy_id, beneficiary_id, q)` 的全部合格事件求和，**再**乘费率取整，
  而不是逐事件乘费率再求和。这是本目录中最容易被写错、也最容易被玩家发现的一类取整套利。

### `ADV-A03` 把补助当 GDP 刷

- **攻击叙述**：「补助是政府花的钱，钱花出去了总该算进 GDP 吧？把补助率拉满，GDP 就上去了。」
- **操作序列**：`boot()`，q=0 启用 P09 且费率取 `valid_range` 上限；`advance(8)`；
  与「不启用 P09、其余完全相同」的对照组逐季比较 `gdp_production_uu` 的**构成分解**。
- **被攻击的不变量**：INV-112（`gdp_production == Σ value_added + Σ pubserv.output`，禁止用销售额求和）、INV-113、INV-114（三重分类完备互斥）。
- **期望行为**：补助**可以**通过「企业现金增加 → 扩产意愿上升 → 下季实际多产」间接影响 GDP，
  但**当季不得有任何一条 GDP 口径直接吃到补助金额**。`kind=12` 的三重分类必须全是 `none`。
- **断言**

```gdscript
    for qq in range(0, 8):
        for row in f.led_rows(12, qq):
            assert_eq(row.prod_class, "none")
            assert_eq(row.exp_class,  "none")
            assert_eq(row.inc_class,  "none")
    # 当季不得同步上升：补助只能通过下季产量起作用
    assert_eq(f.gdp_at(0), f_ctrl.gdp_at(0))                   # q=0 完全相同
    # 若 q>=1 出现差异，必须能被实际产量差异完全解释
    for qq in range(1, 8):
        var dgdp: int = f.gdp_at(qq) - f_ctrl.gdp_at(qq)
        assert_eq(dgdp, f.va_diff_from_quantity(f_ctrl, qq))   # 差额 100% 来自实物产量差，不是转移额
```

- **失败诊断**：q=0 就出现 GDP 差异 ⇒ **缺 INV-113**；差额无法被产量差解释 ⇒ 补助被计入了某个口径的分子，
  说明 `kind` 三重分类白名单没有被 `INV-114` 的覆盖性检验真正覆盖（`test_u_gdp_class_coverage` 形同虚设）。

### `ADV-A04` 提高税率后税收绕过实际税基 〔≡ 计划书点名 ⑤，别名 ADV-05〕

- **攻击叙述**：「个税税率从 10% 拉到 60%，收入就乘以 6 倍吧。反正系统大概是 `税收 = 税率 × 名义收入`。」
- **操作序列**
  1. 六个独立存档，`param.p01_rate_ppm ∈ {100000, 200000, 300000, 400000, 500000, 600000}`。
  2. 每档 `boot()` 同种子，q=0 `policy_enact{policy.P01}`，`advance(12)`。
  3. 记录逐季 `income_tax` 实收（`kind=10`）、`tax_receivable_uu`、`base_eff`（有效税基）、征收能力 `admin_capacity_ppm`。
  4. 追加一档：先跑 P11 税务能力建设 8 季再上 60% 税率，验证「先增加成本、再改变征收覆盖」。
- **被攻击的不变量**：INV-031（`tax_receivable_end == start + (应计 − 实收) − 追征 − 核销`）、
  INV-063（居民只能花已收到的钱）、INV-086（可支配收入恒等式）。
- **期望行为**
  - 实收税额对税率**非线性**，且存在拐点（税基侵蚀 + 征收能力上限同时起作用）。
  - **应计税与实收税分开记账**：差额进 `tax_receivable`，不得直接当作收到。
  - 税基只来自**已过账的收入流**，不得引用任何名义总量（如 `gdp_production`）。
  - P11 先形成成本、4–8 季后才改变覆盖率（计划书 §09 P11 行）。
- **断言**

```gdscript
    var receipts := []
    for r in RATES: receipts.append(run_with_rate(r).led_sum(10, 0, 11))
    # 1) 不是线性：60% 档的实收 < 10% 档实收 × 6 × 0.8（留 20% 余量后仍严格小于）
    assert_lt(receipts[5], receipts[0] * 6 * 8 / 10)
    # 2) 存在拐点：一阶差分至少变号一次，或至少出现一次不增
    assert_true(has_non_increasing_step(receipts), "税收对税率单调等比上升 = 没有税基侵蚀")
    # 3) 税基确实下降，且与税收分别可观测
    assert_lt(f60.derived("derived.tax.base_eff_uu"), f10.derived("derived.tax.base_eff_uu"))
    # 4) 应计与实收分离
    assert_eq(f60.scalar("state.gov.tax_receivable_uu"),
              f60.scalar_prev("state.gov.tax_receivable_uu")
              + f60.accrued(10) - f60.led_sum(10, f60.q(), f60.q())
              - f60.recovered(10) - f60.written_off(10))       # INV-031，容差 0
    # 5) 税基不引用名义总量（静态检查的运行期复核）
    assert_false(f60.tax_base_depends_on("derived.gdp.production_uu"))
```

- **失败诊断**
  - 线性等比上升 ⇒ **缺税基侵蚀通道**：`base_eff` 没有随税率变化，或 `base_eff` 直接等于名义收入。
  - 实收 == 应计恒成立 ⇒ **缺征收能力闸门与 INV-031 的应收账款**；税收变成了「宣布即到账」。
  - P11 上线当季就提升覆盖率 ⇒ **缺 INV-095 的生效时滞**（计划书 §09：P11「先增加成本，再改变征收覆盖」）。

### `ADV-A05` 转移支付回流永动机

- **攻击叙述**：「P03 失业保障替代比例拉满。政府发钱给居民，居民消费，企业赚钱交利润税，
  钱又回到政府。只要回流率够高，政府就能一直发钱不亏。」
- **操作序列**：`boot()`，`param.p03_replacement_ppm` 取上限；q=0 启用 P03；`advance(20)`；
  逐季记录 `gov.cash_uu`、`kind=13 transfer` 累计、`kind=11 profit_tax` 累计、全经济现金总量。
- **被攻击的不变量**：INV-017（每季 Σ Δcash == 0）、INV-018（全经济现金总量恒定）、INV-019。
- **期望行为**：转移支付是**再分配**，不创造现金。政府净现金必然随转移累计单调下降，
  除非通过借款（`kind=15`）补充——而借款会被 C 族的额度与利率规则约束。
  回流率必须 `< 1`，且回流路径逐笔可追溯到 `household_consumption → operating_surplus → profit_tax`。
- **断言**

```gdscript
    assert_eq(f.total_cash_all_agents(), f.scalar("scenario.total_cash_uu"))   # INV-018，逐季
    var net_gov: int = f.led_sum(11, 0, 19) + f.led_sum(10, 0, 19) - f.led_sum(13, 0, 19)
    assert_lt(net_gov, 0, "转移支付的税收回流率 >= 1，存在现金永动机")
    for qq in range(0, 20):
        assert_eq(f.sum_delta_cash_all_agents(qq), 0)                          # INV-017
```

- **失败诊断**：现金总量上升 ⇒ 某条转移路径是**单边过账**（只记收方不记付方），违反 INV-015；
  回流率 ≥ 1 ⇒ 消费与利润税之间存在重复计数，通常是「补助/转移被同时计入企业收入与政府支出的抵减项」。

### `ADV-A06` 给不持有现金的主体发补助

- **攻击叙述**：「`agent.pubserv.*` 不持有现金（其支付由 `agent.gov` 执行）。那我想办法把补助打给它——
  一个没有现金账户的主体收到钱，这笔钱大概会凭空出现在系统里。」
- **操作序列**
  1. 构造内容包变体：`policy.P09` 的 `effect_target` 指向 `agent.pubserv.zhongzhou`。
  2. 载入该内容包。
  3. 若载入通过，q=0 启用 P09 并 `advance(4)`。
- **被攻击的不变量**：INV-015（每笔 txn 有符号过账行之和为 0，两端账户不同）、INV-026（外部世界是显式账户，不存在无对手方收支）、
  INV-020（逐主体资产负债恒等式）、账户 ID 正则（`11_data_contract.md` §4）。
- **期望行为**：**载入期即拒绝**——`account.pubserv.<region>.cash` 不在 `account_id` 的合法集合内，
  `⟹ REJECT(E_EFFECT_TARGET)`。绝不允许「先跑起来再说」。
- **断言**

```gdscript
    var code: int = f.load_content_pack("fixtures/content/adv_a06_pubserv_subsidy/")
    assert_eq(code, Err.E_EFFECT_TARGET)
    assert_eq(f.q(), -1)                                       # 根本没有进入可推进状态
```

- **失败诊断**：载入通过 ⇒ **缺「政策效应目标必须是合法账户主体」的加载期校验**（INV-099 的 `effect_target` 分支）；
  若运行期才 FAULT，说明校验放在了太晚的位置——内容包错误必须在载入期暴露，不能等到第 4 季。

---

## 3 B 族：时序攻击（结算边界上的反复提交与撤回）

### `ADV-B01` 同季两次推进

- **攻击叙述**：「一季推进两次，生产结算两遍，产量翻倍。」
- **操作序列**：`submit("advance_quarter", {})`（第一条被 `advance()` 消费）；在同一 `q` 立刻再 `submit("advance_quarter", {})`。
- **被攻击的不变量**：INV-012（八步单向推进，`state.time.q` 只在 S08 末 +1）、INV-137（被拒命令入档且哈希不变）。
- **期望行为**：`⟹ REJECT(E_PHASE_BUSY)`（结算进行中）或第二条因「每季恰好一条且为该季最后一条」被拒。
  被拒命令**仍写入 `commands.jsonl`** 并记 `accepted:0`。
- **断言**

```gdscript
    var h0 := f.state_hash()
    f.expect_reject("advance_quarter", {}, "E_PHASE_BUSY")
    assert_eq(f.state_hash(), h0)                              # 逐位相同
    assert_true(f.command_log_contains(cmd_id, {"accepted": 0, "reject_code": "E_PHASE_BUSY"}))
```

- **失败诊断**：第二条被接受 ⇒ **缺 `phase != PHASE_IDLE` 闸门**；被拒但未入档 ⇒ **缺 INV-137**，
  后果是同一命令流在不同版本下可能被接受，重放产生分歧（`11_data_contract.md` §6.1 规则 2）。

### `ADV-B02` 结算中途插入命令

- **攻击叙述**：「S05 生产结束、S06 征税之前，我把税率改成 0，这季就白赚了。」
- **操作序列**：用测试专用钩子在 `WriteGuard` 的 S05→S06 边界注入 `policy_set_params{policy.P01, rate:0}`。
- **被攻击的不变量**：INV-138（命令只写 `pending_params` 与命令日志，一切生效在 S02）、INV-013（每步只写其可写子集）。
- **期望行为**：`⟹ REJECT(E_PHASE_BUSY)`。命令受理**只发生在 `PHASE_IDLE` 与 S02**；
  即使被接受，也只能写 `pending_params`，本季 S06 必须用 S02 冻结的参数。
- **断言**

```gdscript
    f.inject_at_step(6, func(): return f.submit("policy_set_params", {...}))
    assert_eq(f.last_reject_code(), "E_PHASE_BUSY")
    assert_eq(f.effective_rate_used_in_s06(), RATE_FROZEN_AT_S02)
```

- **失败诊断**：S06 用了新税率 ⇒ **缺「参数在 S02 冻结」的双缓冲**（`pending` / `active` 分离）；
  这是所有时序攻击里危害最大的一类，因为它让同一季内的因果方向可以被玩家反转。

### `ADV-B03` 立项当季取消，回收预留

- **攻击叙述**：「立项会预留预算。我立十个项目把额度占满，再在同季全部取消，预留应该会退回来——
  如果系统把『释放预留』写成了『增加现金』，我就凭空多了钱。」
- **操作序列**：q=5 连续 `project_launch` 10 个 P04 项目；同季 `project_cancel` 全部；`advance(1)`。
- **被攻击的不变量**：INV-033（`reserved_memo ≤ cash` 且季末归零）、INV-032（`committed_memo` 只由三类动作变动，取消不退已付）、
  INV-093（取消：`committed_memo` 减未付部分，`paid_uu` 不回退，现金不增加）。
- **期望行为**：预留是**表外备查量**（`_memo_uu` 后缀，禁止进入任何资产负债恒等式，见 `10_variable_dictionary.md` §0.2）。
  释放预留**不产生任何账本分录**。同季取消若已发生履约付款，该付款不退；未付部分释放；`cancel_penalty`（`kind=27`）入账。
- **断言**

```gdscript
    var cash_before: int = f.scalar("state.gov.cash_uu")
    launch_ten(); cancel_ten()
    assert_le(f.scalar("state.gov.reserved_memo_uu"), f.scalar("state.gov.cash_uu"))
    assert_eq(f.scalar("state.gov.cash_uu"),
              cash_before - f.led_sum(19, f.q(), f.q()) - f.led_sum(27, f.q(), f.q()))
    f.advance(1)
    assert_eq(f.scalar("state.gov.reserved_memo_uu"), 0)       # 季末归零
    f.assert_conservation()
```

- **失败诊断**：现金因取消而增加 ⇒ **`reserved_memo` 被当成了真账户**，违反 `_memo_uu` 后缀的语义约定；
  这是「预算不是资产」（计划书 §07）在代码里被破坏的典型形态。

### `ADV-B04` 先小规模立项通过审核，再改大

- **攻击叙述**：「大项目要过预算审查。那我先立一个 0.1 U 的小项目通过审核，
  再用 `policy_set_params` 把 `scale_ppm` 改成 10 倍。」
- **操作序列**：q=0 `project_launch{scale_ppm: 100000}`；q=1 `policy_set_params{scale_ppm: 1000000}`；`advance(4)`。
- **被攻击的不变量**：INV-096（`budget_spent ≤ budget_committed`，超预留必须重新审核）、
  INV-092（`Σ paid ≤ Σ spend_plan`，`Σ spend_plan == total_cost`）。
- **期望行为**：`scale_ppm` 不在「允许修改的窗口」内 ⇒ `REJECT(E_PARAM_RANGE)`；
  若内容包允许修改，则**必须重新走一次预算审查与资金来源声明**，否则 `REJECT(E_BUDGET_INSUFFICIENT)`。
- **断言**

```gdscript
    f.expect_reject("policy_set_params",
        {"policy_id": "policy.P04", "params": {"scale_ppm": 1000000}}, "E_PARAM_RANGE")
    assert_le(f.scalar("state.policy.P04.budget_spent_uu"),
              f.scalar("state.policy.P04.budget_committed_uu"))
```

- **失败诊断**：改动被接受且不重新审核 ⇒ **缺「哪些参数可在哪个窗口修改」的 `PolicyDefinition` 字段**，
  等价于预算审查可以被任意绕过。

### `ADV-B05` 让生效季回溯到过去

- **攻击叙述**：「`effective_from_q` 是个季度号。我提交一条把它设成过去某季的命令，
  系统就会把这几季的效果补给我。」
- **操作序列**：q=10 提交 `policy_enact{policy.P03, effective_from_q: 4}`；再试 `policy_set_params` 改同一字段。
- **被攻击的不变量**：INV-098（`effective_from_q` 单调不回溯）、INV-095（`q < effective_from_q` 返回零效应）、
  INV-138（命令不得携带直接状态值）。
- **期望行为**：`effective_from_q` **不是玩家可写字段**。命令中出现该字段 ⇒ `REJECT(E_DIRECT_STATE_WRITE)`；
  若作为合法字段存在，则 `< q` 的取值 ⇒ `REJECT(E_PARAM_RANGE)`。
- **断言**

```gdscript
    f.expect_reject("policy_enact",
        {"policy_id": "policy.P03", "effective_from_q": 4}, "E_DIRECT_STATE_WRITE")
    f.advance(1)
    assert_ge(f.scalar("state.policy.P03.effective_from_q"), 10)
```

- **失败诊断**：命令被接受 ⇒ **`Command.args` 的白名单校验缺失**（INV-138 只检查了 `set_cash`/`set_gdp`/`set_support`
  这几个名字，没有做「args 键必须在该 kind 的 `player_params` 白名单内」的正向校验）。**正向白名单优于负向黑名单。**

---

## 4 C 族：融资永动机

### `ADV-C01` 借新还旧永远没有成本 〔≡ 计划书点名 ②，别名 ADV-02〕

- **攻击叙述**：「到期就发新债还旧债，本金永远不用真还。利率是固定的，所以成本也是固定的，
  跑满 40 季一分钱不还照样活着。」
- **操作序列**
  1. `boot()`，q=0 记录初始 50 U 债务的到期表。
  2. 每季在 S02 之前提交 `issue_bond{amount_uu: 本季到期本金 + 本季利息, tenor_q: 8, holder: "invpool"}`。
  3. 从不提交任何主动偿还；`advance(40)`（若提前终止则记录终止季与原因）。
  4. 逐季记录 `market_rate_ppm`、`debt_service_ratio_ppm`、`interest_paid`、`credit_limit` 与 `reject_code`。
- **被攻击的不变量**：INV-038（新发票息 ≥ `market_rate_ppm(q)`，且 `market_rate_ppm` 对 `dsr_ppm` 单调不减，不允许自动展期）、
  INV-034（融资不超对手方能力）、INV-040（连续 `param.default_grace_q` 季付不出第 1 档 ⇒ `fiscal_restructuring_failed`）、
  INV-035、INV-036（旧债不重定价）、INV-037（到期表与余额一致）。
- **期望行为**
  - `Σ interest_paid` **严格递增**（滚动规模上升 + 利率上升的双重效果）。
  - 存在某季 `⟹ REJECT(E_CREDIT_LIMIT)`（国内额度受 `invpool.cash` 硬约束），或进入重组分支。
  - **不存在自动展期**：到期本金不会因为「反正会再借」而自动延后。
  - 旧批次票息在整局中一字不变（INV-036）。
- **断言**

```gdscript
    var interest := []
    for qq in range(0, 40):
        interest.append(f.led_sum(17, qq, qq))                 # kind 17 = bond_interest
    assert_strictly_increasing_after(interest, 4)              # 前 4 季允许季节性波动，之后严格递增
    assert_true(f.rejections_with_code("E_CREDIT_LIMIT").size() > 0
             or f.scalar("state.meta.termination_reason") == TR_FISCAL_RESTRUCTURING_FAILED,
             "40 季只滚不还却既没触额度上限也没进重组 = 借新还旧零成本")
    # 旧债不重定价
    for b in f.bonds_issued_before(0):
        assert_eq(f.bond_coupon(b), f.bond_coupon_at_issue(b))
    # 利率随偿债率单调不减
    assert_monotone_nondecreasing_in(f.series("market_rate_ppm"), f.series("debt_service_ratio_ppm"))
    assert_eq(f.derived("derived.gov.debt_uu"), f.sum_bond_outstanding())      # INV-035
```

- **失败诊断**
  - 利息不增 ⇒ **缺 INV-038 的利率–偿债率联动**，或新发按旧票息定价。
  - 从未触发额度 ⇒ **缺 INV-034 的对手方能力约束**：`invpool.cash` 没有被当成真实的资金池，国债变成了无限 ATM。
  - 出现「到期未还但债务未违约」 ⇒ **存在自动展期路径**，这是计划书 §07「融资必须有对手方」被架空的信号。

### `ADV-C02` 政府买自己的债

- **攻击叙述**：「我让政府自己持有自己发的债，净债务就抵消了，债务/GDP 指标立刻变好看。」
- **操作序列**：`issue_bond{holder: "gov"}`；再试 `holder: "opening"`、`holder: "cell.haijia.manu"`。
- **被攻击的不变量**：INV-025（`Σ (invpool.bondhold + row.bondhold) == derived.gov.debt_uu`）、
  INV-035、`bond_id` / `holder` 的枚举约束（`E_BOND_FIELD`）。
- **期望行为**：`holder` 是闭枚举，只能是 `invpool` 或 `row` ⇒ 其余 `REJECT(E_BOND_FIELD)`。
  即使内容包被改坏，INV-025 会在 S02 末抓到并 FAULT。
- **断言**

```gdscript
    for h in ["gov", "opening", "cell.haijia.manu", "pubserv.zhongzhou"]:
        f.expect_reject("issue_bond", {"amount_uu": 1000000, "tenor_q": 8, "holder": h}, "E_BOND_FIELD")
    assert_eq(f.scalar("agent.invpool.bondhold_uu") + f.scalar("agent.row.bondhold_uu"),
              f.derived("derived.gov.debt_uu"))
```

- **失败诊断**：任一非法 holder 被接受 ⇒ **枚举被写成了自由字符串**（违反 `11_data_contract.md` §4 规则 3）；
  债务指标随之失去意义，且 INV-025 会在下一季变成 FAULT——**测试应在命令层就拦住，而不是靠 FAULT 兜底**。

### `ADV-C03` 投资池被掏空后继续发债

- **攻击叙述**：「居民投资池的现金是有限的？那我先发债把它掏空，掏空之后系统大概就不检查了。」
- **操作序列**：连续发债直到 `invpool.cash_uu == 0`；再发一笔；再等一季让居民储蓄补充后重试。
- **被攻击的不变量**：INV-034、INV-024（`Σ group.deposit == invpool.deposit_liab == invpool.cash + invpool.bondhold`）。
- **期望行为**：`⟹ REJECT(E_CREDIT_LIMIT)`。发债规模上限是 `min(credit_limit_domestic_memo_uu, invpool.cash_uu)`，
  **两个上限都要检查**，不能只查额度不查现金。下一季居民储蓄流入后上限自然抬升，这是合法的。
- **断言**

```gdscript
    drain_invpool()
    assert_eq(f.scalar("agent.invpool.cash_uu"), 0)
    f.expect_reject("issue_bond", {"amount_uu": 1, "tenor_q": 8, "holder": "invpool"}, "E_CREDIT_LIMIT")
    assert_eq(f.scalar("agent.invpool.deposit_liab_uu"),
              f.scalar("agent.invpool.cash_uu") + f.scalar("agent.invpool.bondhold_uu"))   # INV-024
```

- **失败诊断**：发债成功 ⇒ 只检查了 `credit_limit` 这个**表外备查额度**，没检查对手方**真实现金**。
  这正是计划书 §07「融资必须有对手方」与 §03「不模拟商业银行和货币创造」的交叉点：
  如果对手方能凭空拿出钱，游戏就隐式地模拟了货币创造。

### `ADV-C04` 把未来收入当现金花

- **攻击叙述**：「下季会收到 5 U 的税。那我这季就按 5 U 的额度签合同、付款。反正钱一定会到。」
- **操作序列**：q=0 把 `gov.cash_uu` 用尽（通过合法支出）；再 `project_launch` 一个总成本远超现金的项目，`funding_source: "cash"`。
- **被攻击的不变量**：INV-016（cash ≥ 0，**永不先扣成负数再想办法**）、INV-033（`reserved_memo ≤ cash`）、
  INV-063（居民侧的同一条规则：未收到的预计收入不可支配）、INV-027。
- **期望行为**：`⟹ REJECT(E_NO_FUNDING)`。若项目已在途而现金不足，则 `⟹ ARREARS`：
  按 8 档支付优先级推迟，项目转 `suspended(financing)`，**不允许负国库余额，也不允许无提示的延后**（计划书 §07「短缺先显露」）。
- **断言**

```gdscript
    spend_down_to_zero()
    f.expect_reject("project_launch", {"policy_id":"policy.P04", "region_id":"region.haijia",
                                       "scale_ppm":1000000, "funding_source":"cash"}, "E_NO_FUNDING")
    f.advance(4)
    assert_ge(f.scalar("state.gov.cash_uu"), 0)                                  # INV-016，逐季
    assert_gt(f.arrears_of("project_contracts"), 0)                              # 短缺显露为欠付
    assert_eq(f.project_status("project.P04_0_001"), "suspended_financing")
    assert_eq(f.scalar("state.gov.arrears_uu"),
              f.scalar_prev("state.gov.arrears_uu") + f.new_arrears() - f.cleared_arrears())  # INV-030
```

- **失败诊断**：现金变负 ⇒ **缺 INV-016 的过账前置检查**；项目静默推进 ⇒ **缺 `suspended(financing)` 状态机**，
  玩家会看到「钱不够但项目照做」，这是计划书 §17 P0 级错账。

### `ADV-C05` 用批次刷屏绕过重定价

- **攻击叙述**：「旧债不重定价。那我在低利率时发一万个 1 μU 的批次囤着，以后利率涨了也不影响我。
  顺便把批次表撑爆，系统说不定会自动合并批次——一合并就按新利率重算，反而对我有利/或者直接崩。」
- **操作序列**：单季循环 `issue_bond{amount_uu: 1, tenor_q: 40}` 直到被拒；记录拒绝码与 `bond_batch_cap`。
- **被攻击的不变量**：INV-036（`coupon_ppm_per_q` 发行后被写入即 FAULT）、`param.bond_batch_cap`、INV-007（数值边界）。
- **期望行为**：超过 `param.bond_batch_cap` ⇒ `REJECT(E_CREDIT_LIMIT)` 并报警，
  **不自动合并批次**（`12_simulation_contract.md` §2.4：合并会破坏「旧债不重定价」）。
  同时每笔发行仍受 INV-034 的现金约束，所以刷屏在经济上也不划算。
- **断言**

```gdscript
    var n: int = 0
    while f.submit_ok("issue_bond", {"amount_uu": 1, "tenor_q": 40, "holder": "invpool"}): n += 1
    assert_le(f.bond_count(), f.scalar("param.bond_batch_cap"))
    assert_eq(f.last_reject_code(), "E_CREDIT_LIMIT")
    var coupons_before := f.all_coupons()
    f.advance(8)
    assert_eq(f.all_coupons(), coupons_before)                 # 一个批次的票息都没被改写
    assert_lt(f.quarter_settle_usec(), 1000000)                # 批次刷屏不得把季结算推过 1 s（§17 性能目标）
```

- **失败诊断**：出现合并 ⇒ **违反 INV-036**，旧债被隐式重定价；结算耗时爆炸 ⇒ 债券批次是 O(n) 遍历且没有上限，
  说明 `param.bond_batch_cap` 只写在文档里没进代码。

### `ADV-C06` 把债务减记当收入

- **攻击叙述**：「重组减记 10 U 债务。债务少了 10 U，那资产负债表上净值就多了 10 U——
  如果系统把它记成收入，我的财政收入指标就好看了，说不定还能计入 GDP。」
- **操作序列**：把财政推到重组边缘；`debt_restructure{bond_id, mode:"writedown"}`；`advance(4)`。
- **被攻击的不变量**：INV-028（`debt_end == start + 新增 − 还本 − 确认减记`）、INV-029（新增借款与还本不进任何 GDP 口径）、
  INV-021（`Δnw` 被本季损益完全解释）、`kind=28 writeoff` 的三重分类全为 `none`。
- **期望行为**：减记**必须登记债权人损失**（`11_data_contract.md` §6.1 kind 9 的校验），
  即 `agent.invpool` 或 `agent.row` 的净值等额下降。政府净值上升等于债权人净值下降，**双边**。
  减记不进任何收入口径，不进 GDP，且**普通年份减记为 0**（计划书 §07）。
- **断言**

```gdscript
    var nw_gov_0 := f.scalar("agent.gov.nw_uu"); var nw_pool_0 := f.scalar("agent.invpool.nw_uu")
    do_restructure()
    assert_eq(f.scalar("agent.gov.nw_uu") - nw_gov_0,
              -(f.scalar("agent.invpool.nw_uu") - nw_pool_0))  # 双边，容差 0
    assert_eq(f.derived("derived.fiscal.receipts_uu"), f.receipts_excluding(28))
    for row in f.led_rows(28, f.q()):
        assert_eq(row.prod_class, "none"); assert_eq(row.exp_class, "none"); assert_eq(row.inc_class, "none")
    assert_eq(f.scalar("state.gov.debt_uu"),
              f.scalar_prev("state.gov.debt_uu") + f.led_sum(15, f.q(), f.q())
              - f.led_sum(16, f.q(), f.q()) - f.led_sum(28, f.q(), f.q()))     # INV-028，容差 0
```

- **失败诊断**：减记单边（只减政府负债不减债权人资产）⇒ **缺 INV-015 的对手方**，凭空消灭负债 = 凭空创造净值；
  减记进入 `receipts` ⇒ **缺 `kind` 三重分类**，财政收入指标被污染。

### `ADV-C07` 零期限债券当季发当季还

- **攻击叙述**：「`tenor_q` 填 0 或负数。当季发、当季到期，可能不计息还能刷一笔『收入』。
  或者干脆填个巨大的 `tenor_q`，永远不到期。」
- **操作序列**：分别提交 `tenor_q ∈ {-1, 0, 1, 200, 2^40}`。
- **被攻击的不变量**：INV-037（`Σ_{q'≥q} scheduled_principal == outstanding`）、INV-007（数值边界）、
  `ParameterCard.valid_range`。
- **期望行为**：`tenor_q` 必须在 `valid_range`（首版建议 `[4, 40]`，具体值由参数卡登记）内 ⇒
  其余 `REJECT(E_PARAM_RANGE)`。`tenor_q == 0` 尤其危险：它会让到期表为空而 `outstanding > 0`，直接破坏 INV-037。
- **断言**

```gdscript
    for t in [-1, 0, 1, 200, 1 << 40]:
        f.expect_reject("issue_bond", {"amount_uu": 1000000, "tenor_q": t, "holder": "invpool"}, "E_PARAM_RANGE")
    f.submit("issue_bond", {"amount_uu": 1000000, "tenor_q": 8, "holder": "invpool"})
    f.advance(1)
    for b in f.active_bonds():
        assert_eq(f.sum_scheduled_principal_from(b, f.q()), f.bond_outstanding(b))   # INV-037
```

- **失败诊断**：`tenor_q == 0` 被接受 ⇒ **缺 `valid_range` 的下界校验**；
  `1 << 40` 被接受 ⇒ **缺 INV-007 的上界校验**，后续 `(q << 32)` 形式的 RNG 种子拼接会与季度号发生位重叠（见 `ADV-J01`）。

---

## 5 D 族：物资守恒攻击

### `ADV-D01` 拆单造货（取整套利）

- **攻击叙述**：「买东西按 `付款 = floor(数量 × 价格 / 1e6)` 算。那我把一笔 100 单位的采购拆成 100 笔 1 单位，
  每笔各向下取整一次，总共少付将近 100 μU，货一点不少。反过来，卖的时候拆单就能多收。」
- **操作序列**
  1. 对照组：`cell.haijia.manu` 在 q=1 一次性购入 100 单位 `sector.energy` 之外的可库存中间投入。
  2. 实验组：同一 cell 同季拆成 100 笔各 1 单位。
  3. 两组同种子 `advance(4)`，比较实物库存与现金。
  4. 再做「价格取非整千的病态值」的变体（`price = 1_000_001`），放大取整偏差。
- **被攻击的不变量**：INV-062（付款额 == `idiv_floor(成交量 × 价格, 1e6)`）、INV-003（拆分 Σ 分项 == 原额）、
  INV-005（换算余数写 `log.rounding`，不产生债权债务）、INV-047（库存恒等式）。
- **期望行为**：**同一季、同一买方、同一卖方、同一品种的成交必须先合并数量再计价一次**。
  拆单后的现金差额上界为 0（合并计价后完全无差）；若架构上无法合并，则差额必须 `≤ 1 μU` 且写入 `log.rounding`。
  无论哪种实现，**实物数量两组必须完全相等**。
- **断言**

```gdscript
    assert_eq(f_split.inv_of("cell.haijia.manu", "sector.manu"),
              f_whole.inv_of("cell.haijia.manu", "sector.manu"))               # 实物完全相等
    assert_le(absi(f_split.scalar("agent.cell.haijia.manu.cash_uu")
                 - f_whole.scalar("agent.cell.haijia.manu.cash_uu")), 1)       # 现金差 <= 1 μU
    assert_eq(f_split.log_rounding_sum(0, 4),
              f_split.scalar("state.gov.rounding_residual_uu") + f_split.agent_rounding_residual_sum())
    f_split.assert_conservation()
```

- **失败诊断**：差额随笔数线性增长 ⇒ **缺「同季同对手方同品种合并计价」规则**。
  这是整数记账系统最经典的漏洞，且**必然会被玩家发现**，因为拆单在 UI 上是零成本操作。
  若决定不合并，则必须引入最小成交单位（`param.min_trade_uqs`）把残差压到 μU 量级，
  并在 §13 登记为待决问题。

### `ADV-D02` 制造负库存

- **攻击叙述**：「我下一个远超库存的生产计划。系统按计划扣投入，库存就变负了；
  负库存下季说不定会被当成 0 抹掉，我就白得了一批投入。」
- **操作序列**：`boot()` 后把某 cell 的某项投入库存耗尽（连续满产 3 季不补库），第 4 季仍下满产计划；`advance(1)`。
- **被攻击的不变量**：INV-048（任何库存字段写入后 ≥ 0，不得无提示负库存）、
  INV-046（投入由 `q_actual` 用 `idiv_ceil` 反算且 ≤ 可用量）、INV-043（`output_actual == min(激活约束)`）、
  INV-045（`slack[binding] == 0`）。
- **期望行为**：`Q_materials` 成为紧约束，`output_actual` 下降到库存所能支持的水平，
  `binding_code == "materials"`，未满足的计划写 `unmet_demand`（INV-064）。**库存不得为负，一刻也不行。**
- **断言**

```gdscript
    f.advance(1)
    for c in f.all_cells():
        for s in f.all_sectors():
            assert_ge(f.inv_of(c, s), 0)                       # INV-048
    assert_eq(f.binding_code("cell.haijia.manu"), "materials")
    assert_eq(f.slack_of("cell.haijia.manu", "materials"), 0)  # INV-045
    assert_gt(f.scalar("state.cell.haijia.manu.unmet_demand_uqs"), 0)
    assert_eq(f.inv_end("cell.haijia.manu", "sector.agri"),
              f.inv_start("cell.haijia.manu", "sector.agri") + f.produced() + f.purchased()
              - f.sold() - f.consumed() - f.spoiled())          # INV-047，容差 0
```

- **失败诊断**：出现负库存 ⇒ **缺 INV-048 的写入后置检查**；
  出现「负库存在下季被抹成 0」 ⇒ **存在静默改账路径**，这是计划书 §13 明令禁止的后处理补丁，P0 级缺陷。
  `slack[binding] != 0` ⇒ 五项约束的取最小实现有误，诊断信息会误导玩家（计划书 §04「查原因」环节失效）。

### `ADV-D03` 用未完工资产供能 〔P04 验收测试的对抗版〕

- **攻击叙述**：「电网项目付了 100% 的钱，进度条却只有 60%。但钱都付了，设备总在那儿吧？
  说不定容量已经能用了。再不行我就在第 7 季把 `scale_ppm` 调小，让『已完成量/总量』凑到 100%。」
- **操作序列**
  1. q=0 立项 P04（总成本 4 U，8 季）；
  2. 把 `region.haijia.construction_capacity_uqs` 设为 0（通过合法手段：让 `services` 部门产能被其他项目占满）；
  3. 每季按计划全额付款，`advance(8)`；
  4. q=7 尝试 `policy_set_params{scale_ppm}` 缩小规模以「凑满进度」。
- **被攻击的不变量**：INV-087（付款不制造进度，`construction_progress` 与 `paid_uu` 无函数依赖）、
  INV-088、INV-090（完工充要条件）、INV-091（完工写 `pending`，下季 S01 转 `active`）、INV-054（`capacity_active` 增量写入点全局唯一）。
- **期望行为**：付款可以发生（合同要求付），但 `Δconstruction_progress_ppm == 0`；
  第 8 季进度 < 1e6 ⇒ **不得投运**；缩小规模的命令 `⟹ REJECT(E_PARAM_RANGE)`（在途项目的规模不可改）。
- **断言**

```gdscript
    var cap0: int = f.scalar("state.region.haijia.grid_capacity_uqs_per_q")
    for qq in range(0, 8):
        var p0 := f.project_progress("project.P04_0_001")
        f.advance(1)
        assert_eq(f.project_progress("project.P04_0_001"), p0)         # T-S-P04-PAY-NO-PROGRESS
        assert_gt(f.led_sum(19, qq, qq), 0)                            # 钱确实付出去了
    assert_lt(f.project_progress("project.P04_0_001"), 1000000)
    assert_eq(f.scalar("state.region.haijia.grid_capacity_uqs_per_q"), cap0)   # T-S-P04-NO-EARLY-COMMISSION
    f.expect_reject("policy_set_params", {"policy_id":"policy.P04","params":{"scale_ppm":600000}}, "E_PARAM_RANGE")
```

- **失败诊断**：进度随付款增长 ⇒ **INV-087 被破坏**，这是计划书 §10 点名的验收项，也是「预算不是资产」在实物侧的镜像。
  容量提前生效 ⇒ **缺 INV-091 的一季投运时滞**或 `capacity_active` 存在第二个写者（违反 INV-054）。

### `ADV-D04` 把电力存起来

- **攻击叙述**：「这季电用不完，下季肯定还在。我先让能源满产囤电，等电网项目完工再一次性放出来。」
- **操作序列**：压低全部用电需求（暂停制造业扩产），让能源部门满产 4 季；逐季检查 `inv` 与 `energy_unused_uqs`。
- **被攻击的不变量**：INV-049（`storable == 0` 的部门期末库存恒为 0）、INV-051（电力当期使用，未用作废，不入库存）、
  INV-047、INV-150（内容包 `storable[energy] == 0`）。
- **期望行为**：`state.cell.*.inventory_output_uqs[energy] == 0` 恒成立；未用电量记 `energy_unused_uqs` 并**作废**；
  这是显式的浪费，应在季度报告中作为「可解释的无效产出」呈现，而不是消失。
- **断言**

```gdscript
    for qq in range(0, 4):
        f.advance(1)
        for c in f.all_cells():
            assert_eq(f.inv_of(c, "sector.energy"), 0)          # INV-049
            assert_eq(f.inv_of(c, "sector.services"), 0)
        assert_gt(f.scalar("state.flow.energy_unused_uqs"), 0)  # 浪费被显式登记
        assert_eq(f.scalar("state.flow.energy_supplied_uqs"),
                  f.scalar("state.flow.energy_allocated_uqs") + f.scalar("state.flow.energy_unused_uqs"))
```

- **失败诊断**：能源库存 > 0 ⇒ **`storable` 标志没有在生产/入库路径上真正生效**；
  `energy_unused` 不存在 ⇒ 浪费被静默丢弃，玩家无法理解「为什么我建了电厂却没用上」（计划书 §04 信息设计底线）。

### `ADV-D05` 同季链条造货

- **攻击叙述**：「农业这季产 100 单位粮食，制造业这季就拿去加工。一季之内走两道工序，产出翻倍。」
- **操作序列**：构造一个全部 cell 期初库存为 0、但本季产出充足的夹具；下满产计划；`advance(1)`。
- **被攻击的不变量**：INV-050（可库存中间投入**只来自期初库存**，本季购入补的是下季可用库存）、
  INV-046、`test_u_no_same_quarter_chain`。
- **期望行为**：期初库存为 0 ⇒ `Q_materials == 0` ⇒ 下游 cell 本季产出为 0，`binding_code == "materials"`。
  本季采购入库，下季才能用。这是「显式的离散化简化」（计划书 §13），必须严格执行，否则部门顺序会决定结果。
- **断言**

```gdscript
    f.advance(1)
    assert_eq(f.output_actual("cell.haijia.manu"), 0)
    assert_eq(f.binding_code("cell.haijia.manu"), "materials")
    assert_gt(f.inv_of("cell.haijia.manu", "sector.agri"), 0)   # 本季买到了，但本季没用上
    # 部门结算顺序不影响结果：换一个顺序重跑，哈希必须相同
    assert_eq(f.state_hash(), f_reordered.state_hash())
```

- **失败诊断**：下游当季有产出 ⇒ **INV-050 被破坏**，同季生产链形成；
  后果不只是造货，而是**结算结果依赖部门遍历顺序**，直接摧毁 INV-014 的可重放性。
  换序哈希不同即为铁证。

### `ADV-D06` 用损耗掩盖盘点差异

- **攻击叙述**：「库存对不上的时候，系统大概会把差额记成『损耗』。那我制造大量对不上的情形，
  差额就被吞掉了——反过来，如果吞的方向对我有利，我就白得货。」
- **操作序列**：把 `param.spoil_rate_ppm` 设到 `valid_range` 上限；跑 20 季；
  逐季逐 cell 逐品种验证库存恒等式，并检查 `spoil` 是否同时计入中间消耗。
- **被攻击的不变量**：INV-053（损耗显式登记并计入中间消耗，不允许用「盘点差异」吸收）、INV-047、
  INV-111（`value_added == gross_output − intermediate`）、INV-115（`gdp_expenditure == gdp_production + price_variance_total`，残差恰为 0）。
- **期望行为**：`spoil` 是一个**有名字、有数量、有金额、有日志行**的流量。
  库存恒等式的六项逐项可查；损耗既减库存又计中间消耗，且不重复扣减总产出
  （`12_simulation_contract.md` 裁定 S-05：只有这种写法能让整数恒等式精确闭合）。
- **断言**

```gdscript
    for qq in range(0, 20):
        f.advance(1)
        for c in f.all_cells():
            for s in f.storable_sectors():
                assert_eq(f.inv_end(c, s),
                          f.inv_start(c, s) + f.produced(c, s) + f.purchased(c, s)
                          - f.sold(c, s) - f.consumed(c, s) - f.spoiled(c, s))     # INV-047，容差 0
        assert_eq(f.derived("derived.gdp.expenditure_uu"),
                  f.derived("derived.gdp.production_uu") + f.derived("derived.gdp.price_variance_total_uu"))
        assert_true(f.intermediate_includes_spoil(qq))          # INV-053
```

- **失败诊断**：恒等式残差非 0 却没报错 ⇒ **存在「盘点差异」吸收路径**；
  GDP 三口径残差非 0 ⇒ 损耗只减了库存没进中间消耗，增加值被高估。

### `ADV-D07` 能源自举

- **攻击叙述**：「能源部门自己要用电。如果自用系数接近 1，那产 1 单位电要用 0.99 单位电——
  反过来说只要有一点点电就能不断自我放大。我把内容包里的 `a(energy→energy)` 调到 0.999999 试试。」
- **操作序列**：内容包变体 `a(energy→energy) ∈ {999999, 1000000, 1000001}`；分别载入。
- **被攻击的不变量**：INV-052（能源自用先从本部门产出净出；内容包必须 `a(energy→energy) < 1e6`）、
  INV-150（IO 表每列和 < 1e6）、`E_IO_ENERGY_SELF`、`E_IO_NOT_CONVERGENT`。
- **期望行为**：`≥ 1e6` ⇒ 载入期 `REJECT(E_IO_ENERGY_SELF)`；
  `999999` 虽然合法但会让列和逼近 1，应被 `E_IO_COLSUM`（增加值为正）或 `E_IO_NOT_CONVERGENT` 拦住。
  即使勉强合法，能源 cell 也**跳过能源约束**，自用量用 `idiv_ceil` 从产出净出，不形成同期迭代。
- **断言**

```gdscript
    assert_eq(f.load_content("fixtures/io/energy_self_1000000/"), Err.E_IO_ENERGY_SELF)
    assert_eq(f.load_content("fixtures/io/energy_self_1000001/"), Err.E_IO_ENERGY_SELF)
    var code := f.load_content("fixtures/io/energy_self_999999/")
    assert_true(code == Err.E_IO_COLSUM or code == Err.E_IO_NOT_CONVERGENT)
    # 合法取值下，能源 cell 不产生能源约束候选值
    f.boot(); f.advance(1)
    assert_ne(f.binding_code("cell.xiling.energy"), "energy")   # INV-044：系数为 0/自指的约束不产生候选值
```

- **失败诊断**：载入通过且运行期出现同期迭代 ⇒ **缺 INV-052 的自指处理**，
  后果是结算不收敛或结果依赖迭代次数，直接违反可重放性。

---

## 6 E 族：人口守恒攻击

### `ADV-E01` 全员迁入一区仍享无限住房 〔≡ 计划书点名 ④，别名 ADV-04〕

- **攻击叙述**：「中州工资最高。我把政策全砸在中州，让四个区的劳动人口全迁过去。
  住房不够？大概只是个数字，挤一挤总住得下。」
- **操作序列**
  1. `boot()`；把 P01 免征额、P03 替代比例、P10 医疗拨款全部集中到 `region.zhongzhou`；
  2. 同时压低其余三区的一切吸引力参数（合法范围内）；
  3. `advance(40)`；逐季记录各区 `population_persons`、`housing_stock_units`、`housing_occupied_units`、`migrate_rejected_persons`。
- **被攻击的不变量**：INV-083（`Σ_g housing_occupied ≤ housing_stock ≤ housing_capacity`）、
  INV-084（被住房或迁移成本挡回的人数写 `migrate_rejected_persons`，容量不得自动增长）、
  INV-071（全国人口守恒）、INV-072（逐组来源去向）、INV-073（迁移双边）。
- **期望行为**：住房容量是**硬上限**。迁入被挡回的人留在原地并记 `migrate_rejected_persons`；
  住房紧张通过「住房负担上升 → 生活指数下降 → 支持度下降」反馈，**不是通过容量自动扩张**。
  容量只能由 P06 公共住房建设经 6–12 季施工形成。
- **断言**

```gdscript
    for qq in range(0, 40):
        f.advance(1)
        for r in f.all_regions():
            assert_le(f.scalar("state.region.%s.housing_occupied_units" % r),
                      f.scalar("state.region.%s.housing_stock_units" % r))       # INV-083
            assert_le(f.scalar("state.region.%s.housing_stock_units" % r),
                      f.scalar("state.region.%s.housing_capacity_units" % r))
        assert_eq(f.total_population(), 24000000 + f.cum_births() - f.cum_deaths())   # INV-071
        for g in f.all_groups():
            assert_eq(f.pop(g), f.pop_prev(g) + f.births(g) - f.deaths(g)
                      + f.age_in(g) - f.age_out(g) + f.skill_in(g) - f.skill_out(g)
                      + f.migrate_in(g) - f.migrate_out(g))                       # INV-072，容差 0
    assert_gt(f.scalar("state.flow.migrate_rejected_persons_cum"), 0, "极端诱因下竟无一人被挡回")
    # 住房存量的每一次增长都必须能追溯到一个已完工的 P06 项目
    for ev in f.housing_stock_increases():
        assert_true(f.project_completed_at(ev.q, ev.region, "policy.P06"))
```

- **失败诊断**
  - 占用 > 存量 ⇒ **缺 INV-083 的迁移落地前检查**（检查必须在迁入**之前**，不是事后修正）。
  - 存量自动增长 ⇒ **缺 INV-084 的「容量不得自动增长」**：住房被写成了「需求驱动的软约束」，
    计划书 §08「迁移受职位、住房与迁移成本约束」被架空。
  - `migrate_rejected == 0` ⇒ 迁移函数根本没有住房闸门，或诱因参数设得太弱（后者是测试自身的缺陷，需要调夹具）。

### `ADV-E02` 同季互迁造人

- **攻击叙述**：「A 区 100 人迁到 B 区，同时 B 区 100 人迁到 A 区。如果迁入迁出分别结算，
  两边都先加后减或先减后加，顺序不同就可能多出人来。」
- **操作序列**：构造对称诱因夹具，使 `region.beiyuan ↔ region.zhongzhou` 同季发生双向迁移；
  再做「四区环形迁移」变体（A→B→C→D→A）；各跑 8 季。
- **被攻击的不变量**：INV-073（`migrate_out[a][b] == migrate_in[b][a]`，`Σ 迁入 == Σ 迁出`）、INV-071、INV-072。
- **期望行为**：迁移是**一次性双边记账**，不是两次单边写入。环形迁移的净人口变化为 0，
  但迁移成本（`kind=25 migration_cost`）照收——**迁移不是免费的**。
- **断言**

```gdscript
    for qq in range(0, 8):
        f.advance(1)
        for a in f.all_regions():
            for b in f.all_regions():
                assert_eq(f.migrate_out_matrix(a, b), f.migrate_in_matrix(b, a))   # INV-073
        assert_eq(f.sum_migrate_in(), f.sum_migrate_out())
        assert_eq(f.total_population(), 24000000 + f.cum_births() - f.cum_deaths())
    assert_gt(f.led_sum(25, 0, 7), 0)                          # 环形迁移仍然付了迁移成本
```

- **失败诊断**：总人口变化 ⇒ 迁移写成了「先对全体加迁入、再对全体减迁出」的两趟循环，
  中间状态被其它函数读到；**修法是把迁移做成一个原子的双边矩阵操作**，与账本 `post()` 同构。

### `ADV-E03` 没有教师时培训照样完成 〔≡ 计划书点名 ③，别名 ADV-03〕

- **攻击叙述**：「P05 职业培训扩容，我拨款拉满，席位开满。教师？系统大概只看钱。」
- **操作序列**
  1. `boot()`，夹具把 `state.region.*.teachers_persons` 置 0（合法路径：公共部门工资长期欠拨导致教师流失，
     或剧本变体 `fixtures/scenario/no_teachers/`）；
  2. q=0 `policy_enact{policy.P05}`，招生席位取上限，助学支持拉满；
  3. `advance(20)`；逐季记录 `new_seats`、`enrolled`、`skill_in`、`skill_out`、P05 支出。
  4. 变体：教师数从 0 逐步恢复，验证席位上限随之线性抬升。
- **被攻击的不变量**：INV-081（`新增席位 ≤ teachers × ratio − 在读`，**拨款当季不得产生任何 `skill_in`**）、
  INV-082（技能升档只来自结业队列，`skill_out` 与 `skill_in` 等量配对，滞后 ≥ `param.training_lag_q`）、
  INV-072、INV-095。
- **期望行为**：`teachers == 0 ⇒ new_seats == 0 ⇒ skill_in == 0`，全程。
  **拨款照付**（合同就是这么签的），形成一笔**可解释的无效支出**——这正是计划书 §09
  「政策可以在某些条件下明显无效；玩家应能理解无效发生在哪里」的要求：
  报告必须给出 `blocked_reason = no_teachers`，而不是让玩家自己猜。
- **断言**

```gdscript
    for qq in range(0, 20):
        f.advance(1)
        assert_eq(f.scalar("state.policy.P05.new_seats_units"), 0)
        for g in f.all_groups():
            assert_eq(f.skill_in(g), 0)                        # 一个人也没升档
    assert_gt(f.policy_spend("policy.P05", 0, 19), 0)          # 但钱确实花了
    assert_eq(f.blocked_reason("policy.P05"), "no_teachers")   # INV-100：可见且被阻塞必有原因
    assert_true(f.localization_has("blocked_reason.no_teachers"))
    # 恢复教师后席位上限线性抬升，且结业仍有滞后
    f2.restore_teachers(); f2.advance(1)
    assert_eq(f2.scalar("state.policy.P05.new_seats_units"),
              mini(f2.teachers() * f2.scalar("param.student_teacher_ratio") - f2.enrolled(),
                   f2.seats_requested()))
    assert_eq(f2.skill_in_total(), 0)                          # 当季仍为 0
    f2.advance(f2.scalar("param.training_lag_q"))
    assert_gt(f2.skill_in_total(), 0)                          # 滞后之后才结业
    assert_eq(f2.skill_in_total(), f2.skill_out_total())       # INV-082 等量配对
```

- **失败诊断**
  - `skill_in > 0` ⇒ **缺 INV-081**：培训被写成了「花钱即升级」，计划书 §08「教育按队列结业，不在拨款当季让全民升级」被违反。
  - 席位上限与教师无关 ⇒ 缺 `max_seats = teachers × ratio` 这条硬约束。
  - `blocked_reason` 缺失 ⇒ 违反计划书 §04 信息设计底线（「政策页必须告诉玩家为什么不能执行」），
    玩家会以为是 bug 而不是机制。

### `ADV-E04` 出生死亡双记

- **攻击叙述**：「一个人在同一季既成年又死亡，或者既迁出又死亡。如果两条路径各自扣人，就扣了两次；
  如果各自加人，就多了一个人。」
- **操作序列**：把 `param.death_rate_ppm`、`param.birth_rate_ppm`、`param.age_transition_ppm` 同时设到 `valid_range` 上限；
  同时开启强迁移诱因；跑 40 季。这是一个**故意制造路径冲突**的夹具。
- **被攻击的不变量**：INV-071（死亡是唯一净流出，出生是唯一净流入）、INV-072（逐组八项来源去向）、
  INV-074（年龄有向：成年只能来自低一档）。
- **期望行为**：八条人口流量在 S07 内有**固定的执行顺序**，同一个人不可能被两条路径同时选中。
  推荐顺序（应由 `12_simulation_contract.md` §7.4 固定）：死亡 → 成年 → 技能 → 迁移 → 出生。
  每条流量都写日志，`INV-072` 逐组容差 0。
- **断言**

```gdscript
    for qq in range(0, 40):
        f.advance(1)
        assert_eq(f.total_population(),
                  f.total_population_prev() + f.total_births() - f.total_deaths())    # INV-071
        for g in f.all_groups():
            assert_ge(f.pop(g), 0)
            assert_eq(f.pop(g), f.pop_prev(g) + f.births(g) - f.deaths(g)
                      + f.age_in(g) - f.age_out(g) + f.skill_in(g) - f.skill_out(g)
                      + f.migrate_in(g) - f.migrate_out(g))
        # 年龄有向：minor 组不接收 age_in，elder 组不产生 age_out
        assert_eq(f.age_in(group_of(AGE_MINOR)), 0)
        assert_eq(f.age_out(group_of(AGE_ELDER)), 0)
        # 单季流出不得超过组内人口
        for g in f.all_groups():
            assert_le(f.deaths(g) + f.age_out(g) + f.skill_out(g) + f.migrate_out(g), f.pop_prev(g))
```

- **失败诊断**：出现负人口或恒等式残差 ⇒ **人口流量的执行顺序未固定**，或某条流量读取了已被上一条修改过的 `pop`。
  修法与 `ADV-E02` 相同：把 S07 的人口更新做成「先全部计算流量、后一次性应用」的两相结构，
  流量计算阶段只读 `pop_prev`。

### `ADV-E05` 就业人数超过劳动力

- **攻击叙述**：「制造业缺人就多招。老人、小孩、失业保障领取者，都算上。反正就业人数只是个计数器。」
- **操作序列**：把全部 cell 的扩产意愿推到上限（高价格、高需求预期），跑 20 季；
  另做变体：把某区 `participation_ppm` 设到下限，验证就业随之被压住。
- **被攻击的不变量**：INV-075（`labor_force == floor(pop × participation)`；`unemployed == labor_force − employed ≥ 0`）、
  INV-076（逐地区逐技能 `Σ employed ≤ Σ labor_force`）、INV-077（群组侧与 cell 侧就业逐（地区,技能）精确相等）、
  INV-074（minor/elder 的 `participation == 0` 且 `employed == 0`）、INV-078（首版不允许技能向下替代）。
- **期望行为**：招工有**两道硬闸**（`12_simulation_contract.md` §3.2）：可用劳动力上限 + 工资资金来源。
  招不到人时 `Q_labor` 成为紧约束，`binding_code == "labor"`，而不是「就业数照填、产量照出」。
- **断言**

```gdscript
    for qq in range(0, 20):
        f.advance(1)
        for r in f.all_regions():
            for sk in f.all_skills():
                assert_le(f.employed_by(r, sk), f.labor_force_by(r, sk))         # INV-076
                assert_eq(f.employed_group_side(r, sk), f.employed_cell_side(r, sk))  # INV-077，容差 0
        for g in f.groups_with_age(AGE_MINOR) + f.groups_with_age(AGE_ELDER):
            assert_eq(f.employed(g), 0)                                          # INV-074
        assert_ge(f.scalar("derived.labor.unemployed_persons"), 0)
        assert_eq(f.scalar("derived.labor.unemployment_ppm"),
                  IntMath.idiv_floor(f.unemployed_total() * 1000000, f.labor_force_total()))
```

- **失败诊断**：就业超劳动力 ⇒ **缺 INV-076 的招工上限**，且会连锁破坏 INV-079（工资总额对账）；
  两侧就业不等 ⇒ **群组侧与 cell 侧是两份独立数据而非同一事实的两个索引**，
  这是计划书 §17「人口与就业」验收项的核心，必须逐季交叉校验（INV-151 在载入期也查一遍）。

### `ADV-E06` 退休后继续上班

- **攻击叙述**：「劳动人口不够？那就让 elder 档也参与就业，反正他们也在地区里。」
- **操作序列**：内容包变体把 `participation_ppm[elder] = 300000`；载入；
  再做运行期变体：让大量 working 人口成年进入 elder 后，检查其 `employed` 是否被正确剥离。
- **被攻击的不变量**：INV-074、INV-080（`employment_persons` 只由 S03 与 S07 写；S07 的减少量必须精确等于对应群组的流出就业人数）。
- **期望行为**：载入期 `REJECT(E_POP_AGE_ROLE)`。运行期成年流出时，**就业必须配对剥离**：
  一个人从 working 变成 elder，他的岗位同时从 cell 侧减少，且减少量精确等于流出的就业人数。
- **断言**

```gdscript
    assert_eq(f.load_scenario("fixtures/scenario/elder_works/"), Err.E_POP_AGE_ROLE)
    f.boot(); f.advance(40)
    for qq in range(0, 40):
        assert_eq(f.employment_decrease_s07(qq), f.employed_persons_aging_out(qq))   # INV-080，容差 0
    for g in f.groups_with_age(AGE_ELDER):
        assert_eq(f.scalar_group(g, "participation_ppm"), 0)
        assert_eq(f.employed(g), 0)
```

- **失败诊断**：成年流出后 cell 侧就业未减少 ⇒ **人口与就业脱钩**，
  会表现为「人都老了工厂还在满产」；这是 INV-077 在跨季方向上的对应物，容易被漏掉。

---

## 7 F 族：项目与合同攻击

### `ADV-F01` 取消退款

- **攻击叙述**：「项目干到一半我取消，已经付的钱应该退回来吧？至少合同额度得释放。」
- **操作序列**：q=0 立项 P04；付款 4 季（累计 2 U）；q=4 `project_cancel`；`advance(4)`。
- **被攻击的不变量**：INV-093（`committed_memo` 减未付部分，`paid_uu` **不回退**，现金不增加，
  `residual_value` 与 `cancel_penalty` 均入账）、INV-032、INV-092。
- **期望行为**：已付不退（计划书 §07「项目取消不会释放已实际花掉的钱」、§10「未完工工程登记残值」）。
  取消产生三笔记录：未付部分的承诺释放（表外）、残值登记（`wip → capital` 或 `wip → 0` 并计损失）、
  合同赔偿 `kind=27`。**政府现金只会因取消而减少，绝不增加。**
- **断言**

```gdscript
    var cash_before := f.scalar("state.gov.cash_uu")
    var paid_before := f.project_paid("project.P04_0_001")
    f.submit("project_cancel", {"project_id": "project.P04_0_001"}); f.advance(1)
    assert_le(f.scalar("state.gov.cash_uu"), cash_before)        # 只会减少
    assert_eq(f.project_paid("project.P04_0_001"), paid_before)  # 已付一分不退
    assert_gt(f.led_sum(27, f.q()-1, f.q()), 0)                  # 赔偿真的收了
    assert_eq(f.scalar("state.gov.committed_memo_uu"),
              f.scalar_prev("state.gov.committed_memo_uu") - f.unpaid_at_cancel())
    assert_le(f.project_residual_value("project.P04_0_001"), paid_before)   # 残值不得超过已投入
    f.assert_conservation()
```

- **失败诊断**：现金增加 ⇒ **取消被写成了「冲销已付分录」**，这是账本层面的时间倒流，
  违反「每笔交易双边相等」（计划书 §17）且会让 INV-018 的现金总量守恒立刻报警。
  残值 > 已付 ⇒ 残值评估函数凭空创造资产。

### `ADV-F02` 反复立项占队列

- **攻击叙述**：「施工槽位有限。我在每个区都立满项目占住槽位，下季全取消再立——
  这样既不花钱又能一直占着队列；或者反过来，我用这招把某个区的队列堵死看会不会崩。」
- **操作序列**：每季在四个区各立满 `construction_slots_total` 个项目，下季全取消，重复 20 次。
- **被攻击的不变量**：INV-094（`Σ_{project ∈ r} queue_slot_held ≤ construction_slots_total`，超出者 `suspended(congestion)`，
  **不是静默排队**）、INV-058（施工受推进速度与并发数双重约束）、INV-032。
- **期望行为**：槽位上限是硬约束，超出的立项 `⟹ REJECT(E_NO_SLOT)`；
  **每次立项–取消循环都产生 `cancel_penalty`**，所以占位不是免费的；
  槽位计数在取消当季释放，不得泄漏（跑 20 轮后可用槽位必须回到初值）。
- **断言**

```gdscript
    for round in range(0, 20):
        fill_all_slots(); f.advance(1); cancel_all(); f.advance(1)
        for r in f.all_regions():
            assert_le(f.slots_held(r), f.scalar("state.region.%s.construction_slots_total" % r))
    assert_eq(f.slots_held_total(), 0, "槽位泄漏：20 轮后仍有槽位未释放")
    assert_gt(f.led_sum(27, 0, 39), 0)                          # 占位是有代价的
    assert_gt(f.rejections_with_code("E_NO_SLOT").size(), 0)
```

- **失败诊断**：槽位泄漏 ⇒ **取消路径没有释放 `queue_slot_held`**（引用计数错误的经典形态）；
  无赔偿 ⇒ **缺「取消产生违约或沉没成本」规则**（计划书 §07），立项变成零成本试探，
  玩家会把队列当成免费的信息探针。

### `ADV-F03` 付款制造进度（P04 验收断言的独立复核）

- **攻击叙述**：与 `ADV-D03` 同源，但这里从**合同侧**攻击：
  「我把项目的每季付款计划改成第 1 季一次性付清 4 U。钱到位了，进度总该跟上。」
- **操作序列**：内容包变体把 P04 的 `spend_plan` 改成 `[4U, 0, 0, 0, 0, 0, 0, 0]`；载入；立项；`advance(8)`。
- **被攻击的不变量**：INV-087、INV-088、INV-092（`Σ spend_plan == total_cost`）、`E_POLICY_COST`。
- **期望行为**：一次性付清在**合同上**可能合法（载入期是否允许由 `PolicyDefinition` 的 `spend_plan` 校验决定），
  但**进度仍只由实投施工服务量决定**：8 季的进度曲线必须与「均匀付款」组**完全相同**。
- **断言**

```gdscript
    for qq in range(0, 8):
        assert_eq(f_frontload.project_progress(PID), f_even.project_progress(PID))   # 逐季逐位相同
    assert_ne(f_frontload.scalar("state.gov.cash_uu"), f_even.scalar("state.gov.cash_uu"))  # 现金路径不同
    assert_eq(f_frontload.project_commissioned_q(PID), f_even.project_commissioned_q(PID))
```

- **失败诊断**：前置付款组更早完工 ⇒ **`progress` 对 `paid_uu` 存在函数依赖**，INV-087 被破坏。
  这条测试与 `ADV-D03` 互为独立复核：前者切断施工能力，后者改变付款节奏，**两条都绿才能说 INV-087 成立**。

### `ADV-F04` 无限延期

- **攻击叙述**：「项目缺钱？`project_defer` 延期就行。一直延到第 40 季，成本就永远不发生。」
- **操作序列**：立项后每季提交 `project_defer{project_id, quarters: 4}`，直到被拒；记录拒绝季与拒绝码。
- **被攻击的不变量**：INV-032、INV-094、`Command.kind=6` 的「合同允许延期」校验。
- **期望行为**：延期次数与总延期长度必须有上限（由 `PolicyDefinition.contract_terms` 规定），
  超出 `⟹ REJECT`；每次延期**占用槽位不释放**（否则延期变成了免费保留队列位置），
  且应产生延期费或推高 `cancel_penalty` 基数。延期不得把 `committed_memo` 减少。
- **断言**

```gdscript
    var n := 0
    while f.submit_ok("project_defer", {"project_id": PID, "quarters": 4}): n += 1
    assert_le(n, f.scalar("param.max_defer_count"))
    assert_gt(f.slots_held(REGION), 0, "延期期间竟然释放了槽位")
    assert_eq(f.scalar("state.gov.committed_memo_uu"), COMMITTED_AT_LAUNCH)
```

- **失败诊断**：可以无限延期 ⇒ **缺延期上限规则**。这是本目录中**最可能真的缺失**的一条：
  `11_data_contract.md` §6.1 只写了「合同允许延期」，没有定义上限来源。**见 §13 待决问题 Q-ADV-01。**

### `ADV-F05` 拆分项目绕过槽位

- **攻击叙述**：「一个区只能同时开 3 个项目？那我把一个大电网项目拆成 3 个小的，
  再把每个小的拆成 3 个更小的——反正槽位是按项目数算的。」
- **操作序列**：在同一区立 1 个 `scale_ppm = 1000000` 的项目（对照组）；
  实验组立 9 个 `scale_ppm = 111111` 的项目；比较施工推进速度与完工季。
- **被攻击的不变量**：INV-058（施工同时受 `construction_capacity_uqs`**推进速度**与 `construction_slots_total`**并发数**双重约束）、INV-094、INV-088。
- **期望行为**：**槽位数挡住并发，施工能力挡住总量**。拆成 9 个只会撞上槽位上限（超出者 `suspended(congestion)`），
  即使都进了队列，总推进速度仍受 `construction_capacity_uqs` 限制，**完工季不得早于对照组**。
- **断言**

```gdscript
    assert_le(f_split.active_project_count(REGION), f_split.scalar("state.region.haijia.construction_slots_total"))
    assert_ge(f_split.first_commission_q(), f_whole.first_commission_q())
    assert_le(f_split.total_construction_used(0, 20), f_split.total_construction_capacity(0, 20))
```

- **失败诊断**：拆分后更快完工 ⇒ **只有并发数约束、没有推进速度约束**（INV-058 的一半缺失）。
  这是「双重约束」为什么必须双重的直接证明：单一约束总能被拆分或合并绕过。

### `ADV-F06` 残值套利

- **攻击叙述**：「取消项目会登记残值。如果残值按『计划总投入』算而不是按『实际已投入』算，
  我就付一点点钱、立刻取消、拿走一大笔残值资产。」
- **操作序列**：立项后只付 1 季（0.5 U），立即取消；比较 `residual_value` 与 `paid_uu` 与 `wip`。
- **被攻击的不变量**：INV-093、INV-020（逐主体资产负债恒等式）、INV-021（`Δnw` 被损益完全解释）。
- **期望行为**：`residual_value ≤ wip ≤ Σ paid_uu`。残值是**已形成的在建工程**的评估值，
  不能超过实际投入；取消损失 = `paid − residual` 计入当期损益，净值变化可解释。
- **断言**

```gdscript
    f.advance(1); f.submit("project_cancel", {"project_id": PID}); f.advance(1)
    assert_le(f.project_residual_value(PID), f.scalar("state.gov.wip_uu_at_cancel"))
    assert_le(f.scalar("state.gov.wip_uu_at_cancel"), f.project_paid(PID))
    assert_eq(f.scalar("agent.gov.nw_uu") - NW_BEFORE,
              f.project_residual_value(PID) - f.project_paid(PID) - f.led_sum(27, f.q(), f.q()))  # INV-021
```

- **失败诊断**：残值 > 已付 ⇒ 残值函数引用了 `total_cost` 而不是 `wip`；
  净值变化无法被损益解释 ⇒ 残值登记走了绕过 `post()` 的直接赋值路径（违反 INV-022）。

---

## 8 G 族：政治攻击

### `ADV-G01` 一次性补贴刷支持率

- **攻击叙述**：「选举前一季把 P03 失业保障拉满，给所有人发钱，支持率就上去了。
  选举后立刻撤回，反正支持率已经拿到手了。」
- **操作序列**：`boot()`；q=0..13 常规运行；q=14 把 P03 替代比例拉满；q=15 选举；q=16 撤回；
  `advance(24)`；逐季记录 `living_ppm`、`expectation_ppm`、`trust_ppm`、`support_national_ppm` 与三者的来源分解。
- **被攻击的不变量**：INV-121（生活/预期/信任分开存储、分开更新、分开展示；禁止合成单一「满意度」）、
  INV-122（`trust_ppm` 的更新式中**不存在 `transfer_income` 通道**；恢复速度 < 下降速度）、
  INV-123（支持度变动有来源分解）、INV-124（全国支持度只由群组加权得出且保留分布）。
- **期望行为**：一次性转移**只能**改善「当期生活」分量，**不能**改善「程序信任」分量；
  撤回后生活分量迅速回落，信任分量因**非对称恢复**而长期低于攻击前水平。
  净效果是：短期刷分有效但有限，长期代价明确——这正是计划书 §08
  「短期补贴能缓解生活压力，却不能自动修复长期失信」。
- **断言**

```gdscript
    var trust_before := f.trust_at(13)
    f.advance_to(16)
    assert_eq(f.trust_at(15), trust_before, "转移支付直接抬高了信任 = INV-122 被破坏")
    assert_gt(f.living_at(15), f.living_at(13))                 # 生活分量确实改善了
    f.advance_to(39)
    assert_lt(f.trust_at(39), trust_before)                     # 撤回的代价是长期的
    # 非对称：下降快、恢复慢
    assert_lt(f.scalar("param.trust_recover_ppm"), f.scalar("param.trust_drop_ppm"))
    # 三分量不得被合成
    assert_false(f.state_has_field("state.politics.satisfaction_ppm"))
    # 支持度变动 100% 可分解
    for qq in range(13, 40):
        assert_eq(f.support_delta(qq),
                  f.support_delta_from_living(qq) + f.support_delta_from_expectation(qq)
                  + f.support_delta_from_trust(qq))             # INV-123，容差 0
```

- **失败诊断**：信任随转移上升 ⇒ **INV-122 被破坏**，游戏退化为「发钱即赢」，
  计划书 §08「民众不是一个满意度」失效，且会导致 §17「策略差异」验收项崩溃（所有路线收敛到发钱）。
  出现 `satisfaction_ppm` 字段 ⇒ 三分量在某处被合并，静态检查（INV-121）失效。

### `ADV-G02` 选举季前后套利

- **攻击叙述**：「选举在第 16、32 季。那我第 15 季末把所有难看的账藏起来（延期、欠付都推到 17 季），
  第 17 季再爆——反正席位已经拿到了。」
- **操作序列**：q=12..15 大规模 `project_defer` + 主动制造欠付（把支付优先级调成让欠付集中在低优先档）；
  q=15 选举；q=16 恢复。比较「藏账」组与「不藏账」组的席位结果与 q=17..24 的政治后果。
- **被攻击的不变量**：INV-127（选举只在 `q ∈ {15, 31}`；预算审查 `q ≡ 3 (mod 4)`）、
  INV-126（席位转换是纯函数 `seat_rule(support_national_ppm, seats_total)`）、INV-030（欠付恒等式）、INV-123。
- **期望行为**：藏账**可以奏效**——这是合法的政治策略，不是漏洞。
  但必须满足三条：(a) 欠付在 `state.gov.arrears_uu` 上**始终可见**，不因延期而消失；
  (b) 延期**有成本**（`ADV-F04`）；(c) 爆发后的信任下降幅度**大于**藏账期间的信任维持收益（非对称，INV-122）。
  **测试判定的是「账没被藏掉」，不是「策略不许用」。**
- **断言**

```gdscript
    for qq in range(12, 17):
        assert_eq(f.scalar("state.gov.arrears_uu"),
                  f.scalar_prev("state.gov.arrears_uu") + f.new_arrears(qq) - f.cleared_arrears(qq))
        assert_gt(f.scalar("state.gov.arrears_uu"), 0)          # 欠付始终挂在账上，没有被延期抹掉
    assert_eq(f.election_quarters(), [15, 31])                  # INV-127
    assert_eq(f.seats_gov(), SeatRule.apply(f.support_national_at(15), f.seats_total()))  # 纯函数复算
    # 长期代价大于短期收益
    assert_lt(f.trust_at(24), f_honest.trust_at(24))
    assert_lt(f.support_national_at(31), f_honest.support_national_at(31))
```

- **失败诊断**：欠付因延期而归零 ⇒ **延期被实现成了「取消并重新签约」**，账面被洗白；
  席位无法用纯函数复算 ⇒ 席位规则里混入了状态或随机数，违反 INV-126，重放会分歧。

### `ADV-G03` 用事件改账

- **攻击叙述**：「事件模板能改状态。我写一个事件模板，条件设成必然触发，效果设成 `gov.cash += 10 U`。」
- **操作序列**：内容包变体，`EventTemplate.effects.target` 依次尝试
  `state.gov.cash_uu`、`state.cell.*.inventory_output_uqs`、`state.region.*.housing_capacity_units`、
  `state.pop.*.population_persons`；逐个载入。
- **被攻击的不变量**：INV-130（事件 `effects.target` 只能是六个主观量之一；**事件不得直接写现金、库存、产能、人口，
  首版事件没有任何账本效应**）、`E_EVENT_TARGET`、`E_EVENT_LEDGER`。
- **期望行为**：全部 `⟹ REJECT(E_EVENT_TARGET)` 或 `E_EVENT_LEDGER`，**载入期拒绝**。
  事件只能改预期、信任、支持、组织力、立场、行政能力——即「叙事不能改经济」。
- **断言**

```gdscript
    for tgt in ["state.gov.cash_uu", "state.cell.haijia.manu.inventory_output_uqs",
                "state.region.zhongzhou.housing_capacity_units", "state.pop.beiyuan.working.low.population_persons"]:
        var code := f.load_content(make_event_pack(tgt))
        assert_true(code == Err.E_EVENT_TARGET or code == Err.E_EVENT_LEDGER)
    # 合法目标可以通过
    assert_eq(f.load_content(make_event_pack("trust_ppm")), 0)
    # 且事件抽样用的是 rng.event，不影响 rng.shock
    var shock_draws_before := f.rng_log("rng.shock", f.q())
    f.advance(1)
    assert_eq(f.rng_log("rng.shock", f.q()-1), shock_draws_before)
```

- **失败诊断**：任一非法目标载入通过 ⇒ **事件效应目标白名单是黑名单实现**（只挡了几个名字）。
  正确写法是**正向枚举**：`target` 必须精确匹配六个允许值之一，其余一律拒绝。
  这条直接关系到计划书 §12「生成式 AI 不进入权威结算」的可执行边界——
  如果事件能改账，那么任何内容作者（包括未来的 AI 改写层）都能改账。

### `ADV-G04` 终局之后继续玩

- **攻击叙述**：「失去执政资格了？我再点一次推进季度，说不定能继续。」
- **操作序列**：构造必然提前终局的存档（连续 `default_grace_q` 季付不出第 1 档）；
  终局后连续提交 10 条 `advance_quarter` 与各类政策命令。
- **被攻击的不变量**：INV-128（终局条件式中不含任何 GDP 项；`run_terminated == true` 后任何 `advance_quarter`
  返回 `REJECT` 且状态哈希不变）、INV-040。
- **期望行为**：全部 `⟹ REJECT(E_RUN_TERMINATED)`，状态哈希逐位不变。
  **结算档案可查看**（计划书 §04「政府失败后可查看结算」），但状态不可推进。
- **断言**

```gdscript
    drive_to_termination()
    assert_eq(f.scalar("state.meta.termination_reason"), TR_FISCAL_RESTRUCTURING_FAILED)
    var h := f.state_hash()
    for i in range(0, 10):
        f.expect_reject("advance_quarter", {}, "E_RUN_TERMINATED")
        f.expect_reject("policy_enact", {"policy_id": "policy.P01"}, "E_RUN_TERMINATED")
    assert_eq(f.state_hash(), h)
    assert_true(f.final_report_available())                     # 结算可看
    # 终局判定式不含 GDP
    assert_false(f.termination_rule_depends_on("derived.gdp.production_uu"))
```

- **失败诊断**：可以继续推进 ⇒ **缺 `run_terminated` 闸门**；
  终局判定引用了 GDP ⇒ 违反计划书 §04「经济下滑本身不是立即失败」，
  会让玩家学到错误的因果（以为经济下滑就会输，从而只优化 GDP）。

### `ADV-G05` 席位阈值边界微调

- **攻击叙述**：「席位是按支持率换算的。我把支持率精确调到阈值那一格，
  然后靠一次性小额支出来回跨越，看能不能刷出额外席位或者让换算函数出错。」
- **操作序列**：二分搜索出 `seat_rule` 的每个跳变点；构造支持率恰好落在跳变点 ±1 ppm 的夹具；
  在 q=15 与 q=31 各测一次；再测 `support == 0` 与 `support == 1000000` 两个极端。
- **被攻击的不变量**：INV-126（纯函数、整数、最大余数法、`0 ≤ seats_gov ≤ seats_total`）、
  INV-124（加权用最大余数法）、INV-003。
- **期望行为**：`seat_rule` 是**确定性纯函数**，同输入同输出；跳变点处不出现越界、不出现负席位、
  `Σ seats == seats_total`。±1 ppm 的差异**允许**改变席位——这是规则本身，不是缺陷；
  要测的是**函数在边界上不出错**，不是「结果必须连续」。
- **断言**

```gdscript
    for s in [0, 1, THRESHOLD-1, THRESHOLD, THRESHOLD+1, 999999, 1000000]:
        var seats := SeatRule.apply(s, SEATS_TOTAL)
        assert_ge(seats, 0); assert_le(seats, SEATS_TOTAL)
        assert_eq(SeatRule.apply(s, SEATS_TOTAL), seats)         # 纯函数：重复调用同值
        assert_eq(seats + SeatRule.apply_opposition(s, SEATS_TOTAL), SEATS_TOTAL)   # 最大余数法，和恒等
    assert_eq(f.election_result_at(15), SeatRule.apply(f.support_national_at(15), SEATS_TOTAL))
```

- **失败诊断**：席位和不等于总数 ⇒ **最大余数法未用于席位分配**（INV-003 的应用点被漏掉）；
  同输入不同输出 ⇒ 席位函数读取了外部状态或随机数，重放会分歧（INV-014 崩溃）。

---

## 9 H 族：存档攻击

### `ADV-H01` 存档重载重抽已确定事件 〔≡ 计划书点名 ⑥，别名 ADV-06〕

- **攻击叙述**：「这季抽到了出口需求暴跌。我读档重来，说不定就抽到别的了。」
- **操作序列**
  1. `boot(root_seed=7)`；`advance(10)`；`save("A")`。
  2. 分支一：`advance(1)`，记录 `state_hash`、`shock_log`、`log.rng`、`draw_count[6]`。
  3. 分支二：`load("A")`；`advance(1)`；记录同样内容。
  4. 分支三：`load("A")`；先提交 5 条**会被拒绝**的命令，再 `advance(1)`。
  5. 分支四：`load("A")`；先提交 3 条**会被接受但不影响经济**的命令（如 `set_payment_priority` 换一个同价排列），再 `advance(1)`。
  6. 分支五：用 `replay_mode = commands_only` 从 q=0 重跑到 q=11。
- **被攻击的不变量**：INV-109（每次冲击抽样写 `shock_log`；S01 **先查 `shock_log` 再抽样**，已有记录则复用且不推进计数器）、
  INV-133（`save → load → advance` 与 `advance` 的 `state_hash` 逐位相同，`log.rng` 完全一致）、
  INV-010（`draw = f(root_seed, stream, q, index)`）、INV-131（存档含 6 个计数器与完整命令流）、
  INV-009（随机流隔离）、INV-014。
- **期望行为**：分支一到四的 q=11 `state_hash` **逐位相同**；分支五逐季 `state_hash` 与 `checkpoints.jsonl` 一致。
  被拒命令不推进任何随机流。合法但经济中性的命令只推进它该推进的流。
- **断言**

```gdscript
    var h1 := branch_direct();  var h2 := branch_reload()
    var h3 := branch_reload_with_rejects(); var h4 := branch_reload_with_neutral_cmds()
    assert_eq(h1, h2); assert_eq(h1, h3); assert_eq(h1, h4)
    assert_eq(f1.rng_log("rng.shock", 10), f2.rng_log("rng.shock", 10))
    assert_eq(f1.scalar_array("state.rng.draw_count"), f2.scalar_array("state.rng.draw_count"))
    assert_eq(f1.shock_log_at(10), f2.shock_log_at(10))
    # commands_only 权威重放
    assert_true(ReplayVerify.run("A", "commands_only").ok)
    # 随机流隔离：多触发一个事件不改变冲击
    assert_eq(f_more_events.rng_log("rng.shock", 10), f1.rng_log("rng.shock", 10))   # INV-009
```

- **失败诊断**
  - 哈希不同 ⇒ 抽样用了**状态式 RNG**（`RandomNumberGenerator` 的内部 state 未完整入档），
    或 S01 没有「先查 `shock_log` 再抽样」。
  - 被拒命令改变了结果 ⇒ 拒绝路径推进了计数器（违反 INV-137 的「状态哈希完全不变」）。
  - 多触发事件改变了冲击 ⇒ **随机流不隔离**，计划书 §12「多写一句新闻也改变经济抽样」的风险变成现实。

### `ADV-H02` 直接篡改存档字段

- **攻击叙述**：「`state.json` 是明文 JSON。我把 `state.gov.cash_uu` 改成 999999999999。」
- **操作序列**：`save("B")`；`tamper("B", "/scalars/state.gov.cash_uu", 999999999999)`；`load("B")`。
- **被攻击的不变量**：INV-132（读档复算 `state_hash` 并比对，不符即 `E_SAVE_CORRUPT` 拒绝载入，**不做尽力修复**）。
- **期望行为**：`load` 返回 `E_SAVE_CORRUPT`，**拒绝载入**，给出可读提示（「存档已损坏或被外部修改」）。
  **不尝试修复、不部分载入、不降级继续。** 注意这不是反作弊承诺（§0.1），
  而是「系统不会把一份自相矛盾的账当成真账继续算 30 季」。
- **断言**

```gdscript
    f.save("B")
    f.tamper("B", "/scalars/state.gov.cash_uu", 999999999999)
    assert_eq(f.load("B"), Err.E_SAVE_CORRUPT)
    assert_false(f.is_loaded())
    assert_true(f.last_error_has_localized_text())
```

- **失败诊断**：载入成功 ⇒ **`state_hash` 没有在载入时复算**，或哈希的规范化编码漏掉了这个字段
  （`11_data_contract.md` §6.4 的排除集合被写得过宽）。

### `ADV-H03` 篡改后重算哈希使之自洽

- **攻击叙述**：「哈希会被校验？那我改完字段再重算哈希写回 manifest，档就自洽了。」
- **操作序列**：`save("C")`；`tamper` 改 `state.gov.cash_uu`；`rehash("C")`；`load("C")`。
  变体：改 `state.pop.*.population_persons` 使人口总数 ≠ 24 000 000；改 `bond` 的 `outstanding` 使 `Σ ≠ debt`。
- **被攻击的不变量**：INV-132 的后半段（**载入后立即跑一遍全部 P0 不变量**）、
  INV-020、INV-018、INV-025、INV-035、INV-141..INV-152。
- **期望行为**：哈希校验通过，但**载入后的 P0 不变量全查**会抓住它：
  改现金 ⇒ INV-020（资产负债恒等式）或 INV-018（现金总量）失败；
  改人口 ⇒ INV-141 失败；改债券 ⇒ INV-025/INV-035 失败。**任一失败即拒绝载入。**
- **断言**

```gdscript
    f.save("C"); f.tamper("C", "/scalars/state.gov.cash_uu", 9_000_000_000); f.rehash("C")
    var code := f.load("C")
    assert_ne(code, 0)
    assert_true(code in [Err.E_BALANCE_INIT, Err.E_CASH_TOTAL, Err.E_ASSERT_TOLERANCE])
    assert_false(f.is_loaded())
    # 人口变体
    f.save("C2"); f.tamper("C2", "/arrays/state.pop.population_persons/0", 99_000_000); f.rehash("C2")
    assert_eq(f.load("C2"), Err.E_POP_TOTAL)
```

- **失败诊断**：载入成功 ⇒ **「载入后立即跑全部 P0 不变量」没有实现**，
  只做了哈希校验。后果是坏档会在第 30 季才炸，故障包指向错误的位置，
  违反 `11_data_contract.md` §6.6 的「坏档必须当场发现」。
  **这条测试是 `ADV-H02` 的真正价值所在**：哈希防的是意外损坏，不变量防的是逻辑不自洽。

### `ADV-H04` 跨版本存档

- **攻击叙述**：「我手改 `schema_version` 到一个很大的数，或者把老档拿到新版本里跑，
  说不定新旧规则混用能占到便宜。」
- **操作序列**
  1. `save("D")`；改 `manifest.schema_version` 为 `CURRENT + 1`；`load("D")`。
  2. 用 `tests/fixtures/saves/v1/` 的黄金存档在当前版本载入。
  3. 改 `content_hash` 一个字节；`load`。
  4. 改 `build_id`；`load`。
  5. 改 `param_set_version`；`load`。
- **被攻击的不变量**：INV-135（`schema_version` 高于上限 ⇒ 拒绝，不猜测）、
  INV-134（`content_hash` 或 `param_set_version` 不符 ⇒ 只读检视模式；`build_id` 不符 ⇒ 可继续但 `replay_unreliable`）、
  INV-136（迁移是有序纯函数链，不跳版，不发明数据）。
- **期望行为**：五种情形四种不同结果，**每种都必须明确**：
  高版本 ⇒ `E_SAVE_VERSION_TOO_NEW` 拒绝；低版本 ⇒ 逐版迁移后全部不变量成立；
  `content_hash` / `param_set_version` 不符 ⇒ **只读检视模式**（可看不可推进）；
  `build_id` 不符 ⇒ 可玩但禁用重放验证。**四种之外没有第五种（例如「静默继续」）。**
- **断言**

```gdscript
    assert_eq(f.load_with_version(CURRENT + 1), Err.E_SAVE_VERSION_TOO_NEW)
    assert_eq(f.load_golden("v1"), 0)
    f.assert_all_p0_invariants()
    assert_eq(f.scalar("state.meta.migrated_from_version"), 1)

    f.load_with_content_hash_mismatch()
    assert_true(f.is_readonly_inspection())
    f.expect_reject("advance_quarter", {}, "E_PHASE_BUSY")      # 只读模式不可推进

    f.load_with_build_id_mismatch()
    assert_false(f.is_readonly_inspection())
    assert_true(f.scalar("state.meta.replay_unreliable") == 1)
```

- **失败诊断**：任一情形落入「静默继续」 ⇒ **违反 INV-134 的三分支**；
  迁移后不变量失败 ⇒ 迁移函数发明了数据（违反 M-5「缺失字段禁止用 0 填充」）。

### `ADV-H05` Save-scumming 市场结果

- **攻击叙述**：「这季配给把我的电分少了。读档重来，配给顺序说不定会变。
  再不行我就在读档后改一下无关的命令，让抽样序列错位。」
- **操作序列**：在一个配给紧张的季前 `save`；读档 20 次，每次插入不同数量的**经济中性**命令后推进；
  比较 20 次的配给结果、市场成交、价格。
- **被攻击的不变量**：INV-010（计数器式抽样）、INV-060（`Σ alloc == min(可供, Σ 需求)`，`alloc_i ≤ requested_i`）、
  INV-061（`rationing_rule` 与实际路径一致）、INV-133、INV-008（遍历按稳定 ID 升序）。
- **期望行为**：配给规则是**确定性的**（公开优先级或比例配给，计划书 §13），
  不依赖随机数也不依赖遍历顺序。20 次结果**逐位相同**。
  若配给确实需要随机打破平局，则该抽样必须走 `rng.market` 且 `draw_index` 由 `(q, 稳定ID)` 决定，与命令数无关。
- **断言**

```gdscript
    var base := run_once(0)
    for k in range(1, 20):
        assert_eq(run_once(k), base, "插入 %d 条中性命令后配给结果变了" % k)
    assert_eq(f.rationing_rule(), f.rationing_rule_expected())  # INV-061
    for i in f.ration_claimants():
        assert_le(f.alloc(i), f.requested(i))
    assert_eq(f.sum_alloc(), mini(f.available(), f.sum_requested()))
```

- **失败诊断**：结果随命令数变化 ⇒ **抽样的 `draw_index` 依赖调用顺序而非 `(q, 稳定ID)`**，
  这是计数器式 RNG 最容易实现错的地方；后果是 save-scumming 真的有效，且重放会分歧。

### `ADV-H06` 删改命令流尾部

- **攻击叙述**：「被拒的命令也会入档。我把 `commands.jsonl` 里那几条删掉，历史就干净了——
  说不定重放还会走出不同的路径。」
- **操作序列**：`save("E")`；删除 `commands.jsonl` 最后 5 行；`load("E")`；
  变体：篡改某条命令的 `accepted` 字段；变体：插入一条伪造命令。
- **被攻击的不变量**：INV-131（存档含完整命令流，含被拒命令）、INV-137、
  `manifest.command_log_hash`、INV-132。
- **期望行为**：`command_log_hash` 不符 ⇒ `E_SAVE_CORRUPT`，拒绝载入。
  即使用 `commands_only` 重放，缺失的被拒命令也会导致 `command_count` 不符。
- **断言**

```gdscript
    f.save("E"); f.truncate_commands("E", 5)
    assert_eq(f.load("E"), Err.E_SAVE_CORRUPT)
    f.save("F"); f.tamper("F", "/commands/12/accepted", 1)
    assert_eq(f.load("F"), Err.E_SAVE_CORRUPT)
    f.save("G"); f.append_fake_command("G")
    assert_eq(f.load("G"), Err.E_SAVE_CORRUPT)
```

- **失败诊断**：载入成功 ⇒ **`command_log_hash` 没有被校验**，或命令流不在哈希范围内；
  后果是「重放是权威的」这一承诺失效——而重放是计划书 §03「不可削减的底座」之一。

---

## 10 I 族：外部账户攻击

### `ADV-I01` 无限进口

- **攻击叙述**：「首版固定汇率、外部账户简化。那我就一直进口设备，反正外汇不是问题。」
- **操作序列**：把全部四个部门的进口需求推到上限，连续 20 季；
  逐季记录 `imports_uqs[]`、`world.delivery_capacity_uqs[]`、`world.credit_limit_uu`、`credit_used_uu`、`current_account`。
- **被攻击的不变量**：INV-104（`imports_uqs[s] ≤ world.delivery_capacity_uqs[s]`，且进口支出受买方现金与外部信用额度双重约束）、
  INV-026（不存在无对手方的对外收支）、INV-106（经常账户恒等式）、INV-110（`Δ net_foreign_position` 残差恒 0）。
- **期望行为**：进口受**三重**约束：交付能力（实物）、买方现金（钱）、外部信用额度（融资）。
  任一不足即 `ARREARS`（未满足的进口需求写 `unmet_demand`），**不是静默满足**。
  计划书 §07：「不能仅靠『外汇充足』标签无限采购。」
- **断言**

```gdscript
    for qq in range(0, 20):
        f.advance(1)
        for s in f.all_sectors():
            assert_le(f.imports_uqs(s), f.scalar_array("state.world.delivery_capacity_uqs", s))   # INV-104
        assert_le(f.scalar("state.world.credit_used_uu"), f.scalar("state.world.credit_limit_uu"))
        assert_eq(f.scalar("derived.world.current_account_uu"),
                  f.scalar_prev("derived.world.current_account_uu")
                  + f.exports_uu(qq) - f.imports_uu(qq)
                  - f.foreign_interest_uu(qq) + f.net_foreign_borrowing_uu(qq))     # INV-106，容差 0
        assert_eq(f.delta_net_foreign_position(qq),
                  -(f.current_account_flow(qq) + f.financial_account_flow(qq)))     # INV-110，残差 0
    assert_gt(f.scalar("state.flow.unmet_import_demand_uqs_cum"), 0)                # 约束确实咬住了
```

- **失败诊断**：进口超过交付能力 ⇒ **缺 INV-104**；外部世界变成无限供给方，
  玩家会发现「所有瓶颈都能用进口解决」，整个供给约束系统失效（计划书 §06 的五项约束形同虚设）。

### `ADV-I02` 分批绕过外债额度

- **攻击叙述**：「外部信用额度是总额上限？那我分成 100 笔小额，每笔单独检查时都没超。」
- **操作序列**：单季循环 `issue_bond{holder:"row", amount_uu: 额度/1000}` 直到被拒；
  变体：跨季持续小额发行，检查 `credit_used_uu` 是否累计。
- **被攻击的不变量**：INV-034（外部 ≤ `credit_limit_uu − credit_used_uu`）、INV-107（`external_debt == Σ (holder==row) outstanding`）。
- **期望行为**：额度检查用的是**累计已用量**而非单笔额度 ⇒ 第 N 笔必然 `REJECT(E_CREDIT_LIMIT)`。
  `credit_used_uu` 随还本下降、随发行上升，与 `external_debt` 一致。
- **断言**

```gdscript
    var total := 0
    while f.submit_ok("issue_bond", {"amount_uu": UNIT, "tenor_q": 8, "holder": "row"}): total += UNIT
    assert_le(total, f.scalar("state.world.credit_limit_uu"))
    assert_eq(f.last_reject_code(), "E_CREDIT_LIMIT")
    f.advance(1)
    assert_eq(f.derived("derived.world.external_debt_uu"), f.sum_bond_outstanding_by_holder("row"))  # INV-107
    assert_eq(f.scalar("state.world.credit_used_uu"), f.derived("derived.world.external_debt_uu"))
```

- **失败诊断**：总额超限 ⇒ **额度检查只看单笔**（经典的「逐笔检查代替累计检查」错误）；
  `credit_used` 与 `external_debt` 不符 ⇒ 两个量各写各的，还本时忘了释放额度。

### `ADV-I03` 汇率套利

- **攻击叙述**：「固定汇率？总有个字段存着吧。我找找有没有命令能动它，或者有没有政策的副作用能改它。」
- **操作序列**：遍历全部 12 种命令 `kind` 的全部 `args` 组合模板，寻找能写 `fx_rate_ppm` 的路径；
  再用 `WriteGuard` 在每一步检查该字段是否被写。
- **被攻击的不变量**：INV-105（`fx_rate_ppm` 恒为 1 000 000，任何写入即 FAULT）、INV-013、INV-138。
- **期望行为**：没有任何命令路径能改它；静态检查保证代码中不存在对该字段的写入；
  运行期 `WriteGuard` 把它列入「只读常量」集合。计划书 §02 明确排除「玩家直接操纵汇率」。
- **断言**

```gdscript
    for kind in ALL_COMMAND_KINDS:
        for args in fuzz_args(kind, 200):                       # 结构化模糊，args 键取自并集
            f.submit(kind, args)
    f.advance(4)
    assert_eq(f.scalar("state.world.fx_rate_ppm"), 1000000)     # 逐季，容差 0
    assert_eq(f.write_guard_violations("state.world.fx_rate_ppm"), 0)
    assert_false(f.code_writes_field("state.world.fx_rate_ppm"))   # 静态检查结果的运行期复核
```

- **失败诊断**：字段被改 ⇒ 存在绕过 `post()` 的直接赋值（INV-022 的静态检查有漏网）；
  即使数值没变，只要 `WriteGuard` 记到一次写入，就说明存在一条未来会被误用的路径，**同样判失败**。

### `ADV-I04` 自造出口订单

- **攻击叙述**：「P08 港口与物流升级能提高通行能力。那我升级完，出口就会自动变多——
  产能就是需求，我造多少就能卖多少。」
- **操作序列**：q=0 立项 P08；完工后 `advance(20)`；
  对照组：同时把 `world.export_demand_ppm` 用冲击压到下限，比较出口量。
- **被攻击的不变量**：INV-108（冲击只写 `world.*` 白名单字段）、INV-059（市场对账：`Σ 成交 + Σ 未满足 == Σ 需求`）、
  INV-064（未成交需求写 `unmet_demand`，不允许当作已消费）、计划书 §09 P08「不能自造订单」。
- **期望行为**：出口量 = `min(可供出口量, 外部需求)`。港口升级只放松**供给侧**约束，
  外部需求由 `world.export_demand_ppm` 决定，**与港口容量无关**。
  需求被压低时，升级后的港口容量闲置，`binding_code` 显示为需求侧约束。
- **断言**

```gdscript
    assert_eq(f.exports_uqs(), mini(f.exportable_supply_uqs(), f.external_demand_uqs()))
    assert_eq(f_lowdemand.exports_uqs(), f_lowdemand.external_demand_uqs())
    assert_lt(f_lowdemand.exports_uqs(), f.exports_uqs())       # 升级了但卖不出去
    assert_gt(f_lowdemand.scalar("state.world.port_idle_capacity_uqs"), 0)
    assert_false(f.export_demand_depends_on("state.region.haijia.port_capacity_uqs"))
    # 无销路时不得有 GDP 或支持度奖励（与 P04 同一条验收精神）
    assert_eq(f_lowdemand.gdp_delta_from_commissioning(), 0)
    assert_eq(f_lowdemand.support_delta_from_commissioning(), 0)
```

- **失败诊断**：出口随港口容量上升 ⇒ **供给创造了需求**，这是本目录里最隐蔽的一类重复计数：
  它不违反任何账本恒等式，但让「先建设」路线无条件占优，直接摧毁计划书 §17「策略差异」验收项
  与 §18「某策略在所有开局都压倒性胜出」的风险信号。

### `ADV-I05` 经常账户不闭合

- **攻击叙述**：「进出口、利息、借款分四个地方记。只要有一个地方漏记，
  对外净头寸就对不上，我就能在外部账户上凭空多点钱。」
- **操作序列**：制造四类对外流量同时发生的极端季（大额进口 + 大额出口 + 外债付息 + 新增外债 + 外债还本）；
  连续 20 季；逐季检查两条恒等式。
- **被攻击的不变量**：INV-106、INV-107、INV-110、INV-026。
- **期望行为**：两条恒等式残差**恒为 0**（不是「接近 0」）。
  `agent.row` 是完整账户主体并持有现金，所以 INV-020 的逐主体资产负债恒等式对它同样成立。
- **断言**

```gdscript
    for qq in range(0, 20):
        f.advance(1)
        assert_eq(f.delta_net_foreign_position(qq),
                  -(f.current_account_flow(qq) + f.financial_account_flow(qq)))    # 残差 0
        assert_eq(f.scalar("agent.row.cash_uu") + f.scalar("agent.row.bondhold_uu")
                  + f.row_inventory_value_uu() - f.scalar("agent.row.pay_uu"),
                  f.scalar("agent.row.nw_uu"))                                      # INV-020 对 row 也成立
```

- **失败诊断**：残差非 0 ⇒ 某类对外流量走了单边过账；
  由于 `agent.row` 是真实主体，这类错误会同时触发 INV-018（现金总量守恒），
  **两个不变量同时红是定位单边过账的最快信号**。

---

## 11 J 族：数值边界攻击

### `ADV-J01` int64 溢出

- **攻击叙述**：「金额是 int64。那我想办法把它推到 2^63 附近，让乘法溢出，余额变成负的巨大数——
  或者变成正的巨大数，我就发财了。」
- **操作序列**
  1. 参数夹具把 `AMOUNT_MAX` 附近的值喂给每一处乘法：`amount × ppm`、`qty × price`、`outstanding × coupon`、
     `pop × participation`、`(q << 32) ^ index`。
  2. 对每处调用 `IntMath.mul(a, b)` 的黄金向量测试：`a = AMOUNT_MAX`、`b = 1_000_001`。
  3. 运行期：连续 120 季 + 极端参数组合，检查是否有任何字段越界。
- **被攻击的不变量**：INV-006（一切乘法过 `IntMath.mul` 的显式溢出前置检查，**release 也执行**）、
  INV-007（`|金额| ≤ AMOUNT_MAX`，`|数量| ≤ QTY_MAX`，`price ∈ [PRICE_MIN, PRICE_MAX]`）、INV-002。
- **期望行为**：溢出前置检查命中 ⇒ `FAULT.OVERFLOW` 并导出故障包（这是程序缺陷，不是玩家可达状态）；
  而**玩家可达的路径上**，参数的 `valid_range` 必须保证永远到不了溢出边界 ⇒ 命令层 `REJECT(E_PARAM_RANGE)`。
  换言之：**玩家永远看不到 FAULT，测试用内部 API 才能构造出它**。
- **断言**

```gdscript
    # 单元层：溢出必被抓
    assert_fault(func(): IntMath.mul(AMOUNT_MAX, 1000001), Fault.OVERFLOW)
    assert_fault(func(): IntMath.mul(-AMOUNT_MAX, 1000001), Fault.OVERFLOW)
    # RNG 种子拼接不得位重叠
    assert_eq(RNG.draw_raw(0, 1 << 31, 0), RNG.draw_raw_reference(0, 1 << 31, 0))
    # 场景层：玩家可达路径上永不越界
    f.boot(); fuzz_all_commands(2000); f.advance(120)
    for path in f.all_amount_fields():
        assert_le(absi(f.scalar(path)), AMOUNT_MAX)
    assert_eq(f.fault_count(), 0)
```

- **失败诊断**：溢出未被抓 ⇒ **INV-006 的检查被写在 debug-only 分支**（`assert()` 在 release 被剥离是 GDScript 的常见陷阱）；
  玩家路径上出现 FAULT ⇒ 某个参数的 `valid_range` 没有覆盖到极端组合，
  **修法是收紧 `valid_range` 并在参数卡上登记，而不是放宽不变量**。

### `ADV-J02` 极端税率

- **攻击叙述**：「税率填 0、填 100%、填 150%、填 −10%。总有一个能让系统出错。」
- **操作序列**：对 P01、P02 的税率参数依次提交 `{-100000, 0, 1, 999999, 1000000, 1000001, 2000000}`。
- **被攻击的不变量**：INV-031、INV-086（可支配收入恒等式）、INV-063、`ParameterCard.valid_range`。
- **期望行为**：`valid_range` 之外 ⇒ `REJECT(E_PARAM_RANGE)`。
  `0` 合法：税收为 0，不得出现除零或负税。
  `1000000`（100%）若在 `valid_range` 内则必须能跑：可支配收入为 0，**居民消费为 0 而不是负数**，
  生活指数下降，支持度崩溃——这是一条合法但自毁的策略，游戏必须能正确演出它。
- **断言**

```gdscript
    for r in [-100000, 1000001, 2000000]:
        f.expect_reject("policy_set_params", {"policy_id":"policy.P01","params":{"rate_ppm": r}}, "E_PARAM_RANGE")
    f_zero.set_rate(0); f_zero.advance(4)
    assert_eq(f_zero.led_sum(10, 0, 3), 0)
    f_max.set_rate(1000000); f_max.advance(4)
    for g in f_max.all_groups():
        assert_ge(f_max.disposable(g), 0)                       # 不得为负
        assert_ge(f_max.consumption(g), 0)
        assert_eq(f_max.disposable(g),
                  f_max.wage(g) + f_max.property_income(g) + f_max.transfer(g)
                  + f_max.support_in(g) - f_max.support_out(g) - f_max.income_tax(g))   # INV-086
    assert_lt(f_max.support_national_at(4), f_zero.support_national_at(4))
```

- **失败诊断**：出现负可支配收入 ⇒ **税额没有被 `min(应纳税额, 税基)` 夹住**；
  100% 税率下仍有消费 ⇒ 消费函数用的不是实际可支配收入（违反 INV-063）。

### `ADV-J03` 零人口地区

- **攻击叙述**：「我把西岭的人全迁走。人口为 0 的地区，失业率的分母就是 0，除零崩溃。」
- **操作序列**：构造极端迁移诱因把 `region.xiling` 抽干（或直接用 `fixtures/scenario/empty_region/`）；
  跑 40 季；同时检查该区的 cell 生产、公共服务交付、住房、政治权重。
- **被攻击的不变量**：INV-044（系数为 0 的约束不产生候选值；**禁止除零，也禁止用 `max(c,1)` 代替**）、
  INV-075（失业率公式）、INV-124（人口加权）、INV-103（服务交付）。
- **期望行为**：分母为 0 时**不做除法**，派生量取「未定义」的显式表示（首版约定：`unemployment_ppm` 在
  `labor_force == 0` 时记为 0 并同时置 `undefined` 标志位，UI 显示「—」而非「0%」）。
  生产为 0、服务队列为 0、政治权重为 0，**全部是显式的 0，不是除零的副产物**。
- **断言**

```gdscript
    drain_region("region.xiling"); f.advance(40)
    assert_eq(f.population_of("region.xiling"), 0)
    assert_eq(f.fault_count(), 0)                               # 没有崩溃
    assert_eq(f.scalar("derived.labor.unemployment_ppm.region.xiling"), 0)
    assert_eq(f.flag("derived.labor.unemployment_undefined.region.xiling"), 1)
    for s in f.all_sectors():
        assert_eq(f.output_actual("cell.xiling.%s" % s), 0)
        assert_eq(f.binding_code("cell.xiling.%s" % s), "labor")
    assert_eq(f.support_weight_of("region.xiling"), 0)
    assert_eq(f.sum_support_weights(), 1000000)                 # 其余三区权重重新归一，和仍为 1
```

- **失败诊断**：崩溃或 NaN ⇒ 存在裸 `/`（违反 INV-002 的静态检查）；
  出现 `max(denominator, 1)` 的写法 ⇒ **INV-044 明令禁止**，因为它会把「未定义」伪装成「0%失业」，
  玩家会看到一个人口为 0 的地区「失业率 0%，形势大好」——比崩溃更糟。

### `ADV-J04` 空群组

- **攻击叙述**：「36 个群组允许有空的。空组的平均收入是多少？除以 0 个人试试。」
- **操作序列**：用 `fixtures/scenario/empty_groups/`（6 个空组，覆盖各年龄档与技能档）；
  跑 40 季；触发全部会对群组做「人均」运算的路径：人均可支配收入、生活指数、支持度加权、赡养转移。
- **被攻击的不变量**：INV-142（36 组齐全，允许空组）、INV-124（加权用最大余数法）、INV-085（赡养转移双边）、
  INV-086、INV-044。
- **期望行为**：空组的人均量取 0 并标记未定义；**空组不参与加权**（权重为 0），
  加权和仍精确等于 1 000 000（最大余数法在权重为 0 的项上不分配余数）；
  空组不产生赡养转移的收方或付方。
- **断言**

```gdscript
    f.boot_with("fixtures/scenario/empty_groups/"); f.advance(40)
    assert_eq(f.fault_count(), 0)
    for g in f.empty_groups():
        assert_eq(f.pop(g), 0)
        assert_eq(f.per_capita_disposable(g), 0)
        assert_eq(f.support_weight(g), 0)
        assert_eq(f.support_in(g), 0); assert_eq(f.support_out(g), 0)
    assert_eq(f.sum_support_weights(), 1000000)                 # 容差 0
    assert_eq(f.sum_support_in(), f.sum_support_out())          # INV-085
```

- **失败诊断**：加权和 ≠ 1 000 000 ⇒ 最大余数法把余数分给了空组（权重为 0 的项**必须先被排除再分余数**）；
  这是一个只在空组存在时才暴露的 off-by-one，**必须有专门的夹具**，否则永远测不到。

### `ADV-J05` 全经济归零

- **攻击叙述**：「我让所有部门产出都变成 0。GDP 是 0，价格指数分母是 0，
  实际 GDP 算不出来，整个报告系统应该会崩。」
- **操作序列**：极端夹具——全部 cell 的劳动、投入、能源同时断供（通过合法的连锁：能源部门停产 → 全部停产）；
  连续 8 季全零；然后恢复，检查系统能否正常走出来。
- **被攻击的不变量**：INV-112、INV-115、INV-117（实际 GDP 用基年价重新核算，**禁止用名义 GDP 除以任何价格指数**）、
  INV-066/067/068（价格有界、平滑、不动点）、INV-044。
- **期望行为**：GDP 为 0，三口径残差仍为 0（0 == 0 + 0）；
  实际 GDP 也是 0（因为它是按基年价重算的**数量**，不涉及除法）；
  价格在缺口恒定时严格不变（INV-068 的不动点性质）或按有界规则移动并被 `price_floor/ceil` 夹住；
  恢复后系统正常演进，**不留任何后遗症**（无累积的取整偏置）。
- **断言**

```gdscript
    force_total_shutdown(); f.advance(8)
    assert_eq(f.fault_count(), 0)
    for qq in range(0, 8):
        assert_eq(f.gdp_at(qq), 0)
        assert_eq(f.derived("derived.gdp.expenditure_uu"),
                  f.derived("derived.gdp.production_uu") + f.derived("derived.gdp.price_variance_total_uu"))
        for s in f.all_sectors():
            assert_ge(f.price(s), IntMath.mul_ppm(f.base_price(s), f.scalar("param.price_floor_ppm")))
            assert_le(f.price(s), IntMath.mul_ppm(f.base_price(s), f.scalar("param.price_ceil_ppm")))
    assert_false(f.real_gdp_depends_on("derived.index.consumer_ppm"))              # INV-117
    restore(); f.advance(8)
    assert_gt(f.gdp_at(15), 0)                                  # 能走出来
    assert_le(f.clamp_count(), f.scalar("param.price_clamp_budget_count"))
```

- **失败诊断**：崩溃或 NaN ⇒ 某处用了 `名义GDP / 价格指数`（违反 INV-117，也是计划书 §06 点名的错误）；
  恢复后价格漂移 ⇒ 价格公式存在取整偏置累积（INV-068 的不动点测试没覆盖到零产出这个特例）。

### `ADV-J06` 价格反复触顶

- **攻击叙述**：「我制造持续的极端短缺，让价格一直往上撞天花板。撞多了说不定就穿过去了，
  或者 clamp 的日志会把内存撑爆。」
- **操作序列**：用 `shock.S02`（进口能源/设备价格变化）叠加国内减产，让 `sector.energy` 连续 40 季极端短缺；
  统计 `clamp` 次数与价格轨迹。
- **被攻击的不变量**：INV-066（价格有界）、INV-067（单季变动幅度有界）、
  INV-069（每次 clamp 写 `log.clamp` 并计数；压力测试中超预算即判失败）。
- **期望行为**：价格永不越界；单季变动永不超过 `price_step_max_ppm`；
  clamp 次数超过 `param.price_clamp_budget_count` ⇒ **测试失败并要求调参数或改规则**，
  因为频繁触顶说明价格规则与冲击强度不匹配（计划书 §18「宏观指标无原因地振荡或爆炸 ⇒ 减小调整速度，
  核查时序与单位；禁止事后加平衡项」）。
- **断言**

```gdscript
    apply_shock("shock.S02", 40); f.advance(40)
    for qq in range(0, 40):
        for s in f.all_sectors():
            assert_in_range(f.price_at(qq, s), f.price_floor(s), f.price_ceil(s))
            if qq > 0:
                assert_le(absi(f.price_at(qq, s) - f.price_at(qq-1, s)),
                          IntMath.mul_ppm(f.price_at(qq-1, s), f.scalar("param.price_step_max_ppm")))
    assert_le(f.clamp_count(), f.scalar("param.price_clamp_budget_count"))
    assert_eq(f.log_clamp_rows().size(), f.clamp_count())       # 每次 clamp 都有日志
```

- **失败诊断**：越界 ⇒ clamp 在错误的位置（应在 S07 写 `pending` 之前）；
  clamp 超预算 ⇒ **不要调大 clamp 预算来「修」它**，那是事后平衡项；正确做法是减小价格调整速度或重新校准冲击强度。

### `ADV-J07` 长程压力：100 种子 × 120 季

- **攻击叙述**：不是某个具体玩法，而是「把所有攻击面同时打开，跑久一点，总会有东西塌」。
- **操作序列**
  1. 100 个 `root_seed`，每个跑 120 季（超出首版 40 季的三倍）。
  2. 每个种子附带一条**对抗性命令流**：由 `tests/stress/adv_command_fuzzer.gd` 生成，
     命令 `kind` 与 `args` 从合法域中按种子抽取，**包含大量注定被拒的命令**。
  3. 逐季全量 P0 不变量；逐季 `state_hash` 写入 `checkpoints.jsonl`。
  4. 每个种子在第 60 季存档、读档、继续，验证 `ADV-H01` 的性质在长程下仍成立。
- **被攻击的不变量**：全部 152 条。这是**不变量注册表的覆盖性总检**。
- **期望行为**：无崩溃、无 NaN、无未处理越界、无 FAULT；终局可正常记录；
  季度结算中位数 < 0.5 s、P95 < 1 s（REF-01 参考机）；
  存档往返后逐位一致。
- **断言**

```gdscript
    for seed in range(0, 100):
        var f := AdvFixture.new(); f.boot(root_seed = seed)
        var fuzz := AdvCommandFuzzer.new(seed)
        for qq in range(0, 120):
            fuzz.emit_for_quarter(f, qq)                       # 含大量必被拒的命令
            f.advance(1)
            f.assert_all_p0_invariants()
            if qq == 60:
                f.save("stress_%d" % seed)
                var h := f.state_hash(); f.load("stress_%d" % seed)
                assert_eq(f.state_hash(), h)
        assert_eq(f.fault_count(), 0)
        assert_true(f.final_record_written())
    assert_lt(Bench.median_quarter_usec(), 500000)
    assert_lt(Bench.p95_quarter_usec(), 1000000)
    assert_eq(InvariantCoverage.uncovered(), [])                # 152 条全部被引用过
```

- **失败诊断**：任一不变量在某个种子的某季失败 ⇒ 用 `checkpoints.jsonl` 的 8 个 `step_hash` 二分定位到步骤，
  再定位到 `post()`。**修法是修规则、步长、参数或初值，并为这个种子新增一条回归测试**
  （计划书 §13「禁止后处理补丁」）。
  性能不达标 ⇒ 先剖析再优化（计划书 §17），不得靠削减不变量检查来提速——
  发布构建的抽样策略已经写在 `12_simulation_contract.md` §10，不允许再降。

---

## 12 覆盖矩阵与门槛

### 12.1 攻击面 → 测试

| 任务书点名的攻击面 | 本目录测试 | 条数 |
|---|---|---|
| 套利与重复计数（补助/退税/转移支付） | `ADV-A01..A06` | 6 |
| 时序攻击（结算边界反复提交/撤回） | `ADV-B01..B05` | 5 |
| 融资永动机（借新还旧、买自己的债、未来收入当现金） | `ADV-C01..C07` | 7 |
| 物资守恒（拆分/合并造货、负库存、未完工资产供能） | `ADV-D01..D07` | 7 |
| 人口守恒（迁移造人、技能刷新、出生死亡双记） | `ADV-E01..E06` | 6 |
| 项目与合同（取消退款、占队列、付款制造进度） | `ADV-F01..F06` | 6 |
| 政治（一次性补贴刷支持率、选举季套利） | `ADV-G01..G05` | 5 |
| 存档（重载重抽、跨版本、篡改字段） | `ADV-H01..H06` | 6 |
| 外部账户（无限进口、额度绕过、汇率套利） | `ADV-I01..I05` | 5 |
| 数值边界（溢出、极端税率、零人口、空组、全零产出） | `ADV-J01..J07` | 7 |
| **合计** | | **60** |

### 12.2 不变量 → 测试（反查，机器生成）

`tests/tools/invariant_coverage.gd` 在 CI 中生成下表并与本节比对；不一致即 CI 失败。
下表是**当前应有的对应关系**，用于人工复核生成器是否正确：

| 不变量段 | 主要覆盖测试 |
|---|---|
| INV-001..014（基础设施） | `J01`, `J03`, `J05`, `H01`, `H05`, `J07`, `D05` |
| INV-015..026（账本守恒） | `A05`, `A06`, `C06`, `F01`, `F06`, `I05`, `H03` |
| INV-027..042（财政与债务） | `A04`, `C01`, `C02`, `C03`, `C04`, `C05`, `C06`, `C07`, `G02` |
| INV-043..058（生产与物资） | `D01`, `D02`, `D03`, `D04`, `D05`, `D06`, `D07`, `E05`, `F05` |
| INV-059..070（市场与价格） | `D01`, `H05`, `I04`, `J05`, `J06` |
| INV-071..086（人口与就业） | `E01`, `E02`, `E03`, `E04`, `E05`, `E06`, `J03`, `J04`, `J02` |
| INV-087..100（项目与政策） | `A01`, `A02`, `B03`, `B04`, `B05`, `D03`, `E03`, `F01..F06` |
| INV-101..110（公共服务与外部） | `I01`, `I02`, `I03`, `I04`, `I05`, `A06` |
| INV-111..120（GDP 核算） | `A03`, `A05`, `C06`, `J05` |
| INV-121..130（社会与政治） | `G01`, `G02`, `G03`, `G04`, `G05` |
| INV-131..140（存档与命令） | `B01`, `B02`, `B05`, `H01..H06`, `I03` |
| INV-141..152（剧本硬约束） | `H03`, `D07`, `E06`, `J04`, `A06` |

### 12.3 门槛（对应计划书 §15 G0–G5 与 §17）

| 门槛 | 必须全绿 | 理由 |
|---|---|---|
| G1 之前 | `D02`, `D05`, `E02`, `E04`, `J01`, `H01` | 计划书 §15 G1：「无无来源资金或物资」「连续 40 季可重放」 |
| G2 之前 | `A01`, `A04`, `D03`, `E03`, `F03`, `B05` | 核心闭环的四项政策 P01/P03/P04/P05 各自的对抗面 |
| G3 之前 | **六条点名测试全绿**（`A01`, `C01`, `E03`, `E01`, `A04`, `H01`）+ `I01`, `I05`, `G01` | 计划书 §17 明文要求；政治反馈与外部账户此时成立 |
| G5 之前 | **全部 60 条全绿** | 计划书 §17：「任何 P0 未清零，不发布试玩包」 |
| 每次合并 | 全部 60 条 + 负控制（§0.4） | 对抗测试是回归套件，不是一次性验收 |

**运行预算**：A–G 族属 `tests/scenario/`（全套 < 5 min 的一部分）；
`H04`, `J07` 属 `tests/stress/`，夜间跑。`J07` 单独约 100 种子 × 120 季，预计 20–40 min。

---

## 13 本目录暴露的规则缺口（提交给 `13_open_questions.md` 的维护者）

以下六条是写这份目录时发现的**规则不完整**之处。它们不是测试的缺陷，是契约的缺口；
在裁定之前，对应测试按本文件给出的**保守期望**实现，并在测试文件头标注 `# pending: Q-ADV-0n`。

| 编号 | 缺口 | 影响的测试 | 本目录采用的保守期望 |
|---|---|---|---|
| `Q-ADV-01` | `project_defer` 的延期次数与总长度上限未定义（`11_data_contract.md` §6.1 只写「合同允许延期」） | `ADV-F04`, `ADV-G02` | 上限来自 `param.max_defer_count`（暂定 2 次）与 `param.max_defer_quarters`（暂定 8 季）；延期期间**不释放槽位**；超限 `REJECT`。**已结案**：docs/18 R-DEFER-01（另加每季 1.5% 剩余合同额的延期赔偿，当季付清） |
| `Q-ADV-02` | 同季同对手方同品种成交是否合并计价，未在结算合同中明确（决定 `ADV-D01` 的取整套利是否存在） | `ADV-D01`, `ADV-A02` | 采用**先合并数量再计价一次**；若实现上不可行，则引入 `param.min_trade_uqs` 并把残差压到 ≤ 1 μU |
| `Q-ADV-03` | 失业率等派生量在分母为 0 时的表示方式未定义（`0` 与「未定义」在 UI 上必须可区分） | `ADV-J03`, `ADV-J04` | 值记 0，同时置独立的 `*_undefined` 标志位；UI 显示「—」。**禁止 `max(分母,1)`**（INV-044） |
| `Q-ADV-04` | 补助的计基口径（逐事件乘费率后求和 vs 先求和再乘费率）未写进 `PolicyDefinition` | `ADV-A02` | 采用**先求和再乘费率**（按 `policy_id, beneficiary_id, q` 分组） |
| `Q-ADV-05` | `tenor_q` 的 `valid_range` 未登记参数卡 | `ADV-C07` | 暂定 `[4, 40]`；`tenor_q == 0` 会直接破坏 INV-037，必须在下界上明确排除 |
| `Q-ADV-06` | 「只读检视模式」下哪些命令可用未定义（`ADV-H04` 断言 `advance_quarter` 被拒，但查看类操作应可用） | `ADV-H04` | 只读模式下全部 12 种命令均 `REJECT`；只允许 Presentation 层的查询 |

---

## 14 维护约定

1. **新增一条政策、事件或冲击，必须同时新增至少一条对抗测试**，并在 §12.1 登记。
   `check_adv_meta.gd` 统计 `PolicyDefinition` 数量与 `family:` 覆盖，缺一即构建失败。
2. **修复任何一个 P0 缺陷，必须新增一条对抗测试复现它**（计划书 §13「增加回归测试」）。
   新测试沿用本目录的七段式结构，编号接在对应族尾部。
3. **任何一条测试被标记为 skip 超过一个里程碑，视同该防线不存在**，
   必须在 §13 登记为规则缺口或删除对应机制，不允许长期挂着。
4. 本目录的期望行为若与 `10`/`11`/`12` 号文件冲突，**以那三份为准**，并回改本文件；
   若与 `docs/ref/plan_v1.0.txt` 冲突，**以计划书为准**，并回改那三份（计划书是唯一权威需求来源）。
