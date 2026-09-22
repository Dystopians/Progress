# 21 / 季度报告与解释文案：规则模板规格

> 状态：**唯一权威文案规格**。本文件规定「报告里的每一句话由什么规则生成、填哪些槽位、怎样格式化、怎样被测试」。
> 依据：`docs/ref/plan_v1.0.txt` §02 §04 §06 §07 §08 §09 §10 §11 §12 §13 §14 §17。
> 上游：`docs/10` 变量字典、`docs/11` 数据协议、`docs/12` 结算合同、`docs/14` 参数登记（另有作者，本文只引用，不定义）。
> 同级：`docs/20` 界面与信息架构规格（结构、控件、视觉通道）。
> 引擎：Godot 4.7.2-stable，带类型 GDScript。语言：玩家可见文本全部简体中文；标识符英文 snake_case。

计划书 §12 的硬边界：**生成式 AI 不进入权威结算；首版报告使用规则模板。**
因此本文件的验收判据是：**在固定构建、固定种子、相同命令下，同一状态必然渲染出逐字相同的报告文本。**
任何需要「人写一句」「模型润色一下」才能成句的地方，都是本规格的缺陷。

---

## 0 本文件的地位与边界

### 0.1 规定什么

1. 文案资源文件的**结构、模板 ID 命名空间、占位符语法**（§1）。
2. **格式化器**：内部整数 → 显示字符串的逐位规则，含 μU → U 的舍入（§1.5—§1.7）。
3. **季度简报的风险排序算法**：候选来源、评分、归并、名额配额（§2）。
4. **本季诊断的生成规则**：指标 → 机制域 → 台账证据 → 可比备选动作（§3）。
5. **三类措辞**（已经发生 / 规则推断 / 情景预测）的模板库、时体词表、禁止混用清单（§4）。
6. **「为什么不能执行」**全部阻断类别的模板与必填数字（§5）。
7. **溯源行格式**与引用码文法（§6）。
8. **反事实对比**的标注规则（§7）。
9. **第 40 季发展档案**五维文案（§8）。
10. **lint 流水线与验收清单**（§9、§10）。

### 0.2 不规定什么

- 不定义变量、数据 schema、结算步骤、参数值、剧本数值（`docs/10`—`docs/14`）。
  本文出现的一切数字（`4.00 U`、`8.0 %`、阈值默认值）**是排版夹具或建议默认值**，最终值以参数登记为准。
- 不定义控件、布局、颜色、字号、首屏清单（`docs/20`）。
- 不定义任何模拟规则。凡本文写「按规则 X」，规则 X 的内容由 `docs/12` 决定。

### 0.3 与 `docs/20` 的分工（避免两处各写一套）

| 事项 | 归 `docs/20` | 归本文件（21） |
|---|---|---|
| 三类信息的**判定** | §3.1 §3.2 判定瀑布与映射表 | 引用，不重写 |
| 三类信息的**视觉通道**（徽章字、图标、标尺、数字形态） | §3.3 | 引用，不重写 |
| 三类信息的**措辞**（句式、时体词、禁止混用） | 仅给徽章字与词前缀 | **§4 全部** |
| 风险卡的**结构、排序键、取 3 条、终局措辞禁令** | §7.1.5 | 引用；**§2 给出每个分量的计算式、归并、配额、阈值** |
| 诊断卡的**四段结构** | §7.1.3 | 引用；**§3 给出每段的生成规则与模板** |
| 原因对象的**数据结构、五行版式、RC-01..16、码表** | §9 | 引用；**§5 给出全部 30 码的行 2 模板、必填数字、默认出口** |
| 数字的**显示格式表** | §4.5 | 引用；**§1.5 给出整数 → 字符串的可实现算法与舍入方向** |
| 档案页的**版面、分区、控件断言** | §10.2 | 引用；**§8 给出文案** |

**冲突处理**：本文与 `docs/20` 若出现不一致，以 `docs/20` 为准并登记进本文 §11 待决问题。
本文已知的三处**增补**（不是冲突，是 20 未规定的空白）标记为 `＋增补`，并各自登记待决问题。

### 0.4 「季度简报」与「季度报告」是两个东西

| 名称 | 计划书出处 | 界面落点 | 本文规格 |
|---|---|---|---|
| **季度简报** | §04 环节 01「一页季度简报；最多 3 项优先风险」 | 总览页 `page.overview` 的风险卡区（`docs/20` §7.1.2 诊断卡区）+ 本季已发生条 | §2、§3 |
| **季度报告** | §04 环节 06；§11「季度报告串起结果」 | 季度报告页 `page.report`，六小节（`docs/20` §7.5.1） | §4、§6、§7 |
| **发展档案** | §04「第 40 季形成发展档案」 | `overlay.final_archive` | §8 |

---

## 1 文案资源与渲染契约

### 1.1 资源文件清单

全部玩家可见中文落在下列文件。**`res://sim/`、`res://systems/`、`res://application/`、`res://ui/` 的 `.gd` 文件中不得出现中文字符串字面量**（注释除外，§9.2 L-04）。

| 文件 | 内容 | 消费方 |
|---|---|---|
| `content/text/classes_zh_cn.json` | 三类信息的徽章字、词前缀、类名（与 `docs/20` §3.3 一致） | 全部 |
| `content/text/brief_zh_cn.json` | 风险卡模板 `tpl.brief.*`（§2.8） | 总览页 |
| `content/text/diagnosis_zh_cn.json` | 诊断卡四段模板 `tpl.diag.*`（§3.5） | 总览页、地区页 |
| `content/text/statements_zh_cn.json` | 三类句式模板库 `tpl.actual.* / tpl.derived.* / tpl.projected.*`（§4.3—§4.5） | 报告页、各页说明行 |
| `content/text/reasons_zh_cn.json` | 原因文案 `tpl.reason.*`（§5）；`docs/20` RC-01 指定的资源 | 政策页、预算审查、确认框 |
| `content/text/trace_zh_cn.json` | 溯源行与引用码相关文案 `tpl.trace.*`（§6） | 全部 |
| `content/text/archive_zh_cn.json` | 发展档案文案 `tpl.archive.*`（§8） | 档案覆盖层 |
| `content/text/terms_zh_cn.json` | 名表：地区名、部门名、政策名、集团名、台账名、科目名、单位标签、受控词表（§1.4 `label` 类槽位的唯一来源） | 全部 |

> `docs/20` RC-01 写的是 `content/ui/reasons_zh_cn.tres`。本文取 `.json` 且置于 `content/text/`，理由：
> 文案要进 lint 流水线做正则扫描与差异审阅，`.tres` 二进制化后不可读、不可 diff。
> **这是路径与扩展名的分歧，不是内容分歧**，登记为 RT-OQ-01，需一次裁决后两文件同步。

### 1.2 模板 ID 命名空间

```
tpl_id      = "tpl." domain "." key [ "@" variant ]
domain      = "brief" | "diag" | "actual" | "derived" | "projected"
            | "reason" | "trace" | "archive" | "term"
key         = ^[a-z][a-z0-9_]*$
variant     = ^[a-z][a-z0-9_]*$
```

规则：

| # | 规则 |
|---|---|
| TP-01 | `tpl_id` 全局唯一。重复即加载期失败 `E_DUP_ID`（`docs/11` §4 规则 4）。 |
| TP-02 | 一个 `tpl_id` 对应**恰好一条**中文模板串。同一语义不得存在两条模板（`docs/20` RC-01「模板唯一」的推广）。 |
| TP-03 | 变体 `@variant` 只允许由**一条确定性判据**选择，判据写在模板文件的 `variant_rule` 字段，取值必须**互斥且穷举**；lint 检查两性质（§9.2 L-01）。 |
| TP-04 | 模板 ID 一经进入已发布存档的报告快照即**永不复用、永不改名**（`docs/11` §4 规则 1）。 |
| TP-05 | 模板串中**不得出现英文标识符**（槽位名、规则号、机制 ID、引用码除外，它们经槽位注入）。 |

### 1.3 占位符语法

```
文本      = ( 字面 | 槽位 | 条件段 | 列表段 | 转义 )*
槽位      = "{" slot_name "}"
slot_name = ^[a-z][a-z0-9_]*$                 # 命名占位；禁止位置占位 {0}
条件段    = "[[?" slot_name "]]" 文本 "[[/]]"  # 槽位存在且非空时渲染
列表段    = "[[*" slot_name [ ' sep="' 分隔符 '"' ] "]]" 文本 "[[/]]"
转义      = "{{" | "}}"                        # 渲染为 { }
列表内引用 = "{." field_name "}"                # 只在列表段内合法
```

| # | 规则 |
|---|---|
| PH-01 | **只允许命名占位**。出现 `{0}`、`%s`、`%d`、`String.format` 的位置参数即缺陷。 |
| PH-02 | **禁止在 GDScript 中拼接玩家可见句子**。`res://ui/` 与 `res://application/` 中出现 `"…" + var` 或 `str()` 直接进 `Label.text` 即缺陷（静态可查，L-05）。唯一合法路径是 `JwText.render(tpl_id, slots)`。 |
| PH-03 | 条件段与列表段**嵌套深度 ≤1**，不支持 `else`，不支持表达式。需要分支就做两条变体模板（TP-03）。 |
| PH-04 | 中文无复数与冠词，**禁止实现复数分支**。量词写死在模板里（「3 季」「2 条」「4 项」）。 |
| PH-05 | **必填槽位缺失 → 整条文案不得渲染**，调用方降级到上一级说明并 `push_error`；**禁止渲染半句**、禁止留空位、禁止用默认值悄悄填补。 |
| PH-06 | 未知槽位（模板引用了槽位字典里没有的名字）→ 加载期失败，不到运行期。 |
| PH-07 | 槽位的值**由数据层算好后传入**；渲染器内出现作用于槽位值的算术运算符即缺陷（`docs/20` RC-02 的推广，L-05）。 |
| PH-08 | 模板串正文中**不得出现数字字面量**，除白名单：固定季号（`第 40 季`）、固定档位名（`三档`）、规则里写死的条数（`≤3 项`）。白名单逐条登记在模板文件的 `literal_numbers_ok` 字段，未登记即 lint 失败（L-06）。 |

### 1.4 槽位类型字典

每个槽位在 `content/text/_slots.json` 中登记：`name / type / unit / source_field / required / formatter`。
加载期校验：模板中出现的每个槽位都在字典中；字典中每个槽位至少被一条模板使用（死槽位即缺陷）。

| type | 内部存储 | 单位 | 格式化器 | 示例输出 |
|---|---|---|---|---|
| `u` | `int` μU（`_uu`） | U | `fmt_u` | `1,204.35 U` |
| `u_signed` | `int` μU | U | `fmt_u_signed` | `+0.42 U` / `−1.10 U` |
| `qty` | `int` μQ_s（`_uqs`）+ `sector_idx` | 部门产出单位 | `fmt_qty` | `10.00 单位电力` |
| `persons` | `int` 人 | 人 / 万人 | `fmt_persons` | `9,000,000 人` / `900.0 万人` |
| `units` | `int` 件（`_units`） | 套 / 台（名表给） | `fmt_units` | `1,600,000 套` |
| `pct` | `int` ppm（`_ppm`） | % | `fmt_pct` | `8.0 %` |
| `pct_point` | `int` ppm 差 | 个百分点 | `fmt_ppt` | `1.2 个百分点` |
| `index` | `int` ppm | 指数 | `fmt_index` | `100.0` |
| `quarter` | `int` 内部季索引 q（0 基） | 季 | `fmt_quarter` | `第 8 季` |
| `quarters` | `int` 季数 | 季 | `fmt_quarters` | `3 季` |
| `range_u` / `range_pct` / `range_qty` | 两个同类整数 | 同基础类型 | `fmt_range` | `〔1.80–2.60〕U` |
| `id` | `StringName` | — | 等宽原样 | `project.P04_07_001` |
| `label` | `StringName` → 名表 | — | `terms_zh_cn.json` 查表 | `海岬` |
| `citation` | `String` | — | `fmt_citation` | `ldg.cash#Q07.014` |
| `rule_id` | `String` | — | 前缀 `^` | `^R-PROD-03` |
| `mech_id` | `String` | — | 方括号 | `[M-POWER-01]` |
| `scenario` | enum | — | 名表 | `基线` / `不利条件` |
| `enum_word` | 受控词表 | — | 白名单查表 | `改善` / `恶化` / `持平` |
| `text` | 已渲染子串 | — | 原样 | （只允许来自另一条模板） |

**硬规则**：

- `text` 类槽位的值**只能是另一条模板的渲染结果**，不得是自由字符串（L-05 断言调用栈）。
- `label` 类槽位**禁止直接来自剧本的英文 ID**；必须经 `terms_zh_cn.json` 查表，查不到即 `push_error`（防止界面漏出 `region.haijia`）。
- `enum_word` 的取值白名单：方向 `{改善, 恶化, 持平}`；口径 `{存量, 流量, 指数, 比率}`；期间 `{本季, 年化, 四季合计, 累计至今, 期末, 期初}`。白名单外取值 → 加载期失败。

### 1.5 格式化器（整数 → 字符串，逐位可实现）

**全部格式化器只做整数运算，不得出现 `float`。**（`docs/11` 的整数编码前提；浮点会让「同构建同种子逐字相同」这一验收失效。）

