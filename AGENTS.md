# 经纬 · 协作接手手册（AGENTS.md）

给接手本工程的智能体（Codex、Claude 等）与人。做校对、重新设计、生成图片资源或任何改动之前先读这一份。
**这是活文档**：谁改了工程，谁在文末「交接日志」追加一条；规则、命令或目录变了，同步改正文。

- 工程根：`C:\Users\Fiber Memory\Documents\Jingwei`（下文路径都相对于它）
- 引擎：Godot 4.7.2-stable + 带类型 GDScript（锁定，见 `docs/ENGINE.md`）
- 最后更新：2026-09-22（Codex：400 年方向与协作交接）

## 当前方向提示（2026-09-22，先读）

- **用户已明确改为1600—2000年的400年国家发展游戏**，要求科技树、跨时代建筑选择与升级，尽可能复用现有工程。原40季现代治理版保留为当前运行实现与复用基础，不再作为最终产品范围。
- 改造提案：`docs/_drafts/50_four_centuries_redesign.md`；动态分工、待决项与给Claude的咨询包：`docs/51_codex_claude_handoff.md`。接手时读这两份，完成相关任务后同步交接状态。
- Codex主责图片资源、玩法/文本审视与可玩性指导；Claude 已于 2026-09-22 完成 M0 技术评审（`docs/_drafts/52_claude_m0_technical_review.md`）并接受核心实现分工（SimCore、schema、长局存档与性能、界面代码与资源接入）。**用户已于 2026-09-22 批准重构并拍板 U-1—U-8，总计划见 `docs/53_refactor_master_plan.md`，Claude 正在执行 M1**（每个里程碑结束停下交用户检查）。
- 用户已确认：正常施政持续控制，严重治理失败或可避免的重大军事失败才可能结束；发展为主，外交贸易与抽象战争；建筑卡片/列表，玩法参考《维多利亚3》。具体危机阈值、六阶段与内容数量仍是设计提案，不是已实现功能。
- 本轮仅改规划和交接文档，不改现行结算契约。具体新规则实施前仍须在docs/18裁定并更新契约。旧G5不再作为当前默认推进顺序，先完成新方向的技术评审与可玩切片。
- 原下载授权、资源人工初审、禁止擅自提交/推送的要求继续有效；应用图标与exe暂缓规则保留，但不能据此继续优先完善已改变方向的旧产品。

---

## 0 先读这四条

1. **权威顺序**：`docs/18_rulings.md`（裁定）＞ `docs/10`—`docs/17`（契约）＞ 计划书 `docs/ref/plan_v1.0.txt` ＞ 其余。
   界面以 `docs/20` 为准，报告文案模板以 `docs/21` 为准，新手引导以 `docs/22` 为准，质量门以 `docs/30` 为准。
2. **不提交、不下载**：仓库至今零提交，除非用户明确要求，不要 `git commit` / `push`。
   任何下载（导出模板、字体、图片素材、依赖包）都要先问用户，说明文件名、来源和大小。
3. **改完自证**：按 §6 跑验证清单；截图类改动要真的截图并看过。「测试通过」要写明数字。
4. **动工前登记**：在文末交接日志追加一条「进行中」，写明要改哪些文件；做完改成「完成」，写验证结果与遗留。

---

## 1 现状（一屏）

- 单人回合制国家治理模拟：架空国家「澄湾共和国」，40 季、4 地区、36 群组、4 部门、12 政策、12 事件、3 类外部冲击。
- 里程碑：G0 契约 ～ G4 可玩界面全部完成；G5 剩三项：Windows exe、真人试玩（5 名测试者）、性能登记（协议缺陷，见日志）。
- **打包暂缓**（用户 2026-09-21 决定）：先由 Codex 交付图片资源 → 用户手动初审 → 再决定是否下载导出模板、生成 exe。
  在那之前不要下载导出模板、不要生成 exe，也不要把未经初审的资源接进 `project.godot` 或导出预设。详细进度与已知差异：`docs/40_status_roadmap.md`；发布前置：`docs/41_release_checklist.md`。
- 全量测试 540 项全绿（23 个文件）；无冲击 40 季基线达标（零欠付、审查赤字率最高 0.09、两次选举留任）。
- 发布文档草稿与样例存档在 `release/`。

---

## 2 环境与命令

Windows 11。Git Bash 与 PowerShell 都能用；下面用 Bash 写法。先 `source tools/env.sh`，得到 `$GODOT`（引擎路径）与 `$JW`（工程根）。

