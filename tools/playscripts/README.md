# 行动脚本（playscripts）

把一局的玩家动作写成 JSON，游戏按季度经**真实命令路径**提交并推进。用途：

- 调试、截图时快速走到指定年份；
- 机制改了脚本照样能跑，不依赖旧存档（存档形状变了也不怕）；
- 对照局：同一脚本换种子，或同一种子换打法。

脚本不改任何规则、不直接写状态。每条动作都是一条普通命令，照常经 S02 受理或拒绝；同一脚本同一种子逐位可复现。

## 怎么跑

无界面（打印年表与被拒动作）：

```
godot --headless --path . --script res://tools/play.gd -- res://tools/playscripts/route_a_agrarian.json 1650 every=20 log
```

选项：`seed=<n>` 覆盖种子；`every=<n>` 年表间隔；`save=<槽名>` 跑完另存；`log` 打印每条动作的结果。截止时间不写就用脚本里的 `until`。

带界面（开局后自动快进，停在截止季）：

```
godot --path . -- --jw-play=res://tools/playscripts/screenshot_1612.json --jw-play-until=1620
```

截图工具同样认这两个参数（`tools/capture_ui.gd … --jw-play=<脚本>`）。

## 格式

```json
{
  "schema_kind": "playscript",
  "schema_version": 1,
  "name": "路线甲 重农商贸",
  "scenario": "campaign_1600",
  "seed": 1,
  "until": "1650",
  "research": ["tech.survey", "tech.water_management"],
  "events": {"default": 0, "event.E07": 1},
  "rules": {"build_cash_multiple": 2, "retry_quarters": 40},
  "build_queue": [
    {"build": "building.irrigation_regional", "region": "region.beiyuan", "owner": "gov"}
  ],
  "timeline": [
    {"at": "1605秋", "do": [
      {"trade": "partner.north_ports", "mode": "treaty"},
      {"bond_u": 2.5, "tenor_q": 8}
    ]}
  ]
}
```

| 字段 | 含义 |
|---|---|
| `until` | 推进到哪一季为止（不含）。写法：`"1650"`（该年春）、`"1650秋"`、`"q:120"`（第 120 季，从 0 起） |
| `research` | 研究队列：当前方向完成就换下一项；已完成的自动跳过 |
| `events` | 选择型事件取第几个选项（从 0 起）；`"skip"` 表示不回应；`default` 管没单独写的事件 |
| `rules.build_cash_multiple` | 建造动作要等国库现金超过造价的这个倍数才下令（默认 2） |
| `rules.retry_quarters` | 时间线动作被拒后最多重试几季（默认 40），超过就放弃并记日志 |
| `build_queue` | 按顺序建造：一次只下一项，受理了才轮到下一项，被拒就下季再试 |
| `timeline` | 到了 `at` 那一季（或之后第一个条件满足的季）执行 `do` 里的动作 |

### 动作

| 写法 | 命令 |
|---|---|
| `{"build": "building.x", "region": "region.y", "owner": "firm"｜"gov", "method": "method.z"}` | 新建建筑（等解锁、等钱够才下令） |
| `{"research": "tech.x"}` | 设定研究方向（本季优先于研究队列） |
| `{"retrofit": "building.x"｜"legacy", "region": "region.y", "method": "method.z", "sector": "agri"}` | 改造建筑堆；`legacy` 指开局的既有设施，此时要写 `sector` |
| `{"enact": "policy.P07", "params": [a, b, c, d], "funding": 0}` | 颁布政策（参数是整数槽，含义见政策卡） |
| `{"set_params": "policy.P01", "params": [a, b, c, d]}` | 调整政策参数 |
| `{"repeal": "policy.P03"}` | 撤销政策 |
| `{"launch": "policy.P07", "region": "region.y", "scale_ppm": 1000000, "funding": 0}` | 启动项目 |
| `{"bond_u": 2.5, "tenor_q": 8, "holder": "domestic"｜"foreign"}` | 发债，金额按 U 写 |
| `{"trade": "partner.x", "mode": "export"｜"import"｜"treaty", "dir": "up"｜"down"}` | 贸易安排 |
| `{"raw_kind": 11, "args": [..]}` | 直接写命令码与参数（兜底用） |

ID 一律用内容里的文字 ID（`tech.*`、`building.*`、`method.*`、`policy.P01`、`event.E01`、`region.*`、`partner.*`），不用下标，所以内容顺序变了脚本也不失效。写错的 ID 在开局时就报出来。

## 现有脚本

| 文件 | 用途 |
|---|---|
| `route_a_agrarian.json` | 路线甲「重农商贸」，与 `tools/route_compare.gd` 逐条对应，结果逐位相同 |
| `route_b_workshop.json` | 路线乙「早期工场」，同上 |
| `passive.json` | 无操作局，用来验证「不操作必须亡国」 |
| `screenshot_1612.json` | 概览截图局：种子 7，停在 1612 年春 |