```gdscript
# 舍入方向统一为「离零取半」(round half away from zero)，只在显示层发生，不回写状态。
func _round_div(a: int, b: int) -> int:            # b > 0
    var s: int = -1 if a < 0 else 1
    var m: int = absi(a)
    return s * ((m + b / 2) / b)                   # 整数除；b 为偶数时 b/2 精确
```

| 格式化器 | 算法 | 输出 |
|---|---|---|
| `fmt_u(v_uu)` | `cents = _round_div(v_uu, 10_000)`（0.01 U = 10 000 μU）；整数部 `cents/100` 加半角千分位逗号；小数部 `abs(cents)%100` 补足 2 位；负号用 `−`(U+2212)；值与单位间一个半角空格 | `−1,204.35 U` |
| `fmt_u_signed(v_uu)` | 同上，非负数强制前缀 `+` | `+0.42 U` |
| `fmt_qty(v_uqs, sector)` | `cents = _round_div(v_uqs, 10_000)`（1 Q_s = 1 000 000 μQ_s），2 位小数；单位取 `terms.sector_unit[sector]` | `10.00 单位电力` |
| `fmt_pct(v_ppm)` | `tenths = _round_div(v_ppm, 1_000)`；1 位小数 | `8.0 %` |
| `fmt_ppt(v_ppm)` | 同 `fmt_pct`，单位改「个百分点」，强制带符号 | `+1.2 个百分点` |
| `fmt_index(v_ppm)` | 同 `fmt_pct` 的数值部分，无 `%`，必须同屏带基期（`docs/20` §4.1） | `100.0` |
| `fmt_persons(n)` | `n < 1_000_000` → 整数 + 千分位 + `人`；否则 `tenths = _round_div(n, 100_000)` → 1 位小数 + `万人` | `900.0 万人` |
| `fmt_units(n, kind)` | 整数 + 千分位 + 名表量词 | `1,600 套` |
| `fmt_quarter(q)` | `q ≥ 0` → `第 {q+1} 季`；`q == -1` → 固定词 `开账（第 0 季）`；`q < -1` → `push_error` | `第 8 季` |
| `fmt_quarters(n)` | `{n} 季`；`n == 0` → 固定词 `本季内` | `3 季` |
| `fmt_range(lo, hi, base_fmt)` | `〔` + `base_fmt(lo)` 数值部 + `–`(U+2013) + `base_fmt(hi)` 数值部 + `〕` + 单位；`lo > hi` → `push_error` | `〔1.80–2.60〕U` |
| `fmt_citation(ledger, q, row)` | 见 §6.2 | `ldg.cash#Q07.014` |

**非零显示为零的禁令**（防止把 0.004 U 说成「0.00 U」，等于宣称没有发生）：

- 若 `v_uu != 0` 且 `_round_div(v_uu, 10_000) == 0`，`fmt_u` 渲染固定词 `小于 0.01 U`（负值 `大于 −0.01 U`），**不渲染 `0.00 U`**。
- `fmt_qty`、`fmt_pct` 同理，固定词分别为 `小于 0.01 {unit}`、`小于 0.1 %`。
- 台账视图与调试导出不受此规则约束，一律显示 μU 原值（`docs/20` §4.5）。

### 1.6 内部季索引与显示季号

| 场合 | 取值 |
|---|---|
| 状态、存档、命令流、日志（`docs/11` `_q` 后缀） | 0 基；`q = 0` 是基年第 1 季 |
| 玩家可见文案、引用码 `Q<nn>` | 1 基；`第 (q+1) 季` |
| 开账分录（`log.ledger.kind = 24`，内部 `q = −1`） | 文案固定词 `开账（第 0 季）`；引用码 `Q00` |
| 预算审查窗口 | 内部 `q ≡ 3 (mod 4)` → 显示 **第 4 / 8 / … / 40 季**（`docs/20` §18 第 2 条已裁决） |
| 选举 | 内部 `q ∈ {15, 31}` → 显示 **第 16 / 32 季** |

**任何模板中的季号槽位一律是 `quarter` 类型（传内部 q），由格式化器加 1。**
模板串里出现手写的 `第 N 季`（N 为数字字面量）只允许在 §1.3 PH-08 白名单内（如固定句「第 40 季形成发展档案」）。

### 1.7 舍入与加总一致性（必须可验收）

显示层舍入会让「分项之和 ≠ 合计」。首版取**如实显示 + 显式差额行**，不取最大余数法分摊：分摊会改动单笔金额的显示值，破坏「每个数字可回到台账原值」。

| # | 规则 |
|---|---|
| RD-01 | 合计单元格一律由 **μU 原值求和后**格式化，**禁止对已格式化的字符串求和**。 |
| RD-02 | 若 `Σ fmt(分项) ≠ fmt(Σ 分项)`，该表/该块**必须**追加一行：`tpl.trace.rounding_gap`「显示舍入差 {delta_u}（各项按 0.01 U 独立舍入所致；台账原值合计无残差）」。 |
| RD-03 | `abs(delta_uu) ≤ 5_000 × n`（n 为分项数）。超出即缺陷 —— 说明合计不是这些分项之和。 |
| RD-04 | 差额行**不得**出现在 `ACTUAL` 的对账恒等式行上；对账恒等式（`docs/12` §6.9）用 μU 原值判定，残差必须为 0，显示层用固定句 `tpl.actual.identity_ok`。 |
| RD-05 | 比率类不做差额行；分母必须同屏给出绝对数（`docs/20` §4.2）。 |

---

## 2 季度简报：风险排序算法

> 计划书 §04 环节 01：**一页季度简报；最多 3 项优先风险。**
> 计划书 §18 风险信号：**玩家只看一条综合分数 → 改进目标与报告；展示分布和长期承诺。**
> `docs/20` §7.1.5 已定：十个检测器、排序键 `(紧迫度季数 升序, 可干预性 降序, 影响人口权重 降序)`、取前 3、不足不补、终局措辞禁令。
> 本节定义：每个分量**怎么算**、候选**怎么去重**、名额**怎么分配**、折叠阈值**是什么**。

### 2.1 为什么不是一个加权总分

风险排序**不得**用 `w1·紧迫 + w2·可干预 + w3·人口` 这类加权和。理由与 §8「不合成单一国力分数」同源：三个分量量纲不同（季、条数、人口比），权重是不可检验的作者假设，且加权和会让「四季后爆掉的大问题」被「本季的小问题」用权重换掉，玩家无法解释排序。
首版采用**字典序**，并给出它的**整数编码**，使排序键可存档、可断言、可二分调试。

### 2.2 候选对象

```gdscript
class_name JwRiskCandidate extends RefCounted

var code: StringName            # det.* 检测器 ID
var quarter: int                # 内部 q，检出季
var domain: StringName          # §2.4 机制域，恰好一个
var anchor_id: StringName       # 归一化锚点实体（§2.5），符合 docs/11 §4 ID 正则
var root_key: StringName        # §2.5 构造
var mechanism_rank: int         # 1 = 机制层，2 = 症状层（§2.5）
var urgency_q: int              # §2.3，0..99
var intervenability: int        # §2.3，可提交候选政策条数
var pop_weight_ppm: int         # §2.3，0..1_000_000
var severity_max: int           # NOTE | GAP | BLOCK 的上限（§2.7）
var evidence: Array             # ≥2 条 {ledger_alias, filter, count_or_gap}
var manifestations: Array       # 归并进来的其他候选（§2.5）
var slots: Dictionary           # 已格式化的槽位，UI 只填不算
```

**完整性闸门**：任一字段缺失或 `evidence.size() < 2` 的候选**不得进入排序**，debug 构建 `push_error`，发布构建丢弃并写 `log.explanations`。理由：`docs/20` §7.1.3 要求诊断卡的「证据」段有 2–4 个台账入口，凑不出证据的风险无法核查，不该出现在简报里。

### 2.3 三个分量的计算式

| 分量 | 定义 | 计算式 | 无法计算时 |
|---|---|---|---|
| `urgency_q` | **距离危害发生的季数**（不是严重度） | 见下表逐检测器 | 记 `99`（`docs/20` §7.1.5 原文） |
| `intervenability` | **本季可提交的候选政策条数** | 对该域候选政策集（§2.4 表）逐条做一次资格检查（`docs/20` §17 dry-run 接口），返回**无 `BLOCK` 级原因**者计入；每季缓存一次 | `0`（仍显示，干预段改写，§3.4） |
| `pop_weight_ppm` | **受影响人口占全国人口比** | `Σ state.group.population_persons(受影响群组) × 1_000_000 / Σ 全国` | 全国性风险记 `1_000_000` |

`urgency_q` 逐检测器：

| 检测器 | `urgency_q` | 备注 |
|---|---|---|
| `det.cash_path` | 首次触及现金底线的季 − 当前季 | 四季窗口内必可计算 |
| `det.maturity` | 首个「到期本金+票息 > 该季可用现金+已计划新融资」的季 − 当前季 | |
| `det.queue_stall` | `0`（已停滞） | 停滞已是既成 |
| `det.binding` | `0`（约束已生效） | |
| `det.unemployment` | 已越阈值 → `0`；仅趋势越阈值 → 按当前环比外推到阈值所需季数，上限 `99` | 外推式登记为 `R-DIAG-UNEMP` |
| `det.housing` | 同上 | |
| `det.service_avail` | 已越阈值 → `0`；排队增长 → 外推 | |
| `det.ext_credit` | 额度余量 ÷ 近四季平均占用速率（向下取整） | 速率为 0 → `99` |
| `det.trust_drop` | `99` | 信任下降本身没有到期时点 |
| `det.output_drop` | `99` | 同上；且受 §2.7 severity 上限约束 |

> 后果：`det.output_drop` 与 `det.trust_drop` 天然沉到排序末尾。这与计划书 §04「经济下滑本身不是立即失败」一致，**是设计意图，不是副作用**。

### 2.4 机制域与检测器映射（穷举，不得留「其他」）

计划书 §02 点名的四个域必须能被定位到：**就业、供电、住房、融资**。另设四个域承载确实不属于这四项的情形。

| 域 ID | 中文名 | 点名域 | 归一化锚点 | 候选政策集 |
|---|---|---|---|---|
| `mech.employment` | 就业 | ✔ | 地区 | P05、P03、P09、P01 |
| `mech.power` | 供电 | ✔ | 地区 | P04、P09 |
| `mech.housing` | 住房 | ✔ | 地区 | P06、P01 |
| `mech.finance` | 融资 | ✔ | 全国 | P01、P02、P11、P12（支出排序/延期/重组为命令，不是政策，另计入出口） |
| `mech.service` | 公共服务 | | 地区 | P10、P06、P05 |
| `mech.supply` | 产能与投入 | | cell（地区×部门） | P07、P08、P09 |
| `mech.external` | 外部约束 | | 全国 | P08、P09 |
| `mech.politics` | 政治支持 | | 全国 | P12、P03（并附固定句：政治支持不是可直接设定的量） |

检测器 → 域（**一对一，或由一个确定性子键决定**）：

| 检测器 | 域的确定方式 |
|---|---|
| `det.binding` | 由 `flow.cell.binding_code`：`labor`→`mech.employment`；`energy`→`mech.power`；`capacity`/`materials`→`mech.supply`；`plan`→**不产生候选**（计划约束不是瓶颈） |
| `det.output_drop` | 同上，取该 cell 本季 `binding_code` |
| `det.queue_stall` | 由 `state.project.suspension_reason`：资金→`mech.finance`；施工能力→`mech.supply`；设备交付→`mech.external`；前置条件→按前置条件所属域 |
| `det.cash_path` / `det.maturity` | `mech.finance` |
| `det.unemployment` | `mech.employment` |
| `det.housing` | `mech.housing` |
| `det.service_avail` | `mech.service` |
| `det.ext_credit` | `mech.external` |
| `det.trust_drop` | `mech.politics` |

**优先落到点名域**：当一个候选按上表可落到非点名域、但其证据链的上一跳属于点名域时（例：`det.queue_stall` 因资金停滞 → `mech.finance`），取**点名域**。该规则只在上表已给出确定映射时不适用（上表优先），仅用于 §2.5 归并时选代表。

### 2.5 同一根因不占三个名额（归并）

**根键**：

```
root_key = domain + "|" + anchor_norm(domain, candidate) + "|" + sub_key
anchor_norm: mech.power/employment/housing/service → region_id
             mech.supply                            → cell_id
             mech.finance/external/politics         → "national"
sub_key:     mech.supply → 紧约束的投入部门 sector_id
             其余        → ""
```

| # | 规则 |
|---|---|
| RB-01 | `root_key` 相同的候选**合并为一条**。合并后只占 1 个名额。 |
| RB-02 | 代表的选取：`mechanism_rank` 小者胜（机制层 1 优于症状层 2）；并列时按 §2.6 排序键取先者；再并列按 `code` 字典序。**稳定且与输入顺序无关**。 |
| RB-03 | 被合并者进入代表的 `manifestations[]`，在卡片内渲染为一行：`tpl.brief.manifestations`「同一限制因素的其他表现：{list}」。**不另占名额、不另起卡片。** |
| RB-04 | 玩家可见文本中**不得出现「根因」「根本原因」**（是因果断言）。统一措辞为「**同一限制因素**」（`docs/20` §9.4 的固定措辞「模型中的限制因素」的名词形式）。`root_key` 只是内部字段名。 |
| RB-05 | `mechanism_rank`：`det.binding`、`det.queue_stall`、`det.cash_path`、`det.maturity`、`det.ext_credit`、`det.service_avail`、`det.housing`、`det.unemployment` = 1；`det.output_drop`、`det.trust_drop` = 2。 |

