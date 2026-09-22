# 15 / 模块切分与并行实现边界

本文件是**实现期的分工契约**。计划书 §12 规定了四层职责与禁止事项，本文件把它落到具体文件，
使多名实现者（或多个智能体）可以并行工作而不互相踩踏。

规则：**一个文件只有一个负责人。** 跨文件的需求只能通过下面登记的公开接口表达，
不允许「顺手改一下别人的文件」——那是耦合失控的起点（计划书 §18 的第一条风险信号）。

## 分层与禁止事项（计划书 §12，原文约束）

| 层 | 职责 | 禁止事项 |
|---|---|---|
| `sim/` SimCore | 状态、结算、账户、政策和领域规则 | 不得依赖场景树、UI 节点和叙事文案 |
| `application/` + `systems/` | 命令检查、回合调度、存档、重放 | 不得绕开资金与政策权限校验 |
| `ui/` Presentation | 地图、表格、图表、报告与输入 | 不得直接修改 GDP、民意或库存 |
| `content/` Content | 剧本、政策、冲击、参数与本地化 | 不得隐藏不可追溯的脚本副作用 |

强制检查：`sim/` 下任何文件出现 `Node`、`Control`、`get_tree()`、`SceneTree`、`tr(` 即为违规，
由 `tools/layer_check.py` 在闸门里机器检查。

## 模块清单

### 基础设施（最先实现，所有人依赖）

| 文件 | 职责 | 关键点 |
|---|---|---|
| `sim/jw_units.gd` | 单位常量与换算 | `U_SCALE = 1_000_000`、`PPM = 1_000_000`、各部门 `Q_s` 定义 |
| `sim/jw_math.gd` | 整数定点算术 | `floor_div`、`mul_ppm`、`split_largest_remainder`、乘法前缩放、溢出检查 |
| `sim/jw_ids.gd` | 稳定 ID 与索引 | ID 字符串 ↔ 稠密整数下标的双向映射，热路径只用下标 |
| `sim/jw_result.gd` | 结果与错误码 | 所有可失败操作返回 `{ok, code, detail}`，**禁止静默改账** |

### 状态与账本

| 文件 | 职责 |
|---|---|
| `sim/state/sim_state.gd` | 权威状态根；`to_dict()` / `from_dict()` / `state_hash()` |
| `sim/state/rng_streams.gd` | 命令流与冲击流**分离**的确定性随机（计划书 §12：多写一句新闻不得改变经济抽样） |
| `sim/ledger/account.gd` | 账户实体（存量） |
| `sim/ledger/ledger.gd` | 复式账本：每笔交易双边入账，残差恒为 0 |
| `sim/ledger/bond_book.gd` | 债券批次：面值/票息/期限/债权人/季度票息/到期本金，逐批次计息 |
| `sim/ledger/treasury.gd` | 国库现金、支付优先级、欠付、延期、重组减记 |

### 实体与机制

| 文件 | 职责 |
|---|---|
| `sim/population/population.gd` | 36 群组；人口守恒；出生/死亡/成年/退休/技能队列 |
| `sim/population/migration.gd` | 迁移：受职位、住房与迁移成本约束，来源去向必须一致 |
| `sim/population/labor_market.gd` | 就业匹配、技能错配、失业统计（分母是劳动力） |
| `sim/sectors/io_table.gd` | 投入产出技术系数 |
| `sim/sectors/inventory.gd` | 库存恒等式：期末 = 期初 + 生产 + 购入 − 售出 − 生产耗用 − 损耗 |
| `sim/sectors/capital.gd` | 生产资本、折旧、维护；**完工资产下一季才供能** |
| `sim/sectors/pricing.gd` | 有界平滑的下一季价格调整，同季不得循环放大 |
| `sim/sectors/sector_model.gd` | `Q_actual = min(Q_plan, Q_capacity, Q_labor, Q_energy, Q_materials)`；系数为零跳过该约束 |
| `sim/projects/project_queue.gd` | 建设队列、履约进度、按进度付款；**付款不得直接制造进度** |
| `sim/projects/asset_commissioning.gd` | 完工判定、投运、未完工残值、合同赔偿 |
| `sim/policy/policy_def.gd` | 政策定义的运行时表示 |
| `sim/policy/policy_engine.gd` | 资格 → 预算预留 → 生效 → 运行费 → 退出 |
| `sim/politics/interest_groups.gd` | 3 集团的成员规模与组织资源随经济结构动态推导 |
| `sim/politics/politics.gd` | 选票 / 组织影响力 / 行政能力**分开计算**；预算审查与留任判定 |
| `sim/world/world_market.gd` | 出口需求、进口交付能力、外部信用额度、固定汇率 |
| `sim/world/shocks.gd` | 3 类外生冲击的抽样与传导（用冲击流，抽样写日志） |
| `sim/report/diagnostics.gd` | 约束诊断与溯源；区分「已经发生 / 规则推断 / 情景预测」 |

### 调度与应用层

| 文件 | 职责 |
|---|---|
| `systems/commands.gd` | 命令定义、序列化、合法性校验 |
| `systems/turn_runner.gd` | 计划书 §13 的 8 步固定顺序结算 |
| `systems/event_engine.gd` | 12 事件模板的条件求值（**不是随机弹窗**） |
| `systems/content_loader.gd` | 加载并校验 `content/*.json`，缺字段即拒绝启动 |
| `systems/saves.gd` | `schema_version` / `content_hash` / 回合 / 状态 / 随机流状态 |
| `application/game.gd` | 应用层门面：UI 只能通过它读状态、投命令 |
| `application/replay.gd` | 命令流 + 冲击流重放；同构建同种子同命令 ⇒ 逐位相同 |

## 并行实现的接口纪律

1. **先骨架后实现**：`sim/` 与 `systems/` 的全部类名、成员、方法签名先一次性定稿（带类型、带文档注释、空实现），
   通过解析闸门后才允许并行填充实现体。填充者**不得修改签名**；确需修改，登记为接口变更请求，由一人统一改。
2. **测试与实现分离**：测试作者依据 `docs/12_simulation_contract.md` 与骨架签名独立写测试，
   不看实现体。测试与实现不一致时，先判定契约怎么说，而不是改测试迁就实现。
3. **热路径不分配**：季度结算内禁止新建对象与字典；状态用稠密数组 + 整数下标。
   这是 §17 性能门槛（中位数 < 0.5 s）的实现前提。
4. **一切失败显式化**：任何不能完成的操作返回错误码并登记欠付/延期/取消，
   绝不静默改账，也绝不在回合结束后打「平衡修正」补丁（计划书 §13 明令禁止）。