| 做什么 | 命令 |
|---|---|
| 总闸门（分层 + 解析 + 全量测试） | `bash tools/gate.sh` |
| 解析闸门（每个 .gd 可编译、可实例化） | `bash tools/check.sh` |
| 分层闸门（sim/ 无 float、无场景树、无 UI） | `python tools/layer_check.py` |
| 测试 | `bash tools/test.sh [--suite=unit\|replay\|scenario\|stress\|ui] [--filter=关键词] [--verbose]` |
| 内容闸门 | `python tools/validate_content.py`；新增参数卡后 `python tools/build_param_registry.py`（重生成 `registry.json` 与 `docs/14`） |
| 刷新类缓存（新增或改名 `class_name` 后必须） | `"$GODOT" --headless --path . --import` |
| 运行游戏 | `"$GODOT" --path . -- --jw-autostart=1000000`（可加 `--ui-scale=1.25`、`--window-size=1366x768`、`--jw-goal=0\|1\|2`） |
| 截图（必须开窗，不能 `--headless`） | `"$GODOT" --path . --windowed --resolution 1600x900 --script res://tools/capture_ui.gd -- 输出.png [等待帧=90] [推进季数=0] [页面] --jw-autostart=1000000` |
| 界面冒烟（走完 40 季） | `"$GODOT" --headless --path . --script res://tools/ui_snapshot.gd -- --smoke --full` |
| 无冲击基线 | `"$GODOT" --headless --path . --script res://tools/diag_baseline.gd -- 40 1000000 99 noshock` |
| 单一政策干预 | `"$GODOT" --headless --path . --script res://tools/diag_intervention.gd -- p01_up@3`（或 `eNN@季`、`lNN_r@季`） |
| 样例存档 | `"$GODOT" --headless --path . --script res://tools/make_sample_saves.gd`，再把 `%APPDATA%\Godot\app_userdata\经纬 Jingwei\saves\sample_*` 拷进 `release/saves/` |
| 资源包导出（不需要导出模板） | `"$GODOT" --headless --path . --export-pack "Windows Desktop" build/x.pck`；试跑：`"$GODOT" --main-pack build/x.pck -- --jw-autostart=1000000` |
| 性能基准 | `"$GODOT" --headless --path . --script res://tools/bench_quarter.gd [-- --profile=full]` |

截图的「页面」参数：`overview` / `region` / `policy` / `society` / `report`；`页面@节点标记`（滚到该节点，如 `overview@TrendCharts`）；
`term:<术语>`（打开术语卡，如 `term:slot`）；`rules:<1-13>`（规则手册定位到某节）；`overlay:<覆盖层>[@节点标记]`（如 `overlay:archive@DimPolitics`）。

其他诊断脚本都在 `tools/diag_*.gd`，文件头第一行写着用途与参数。
Python 输出中文时设 `PYTHONIOENCODING=utf-8`，否则控制台乱码。

---

## 3 目录地图

| 路径 | 内容 | 改动须知 |
|---|---|---|
| `sim/` | SimCore：状态块、账本、部门、人口、政策、项目、政治、外部世界。整数定点 | 规则变更先写裁定（§4） |
| `systems/` | 回合执行器（8 步结算）、命令、内容加载器、事件引擎、存档 | 同上 |
| `application/` | `JWGame` 门面（界面唯一入口）、重放 | 界面需要的新数据在这里加只读方法 |
| `ui/` | 界面：`main.gd` 外壳；`core/`（会话、读模型、目录、文案、主题、格式化）；`pages/` 五页；`overlays/` 覆盖层；`components/` 组件；`shell/` 顶栏与底部固定区；`onboarding/` 新手引导 | 只读渲染，不算数 |
| `ui/text/zh_cn/*.json` | **全部界面文案**（13 个文件，`{"t": {key: 文本}}`） | 校对主战场 |
| `ui/theme/palette.json` | 色板唯一来源（token → hex、kind、allowed_on） | 改色先读 docs/20 §12 |
| `ui/config/ui_config.json` | 界面暂定量（地区主题短语、情景定义、诊断阈值、地区多边形轮廓……），每项带 `pending_owner` | 不进内容指纹 |
| `content/` | 剧本、12 政策、12 事件、3 冲击、参数卡（`parameters/params_core.json`） | **改任何文件都会改内容指纹**（§4） |
| `tests/` | `unit` / `scenario` / `replay` / `stress` / `ui`；框架在 `tests/framework/jw_test.gd` | 测试文件名 `*_test.gd`，方法 `test_*` |
| `tools/` | 闸门脚本、诊断脚本、截图、基准、样例存档、Python 离线校验 | |
| `docs/` | 契约与规格（见 §3.1）；`docs/_drafts/` 草稿与旧截图；`docs/ref/` 计划书原件 | |
| `release/` | 发布文档（指南、版本说明、已知限制、反馈表）与样例存档 `release/saves/` | |
| `build/` | 导出产物（不入库、导出过滤排除） | |

### 3.1 文档索引

| 文档 | 用途 |
|---|---|
| `docs/10_variable_dictionary.md` | 全部状态 / 流量 / 派生量的 ID、单位、写入步骤、不变量 |
| `docs/11_data_contract.md` | 内容与存档的数据格式、命令表（§6.1） |
| `docs/12_simulation_contract.md` | 8 步结算合同；§17 是逐轮增补条目 |
| `docs/13_open_questions.md` | 待决问题登记 |
| `docs/14_parameter_registry.md` | 参数登记表（**生成物，勿手改**） |
| `docs/15`、`16`、`17` | 模块切分、外部世界设计、API 骨架（状态数组表） |
| `docs/18_rulings.md` | **裁定记录，最高优先级**：R-xxx-NN，按轮次追加 |
| `docs/20_ui_spec.md` | 界面与信息架构规格（组件、布局、禁止事项 §15、验收 §16） |
| `docs/21_report_templates.md` | 季度报告与解释文案的规则模板、措辞纪律 |
| `docs/22_onboarding.md` | 前四季引导、试玩协议、记录表 |
| `docs/30`、`31` | 质量门与测试矩阵；恶意玩家（对抗）测试目录 |
| `docs/40`、`41` | 进度路线图、发布清单（活文档） |
| `docs/ENGINE.md` | 引擎版本锁定、参考机登记 |

---