**典型归并**（必须成为夹具测试）：海岬制造 `det.output_drop`（binding=energy）与海岬 `det.binding`（energy）→ 同 `root_key = mech.power|region.haijia|` → 合并，代表是 `det.binding`，产出下降作为「其他表现」出现在同一张卡里。
**这就是「同一根因不占三个名额」的实现**：它发生在排序之前，而不是靠事后去重。

### 2.6 排序键与整数编码

```
rank_int = clampi(urgency_q, 0, 99) * 1_000_000
         + (999 - mini(intervenability, 999)) * 1_000
         + (999 - mini(pop_weight_ppm / 1_001, 999))
```

- **升序**排列 `rank_int`，等价于 `docs/20` §7.1.5 的字典序三元组，且可存进存档做回归断言。
- 完全并列时的稳定尾键：`(root_key 字典序 升序, code 字典序 升序)`。**排序必须稳定：同输入两次输出逐字相同**（`docs/20` RC-11 的同款要求）。
- `rank_int` **不是给玩家看的分数**，不得渲染进任何玩家可见文本（L-07 断言）。

### 2.7 名额分配、配额与严重度上限

| # | 规则 |
|---|---|
| RB-10 | 名额 = 3（`docs/20` §7.1.5）。按 `rank_int` 升序依次放入。 |
| RB-11 | **每个 `root_key` 至多 1 席**（归并后自动成立，仍作为断言保留）。 |
| RB-12 | **每个 `domain` 至多 2 席**。例外：候选集中不同 `domain` 的个数 < 2 时，按序填满并在卡组下方渲染 `tpl.brief.single_domain`「本季的优先风险集中在同一机制域：{domain_name}」。`＋增补`（`docs/20` §7.1.5 未规定，登记 RT-OQ-02）。 |
| RB-13 | **不足 3 项时显示实际条数，禁止用次要项凑满**（`docs/20` §7.1.5 第 3 条）。零项时渲染 `tpl.brief.empty`，内含阈值说明与规则卡入口。 |
| RB-14 | **严重度上限**：产出、增长、指数类下降只能是 `NOTE`（`docs/20` §7.1.5 第 5 条）。`det.output_drop`、`det.trust_drop` 的 `severity_max = NOTE`。 |
| RB-15 | **终局风险不走这三个名额**。留任资格与财政重组两项判据（唯二允许终局措辞者）渲染为独立区块 `tpl.brief.terminal_*`，必须同时写出触发规则 ID 与判据表达式与当前判定数值三项。 |
| RB-16 | 折叠阈值：候选满足 `urgency_q ≤ param.brief.urgency_horizon_q`（建议默认 4）**或** `pop_weight_ppm ≥ param.brief.pop_weight_floor_ppm`（建议默认 100 000 = 10 %）即为「达到优先」。未达到者不占名额，合并为一行 `tpl.brief.folded`。**阈值是登记参数，界面与文案层不得硬编码**（`docs/20` §17）。 |

### 2.8 简报模板库（`tpl.brief.*`）

风险卡的四段沿用 `docs/20` §7.1.3（症状 / 证据 / 机制 / 干预），文案见 §3.5。本节只给卡外与卡头文案。

| tpl_id | 模板 | 必填槽位 | 类 |
|---|---|---|---|
| `tpl.brief.header` | `第 {quarter} 季简报 · 优先风险 {shown_count} 项（阈值内共 {total_count} 项）` | quarter, shown_count, total_count | `DERIVED` |
| `tpl.brief.card_title` | `{domain_name} · {anchor_name}` | domain_name(label), anchor_name(label) | — |
| `tpl.brief.urgency_soon` | `按规则，最早在第 {trigger_quarter} 季（还有 {remaining_quarters}）触及 {threshold_name}。{rule_id}` | trigger_quarter, remaining_quarters, threshold_name, rule_id | `DERIVED` |
| `tpl.brief.urgency_now` | `按规则，本季已处于 {threshold_name} 之内。{rule_id}` | threshold_name, rule_id | `DERIVED` |
| `tpl.brief.urgency_unknown` | `按规则，本项无可计算的触发时点；排序按人口影响与可干预条数。{rule_id}` | rule_id | `DERIVED` |
| `tpl.brief.scope` | `影响人口 {affected_persons}（占全国 {share_pct}）。` | affected_persons, share_pct | `ACTUAL` |
| `tpl.brief.manifestations` | `同一限制因素的其他表现：[[*items sep="、"]]{.label}[[/]]。` | items | `DERIVED` |
| `tpl.brief.single_domain` | `本季的优先风险集中在同一机制域：{domain_name}。其余机制域本季无达到阈值的候选。` | domain_name | `DERIVED` |
| `tpl.brief.folded` | `另有 {folded_count} 项低于优先阈值（阈值：{horizon_quarters} 内触发，或影响人口占比 {weight_floor_pct}）。` | folded_count, horizon_quarters, weight_floor_pct | `DERIVED` |
| `tpl.brief.empty` | `本季没有达到优先阈值的风险。阈值：{horizon_quarters} 内触发，或影响人口占比 {weight_floor_pct}。可查看全部 {total_count} 项候选与各自阈值。` | horizon_quarters, weight_floor_pct, total_count | `DERIVED` |
| `tpl.brief.no_tool` | `首版无对应政策工具：{explain}。` | explain(text) | `DERIVED` |
| `tpl.brief.terminal_retention` | `执政结束判据 · 留任资格：{rule_id}，判据表达式 {expr}，当前判定值 {current_value}（判定阈值 {threshold_value}）。` | rule_id, expr, current_value, threshold_value | `DERIVED` |
| `tpl.brief.terminal_restructure` | `执政结束判据 · 财政重组：{rule_id}，判据表达式 {expr}，当前判定值 {current_value}（判定阈值 {threshold_value}）。` | 同上 | `DERIVED` |
| `tpl.brief.terminal_note` | `经济下滑本身不触发执政结束。触发条件只有以上两条。` | — | `DERIVED` |

**禁用词（本区块额外）**：`失败`、`淘汰`、`倒计时`、`game over`（`docs/20` §7.1.5 第 5 条，进 §9.2 L-02 词表）。

### 2.9 本节验收

| ID | 断言 |
|---|---|
| RT-AC-01 | 构造「海岬电力紧约束 + 海岬制造产出下降」夹具：简报只出现 **1** 张卡，卡内含「同一限制因素的其他表现」行；产出下降不单独成卡。 |
| RT-AC-02 | 构造「三个地区同时电力紧约束 + 一条融资缺口」夹具：3 席中 `mech.power` 至多 2 席（RB-12）。 |
| RT-AC-03 | 构造「只有 1 项达到阈值」夹具：渲染 1 张卡 + 折叠行；断言卡数 == 1（不凑满）。 |
| RT-AC-04 | 构造「零候选」夹具：渲染 `tpl.brief.empty`，且含阈值数值与规则卡入口。 |
| RT-AC-05 | 同一状态连续调用排序 100 次，输出的 `(code, root_key)` 序列逐次完全相同（稳定性）。 |
| RT-AC-06 | 构造「连续 4 季产出下滑」夹具：页面上不出现终局措辞，该候选 `severity == NOTE`（与 `docs/20` AC-29 同源，此处断言的是**文案**）。 |
| RT-AC-07 | 扫描全部简报渲染结果，`rank_int`、`root_key`、`det.*`、`mech.*` 等内部标识符**不出现**在玩家可见文本中。 |

---

## 3 本季诊断：指标 → 机制 → 证据 → 备选动作

> 计划书 §02：**报告把问题定位到就业、供电、住房或融资，而不是只显示红色数字。**
> 计划书 §04 环节 02：**沿着指标进入机制，而非在菜单中试错。**
> 计划书 §11 结构草图：**「供电是海岬当前生产约束之一。先核查：限电记录、设备与燃料供给。再比较：升级、维护或暂缓扩产。所有数据均可进入对应台账。」**
> 四段结构由 `docs/20` §7.1.3 规定（症状 / 证据 / 机制 / 干预）。本节规定四段各自的**生成规则与文案**。

### 3.1 段一 · 症状（必须 `ACTUAL`）

| # | 规则 |
|---|---|
| DG-01 | 症状句**恰好 1 个定量事实**，来自已结算季的台账，带单位、口径、变化方向。多于一个数字的症状句即缺陷（多个数字属于证据段）。 |
| DG-02 | 变化方向用受控词 `enum_word ∈ {改善, 恶化, 持平}` + 箭头 + 符号三通道（`docs/20` §4.5）。**「持平」的判据必须给出**：`abs(delta) ≤ param.diag.flat_band_*`，阈值为登记参数。 |
| DG-03 | 症状句**禁止**出现机制词（「因为电力」）、禁止出现干预词（「应当升级」）。它只陈述发生了什么。 |
| DG-04 | 症状必须带引用码（裸引用码，`docs/20` §3.5 规则 1）。 |

### 3.2 段三 · 机制（必须 `DERIVED`）：指标 → 机制域定位表

机制段的唯一数据来源是 `flow.cell.binding_code`（`docs/12` §5.3：「`binding_code` 是报告里『模型中的限制因素』的唯一数据来源」）与项目 `suspension_reason`、服务 `availability_ppm`、现金路径。

| 指标（症状） | 定位依据字段 | 机制域 | 机制 ID | 一句假设摘要（必须出现） |
|---|---|---|---|---|
| 部门产出下降 / 停滞 | `flow.cell.binding_code == energy` | 供电 | `[M-POWER-01]` | 其余四项约束按本季实际值不变 |
| 部门产出下降 / 停滞 | `binding_code == labor` | 就业 | `[M-LABOR-01]` | 技能档可用人数按本季实际值不变 |
| 部门产出下降 / 停滞 | `binding_code == capacity` | 产能与投入 | `[M-CAP-01]` | 维护欠账比例按本季实际值不变 |
| 部门产出下降 / 停滞 | `binding_code == materials` | 产能与投入 | `[M-MAT-01]` | 上季末投入库存按实际值不变 |
| 失业率上升 | `derived.labor.unemployment_ppm` + 招工两道硬闸（`docs/12` §3.2） | 就业 | `[M-LABOR-02]` | 岗位需求按本季计划不变 |
| 家庭负担率上升 | `derived.group.housing_burden_ppm` | 住房 | `[M-HOUSE-01]` | 住房存量与分配规则不变 |
| 服务可及性下降 / 排队增长 | `state.pubserv.availability_ppm`、`queue_persons`、维护欠账 | 公共服务 | `[M-SERV-01]` | 运行费拨付按本季实际不变 |
| 现金路径触底 | 四季现金预测（空命令重跑，`docs/12` §8.6） | 融资 | `[M-FIN-01]` | 不提交新草案、外部条件按基线 |
| 到期本金挤占 | `derived.fiscal.next4q_debt_service_uu` + 逐批次票息 | 融资 | `[M-FIN-02]` | 不新增借款、不重组 |
| 项目停滞 | `state.project.suspension_reason` | 按 §2.4 表 | `[M-PROJ-01]` | 队列与交付按本季实际不变 |
| 外部额度 / 交付能力吃紧 | `state.world.credit_limit_uu − credit_used_uu`、`delivery_capacity_uqs` | 外部约束 | `[M-EXT-01]` | 外部条件按基线情景 |
| 支持度 / 信任下降 | `state.group.trust_ppm`、`support_ppm` 的分解（`log.explanations`） | 政治支持 | `[M-POL-01]` | 三个主观量按各自规则分别更新 |

| # | 规则 |
|---|---|
| DG-10 | 机制段**必须**出现固定措辞「**模型中的限制因素**」，且**必须**带机制 ID 与规则号（`docs/20` §7.1.2 诊断卡机制行）。 |
| DG-11 | 机制段**必须**出现一句假设摘要（上表最后一列），且假设摘要必须与 §7 反事实块里列出的假设**同源同值**（同一数据对象，L-08 断言）。 |
| DG-12 | **多个瓶颈不做相加展示**（`docs/12` §5.3、计划书 §13）。机制段只列 argmin 与五项数值，**禁止**出现「合计瓶颈影响」「瓶颈分数」「贡献占比」类表述。 |
| DG-13 | `binding_code == plan` 时**不生成机制段**，改用固定句 `tpl.diag.mech_plan`：`按规则本季产量由计划量决定，五项约束均未触顶。` —— 这不是瓶颈。 |

### 3.3 段二 · 证据（先核查）：台账 ID 的选取规则

| # | 规则 |
|---|---|
| DG-20 | 证据 **2–4 条**（`docs/20` §7.1.3）。少于 2 条 → 该候选不得成卡（§2.2 完整性闸门）。 |
| DG-21 | 每条证据 = `{台账别名, 过滤器, 计数或缺口量}`，**必须带数字**：`n 行` 或 `缺口 {gap}`。只给入口不给数量即缺陷。 |
| DG-22 | 排序：有缺口量者按 `abs(缺口)` 降序在前；其余按台账优先级表（下表）。稳定排序。 |
| DG-23 | 至少 1 条证据必须来自**机制段所依据的台账**（供电 → `ldg.constraint` 或 `ldg.service`；融资 → `ldg.cash` 或 `ldg.debt`），否则机制段不可核查。 |
| DG-24 | 证据段是 `ACTUAL`，用裸引用码；点击必须滚动定位并高亮该行（`docs/20` §2.4）。 |

各域的**默认证据台账优先级**（实现按此顺序补足到 2–4 条）：

| 域 | 台账优先级 |
|---|---|
| 供电 | `ldg.constraint` → `ldg.service` → `ldg.inventory`（燃料）→ `ldg.project`（电网在建） |
| 就业 | `ldg.labor` → `ldg.constraint` → `ldg.population`（迁移）→ `ldg.household` |
| 住房 | `ldg.household` → `ldg.population` → `ldg.project`（在建住房）→ `ldg.opex` |
| 融资 | `ldg.cash` → `ldg.debt` → `ldg.commit` → `ldg.opex` |
| 公共服务 | `ldg.service` → `ldg.opex` → `ldg.labor`（人员）→ `ldg.project` |
| 产能与投入 | `ldg.constraint` → `ldg.inventory` → `ldg.value_added` → `ldg.project` |
| 外部约束 | `ldg.external` → `ldg.commit` → `ldg.project` → `ldg.inventory` |
| 政治支持 | `ldg.politics` → `ldg.household` → `ldg.service` → `ldg.tax` |

### 3.4 段四 · 干预（再比较）：可比备选动作

| # | 规则 |
|---|---|
| DG-30 | **2–3 条**候选动作（`docs/20` §7.1.3）。每条 = **一条可执行的 UI 命令** + 代价短语 + 最早反馈季。**禁止纯文字建议**（`docs/20` RC-08 的推广）。 |
| DG-31 | **可比性定义（硬）**：同一张卡里的候选动作必须在**同三个维度**上都给出数字：① 一次性成本（`u`）② 每季持续成本（`u`）③ 最早反馈季（`quarter`）。任一条缺任一维 → 该条不得与其他条并列，降级到「其他可选动作 ▸」列表。 |
| DG-32 | **排序固定**：最早反馈季升序 → 一次性成本升序 → 政策 ID 升序。并且**必须**渲染固定句 `tpl.diag.order_note`：`以下选项按最早反馈季排列，不代表推荐顺序。` |
| DG-33 | **禁用词**：`推荐`、`最优`、`最佳`、`应当先`、`建议优先`、`正确选择`（进 L-02 词表）。计划书 §05：「没有『必须先修电网』的隐藏答案。」 |
| DG-34 | 每条动作**必须**附一句不保证句 `tpl.diag.no_guarantee`：`该动作改变的是条件，不直接产生产出或支持率。` （计划书 §06「政策改变的是条件」；§10 验收「没有销路时，不能直接发放 GDP 与支持率奖励」。） |
| DG-35 | 候选为 0 条时 **不得留空**：渲染 `tpl.brief.no_tool`「首版无对应政策工具：{explain}」，`explain` 来自域表的固定说明串。 |
| DG-36 | 候选动作若本身会触发 `BLOCK` 级原因，**仍然列出**，但必须内联该原因的行 2（§5），让玩家看到「差多少」而不是看不到选项。 |

### 3.5 诊断模板库（`tpl.diag.*`）

四段各一条基模板 + 每域一条机制变体。变体选择判据 = `domain`（互斥穷举，TP-03）。

| tpl_id | 模板 | 类 |
|---|---|---|
| `tpl.diag.symptom` | `实记 · 第 {quarter} 季{anchor_name}{metric_name}为 {value}，较上季{direction_word} {delta}。 ▸{citation}` | `ACTUAL` |
| `tpl.diag.evidence_head` | `先核查：` | — |
| `tpl.diag.evidence_item` | `{ledger_name}（{count_text}） ▸{citation}` | `ACTUAL` |
| `tpl.diag.mech@power` | `推算 · 模型中的限制因素：{anchor_name}制造的可用供电服务。五项约束中电力最紧，其余项本季未触顶。假设：{assumption}。{mech_id} {rule_id} 输入：{citations}` | `DERIVED` |
| `tpl.diag.mech@employment` | `推算 · 模型中的限制因素：{anchor_name}{skill_tier}档可用劳动力。按用工系数换算后劳动项最紧。假设：{assumption}。{mech_id} {rule_id} 输入：{citations}` | `DERIVED` |
| `tpl.diag.mech@housing` | `推算 · 模型中的限制因素：{anchor_name}住房容量与家庭负担。按当前存量与分配规则，住房支出占可支配收入 {burden_pct}。假设：{assumption}。{mech_id} {rule_id} 输入：{citations}` | `DERIVED` |
| `tpl.diag.mech@finance` | `推算 · 模型中的限制因素：第 {trigger_quarter} 季的可用现金。该季应付 {need_u}，可用 {avail_u}，缺口 {gap_u}。假设：{assumption}。{mech_id} {rule_id} 输入：{citations}` | `DERIVED` |
| `tpl.diag.mech@service` | `推算 · 模型中的限制因素：{anchor_name}{service_name}的实际可用率 {avail_pct}（名义容量 {capacity_qty}，排队 {queue_persons}）。假设：{assumption}。{mech_id} {rule_id} 输入：{citations}` | `DERIVED` |
| `tpl.diag.mech@supply` | `推算 · 模型中的限制因素：{anchor_name}{sector_name}的{bound_name}。按投入系数换算后该项最紧。假设：{assumption}。{mech_id} {rule_id} 输入：{citations}` | `DERIVED` |
| `tpl.diag.mech@external` | `推算 · 模型中的限制因素：外部信用额度余量 {credit_u} 与交付能力余量 {delivery_qty}。假设：{assumption}。{mech_id} {rule_id} 输入：{citations}` | `DERIVED` |
| `tpl.diag.mech@politics` | `推算 · 模型中的限制因素：{group_or_bloc_name}的{subjective_name}。三个主观量分别更新，本季变动来源见分解。假设：{assumption}。{mech_id} {rule_id} 输入：{citations}` | `DERIVED` |
| `tpl.diag.mech_plan` | `推算 · 按规则本季产量由计划量决定，五项约束均未触顶。{rule_id} 输入：{citations}` | `DERIVED` |
| `tpl.diag.bounds_list` | `五项约束（同一产品口径）：计划 {b_plan}、产能 {b_capacity}、劳动 {b_labor}、能源 {b_energy}、材料 {b_materials}；实际 {q_actual}。各项不可相加。` | `DERIVED` |
| `tpl.diag.order_note` | `以下选项按最早反馈季排列，不代表推荐顺序。` | — |
| `tpl.diag.action` | `{action_label}：一次性 {capex_u}，每季 {opex_u}，最早反馈{feedback_quarter}。` | `DERIVED` |
| `tpl.diag.no_guarantee` | `该动作改变的是条件，不直接产生产出或支持率。` | — |
| `tpl.diag.action_blocked` | `{action_label}（当前不可提交：{reason_line2}）` | `DERIVED` |

### 3.6 本节验收

| ID | 断言 |
|---|---|
| RT-AC-10 | 每个 `mech.*` 域都存在 `tpl.diag.mech@<域>`；变体判据互斥且穷举（L-01）。 |
| RT-AC-11 | 任一诊断卡渲染结果中，机制段含固定串「模型中的限制因素」、一个 `[M-…]`、一个 `^R-…`、一句假设摘要。 |
| RT-AC-12 | 任一诊断卡的证据段条数 ∈ [2,4]，每条含数字，且至少一条台账属于 §3.3 该域优先级表的前两位。 |
| RT-AC-13 | 任一诊断卡的干预段：条数 ∈ [2,3] 或渲染了 `tpl.brief.no_tool`；并列的每条都含三个维度的数字；含 `tpl.diag.order_note` 与 `tpl.diag.no_guarantee`。 |
| RT-AC-14 | 全量渲染扫描：不出现 DG-33 禁用词；不出现「合计瓶颈」「瓶颈分数」「贡献占比」（DG-12）。 |
| RT-AC-15 | 构造 `binding_code == plan` 夹具：渲染 `tpl.diag.mech_plan`，且该 cell 不产生风险候选。 |

---

## 4 三类措辞：已经发生 / 规则推断 / 情景预测

> 计划书 §04 信息设计底线：**报告必须区分「已经发生」「规则推断」和「情景预测」。**
> 计划书 §13 第 08 步：**区分会计贡献、约束诊断与情景预测。**
> 分类**判定**见 `docs/20` §3.1—§3.2（本文不重写）；视觉通道见 `docs/20` §3.3。本节只管**句子**。

### 4.1 词前缀与徽章字（与 `docs/20` §3.3 一致，不得另立）

| 类 | 散文行前缀 | 表格徽章字 | 数字形态 |
|---|---|---|---|
| `ACTUAL` 已经发生 | `实记 · ` | `实` | 永不带区间 |
| `DERIVED` 规则推断 | `推算 · ` | `算` | 货币与数量必单值；时滞/季数可带规则给定区间并标注来源 |
| `PROJECTED` 情景预测 | `预测 · ` | `预` | 必带 `〔lo–hi〕` + 情景名 + `到第 N 季` |

**每条散文行的最左必须是前缀**，前缀与正文之间一个半角空格加 `·` 加半角空格，不得省略、不得折行（`docs/20` §3.4）。

### 4.2 时体标记词表（中文没有时态形态，因此规定为受控词表）

| 类 | **必须至少出现一个** | **允许** | **禁止（出现即 lint 失败）** |
|---|---|---|---|
| `ACTUAL` | `已`、`了`、`本季`、`第 N 季`、`期末`、`期初`、`实收`、`实付`、`记入`、`完成` | 完成体、既成陈述、精确加总 | `将`、`会`、`预计`、`可能`、`大致`、`约`、`有望`、`若`、`估计`、`倾向`、`应该`、`区间`、`〔` `〕` |
| `DERIVED` | `按规则`、`按当前参数`、`在其余项不变的条件下`、`为`、`等于`、`处于`、`不早于`、`才`、`仍` | 条件式陈述、换算、口径说明 | `已经`、`实际上`、`实记`、`预计`、`可能`、`将`、`会`、`有望`、`若无意外`；以及一切因果断言（§4.6） |
| `PROJECTED` | `预测`、`预计`、`若`、`在{情景}下`、`到第 N 季` | 区间、情景名、假设条数 | `已`、`实记`、`实际`、`确定`、`必然`、`一定`、`保证`、`必将`；以及任何台账引用码 |

补充硬规则：

| # | 规则 |
|---|---|
| WD-01 | `ACTUAL` 句中**不得**出现 `〔` `〕` `±` `–`(区间连接符)（`docs/20` §3.3 通道④正则）。 |
| WD-02 | `DERIVED` 的货币/数量主数值**不得**带区间；**时滞与季数允许**规则给定的区间，此时必须紧跟 `（区间来源：政策定义）`。 |
| WD-03 | `PROJECTED` 主句**必须**同时含区间、情景名、`到第 {N} 季` 三者；缺一即失败。 |
| WD-04 | `PROJECTED` 主句**不得**出现台账引用码（`docs/20` §3.5 规则 3）。规则号只允许出现在「假设 N 条 ▾」展开内。 |
| WD-05 | `DERIVED` 的引用码必须整体位于 `输入：` 之后，且同行必须有 `^R-…`（`docs/20` §3.5 规则 2）。 |
| WD-06 | 一个句子只有一个类。**禁止一句话跨类**；跨类内容拆成两句、两行、两个单元格。 |

### 4.3 「已经发生」模板库（`tpl.actual.*`，12 条）

全部来自已结算季的台账，全部带裸引用码，全部可精确加总。

| tpl_id | 模板 |
|---|---|
| `tpl.actual.quarter_summary` | `实记 · 第 {quarter} 季收入 {receipts_u}、支出 {outlays_u}、新增债务 {new_debt_u}、完工项目 {completed_count} 项。 ▸{citation}` |
| `tpl.actual.transaction` | `实记 · 第 {quarter} 季{payer_name}向{payee_name}支付{account_name} {amount_u}。 ▸{citation}` |
| `tpl.actual.wage_paid` | `实记 · 第 {quarter} 季{sector_name}在{region_name}实付工资 {amount_u}，覆盖 {persons}。 ▸{citation}` |
| `tpl.actual.project_payment` | `实记 · 第 {quarter} 季向{project_name}履约付款 {amount_u}，累计已付 {paid_total_u}（合同总额 {total_cost_u}）。 ▸{citation}` |
| `tpl.actual.tax_collected` | `实记 · 第 {quarter} 季{tax_name}实征 {amount_u}，法定税基 {base_u}，征收覆盖率 {coverage_pct}。 ▸{citation}` |
| `tpl.actual.debt_flow` | `实记 · 第 {quarter} 季新增借款 {issue_u}、还本 {principal_u}、付息 {interest_u}；期末债务 {debt_end_u}。 ▸{citation}` |
| `tpl.actual.production` | `实记 · 第 {quarter} 季{region_name}{sector_name}产出 {output_qty}，入库 {stock_in_qty}，售出 {sold_qty}。 ▸{citation}` |
| `tpl.actual.identity_ok` | `实记 · 库存恒等式核对通过：期末 = 期初 + 生产 + 购入 − 售出 − 生产耗用 − 损耗，残差 0。 ▸{citation}` |
| `tpl.actual.employment_change` | `实记 · 第 {quarter} 季{region_name}雇佣 {hires_persons}、离职 {separations_persons}；期末就业 {employed_persons}。 ▸{citation}` |
| `tpl.actual.population_flow` | `实记 · 第 {quarter} 季{flow_name}：来源{from_group_name} {persons}，去向{to_group_name}。 ▸{citation}` |
| `tpl.actual.arrears` | `实记 · 第 {quarter} 季{payee_name}的{account_name}欠付 {amount_u}，按支付优先级第 {priority_rank} 档处理。 ▸{citation}` |
| `tpl.actual.commissioned` | `实记 · 第 {quarter} 季{project_name}完工登记；新增能力自第 {effective_quarter} 季起计入。 ▸{citation}` |