## 4 铁律（违反即缺陷；多数有测试或静态检查拦截）

| 规则 | 说明 | 谁拦截 |
|---|---|---|
| 整数定点 | SimCore 不得有 float 影响状态。货币 μU（1 U = 1 000 000 000 μU），比率 ppm，实物 μQ。拆分用 `JWMath.split_lr_into`，各项之和必须精确等于原额 | `layer_check.py` |
| 确定性 | 同构建 + 同种子 + 同命令流 ⇒ 逐位相同。随机只走 `JWRngStreams`；读系统时钟只允许用于诊断（如 `JWTurnRunner.step_us`），不得影响结算 | 重放测试、存读档往返 |
| 分层 | `ui/` 只能经 `JWGame` 访问模拟；界面不自行计算数值（docs/20 B-02），要算的放 `JwReadModel` 或 `JWGame` | `test_ui_code_only_touches_sim_through_jwgame` |
| 文案外置 | `ui/*.gd` 的字符串里不得出现汉字（标点可以）；文案一律进 `ui/text/zh_cn/*.json`；key 全局不重复；模板槽 `{name}` 渲染时必须齐全 | `test_no_cjk_string_literals_in_ui_code`、`test_literal_text_keys_exist` |
| 色板 | 只用 `palette.json` 的 token；遵守 `allowed_on`（例：`series.*` 只能画在 `bg.abyss` 上）；赭色只表示风险（docs/20 §12 赭色禁令） | 评审 |
| 三类信息 | 实（已结算，可追到台账）/ 算（按公开规则推出）/ 预（依赖未来，带区间）不得混在同一格；用 `JwUi.class_line` 与 `JwInfo.Cls` | 界面测试 |
| 内容指纹 | `content/` 下任何文件改动（含重新排版 JSON）都会改内容指纹 ⇒ 旧存档只读 ⇒ **必须重生成 `release/saves/`** | 存档读取 |
| 新参数 | `params_core.json` 加九字段卡 → `JWUnits.Param` 枚举**末尾追加**并改 `PARAM_N` → `content_loader.gd` 的 `PARAM_IDS` 同序追加 → 跑 `build_param_registry.py` | 加载器覆盖率检查 |
| 新状态 | 所属块的 `STATE_ARRAY_IDS` / `STATE_ARRAY_SUBSYS` 末尾追加，补 `allocate` / `state_array` / `set_state_array`；在 docs/10、docs/17 登记 | 哈希与存档测试 |
| 规则变更 | 先在 docs/18 写裁定（编号、问题、裁定、测试），再在 docs/12 §17 追加合同条目 | 评审 |
| 测试纪律 | 用例执行中出现运行错误（脚本错误、格式化失败、push_error）即判失败；故意触发的用例设 `expected_engine_errors` | 测试运行器 |
| 节点标记 | `JwUi.tag(节点, "标记")` 写入 `jw_id`，测试、新手引导、截图工具靠它定位；改名前全仓搜索 | 界面测试 |
| 界面禁止事项 | 不做单一综合分数、不合成「瓶颈指数」、不无原因置灰、不隐藏规则、不作真实世界因果断言、不用六边格或真实地理（docs/20 §15 B-01—B-15） | 评审、部分测试 |

---

## 5 任务手册

### 5.1 校对（文字）

- **文案在哪**：
  - 界面：`ui/text/zh_cn/`。按前缀找：
    - `common` 通用词、单位、格式；
    - `shell` 顶栏与底部固定区；
    - `overview` 总览与诊断卡；
    - `region`、`society`、`policy` 三页；
    - `report` 季度报告；
    - `overlays` 覆盖层：新局、存档、年度审查、档案、引导；
    - `reasons` 原因卡与草案；
    - `ledger` 台账与加载错误；
    - `rules` 规则卡、规则手册、事件条件；
    - `fiscal` 财政表；
    - `charts` 图表、地图、分布条；
    - `glossary` 术语表。
  - 内容：`content/**/*.json` 的 `label_zh`、`desc_zh` 等字段。改了会动内容指纹，见 §4。
  - 发布文档：`release/*.md`。
  - 规格：`docs/*.md`。
- **规则**：
  - 保留模板语法：`{槽位}`、条件段 `[[?槽位]]……[[/]]`、列表段 `[[*槽位 sep="、"]]……{.字段}……[[/]]`，花括号本身写 `{{` `}}`（`JwText` 文件头）。
    缺必填槽位的整条文案不渲染。数字不要写死在文案里，一律由槽位与 `JwFormat` 格式化，格式规范见 docs/20 §4.5。
  - 术语与 `glossary.json` 保持一致。
  - 措辞纪律见 docs/21 与 docs/20 §9.4：
    - 用「模型中的限制因素」，不作真实世界因果断言；
    - 不出现评分、国力、治理得分一类词；
    - 预测必须带区间和情景名。
  - 简体中文、全角标点；数字与单位之间留半角空格，如「40 季」「0.52 U」。
- **验证**：`bash tools/test.sh --suite=ui`（文案 key 完整、模板槽能渲染、无汉字字面量）。改了内容文件还要跑内容闸门并重生成样例存档。

### 5.2 重新设计（界面与交互）

- **结构**：
  - `ui/main.gd`：外壳，负责页面与覆盖层路由。
  - `JwSession`：草案、试算、推进、存读档。
  - `JwReadModel`：从 `JWGame.view()` 读数，一切计算放在这里。
  - `JwCatalog`：内容元数据与 `ui_config`。
  - 页面、覆盖层、组件只负责组装控件。
  - 工具类：`JwUi`（控件工厂）、`JwTheme`（色板、字体、StyleBox）、`JwFormat`（数字格式）、`JwText`（文案渲染）。
- **视觉系统**：
  - 色板 token 与用法约束见 `palette.json`。
  - 字号角色见 `JwTheme.ROLES`：`title_page`、`title_block`、`body`、`num`、`caption`……
  - 4 lu 栅格，圆角 2 lu，不用阴影。
  - 缩放只经 `--ui-scale`（`Window.content_scale_factor`）。
  - 宽度与高度分档见 `JwScale`（WIDE/MID、TALL/SHORT）。
- **自绘组件**：
  - `JwNumberCell`：数字格，带台账与规则入口。
  - `JwTable`、`JwBar`。
  - `JwIcon`：单色矢量图标。
  - `JwClassRule`：三类信息左标尺。
  - `JwChartFrame` / `JwLineChart`：图表，带四标注。
  - `JwDistributionBar`：P10—P90 色带。
  - `JwCommitTimeline`：12 季承诺泳道。
  - `JwRegionMap`：地区多边形图。
- **规格与验收**：docs/20（布局 §7、组件 §13、禁止事项 §15、验收条目 §16），docs/22（引导锚点）。
- **做法**：
  - 改之前先按 §2 截图存底，改完同位置再截一张对比。
  - 窄屏或矮屏用 `--resolution 1366x768` 与 `--ui-scale=1.5` 各看一次。
  - 跑界面测试与冒烟。

### 5.3 生成图片资源

**第二轮扩充进行中**：截至2026-09-22第三检查点，另有B05—B07建筑54张、物资12张、北原／中州农业期状态12张，选用原图合计120张。目标为144建筑＋48物资／服务＋72地区状态＋6原章节画=270张。继续以`assets/expansion_v2_plan.json`与`docs/_drafts/asset_review/v2/manifest.json`核对实际进度，下方36建筑＋6章节画是第一轮登记，不能误当总量。新图仍待初审，未接入。

**现状**：现行 UI 仍使用代码绘制图形，无随包字体。`assets/buildings/b01/`—`b04/` 已有 36 张跨时代建筑 PNG 候选（1254 × 1254、透明），`assets/eras/e01/` 有 6 张章节画（1536 × 1024、不透明）。B01 风格与质量获用户认可，新增批次待初审，全部未接入 UI。清单见 `assets/ASSETS.md`，统一审核入口 `docs/_drafts/asset_review/catalog/index.html`。接入时按 manifest 的 file 字段取选用版本，勿按 ID 猜文件名。
- 图标（`JwIcon`）、三类信息左标尺（`JwClassRule`）、图表与地图都是代码绘制。
- 字体用系统字体（微软雅黑优先），见 `JwTheme` 文件头。
- 没有应用图标：导出的 exe 会带 Godot 默认图标。

**可以接的活**：

| 资源 | 规格 | 接入点 |
|---|---|---|
| 应用图标 | SVG 母版 + 256 px PNG + 多尺寸 ICO（16/32/48/64/128/256）。深底（`bg.abyss` #0B1620）上的单色或双色几何图形。建议意象：经纬网格 / 罗盘刻度，不用真实国家轮廓，不用文字 | `project.godot` 的 `application/config/icon`；`export_presets.cfg` 的 Windows `application/icon`（.ico） |
| 启动画面（可选） | PNG，底色 `bg.abyss`，居中图形，无文字或只用「经纬」二字 | `project.godot` 的 `application/boot_splash/*` |
| 替换图标集（可选） | 14×14 lu 单色（规则角标 12×12），SVG 优先；灰度下仍可区分，三类信息按实心度递减：实心方 / 半填菱 / 空心菱；禁止 emoji（docs/20 §12.4） | 保持 `JwIcon` 的 kind 名集合不变，改成加载资源绘制 |
| 左标尺纹理（可选） | 3×12 px、9-patch、垂直平铺：实线 / 短划 6-3 / 点线 2-4（docs/20 §3.3） | 目前 `JwClassRule` 代码画，换纹理要保持灰度可辨 |
| 地区图轮廓 | **不是图片**，是 `ui/config/ui_config.json` 的 `region_polygons`（坐标空间 1000×700）。改形状必须保持四区两两共享边（拓扑以 `content/scenarios/chengwan/regions.json` 的 adjacency 为准），抽象示意，禁止真实地理 | 改完跑 `test_region_map_labels_edges_and_topology` |
| 随包字体（可选，需用户同意下载） | Noto Sans SC / Noto Serif SC 子集化（docs/20 FT-1—FT-5），每个字体文件带同名 `.license` | `JwTheme.family_font` |

**风格**：
- 深色档案感：底色 `bg.base` #0F1D28，面板 `bg.panel` #162734，强调 `teal.core` #5FB3A4。
- 纸面页（报告、档案）用 `bg.paper` #ECE7DE，配墨色字。
- 风险专用赭色：`ochre.core` #D9954A，不做装饰。
- 线条克制，不用渐变、阴影、写实插画。