### 4.4 「规则推断」模板库（`tpl.derived.*`，13 条）

全部由已结算状态按公开规则算出，全部带 `^R-` 与 `输入：`。

| tpl_id | 模板 |
|---|---|
| `tpl.derived.binding` | `推算 · {region_name}{sector_name}本季的紧约束为{bound_name}；其余四项未触顶。{rule_id} 输入：{citations}` |
| `tpl.derived.bounds_not_additive` | `推算 · 五项约束按同一产品口径换算后取最小值；各项数值不可相加，也不合成瓶颈分数。{rule_id}` |
| `tpl.derived.no_capacity_this_q` | `推算 · 按规则本季无产能贡献 {mech_id}。完工资产下一季才提供新增能力。{rule_id} 输入：{citations}` |
| `tpl.derived.earliest_commission` | `推算 · 按当前交付进度 {delivery_pct} 与施工进度 {construction_pct}，最早投运不早于第 {earliest_quarter} 季。{rule_id} 输入：{citations}` |
| `tpl.derived.debt_service_4q` | `推算 · 第 {q_from}–{q_to} 季到期本金 {principal_u}、票息 {coupon_u}，合计 {total_u}。逐批次计算，不因新发利率重定价。{rule_id} 输入：{citations}` |
| `tpl.derived.commitments` | `推算 · 已签合同按履约进度，第 {q_from}–{q_to} 季应付 {amount_u}（{contract_count} 份）。{rule_id} 输入：{citations}` |
| `tpl.derived.opex` | `推算 · {asset_name}启用后每季运行费 {opex_u}；停拨款按规则降低实际可用率，不删除已建资产。{rule_id} 输入：{citations}` |
| `tpl.derived.withdraw_cost` | `推算 · 撤回{project_name}的代价三项：已付不可收回 {sunk_u}、未完工残值 {residual_u}、合同赔偿 {penalty_u}。{rule_id} 输入：{citations}` |
| `tpl.derived.next_binding` | `推算 · 在其余项不变的条件下，解除{bound_name}后的次紧约束为{next_bound_name}，可达产量 {next_output_qty}。{rule_id} 输入：{citations}` |
| `tpl.derived.priority_displace` | `推算 · 按支付优先级，本方案使第 {priority_rank} 档的{displaced_name}延付 {amount_u}。{rule_id} 输入：{citations}` |
| `tpl.derived.unemployment_basis` | `推算 · 失业率 {rate_pct} 由就业分配反算，分母为劳动力 {labor_force_persons}，不是总人口。{rule_id} 输入：{citations}` |
| `tpl.derived.variance_verdict` | `推算 · 本季实记 {actual_value}（实）与上季预测区间 {range_text}（预）比较：{verdict_word}。{rule_id}` |
| `tpl.derived.lag_range` | `推算 · {policy_name}的最早反馈为 {lag_range}（区间来源：政策定义）。{rule_id}` |

> `tpl.derived.variance_verdict` 是**唯一**允许在一句话里同时出现 `ACTUAL` 值与 `PROJECTED` 区间的模板：
> 它本身是「按规则做的比较」，整句归 `DERIVED`，且两个来源值各自带自己的徽章字（`docs/20` §7.5.1 第一小节例外）。
> `verdict_word ∈ {区间内, 高于上界, 低于下界}`（受控词表；`区间内` 时数值差不显示——落在区间内不算偏差，`docs/20` VT-2）。

### 4.5 「情景预测」模板库（`tpl.projected.*`，11 条）

全部必带区间 + 情景名 + 到第 N 季 + 假设入口；全部禁止台账引用码。
情景只有两个：`基线`（`SC-base`）与 `不利条件`（`SC-adverse`），定义来自剧本配置（`docs/20` §18 第 4 条）。

| tpl_id | 模板 |
|---|---|
| `tpl.projected.cash_path` | `预测 · {scenario}下，第 {q_from}–{q_to} 季期末现金落在 {range_u}，最窄余量出现在第 {worst_quarter} 季。假设 {assumption_count} 条 ▾` |
| `tpl.projected.cash_worst` | `预测 · {scenario}下，到第 {horizon_quarter} 季最窄余量为 {range_u}。假设 {assumption_count} 条 ▾` |
| `tpl.projected.output` | `预测 · {scenario}下，{region_name}{sector_name}产出到第 {horizon_quarter} 季落在 {range_qty}。假设 {assumption_count} 条 ▾` |
| `tpl.projected.unemployment` | `预测 · {scenario}下，失业率到第 {horizon_quarter} 季落在 {range_pct}（分母为劳动力）。假设 {assumption_count} 条 ▾` |
| `tpl.projected.receipts` | `预测 · {scenario}下，{tax_name}到第 {horizon_quarter} 季落在 {range_u}。假设 {assumption_count} 条 ▾` |
| `tpl.projected.export` | `预测 · {scenario}下，出口收入到第 {horizon_quarter} 季落在 {range_u}。假设 {assumption_count} 条 ▾` |
| `tpl.projected.price` | `预测 · {scenario}下，{sector_name}价格指数到第 {horizon_quarter} 季落在 {range_pct}（基期=第 1 季）。假设 {assumption_count} 条 ▾` |
| `tpl.projected.living` | `预测 · {scenario}下，消费与公共服务指数到第 {horizon_quarter} 季落在 {range_pct}（基期=第 1 季）。假设 {assumption_count} 条 ▾` |
| `tpl.projected.retention_margin` | `预测 · {scenario}下，到第 {horizon_quarter} 季的留任裕度落在 {range_pct}。本预览不预测选举结果。假设 {assumption_count} 条 ▾` |
| `tpl.projected.two_column` | `预测 · 同一方案两种情景对照：基线 {range_base}；不利条件 {range_adverse}（均到第 {horizon_quarter} 季）。假设 {assumption_count} 条 ▾` |
| `tpl.projected.assumption_item` | `{assumption_text}（{param_or_field} = {value}，来源：{source_type}）` |

> **`tpl.projected.retention_margin` 的禁令**：不得出现 `胜算`、`概率`、`把握`、`赢`、`连任几成`。
> 首版不输出概率（没有校准过的分布，`docs/14`「不应宣称的精度」）。只给规则给出的裕度区间。

### 4.6 禁止混用清单（正则可 lint）

扫描域：全部 `content/text/*.json` 的模板串 + 全量夹具渲染结果快照。

| # | 检查 | 正则 / 判据 | 处置 |
|---|---|---|---|
| MX-01 | `ACTUAL` 行含预测词 | 行首 `实记 · ` 且匹配 `(将|会|预计|可能|大致|约|有望|若|估计|倾向|应该)` | 失败 |
| MX-02 | `ACTUAL` 行含区间符 | 行首 `实记 · ` 且匹配 `[〔〕±]` 或 `\d\s*–\s*\d` | 失败 |
| MX-03 | `DERIVED` 行含既成词 | 行首 `推算 · ` 且匹配 `(已经|实际上|实记)` | 失败 |
| MX-04 | `DERIVED` 行含预测词 | 行首 `推算 · ` 且匹配 `(预计|可能|将会|有望)` | 失败 |
| MX-05 | `DERIVED` 货币区间 | 行首 `推算 · ` 且匹配 `〔[^〕]*〕\s*U` | 失败 |
| MX-06 | `DERIVED` 缺规则号或缺 `输入：` | 行首 `推算 · ` 且（不含 `\^R-` 或 不含 `输入：`）且不在 §4.4 免除名单（`bounds_not_additive`、`lag_range`、`variance_verdict`） | 失败 |
| MX-07 | `DERIVED` 裸引用码 | 行首 `推算 · ` 且 `ldg\.` 出现位置在 `输入：` 之前 | 失败 |
| MX-08 | `PROJECTED` 含引用码 | 行首 `预测 · ` 且匹配 `ldg\.` | 失败 |
| MX-09 | `PROJECTED` 缺三件套 | 行首 `预测 · ` 且（不含 `〔.*–.*〕` 或 不含情景名 或 不含 `到第 .* 季`/`第 .*–.* 季`） | 失败 |
| MX-10 | `PROJECTED` 含确定词 | 行首 `预测 · ` 且匹配 `(已|实记|实际|确定|必然|一定|保证|必将)` | 失败 |
| MX-11 | 一句跨类 | 同一行出现 ≥2 个类前缀或 ≥2 个徽章字 | 失败 |
| MX-12 | 无前缀的解释句 | `statements/diagnosis/archive` 资源中的块级句首无三前缀之一 | 失败 |

### 4.7 三类共用的禁用词

| 组 | 词 | 例外 |
|---|---|---|
| 空洞阻断词（`docs/20` §9.4） | `不可用`、`无效`、`错误`、`失败`、`不满足条件`、`无法执行`、`请稍后`、`未知原因` | 紧跟 `：{原因}` 且该原因含数字与季度 |
| 真实世界因果断言（扫描域限于：报告小节四、诊断卡机制段、反事实文案，`docs/20` §9.4） | `原因是`、`证明了`、`因为…所以…`、`导致了` | 白名单：模型内链路描述（「队列拥堵使进度停滞」）、UI 操作说明、引用计划书原文 |
| 综合分数（计划书 §04、§18） | `总分`、`综合评分`、`治理得分`、`国力`、`评级`、`星级`、`排名`、`本季评分` | 无 |
| 终局（`docs/20` §7.1.5） | `失败`、`淘汰`、`倒计时`、`game over` | 仅 `tpl.brief.terminal_*` 与档案页 `tpl.archive.early_*` 中的「执政结束」表述，且必须带规则 ID 与判据数值 |
| 推荐（§3.4 DG-33） | `推荐`、`最优`、`最佳`、`应当先`、`建议优先`、`正确选择` | 无 |
| 概率（§4.5） | `胜算`、`概率`、`把握`、`几成` | 无（首版不输出概率） |
| 精度伪装（计划书 §14） | `基尼系数`、`精确到`、`真实国家`、`预测工具` | 无 |

### 4.8 本节验收

| ID | 断言 |
|---|---|
| RT-AC-20 | 三个模板库各 ≥8 条（实际 12 / 13 / 11），每条都有至少一个夹具能渲染出完整句子（无 `PH-05` 降级）。 |
| RT-AC-21 | MX-01..MX-12 全部通过：对模板串静态扫描 + 对全量夹具渲染快照扫描，两遍都跑。 |
| RT-AC-22 | §4.7 禁用词扫描通过（含例外判定，例外必须被至少一个夹具覆盖，证明例外逻辑本身被测过）。 |
| RT-AC-23 | 抽取任意 20 条渲染结果，人工逐条判读其类，与 `info_class` 字段一致率 100 %（可理解性门槛的文案侧，配合 `docs/20` AC 与计划书 §17「可理解性」）。 |

---

## 5 「为什么不能执行」：阻断原因文案

> 计划书 §04：**政策页必须告诉玩家「为什么不能执行」。**
> 计划书 §11：**对会导致资金缺口的方案给出具体原因，不只显示「不可用」。**
> 结构、五行版式、RC-01..RC-16、30 类码表由 `docs/20` §9 规定。**本节补齐 `docs/20` 只给了判据而未给模板的 20 条，并为全部 30 条规定必填数字与默认出口。**

### 5.1 通则

| # | 规则 |
|---|---|
| RS-01 | 原因文案整体是 `DERIVED` 类，受 §4.2 词表约束（行 1 类别名与行 5 链接除外）。 |
| RS-02 | 行 2 **必须**含 `need / avail / gap` 三个数字，例外只有 `blk.window`、`blk.authority`、`blk.duplicate`（`docs/20` RC-04、§9.1），它们用**时点 / 权限名 / 已存在对象**替代。 |
| RS-03 | **「缺多少」必须是可读数字**：缺钱写 `{gap_u}`，缺时间写 `{gap_quarters}`，缺前置写**哪一条**（条目名 + 当前值 + 需要值），缺人写 `{gap_persons}`，缺额度写 `{gap_u}` 与 `{gap_qty}` 两者。 |
| RS-04 | 每条至少 1 条出口，形如 `〈动作〉（代价：〈定量或定性后果〉；缺口降至 {residual_gap}）`，且必须是可执行 UI 命令（`docs/20` RC-06..RC-08）。**等待也是出口，但必须写到第几季。** |
| RS-05 | 行 1 显示中文类别名，**不显示原因码**（`docs/20` §9.2）。 |
| RS-06 | 未登记的 `reject_code` → 渲染 debug 专用兜底模板 `tpl.reason.unmapped`，**同时使覆盖测试失败**。发布构建中出现兜底模板即 P0 缺陷（它等价于「只显示不可用」，正是计划书 §04 禁止的）。 |
| RS-07 | 载入期 / 内容校验类错误码（`docs/11` §7 的 `E_*`：`E_SCHEMA_HEADER`、`E_PARAM_RANGE` 等）**不进入玩家文案**，只进开发者诊断面板。玩家命令流上的拒绝码才映射到本节。 |

### 5.2 BLOCK · 规则上不可能（10 类 + 1 增补 = 11）

行 2 模板（前 10 条与 `docs/20` §9.6 一致，此处补足槽位与出口）：

| 码 | 中文类别名 | 行 2 模板 | 必填数字 | 默认出口 |
|---|---|---|---|---|
| `blk.authority` | 法定权限不足 | `需要：{authority_name}；当前：{authority_current}。最早可取得途径：{path_label}（第 {path_quarter} 季）。` | 时点 | 等待至第 {path_quarter} 季；改选其他工具 |
| `blk.bloc_condition` `＋增补` | 政治条件不满足 | `本政策要求{bloc_name}的联盟条件；当前组织强度 {strength_pct}，条件阈值 {threshold_pct}，差 {gap_ppt}。` | 差值（个百分点） | 改规模/改地区以降低反对；等待至第 {next_review_quarter} 季审查窗口 |
| `blk.window` | 审查 / 立法窗口未开 | `下一窗口：第 {window_quarter} 季（还有 {remaining_quarters}）。` | 季数 | 等待至第 {window_quarter} 季；改为窗口外可提交的工具 |
| `blk.precond` | 前置条件未满足 | `前置条件 {index}/{total}「{cond_name}」：需要 {required_value}，当前 {current_value}，差 {gap_value}。` （逐条重复） | 逐条差值 | 先提交满足该前置的动作；等待队列/队列结业 |
| `blk.queue` | 执行队列无空位 | `需要 {need_slots} 位，余位 {free_slots}，最早入队第 {earliest_quarter} 季（占用者：{holder_name}，至第 {holder_release_quarter} 季）。` | 位数、季 | 改期至第 {earliest_quarter} 季；撤回占用者（代价见成本卡） |
| `blk.param_range` | 参数越界 | `允许范围 {range_lo}–{range_hi}，当前 {current_value}，超出 {gap_value}。` | 超出量 | 将参数改到 {range_hi}（或 {range_lo}） |
| `blk.target_invalid` | 作用对象无效或为空组 | `{policy_name} 不适用于 {target_name}；适用范围共 {scope_count} 项：{scope_list}。` | 项数 | 改选适用对象 |
| `blk.duplicate` | 重复立项或重复领取 | `已存在：{existing_name}（第 {existing_quarter} 季生效，至第 {existing_until_quarter} 季）。` | 时点 | 改为修改既有条目；等待至第 {existing_until_quarter} 季 |
| `blk.conflict` | 互斥政策已生效 | `与生效中的 {policy_name} 互斥（自第 {since_quarter} 季，至第 {until_quarter} 季）。` | 时点 | 先撤回 {policy_name}（代价见成本卡）；等待至第 {until_quarter} 季 |
| `blk.source_unassigned` | 资金来源未指派 | `本季应付 {need_u}，已指派 {avail_u}，未指派 {gap_u}。` | 钱 | 指派来源（税收调度/现金/债券）；缩减规模至 {feasible_scale} |
| `blk.source_overassigned` | 来源重复指派 | `{source_name} 可用 {avail_u}，已指派 {need_u}，超出 {gap_u}。` | 钱 | 取消其中一条指派；改指派到 {alt_source_name} |

> `blk.bloc_condition` 是**增补码**：`docs/12` 有独立的 `E_BLOC_VETO`，与法定权限不是一回事（权限是制度授权，联盟条件是政治条件），合并成一条会让玩家看不出「差多少个百分点」。
> 需 `docs/20` §9.6 同步增一行，登记 RT-OQ-03。

### 5.3 GAP · 可能但有后果（12 类）

| 码 | 中文类别名 | 行 2 模板 | 必填数字 |
|---|---|---|---|
| `gap.cash_now` | 当季现金不足 | `本季应付 {need_u}，可用 {avail_u}（期初现金 {cash_start_u} ＋本季确定收入 {receipts_certain_u}），缺口 {gap_u}。` | 钱 ×4 |
| `gap.cash_path` | 四季现金路径缺口 | `在{scenario}下，第 {worst_quarter} 季期末现金为 {worst_cash_u}，低于底线 {floor_u}，缺口 {gap_u}。` | 钱 ×3、季 |
| `gap.reserve_floor` | 触及最低现金底线 | `期末现金 {cash_end_u}，底线 {floor_u}，余量 {gap_u}。` | 钱 ×3 |
| `gap.debt_maturity` | 到期本金挤占 | `第 {due_quarter} 季到期本金 {principal_u} ＋票息 {coupon_u} ＝ {need_u}；该季可用 {avail_u}，缺口 {gap_u}。` | 钱 ×5、季 |
| `gap.borrow_cap` | 融资额度不足 | `拟新增借款 {need_u}；居民投资池可吸纳 {pool_u} ＋外部额度余量 {ext_u} ＝ {avail_u}，缺口 {gap_u}。` | 钱 ×5 |
| `gap.borrow_price` | 融资价格超上限 | `按规则定价票息 {rate_pct}／季，上限 {cap_pct}／季，超出 {gap_ppt}。` | 比率 ×3 |
| `gap.fx_credit@credit` | 外部额度不足 | `进口需求 {need_u}；外部信用额度余量 {avail_u}，缺口 {gap_u}。` | 钱 ×3 |
| `gap.fx_credit@delivery` | 交付能力不足 | `进口需求 {need_qty}；本季交付能力余量 {avail_qty}，缺口 {gap_qty}（折合 {gap_u}），最早可交付第 {earliest_quarter} 季。` | 数量 ×3、钱、季 |
| `gap.commit_overlap` | 承诺叠加超未来可支配 | `第 {q_from}–{q_to} 季：已签承诺 {committed_u} ＋本草案新增 {new_u} ＝ {need_u}，同期可支配 {avail_u}，超出 {gap_u}。` | 钱 ×5 |
| `gap.opex_unfunded` | 长期运行费无经常性来源 | `{asset_name} 投运后每季运行费 {opex_u}；第 {q_from}–{q_to} 季无对应经常性来源，四季合计缺口 {gap_u}。` | 钱 ×2、季 ×2 |
| `gap.priority_displace` | 支付优先级挤出 | `按支付优先级，本方案使第 {priority_rank} 档的{displaced_name}延付 {gap_u}（该档本季应付 {need_u}，可用 {avail_u}）。` | 钱 ×3、档位 |
| `gap.tax_overestimate` | 税收调度高估 | `方案假定税收调度 {need_u}；按当前征收覆盖率 {coverage_pct}，可实现 {avail_u}，高估 {gap_u}。` | 钱 ×3、比率 |
| `gap.cancel_cost` | 取消违约金未纳入来源 | `取消{contract_name}的合同赔偿 {penalty_u} 未出现在来源指派中；应付合计 {need_u}，已指派 {avail_u}，缺口 {gap_u}。` | 钱 ×4 |

**`gap.fx_credit` 的变体选择判据**（TP-03 要求互斥穷举）：
`额度余量 < 需求` 且 `交付能力余量 ≥ 需求` → `@credit`；`交付能力余量 < 需求` → `@delivery`；两者皆不足 → `@delivery`（更早触发的物理约束优先），并在行 3 追加一条 driver 指出额度也不足。

### 5.4 NOTE · 不阻断，但必须显示（8 类）

| 码 | 中文类别名 | 行 2 模板 | 必填数字 |
|---|---|---|---|
| `note.supply_no_demand` | 新增供给无对应需求 | `新增容量 {added_qty}／季；按当前需求预期可吸收 {absorb_qty}／季，闲置 {idle_qty}／季。` | 数量 ×3 |
| `note.staff_short` | 实施人员不足 | `{staff_kind}存量 {have_persons}，政策所需 {need_persons}，差 {gap_persons}；按结业队列最早补足第 {earliest_quarter} 季。` | 人 ×3、季 |
| `note.skill_mismatch` | 技能错配将限制效果 | `{region_name}{skill_tier}档可用 {have_persons}，岗位需求 {need_persons}，差 {gap_persons}。` | 人 ×3 |
| `note.feedback_late` | 反馈晚于任期或选举窗口 | `最早反馈第 {feedback_quarter} 季，晚于{horizon_name}（第 {horizon_quarter} 季）{gap_quarters}。` | 季 ×3 |
| `note.concentration` | 效果集中单一地区 | `{region_name}占本政策效果量 {share_pct}，集中度阈值 {threshold_pct}，超出 {gap_ppt}。` | 比率 ×3 |
| `note.irreversible` | 含不可逆支出 | `本草案含不可逆支出 {irrev_u}（{item_count} 项）；取消后不可收回部分 {sunk_u}。` | 钱 ×2、项数 |
| `note.opposition` | 主要集团反对且触及留任裕度 | `{bloc_name} 组织强度 {strength_pct}（阈值 {threshold_pct}）；当前留任裕度 {margin_ppt}（阈值 {margin_threshold_ppt}）。` | 比率 ×4 |
| `note.exit_lock` | 退出规则锁定 | `{policy_name} 处于最短存续期内，至第 {unlock_quarter} 季（还有 {remaining_quarters}）；提前撤回成本 {exit_cost_u}。` | 季 ×2、钱 |

### 5.5 出口短语模板库（`tpl.reason.exit.*`）

出口 = 可执行命令 + 代价 + 剩余缺口（`docs/20` RC-06/07/08）。

| tpl_id | 模板 |
|---|---|
| `tpl.reason.exit.scale_down` | `缩减规模至 {feasible_scale}（代价：{effect_delta_text}；缺口降至 {residual_gap}）` |
| `tpl.reason.exit.defer` | `改期至第 {target_quarter} 季（代价：最早反馈推迟 {delay_quarters}；缺口降至 {residual_gap}）` |
| `tpl.reason.exit.assign_source` | `指派来源：{source_name}（代价：{source_cost_text}；缺口降至 {residual_gap}）` |
| `tpl.reason.exit.borrow` | `发行债券 {issue_u}（代价：每季票息 {coupon_u}，第 {maturity_quarter} 季到期还本 {principal_u}；缺口降至 {residual_gap}）` |
| `tpl.reason.exit.cut_other` | `削减{other_item_name} {cut_u}（代价：{other_effect_text}；缺口降至 {residual_gap}）` |
| `tpl.reason.exit.cancel` | `撤回{subject_name}（代价：已付不可收回 {sunk_u}、残值 {residual_u}、赔偿 {penalty_u}；缺口降至 {residual_gap}）` |
| `tpl.reason.exit.wait` | `等待至第 {target_quarter} 季{window_name}（还有 {remaining_quarters}；届时缺口 {residual_gap}）` |
| `tpl.reason.exit.change_target` | `改选作用对象为{alt_target_name}（代价：{effect_delta_text}；缺口降至 {residual_gap}）` |
| `tpl.reason.exit.accept_arrears` | `接受欠付并进入支付排序（代价：第 {priority_rank} 档的{displaced_name}延付 {gap_u}；缺口降至 {residual_gap}）` |
| `tpl.reason.exit.recompute` | `需重新计算 ▸ 试算` （RC-07：无法计算 `residual_gap` 时的唯一合法写法） |

### 5.6 多条原因并列与折叠

| # | 规则 |
|---|---|
| RS-10 | 排序 `severity` BLOCK > GAP > NOTE；同级 `(最早触发季 升序, |缺口| 降序, 码字典序 升序)`，稳定（`docs/20` RC-11）。 |
| RS-11 | 同一 `subject_id` 上的同码原因合并为一条，`drivers` 累加；**不同码不合并**（不同码意味着不同处置路径）。 |
| RS-12 | drivers 金额降序最多 3 条，其余 `tpl.reason.drivers_more`「另有 {n} 项合计 {amount_u}」（`docs/20` RC-10）。 |
| RS-13 | 一个草案上的原因总数 > 6 时，前 6 条展开，其余折叠为 `tpl.reason.more`「另有 {n} 条原因 ▸」。**BLOCK 级永不折叠。** |
| RS-14 | 同一 Reason 在政策目录、政策卡、预算审查、确认框四处由同一渲染函数输出（`docs/20` RC-13）；文案侧断言：四处渲染结果字符串完全相等。 |

### 5.7 本节验收

| ID | 断言 |
|---|---|
| RT-AC-30 | 31 个码（30 + `blk.bloc_condition`）各有恰好一条行 2 模板；变体判据互斥穷举。 |
| RT-AC-31 | 每个码有 ≥1 个构造夹具能触发，并渲染出五行完整文案（`docs/20` AC-24(b) 的文案侧）。 |
| RT-AC-32 | 全部渲染结果中，行 2 含 `need/avail/gap` 三数字（三类例外除外）；行 4 每条出口含 `残余缺口` 或 `试算`。 |
| RT-AC-33 | 全部渲染结果不含 §4.7 空洞阻断词（含例外判定）。 |
| RT-AC-34 | 同一 Reason 在四个渲染点的输出字符串逐字相等（RS-14）。 |
| RT-AC-35 | 构造一个未登记 `reject_code` 的夹具：渲染 `tpl.reason.unmapped` **且**覆盖测试红灯（证明兜底不会静默通过）。 |

---

## 6 溯源格式

> 计划书 §13：**每条变化附带实体 ID、来源操作、金额／数量、时间和约束。**

### 6.1 溯源对象（五字段，缺一不得渲染）

```gdscript
class_name JwTrace extends RefCounted
var entity_id: StringName     # 实体 ID，符合 docs/11 §4 正则
var source_op: StringName     # 来源操作：命令 ID，或结算步 "S01".."S08" + log.ledger.kind
var amount_value: int         # 金额/数量的内部整数
var amount_kind: StringName   # "uu" | "uqs" | "persons" | "units" | "ppm"
var time_q: int               # 内部季索引
var constraint: StringName    # 约束：binding_code / arrears 原因 / 优先级档 / "none"
var citation: String          # §6.2
```