**放置**：
- 新建 `res://assets/<类别>/`，例如 `assets/icon/`、`assets/fonts/`。
- PNG / SVG / TTF 是 Godot 资源，导出时自动进包；新的 JSON 等非资源文件要加进 `export_presets.cfg` 的 `include_filter`。
- 在 `assets/ASSETS.md` 登记每个文件：来源（哪个工具、提示词或手绘）、授权、日期、用途。

**交付与初审**（用户要手动初审，未通过前不接入工程配置）：
1. 资源放进 `assets/<类别>/`，在 `assets/ASSETS.md` 登记，每条状态写「待初审」。
2. 附预览：`docs/_drafts/asset_review/` 下放每个资源在实际底色上的效果图，例如 `bg.abyss` 上的应用图标，以及图标在 14 / 28 lu 的大小。
3. 在交接日志写一条「完成 · 待用户初审」，列出文件清单。
4. 用户初审通过后，才把资源接进 `project.godot`、导出预设或界面代码，并把 `ASSETS.md` 状态改为「已接入」。

**接入后的验证**：
1. `--import` 后截图看效果。
2. `--export-pack` 导出资源包，确认文件在包里。
3. 用 `--main-pack` 试跑一次。

---

## 6 交付前验证清单

1. 新增或改名了 `class_name`：`"$GODOT" --headless --path . --import`。
2. `bash tools/gate.sh`，或至少跑解析闸门、分层闸门和受影响的测试套件。交付说明里写明测试项数。
3. 改了 `content/`：跑 `validate_content.py`、`build_param_registry.py`，并重生成 `release/saves/`。
4. 改了界面：截图并实际看过；跑界面冒烟 `--smoke --full`。
5. 改了结算规则：
   - 跑无冲击基线，验收口径是零欠付、审查赤字率 < 0.15、两次选举留任。
   - 相关政策跑单一干预。
   - 写 docs/18 裁定。
6. 玩家可见的行为变了：更新 `release/KNOWN_LIMITATIONS.md` / `GUIDE.md` / `RELEASE_NOTES.md` 与 `docs/40`。
7. 在本文件交接日志里写一条。

---

## 7 已知的坑

- **`PackedInt64Array` 是值类型**：
  - `(dict[key] as PackedInt64Array).append(x)` 只改副本，要取出、追加、写回。
  - `for a in [x, y]: a.resize(n)` 也改不到成员。
- **GDScript 运行错误只中止当前函数**，调用方照常往下走。测试运行器已经把这类错误判为失败，别绕过。
- **`load()` 对编译失败的脚本也返回对象**：解析闸门查的是 `can_instantiate()`。
- **`--headless` 没有渲染**：截图必须开窗。
- **导出包只含资源文件与 `include_filter` 列出的文件**：`ui/*.json` 已加入。新增非资源文件要同步加进过滤器。
- **自动存档槽**：并行开两个进程会抢默认槽；测试夹具用 `autosave_test`。
- **整除警告**：确认是有意的整除时，加 `@warning_ignore("integer_division")`。
- **别整体重排 `content/` 下的 JSON**：会改内容指纹。`ui/` 下的 JSON 可以重排。
- **给智能体的**：
  - 用 shell heredoc 写含反斜杠的补丁容易被改写，先写成脚本文件再运行。
  - 补丁脚本里用「断言锚点恰好出现一次」再替换。

---

## 8 协作约定（Codex ↔ Claude）

- 开工：读本文件与交接日志最近几条，再在日志里写「进行中」并列出要动的文件。同一文件区域同一时间只让一个智能体改。
- 语言：文档与注释用简体中文；代码标识符用英文（类名 `JW*` 属 SimCore，`Jw*` 属界面）；缩进遵守 `.editorconfig`（`.gd` 用 tab）。
- 大改先出方案：写在日志或 `docs/_drafts/`，再动手；跨层改动先写裁定。
- 不删用户数据：`user://saves`（`%APPDATA%\Godot\app_userdata\经纬 Jingwei\saves`）是本机数据，只读不删；样例存档从那里拷出来。
- 交付：日志条目改成「完成」，写清楚做了什么、怎么验证的（命令与结果数字）、遗留问题。

---

## 9 交接日志（新条目追加在最上面）

格式：`日期 · 执行者 · 状态（进行中 / 完成 / 搁置）· 范围`，下面写：改动、验证、遗留。

### 2026-09-22 · Codex · 进行中 · 四倍建筑扩充、物资资源与地区状态画

- 第四检查点开工：制作B08造船／车辆／轻型车辆／电气／电子／通信18建筑、海岬农业期6状态与后续物资。占用既有assets及asset_review/v2、设计54、docs/51自有区；上一目标回合属实质进展（新增51图及修正、像素与视觉核验），目标仍270。

- 第二检查点：B06 纺织／服装／皮革／造纸／印刷／玻璃18建筑、中州农业期6状态、轻工业9物资新增33张，累计102张；本轮60/60原图目检与像素核验，60个独立哈希、154处本地链接有效。审核页60/60加载，中州6/6并排与印刷灰度样本已看；新增6张有1—38个alpha=1/255外圈残留。校正印刷厂为“胶印出版中心”、中州地标为实际母图三拱桥；设计54补充轻工业选择。第三检查点开工：B07六家族18建筑。仍属进行中，不覆写v1、不接入，目标270不缩减。

- 用户明确认为 42 张太少，要求建筑与资源至少再翻两倍，并让场景反映地区多种状态；允许直接设计。按较充分的四倍口径执行：建筑 36→至少144 张，不以改名、缩放或重色凑数；另设计 48 张物资／服务卡图；新增四地区×三时代组×六状态共72张地区场景，保留原6张章节画。
- 占用 `assets/buildings/b05/`—`b10/`、`assets/goods/`、`assets/regions/`、对应 prompts、`assets/expansion_v2_plan.json`、`docs/_drafts/54_asset_expansion_design.md`、asset_review/v2 及新批次审核目录；同步 ASSETS、docs/51 自有区。内置 imagegen，每图独立生成，未经初审不接入。
- 已看到 Claude 的 stash 恢复说明；当前选用36建筑＋6章节画原图数量已核对。此后按独立 manifest 追加，不覆写旧批次，不动 Claude 核心代码、content、裁定或提交。
- 目标保持完整；设计表、首批图片或某个子批完成均不等于本轮全目标完成。完工须核对数量、每图独立语义、地区／时代／状态覆盖、透明度、来源、预览与总包。
- 第三个检查点：B07六家族18张完成生成与自查，累计120张（建筑90、物资12、状态12、章节6）。本轮78/78原图目检、像素、独立哈希通过，目录78/78加载；水泥三代深底、冶金三代浅底已看。水泥厂v3清除游离杂点（v2失败保留），炼铁v2清理白边，高炉v2纠正铁水为热金属。新增6张各1—19个alpha=1/255外圈残留。后续B08—B10共54建筑、36物资、60状态仍须完成；不能关掉270目标。设计54新增建设／设备链选择，未动实现区。
- 第一个检查点：B05六家族18建筑、3物资卡、北原农业期6状态共27张新增，合计69张选用原图。原图27/27逐张视觉审阅与像素／哈希核验，18建筑＋3物资为1254×1254透明PNG，6场景1536×1024不透明；5张有6—28个alpha=1/255外圈残留。两张现代设施黄色装卸标记定点修正，原版归档；“畜力磨坊”按画面改名“石磨作坊”。
- 验证与遗留：v2审核网页27/27加载，18/3/6类别与园艺搜索3项正确；614 px窄页无横溢；已看6状态并排、物资浅底64 px、建筑灰度／园艺64 px样本。局部链接检查70处通过（新增QA链接随后由同脚本重验）；未动游戏代码，不重复Claude正在进行的全量验证。总目标270未完成，余B06—B10、45物资与66地区状态继续；QA、实际计数与后续生产工具在`docs/_drafts/asset_review/v2/`，勿跑旧v1整理器覆盖新登记。

### 2026-09-22 · Claude · 完成 · 停顿待用户检查 · 四百年重构 M1（总计划 docs/53）

- **用户决定**（U-1—U-8，详见 docs/53 §0）：推送到 GitHub `Dystopians/Progress`（公开）；先 4 区但维度可扩；默认每年规划一次；做到 M3、每个里程碑停；旧 40 季保留为可选剧本；允许通胀、默认显示实际值；Codex 卡片未到时 Claude 写占位内容；很少终局、多是代价。
- **Git**：仓库已有提交。基线 `d883734` 已推送；里程碑内部只做本地提交，里程碑结束时推送。`.gitattributes` 固定 LF（内容指纹依赖字节）。M1-1、M1-2 两次本地提交用了 `git add -A`，顺带收进了 Codex 当时已落盘的 `assets/` 文件（只是存档，不代表接入或初审通过）。**此后 Claude 只 `git add` 自己负责的目录**，不再提交 Codex 的半成品；也不再用 `git stash`（2026-09-22 一次 stash 恢复曾把 Codex 已改名为 `_v2` 的 `b03/transport_modern.png`、`b04/utility_early.png` 复活，已手工移出，工作区与 Codex 当时的状态一致，请 Codex 核对）。
- **写入范围**：M1 期间 `sim/ systems/ application/ ui/ tests/ tools/ content/ docs/18 docs/53` 由 Claude 写入；Codex 继续在 `assets/`、`docs/_drafts/` 与 docs/51 的自有区工作。
- **M1-1 完成**：多剧本并存（`res://content#<剧本名>`，默认 `chengwan`）；战役剧本 `content/scenarios/campaign_1600/`（M1 骨架，经济数据暂为现代副本）；`mode` / `start_year` 进状态；存档升 v2（含 v1 → v2 迁移）；开局覆盖层可选剧本；战役按公历显示季度（「1600 年春」）。裁定 R-SCENARIO-01、R-CLOCK-01 第一部分（docs/18 末尾新节）。全量 547 / 547。
- **M1-2 完成**：地区数由剧本决定（R-SCENARIO-02），5 区测试剧本查出并修正四处 R/S 混用。
- **M1-3 完成**：战役模式的货币发行（R-MONEY-01）与随价格水平移动的长期上下限（R-PRICE-LONG-01）；新状态块 `sim/money/money.gd`；全量 555 / 555。1600 季长局验证并入 M1-9（要先有 M1-7 危机状态机）。
- **M1-4—M1-9 完成**：稳定实体号与压实（R-CAP-01）；建筑堆（R-BUILDING-01，新块 `sim/buildings/`）；战役政府更替与危机状态机（R-REGIME-01、R-CRISIS-01，新块 `sim/politics/crisis.gd`）；长期闭合两条（R-CLOSURE-01）；劳动力缩减离职（R-LABOR-SHRINK-01）；批量推进（`JWGame.advance_batch`，确认框推进 1 / 5 年）；存档检查点归属与一次写入（R-SAVE-03，修复重放空过）。全量 572 / 572。样例存档已重生成为 v2（`release/saves/`，内容指纹 deecb4f5 不变）。
- **报告**：`docs/_drafts/54_m1_report.md`；截图 `docs/_drafts/ui_shots/m1/`；新工具 `tools/diag_long.gd`、`bench_long.gd`、`diag_money.gd`、`diag_region5.gd`、`diag_speed.gd`。
- **已知风险**：无人操作时现代经济副本 25—40 年走向萧条（储蓄无投资渠道、结构性赤字），列为 M2 首要标定任务；退化经济里违约债占满债券表（M3 债务重组）。
- **机器负载**：本轮后段测试与基准都在高负载下跑（单季约 530 ms，旧提交同样），性能数字需安静机器复测。
- **下一步**：等用户检查 M1，同意后开始 M2（1600—1650 切片）。 → M1-3 长期价格 → M1-4 容量回收 → M1-5 建筑堆 → M1-6/7 政府拆分与危机 → M1-8 批量推进 → M1-9 长局基准。