| # | 规则 |
|---|---|
| TR-01 | 五字段（entity / source_op / amount / time / constraint）**任一缺失即不得渲染**，`push_error`。 |
| TR-02 | `constraint == "none"` 时**必须显式写出**固定词 `无（本笔不受约束限制）`，**不得留空**。留空无法区分「没有约束」与「忘了填」。 |
| TR-03 | `source_op` 必须落在受控集合：命令 ID（`docs/11` §6.1）∪ `{S01..S08}` × `log.ledger.kind`（`docs/11` §5.3 的 28 个 kind）。自由字符串即缺陷。 |
| TR-04 | 溯源行是 `ACTUAL`（它描述既成分录），用裸引用码。 |
| TR-05 | `ACTUAL` 的每个数字**必须**能解析到至少一条 `JwTrace`；`DERIVED` 必须能解析到规则号 + ≥1 条输入 `JwTrace`；`PROJECTED` 不带 `JwTrace`（它没有分录）。 |

### 6.2 引用码文法

```
citation     = ledger_alias "#Q" quarter2 "." row
ledger_alias = "ldg." 1*( %x61-7A / "_" )        ; docs/20 §2.4 的 19 张台账之一
quarter2     = 2DIGIT                             ; 显示季号 00..40（00 = 开账）
row          = 3*6DIGIT                           ; 台账内 1 基行号，左侧补零到 3 位
```

正则（lint 用）：`^ldg\.[a-z_]+#Q(0[0-9]|[1-3][0-9]|40)\.[0-9]{3,6}$`

| # | 规则 |
|---|---|
| CT-01 | `ledger_alias` 必须在 `docs/20` §2.4 表内；表外别名即缺陷。 |
| CT-02 | `Q` 后为**显示季号**（内部 q + 1），开账分录 `q = −1` → `Q00`。 |
| CT-03 | 行号 1 基，与台账视图显示行号一致；点击后滚动定位并高亮该行（`docs/20` §2.4）。 |
| CT-04 | 引用码在文案中一律以 `▸` 前导（`▸ldg.cash#Q07.014`），等宽字体，不参与断行。 |
| CT-05 | 多条引用码用半角顿号分隔上限 3 条，超出折叠为 `等 {n} 条 ▸`。 |

### 6.3 溯源行模板（`tpl.trace.*`）

| tpl_id | 模板 |
|---|---|
| `tpl.trace.line` | `{entity_name}（{entity_id}） · {source_op_name} · {amount_text} · 第 {quarter} 季 · 约束：{constraint_name} ▸{citation}` |
| `tpl.trace.constraint_none` | `无（本笔不受约束限制）` |
| `tpl.trace.constraint_binding` | `产量受{bound_name}限制` |
| `tpl.trace.constraint_arrears` | `按支付优先级第 {priority_rank} 档，欠付 {amount_u}` |
| `tpl.trace.constraint_ration` | `按配给比例 {ration_pct} 分配` |
| `tpl.trace.constraint_queue` | `队列位次 {queue_slot}，占用至第 {release_quarter} 季` |
| `tpl.trace.rounding_gap` | `显示舍入差 {delta_u}（各项按 0.01 U 独立舍入所致；台账原值合计无残差）` |
| `tpl.trace.more` | `等 {count} 条 ▸` |
| `tpl.trace.inputs` | `输入：[[*items sep="、"]]{.citation}[[/]]` |

### 6.4 三类的溯源义务矩阵

| 类 | 必须有 | 禁止有 |
|---|---|---|
| `ACTUAL` | 裸引用码；可解析到 `JwTrace` 五字段 | 区间、情景名 |
| `DERIVED` | `^R-` 规则号 + `输入：` 后的引用码（≥1） | 裸引用码（`输入：`之前） |
| `PROJECTED` | 情景名 + 区间 + 到第 N 季 + 假设条数入口 | 任何台账引用码 |

### 6.5 本节验收

| ID | 断言 |
|---|---|
| RT-AC-40 | 全量渲染扫描：每个引用码匹配 §6.2 正则，且 `ledger_alias ∈ docs/20 §2.4`。 |
| RT-AC-41 | 构造开账分录夹具：渲染 `Q00` 与固定词「开账（第 0 季）」。 |
| RT-AC-42 | 构造 `constraint == none` 夹具：渲染固定词，且不出现空字段。 |
| RT-AC-43 | 抽样 50 条 `ACTUAL` 数字，逐条能解析到 `JwTrace` 五字段（TR-05）。 |
| RT-AC-44 | 构造分项舍入不闭合的夹具：渲染 `tpl.trace.rounding_gap`，且 `abs(delta_uu) ≤ 5_000 × n`（RD-03）。 |

---

## 7 反事实对比的标注规则

> 计划书 §13：**解释器不冒充因果识别。页面使用「模型中的限制因素」措辞，反事实对比标注其假设，不宣称识别了真实世界因果。**

### 7.1 允许出现的位置（穷举，其余位置出现即缺陷）

1. 诊断卡机制段之后的「若解除该限制因素」行（`tpl.derived.next_binding`）。
2. 季度报告小节四「模型中的限制因素」。
3. 预算审查 A2 情景对照（`docs/20` §8.3）。
4. 发展档案的分维说明（§8），且仅限模型内重算。

### 7.2 类的判定（决定它是 `DERIVED` 还是 `PROJECTED`）

| 条件 | 类 |
|---|---|
| 被改动的量全部是**已结算状态量**，且重算只用公开规则、不涉及未来外生量与行为假设 | `DERIVED`（`docs/20` §3.2 映射表：「解除紧约束后的次紧约束与新产量（假设其余项不变）」） |
| 改动涉及未来外生量、行为假设、未提交草案或随机抽样 | `PROJECTED`，**必带区间与情景名** |

### 7.3 强制三段式（顺序固定，缺段即缺陷）

```
段1 对比：{类前缀}{counterfactual_clause}，{metric_name}为 {alt_value}（当前 {actual_value}，差 {delta}）。{rule_id}
段2 假设：假设（{assumption_count} 条）：
         ① {assumption_text}（{param_or_field} = {value}，来源：{source_type}）
         ② …
段3 免责：本对比是模型内的重算，说明的是模型中的限制因素，不是对现实世界因果的识别。
```

| # | 规则 |
|---|---|
| CF-01 | 段 2 **≥1 条**假设，每条必须有 `param_or_field`、`value`、`source_type`。`source_type ∈ {观测, 文献, 设计假设, 派生计算}`（计划书 §14 的四类，`docs/11` §5.15 `ParameterCard`）。 |
| CF-02 | 段 3 是**逐字固定句**，不得改写、不得省略、不得只放进悬浮提示。 |
| CF-03 | 块标题固定为 `反事实对比（假设：{assumption_count} 条）`（`docs/20` §9.4 固定措辞）。 |
| CF-04 | 段 1 的条件从句只能用 `若{条件}` 或 `在{条件}下`，**禁止** `如果当初…就会…`、`原本可以`、`本应`。 |
| CF-05 | **禁止**对比两个都不是模型量的东西；`metric_name` 必须是 `docs/10` 变量字典中的量。 |
| CF-06 | 段 1 的假设摘要与段 2 的假设清单必须来自**同一数据对象**（§3.2 DG-11，L-08 断言）。 |
| CF-07 | **禁止**在反事实里做政策优劣结论（「说明先修电网更好」），受 DG-33 推荐禁用词约束。 |

### 7.4 模板库（`tpl.cf.*`）

| tpl_id | 模板 |
|---|---|
| `tpl.cf.header` | `反事实对比（假设：{assumption_count} 条）` |
| `tpl.cf.release_binding` | `推算 · 若{bound_name}不再是紧约束，在其余项不变的条件下，{region_name}{sector_name}产量为 {alt_qty}（当前 {actual_qty}，差 {delta_qty}）。{rule_id}` |
| `tpl.cf.no_project` | `推算 · 若不提交{project_name}，在其余项不变的条件下，第 {horizon_quarter} 季期末现金为 {alt_u}（当前方案 {actual_u}，差 {delta_u}）。{rule_id}` |
| `tpl.cf.opex_unfunded` | `推算 · 若{asset_name}的运行费不拨付，按规则实际可用率为 {alt_pct}（当前 {actual_pct}，差 {delta_ppt}）；已建资产不删除。{rule_id}` |
| `tpl.cf.scenario_pair` | `预测 · 同一方案在两种情景下：基线 {range_base}；不利条件 {range_adverse}（均到第 {horizon_quarter} 季）。假设 {assumption_count} 条 ▾` |
| `tpl.cf.assumption_item` | `{assumption_text}（{param_or_field} = {value}，来源：{source_type}）` |
| `tpl.cf.disclaimer` | `本对比是模型内的重算，说明的是模型中的限制因素，不是对现实世界因果的识别。` |

### 7.5 本节验收

| ID | 断言 |
|---|---|
| RT-AC-50 | 每一处渲染出 `tpl.cf.*` 的地方，同屏必然出现 `tpl.cf.disclaimer` 与 ≥1 条 `tpl.cf.assumption_item`。 |
| RT-AC-51 | `tpl.cf.disclaimer` 的渲染结果与模板串逐字相等（无变体、无截断）。 |
| RT-AC-52 | 反事实文案扫描：不含 §4.7 因果断言词（在扫描域内）、不含 CF-04 禁用句式、不含推荐词。 |
| RT-AC-53 | 构造一个涉及未来外生量的反事实夹具：其类为 `PROJECTED` 且带区间与情景名（CF §7.2）。 |

---

## 8 第 40 季发展档案

> 计划书 §04：**第 40 季形成发展档案；失去留任资格或财政重组失败时，执政提前结束。经济下滑本身不是立即失败。结算展示生活、分配、能力、韧性与政治结果，不以单一国力分数替代。**
> 版面、分区与控件断言见 `docs/20` §10.2。本节给文案与各维的指标口径。

### 8.1 五维定义（不可互相换算）

| 维 | 量纲 | 必须展示的指标（各维 3–4 项，均带口径） | 必须展示的分布 |
|---|---|---|---|
| **生活** | 指数 / 比率 / 人 | 消费与公共服务指数（基期=第 1 季）；家庭负担率；服务可及性；公共服务排队人数 | 家庭负担率的 ≥3 分位点，或 4 地区分解 |
| **分配** | 金额 / 比值 / 组数 | 可支配收入分位（P20 / P50 / P80）；分位比 P80/P20；受益组数与受损组数；地区间收入差 | 收入分位 ≥3 点 + 4 地区分解 |
| **能力** | 数量 / 人 / 比率 | 各部门可用产能；技能档人数分布；公共服务名义容量；税收覆盖率 | 4 部门分解 + 三技能档分解 |
| **韧性** | 季 / 金额 / 比率 | 触及现金底线的季数；未来四季到期集中度；冲击期间指标回落幅度与恢复季数；外部额度余量 | 40 季时间序列 + 冲击窗口标注 |
| **政治** | 比率 / 组数 | 支持度（分 4 地区）；三个集团组织强度；程序信任；留任判定结果与判据数值 | 4 地区支持度分解 + 三集团分解 |

| # | 规则 |
|---|---|
| AR-01 | 五维**不合成总分**，也**不做跨维加权**。档案页首固定句 `tpl.archive.no_score` 必须渲染。 |
| AR-02 | 每维末尾固定句 `tpl.archive.dim_no_score`：`本维度不与其他维度合成为单一分数。` |
| AR-03 | **禁用词**：`总分`、`综合评分`、`国力`、`评级`、`星级`、`排名`、`得分`、`通关`、`胜利`、`失败`（§4.7）。执政结束只用 `tpl.archive.early_*` 的规则化表述。 |
| AR-04 | **分配维禁用** `基尼系数`（计划书 §14：不从平均群组收入输出精确基尼系数）。改用分位与分位比，并必须渲染 `tpl.archive.dist_caveat`。 |
| AR-05 | 每个维度的每个指标都必须带 §1.4 口径（单位、存/流、期间、价格基期、分母、指数基期），走 `docs/20` §4.1 的数字三件套。 |
| AR-06 | 档案文案中的**变化**一律 `ACTUAL`（40 季既成事实）；**解释性归因**一律 `DERIVED` 且受 §7 反事实规则约束；**不得出现 `PROJECTED`**（游戏已结束，没有下季）。 |

### 8.2 模板库（`tpl.archive.*`）