### 2026-09-22 · Codex · 完成 · 待用户初审 · 扩充跨时代资源 B02—B04／E01

- 用户肯定 B01 质量并要求继续完成尽可能多的资源；保持内置 imagegen 与现有风格，先补齐剩余 9 家族的 27 张建筑，再推进 6 张时代画。队列见 `assets/production_plan.json`，不是已冻结玩法合同。
- 占用 `assets/buildings/b02/`—`b04/`、`assets/eras/e01/`、对应 `assets/prompts/`、`docs/_drafts/asset_review/` 批次目录、`assets/ASSETS.md`、资源生产清单；在 docs/51 维护自有资源状态。无游戏代码／content／工程配置改动，不占用 Claude 区域。
- B01 风格与质量获用户认可；新增图仍待初审，原图及提示词入工程，未经初审不接入。每批检查实际 alpha、形体、时代特征、小图辨识与来源。
- 交付：新增 27 张建筑＋6 张章节画，合并 B01 为 36 建筑＋6 章节画；42 份生成提示词、4 份修正提示词、来源／SHA-256／元数据／分批 QA、可搜索离线审核目录与总 ZIP。修正物流站黄色路桩、水井不合理溢流、信息时代黄橙设备；原生 PNG 未经脚本像素修改。
- 验证：36/36 建筑透明、6/6 章节画不透明；31/36 建筑外圈全透明，5 张各有 1–8 个 alpha=1/255 残留已记录。深浅底、灰度、64 px 列表与六时代总览截图均实际查看；目录 42/42 图片加载、筛选 9 项、搜索港口 3 项、窄页无横向溢出。ZIP 136 文件、42 张 PNG 哈希一致、CRC 通过、465 处本地链接有效。
- 工程快照：分层无违规、解析 145/145，失败 0，退出 0；根证书库／日志目录提示与 ObjectDB 33 个／资源 29 个未释放见总 QA。本轮未改代码，不重复全量测试，不以此代替 Claude 的 M1 验收。
- 交接：docs/51 自有资源区更新 H-004，已读 docs/53 用户批准与 Claude M1 进度；全部未接入、未导出、未下载、未提交／推送。剩余科技／状态图标与 D-001 内容卡是后续工作，不能说全游戏美术或设计完成。

### 2026-09-22 · Claude · 完成 · 400 年改造 M0 技术评审

- 新增 `docs/_drafts/52_claude_m0_technical_review.md`：
  - 七问逐条回答，给到文件与行号；
  - 复用分级总表；
  - M1（约 6—10.5 工作日）与 M2（约 8.5—13.5 工作日）的范围、风险与放行条件；
  - M3 战争边界、替代方案与取舍；
  - 十三条裁定草案；
  - 给 Codex 的数据合同字段草案。
- 同步：docs/51（评审区、任务表、H-003）、本文件方向提示。
- 核实过的代码事实：
  - 时长只接受 40 或 120（`content_loader.gd:1070`），剧本目录写死（`:65`）；
  - 选举写死在第 15、31 季，四种直接终局（`politics.gd:121-123`、`:659-698`）；
  - 项目表 64 槽只增不删（`project_queue.gd:213`），债券表 512 槽无回收；
  - 价格绝对上下限为基年价 0.4—2.5 倍（`jw_units.gd:28-30`）；
  - 项目不能写工业产能（`asset_commissioning.gd:291`）；
  - 生产单元产能唯一增量写入点在 S01（`capital.gd` 的 `commit_pending`）；
  - 主体表固定 60 个编号，外部世界只有一个账户（`jw_ids.gd:33-39`）。
- 验证：只改文档，未跑测试（代码未动）。
- 遗留：用户决定是否开工 M1，以及动核心前的基线提交或备份；Codex 确认「建筑堆」并按 §5 起草 D-001。

### 2026-09-22 · Codex · 完成 · 待用户初审 · B01 跨时代建筑资源批量制作