| tpl_id | 模板 | 类 |
|---|---|---|
| `tpl.archive.title` | `澄湾共和国 · 发展档案 · 第 {quarter} 季` | — |
| `tpl.archive.no_score` | `本档案由五个不可互相换算的维度组成，不产生总分，也不做跨维度加权。` | — |
| `tpl.archive.dim_no_score` | `本维度不与其他维度合成为单一分数。` | — |
| `tpl.archive.living` | `实记 · 第 {quarter} 季消费与公共服务指数 {living_index}（基期=第 1 季，开局 100.0）；家庭负担率中位 {burden_median_pct}；服务可及性 {access_pct}；排队 {queue_persons}。 ▸{citation}` | `ACTUAL` |
| `tpl.archive.living_span` | `实记 · 四十季间，家庭负担率最高出现在第 {peak_quarter} 季（{peak_pct}），最低第 {trough_quarter} 季（{trough_pct}）。 ▸{citation}` | `ACTUAL` |
| `tpl.archive.dist` | `实记 · 可支配收入 P20 {p20_u}、P50 {p50_u}、P80 {p80_u}；分位比 P80/P20 为 {ratio}。受益群组 {gainer_count} 个，受损群组 {loser_count} 个（口径：与第 1 季实际可支配收入比较）。 ▸{citation}` | `ACTUAL` |
| `tpl.archive.dist_caveat` | `分配结果按群组间差距与收入分位近似给出；本模型没有模拟组内全部差异，不输出基尼系数。` | — |
| `tpl.archive.capacity` | `实记 · 各部门可用产能：农业 {cap_agri}、制造 {cap_manu}、能源 {cap_energy}、服务 {cap_services}；技能档人数 低 {low_persons}／中 {mid_persons}／高 {high_persons}；税收覆盖率 {coverage_pct}。 ▸{citation}` | `ACTUAL` |
| `tpl.archive.resilience` | `实记 · 四十季中触及现金底线 {floor_quarters}；到期最集中的一季为第 {peak_quarter} 季（本息 {peak_u}）；外部额度余量期末 {credit_left_u}。 ▸{citation}` | `ACTUAL` |
| `tpl.archive.shock_recovery` | `实记 · {shock_name} 发生于第 {shock_quarter} 季，持续 {shock_quarters}；{metric_name} 回落 {drop_pct}，回到冲击前水平用了 {recovery_quarters}。 ▸{citation}` | `ACTUAL` |
| `tpl.archive.shock_none` | `实记 · 本局未发生该类外生冲击。` | `ACTUAL` |
| `tpl.archive.politics` | `实记 · 期末支持度：北原 {sup_beiyuan}、中州 {sup_zhongzhou}、海岬 {sup_haijia}、西岭 {sup_xiling}；程序信任 {trust_pct}；集团组织强度：农业合作联盟 {bloc_agri}、工商业联盟 {bloc_business}、劳动与公共服务联盟 {bloc_labor}。 ▸{citation}` | `ACTUAL` |
| `tpl.archive.retention` | `实记 · 第 {election_quarter} 季留任判定：{verdict_word}；判据 {rule_id}，当时判定值 {value}，阈值 {threshold}。 ▸{citation}` | `ACTUAL` |
| `tpl.archive.limiting_factors` | `推算 · 四十季中出现次数最多的模型限制因素：[[*items sep="、"]]{.name}（{.count}）[[/]]。各项不可相加，也不合成排名分数。{rule_id} 输入：{citations}` | `DERIVED` |
| `tpl.archive.early_end` | `实记 · 执政于第 {quarter} 季提前结束。触发条款 {rule_id}；触发季第 {quarter} 季；当时判定值 {value}（阈值 {threshold}）。 ▸{citation}` | `ACTUAL` |
| `tpl.archive.early_end_note` | `经济下滑本身不触发执政结束。触发条件为：{retention_rule_expr} 或 {restructure_rule_expr}。` | `DERIVED` |
| `tpl.archive.goal_recap` | `实记 · 开局选定的任期目标：{goal_name}。共同约束的履行情况：基本服务断供 {outage_quarters}；债务承诺披露 {disclosure_count} 次。 ▸{citation}` | `ACTUAL` |

> `verdict_word ∈ {留任, 未留任}`（受控词表）。**不得**写「胜利」「失败」「通关」。

### 8.3 本节验收

| ID | 断言 |
|---|---|
| RT-AC-60 | 第 40 季夹具：渲染 5 个维度区块，各含 ≥3 个带口径的指标与 ≥1 个分布；渲染 `tpl.archive.no_score` 与 5 条 `tpl.archive.dim_no_score`。 |
| RT-AC-61 | 两类提前结束夹具（失去留任资格 / 财政重组失败）：首屏渲染 `tpl.archive.early_end` 三项（条款 ID、触发季、判定数值）与 `tpl.archive.early_end_note`。 |
| RT-AC-62 | 档案全量文案扫描：不含 AR-03 禁用词，不含 `基尼系数`，不出现任何 `预测 · ` 前缀（AR-06）。 |
| RT-AC-63 | 构造「未发生冲击」夹具：渲染 `tpl.archive.shock_none`，不留空区块。 |

---

## 9 文案工程：资源、lint 与覆盖

### 9.1 唯一真源

- 玩家可见中文**只在** `content/text/*.json`。代码只持 `tpl_id` 与槽位。
- 名表 `terms_zh_cn.json` 是 `label` 类槽位的唯一来源；剧本英文 ID → 中文名的映射只此一处。
- 模板文件带 `schema_version` 与 `content_hash`，进存档 manifest（与 `docs/11` §6.3 一致），保证「同一存档回放渲染出同样的报告」。

### 9.2 lint 流水线（`tools/lint_text.gd`，CI 必跑）

| ID | 检查 | 失败即 |
|---|---|---|
| L-01 | 模板结构：`tpl_id` 唯一；占位符闭合；槽位在字典内；无死槽位；变体判据互斥且穷举 | P0 |
| L-02 | 禁用词：§4.7 全部词表 + §2.8 终局词 + DG-33 推荐词，含例外判定 | P0 |
| L-03 | 三类措辞：MX-01..MX-12（模板串 + 夹具渲染快照两遍） | P0 |
| L-04 | 代码中无中文字符串字面量：扫 `res://{sim,systems,application,ui}/**/*.gd` 的字符串字面量匹配 `[一-鿿]`（注释豁免） | P0 |
| L-05 | 无运行期拼句：`res://{ui,application}/` 中 `Label.text` / `RichTextLabel.text` 的赋值右侧只允许 `JwText.render(...)` 或常量；槽位值上无算术运算符 | P0 |
| L-06 | 模板串中无未登记数字字面量（PH-08） | P1 |
| L-07 | 内部标识符不外泄：渲染结果中不出现 `det.`、`mech.`、`root_key`、`rank_int`、`reason.`、`E_`、`ldg.` 之外的命名空间前缀 | P1 |
| L-08 | 假设同源：诊断卡机制段的假设摘要与反事实段 2 的假设清单指向同一数据对象 | P1 |

### 9.3 覆盖测试（`tests/text/`）

| 测试 | 断言 |
|---|---|
| `test_template_coverage` | 每个 `det.*` 有简报模板；每个 `mech.*` 有诊断变体；每个 `reject_code` 有原因模板；每个 `log.ledger.kind` 有溯源 `source_op` 名称 |
| `test_render_snapshot` | 固定夹具 → 渲染结果与黄金快照逐字相等；快照文件进版本库，差异必须人工审阅 |
| `test_determinism` | 同一存档回放两次，全部报告文本逐字相等（计划书 §12 重放承诺的文案侧） |
| `test_no_orphan_template` | 每条模板至少被一个夹具渲染过（死模板即缺陷） |

---

## 10 验收清单汇总

| 区 | 条目 |
|---|---|
| 风险排序 | RT-AC-01 … RT-AC-07 |
| 诊断 | RT-AC-10 … RT-AC-15 |
| 三类措辞 | RT-AC-20 … RT-AC-23 |
| 原因文案 | RT-AC-30 … RT-AC-35 |
| 溯源 | RT-AC-40 … RT-AC-44 |
| 反事实 | RT-AC-50 … RT-AC-53 |
| 发展档案 | RT-AC-60 … RT-AC-63 |
| 工程 | L-01 … L-08；`tests/text/` 四项 |

**缺陷分级**（沿用计划书 §17）：错账、错类（把 `PROJECTED` 标成 `ACTUAL`）、渲染出兜底原因模板 = **P0**；
缺证据、缺出口、缺假设 = **P1**；措辞冗长、折叠阈值不合适 = **P2**。

---

## 11 待决问题

| # | 问题 | 影响 | 阻塞级别 |
|---|---|---|---|
| RT-OQ-01 | 文案资源的路径与格式：`docs/20` RC-01 写 `content/ui/reasons_zh_cn.tres`，本文取 `content/text/reasons_zh_cn.json`（要可 diff、可正则 lint） | 两份文档必须同口径 | 需一次裁决 |
| RT-OQ-02 | §2.7 RB-12「每域至多 2 席」是本文增补，`docs/20` §7.1.5 只说「取前 3 条」 | 简报选卡结果 | 需与 `docs/20` 作者确认；建议 20 §7.1.5 第 3 条补一句 |
| RT-OQ-03 | `blk.bloc_condition` 为增补码（对应 `docs/12` 的 `E_BLOC_VETO`），`docs/20` §9.6 把政治条件并入 `blk.authority` | 原因码表从 30 变 31；AC-24 覆盖 | 需与 `docs/20` 作者确认 |
| RT-OQ-04 | 部门产出单位的中文标签（`单位电力` 等）需剧本提供 `sector.unit_label_zh` | `fmt_qty` 全部输出 | 剧本配置 |
| RT-OQ-05 | 十个检测器阈值、`param.brief.urgency_horizon_q`、`param.brief.pop_weight_floor_ppm`、`param.diag.flat_band_*` | §2 全部判据 | 参数登记（`docs/14`） |
| RT-OQ-06 | `intervenability` 需要对 12 条政策各做一次资格 dry-run；每季一次的成本需实测（`docs/20` §5.5 线程契约 + 计划书 §17 性能门槛 0.5 s 中位） | 简报生成耗时 | G4 实测；超标则改为「按域预筛」 |
| RT-OQ-07 | `reject_code` 的真实 `E_*` 穷举表尚未见到（`docs/20` §18 第 5 条同问题） | §5 的映射与 RT-AC-31 | 需 `docs/12` 补穷举表 |
| RT-OQ-08 | 「留任裕度」`margin_ppt` 的定义（席位转换规则下的裕度如何量化） | `note.opposition`、`tpl.projected.retention_margin`、档案政治维 | 变量字典 + 结算合同 |
| RT-OQ-09 | 「四季」口径（含本季 / 不含本季）尚未统一（`docs/20` §18 第 1 条） | §5 全部 `{q_from}–{q_to}` 模板 | 随 20 的裁决走，本文不另立 |
| RT-OQ-10 | 黄金快照测试的维护成本：模板一改，快照全红 | `test_render_snapshot` | 建议快照按模板分文件存放，改一条只红一个文件 |

---

## 附录 A · 模板计数

| 域 | 条数 | 出处 |
|---|---|---|
| `tpl.brief.*` | 14 | §2.8 |
| `tpl.diag.*` | 17 | §3.5 |
| `tpl.actual.*` | 12 | §4.3 |
| `tpl.derived.*` | 13 | §4.4 |
| `tpl.projected.*` | 11 | §4.5 |
| `tpl.reason.*` | 31 行 2 模板 + 10 出口 + 3 辅助 | §5.2—§5.5 |
| `tpl.trace.*` | 9 | §6.3 |
| `tpl.cf.*` | 7 | §7.4 |
| `tpl.archive.*` | 17 | §8.2 |

任务书要求「三类措辞每类至少 8 条模板」：实际 12 / 13 / 11，均满足。

## 附录 B · 一个完整渲染样例（排版夹具，数值非参数提案）

```
第 07 季简报 · 优先风险 2 项（阈值内共 5 项）

┌ 供电 · 海岬 ────────────────────────────────────────────────
│ 实记 · 第 07 季海岬制造增加值为 3.42 U，较上季恶化 ▼ 0.28 U。 ▸ldg.value_added#Q07.006
│ 先核查：
│   约束诊断（1 行，缺口 2.10 单位电力） ▸ldg.constraint#Q07.014
│   服务容量与可及性（可用率 82.0 %）   ▸ldg.service#Q07.031
│   库存对账（燃料期末 0.90 Q_energy）  ▸ldg.inventory#Q07.077
│ 推算 · 模型中的限制因素：海岬制造的可用供电服务。五项约束中电力最紧，其余项本季未触顶。
│        假设：其余四项约束按本季实际值不变。[M-POWER-01] ^R-PROD-03
│        输入：ldg.constraint#Q07.014、ldg.service#Q07.031
│ 推算 · 五项约束（同一产品口径）：计划 4.00、产能 3.80、劳动 3.95、能源 3.42、材料 4.10；
│        实际 3.42。各项不可相加。 ^R-PROD-03
│ 同一限制因素的其他表现：海岬制造产出下降。
│ 按规则，本季已处于 供电可用率下限 之内。 ^R-DIAG-POWER
│ 影响人口 500.0 万人（占全国 20.8 %）。
│ 以下选项按最早反馈季排列，不代表推荐顺序。
│   ① 电网可靠性升级（海岬）：一次性 4.00 U，每季 0.02 U，最早反馈第 15 季。
│   ② 设备投资补助（海岬·制造）：一次性 0.60 U，每季 0.00 U，最早反馈第 09 季
│      （当前不可提交：本季应付 0.60 U，已指派 0.00 U，未指派 0.60 U。）
│   该动作改变的是条件，不直接产生产出或支持率。
│ 反事实对比（假设：2 条）
│   推算 · 若电力不再是紧约束，在其余项不变的条件下，海岬制造产量为 3.80 Q_manu
│          （当前 3.42 Q_manu，差 0.38 Q_manu）。^R-PROD-03
│   假设（2 条）：
│     ① 其余四项约束按本季实际值不变（flow.cell.bound_* = 本季值，来源：派生计算）
│     ② 需求预期按上季滞后值不变（flow.cell.output_plan_uqs = 4.00，来源：设计假设）
│   本对比是模型内的重算，说明的是模型中的限制因素，不是对现实世界因果的识别。
└──────────────────────────────────────────────────────────
```