- 用户告知Claude已开始接手审阅，并要求Codex先批量生成资源。首批范围：水利、工场、教育三家族各三个时代，共9张建筑PNG，及资源登记、提示词、元数据与审核预览。
- Codex占用：`assets/buildings/b01/`、`assets/ASSETS.md`、`assets/prompts/b01/`、`docs/_drafts/asset_review/b01/`；仅在本文件追加/更新本条，在`docs/51_codex_claude_handoff.md`追加资源进度区，不修改Claude评审区或游戏代码/配置。
- 使用内置imagegen；待用户初审，不接入。用户本轮授权先批量制作，覆盖主稿先少量初审再扩量的建议顺序，接入前初审要求仍保留。
- 交付：9 张 1254 × 1254 RGBA PNG、9 份生成提示词和 1 份定点修正提示词；ASSETS 登记、manifest、只读检查脚本、2 个审核网页、3 张深浅底／灰度截图及资源 ZIP。现代工厂黄黑条已修正；原图原生保存，不用脚本编辑像素。审核目录加 .gdignore。
- 自查：9/9 有透明背景，8/9 外圈全透明；蒸汽工厂 6 个边缘像素 alpha=1/255 已登记。网页 27/27 图像加载，筛选教育显示 3 张，窄页无横向溢出。已实际查看深底、浅底、灰度和教育 128／64 px；64 px 必须保留名称。ZIP 30 文件、72 处本地链接有效，包内 9 张 PNG 哈希一致，CRC 通过。
- 工程验证：分层无违规；PowerShell 直接运行解析脚本，138/138 可解析，失败 0。Git Bash 管道权限错误、Godot 日志／设置权限及根证书错误，退出 ObjectDB 32／资源 28 提示如实记在 QA。首次两份截图编码后缀不符已修正并隔离，不称零错误日志。未改游戏代码或 content，未重跑全量测试，未下载、提交、推送或导出。
- 协作：已读 Claude H-003，docs/51 自有区域回复认同聚合建筑堆及部分改造呈现；D-001 尚未开始。资源未接入，等用户初审；不改 Claude 评审区。后续接入仍需按 §5.3 实机截图、资源包与运行验证。

### 2026-09-22 · Codex · 完成 · 400 年国家发展改造规划与协作交接

- 2026-09-21开工，22日完成。用户确认1600—2000、正常施政持续控制且严重失败才可能终局、发展为主含外交贸易与抽象战争、建筑卡片/列表并参考《维多利亚3》。Codex负责图片、玩法/文本审视与协作维护。
- 新增 `docs/_drafts/50_four_centuries_redesign.md` v0.2（时代/科技/建筑/经济/战争/复用/迁移/M0—M4验收/美术分批）；新增 `docs/51_codex_claude_handoff.md` H-002（分工、状态队列、7项技术问题与可转发咨询包）；同步本文件、README、docs/40、docs/41。共6份文档，仅规划与协作状态，不改代码、content、工程配置或用户存档。
- 验证：`bash tools/gate.sh`退出0，分层无违规、解析138/138、23文件540/540测试通过、17,416条断言；测试约158.4秒。6份文档UTF-8读取通过，5个本地Markdown链接全部存在，坏链0。未生成图片、未下载、未提交、未导出。
- 验证输出说明：图表缺单位错误是用例显式声明的1条预期错误；退出时另有ObjectDB/资源未释放提示（解析32/28、测试212/35），不冒称无警告，本轮不扩大为代码修复。
- 遗留：具体危机阈值、产业所有权/投资接口、资源粒度、长局容量与历史归档待技术评审；六阶段和内容数量仍为提案。未找到可直接联系Claude的通道，尚未发送咨询或收到评审，已准备共享文档交接。实际实现及美术生成未开始。

### 2026-09-21 · Claude · 完成 · 记录打包暂缓

- 用户决定：先不打包。等 Codex 的图片资源到位、用户手动初审完毕，再考虑是否下载导出模板生成 exe。
- 已同步：本文件 §1 与 §5.3（新增「交付与初审」流程）、`docs/40` §3、`docs/41` §2。

### 2026-09-21 · Claude · 完成 · 建立本手册

- 新增 `AGENTS.md`（本文件）与 `CLAUDE.md`（导入本文件）；README 补上指向与测试套件。
- 遗留：
  - **性能登记**：契约档基准跑完，单季中位数 71.1 ms、P95 99.2 ms、P99 103.2 ms、最大 150.6 ms，三轮极差 1.3 ms。
    但 300 局全部按规则提前终局，有效样本 9 228，只有协议值 35 400 的 26%，脚本因此拒绝登记。
    协议（docs/30 §7.3「100 种子 × 120 季」）默认对局不会终局，需要一次裁定：接受提前终局并规定样本量下限，
    或改用不会终局的驱动方式。已登记在 docs/13。
  - **Windows exe**：需下载 Godot 4.7.2 官方导出模板（约 1 GB）。暂缓，见上一条。
  - **真人试玩**：5 名测试者，记录表在 docs/22 与 `release/FEEDBACK_FORM.md`。

### 2026-09-21 · Claude · 完成 · 第六轮（事件、延期、政策衰减、T1 界面、发布准备）

- 裁定 R-EVENT-01、R-LAUNCH-01、R-SAVE-02、R-AUTOSAVE-01、R-PREVIEW-01、R-DEFER-01、R-P10-01、R-P11-02、R-P12-02、
  R-EXIT-OPEX-01、R-GLOSS-01、R-EXPORT-01、R-UI-T1-01（详见 docs/18）。
- 验证：全量 540 / 540；无冲击基线达标；资源包导出后能开局；样例存档经往返与权威重放核对。
- 遗留：命令 7（档间调剂）与 11（常设指令）无设计，界面不提供入口；全局检索未做（规格允许移出首版）。
