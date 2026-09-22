# 引擎与构建环境（已锁定）

| 项 | 值 |
|---|---|
| 引擎 | Godot **4.7.2-stable** (official, ed1daf0bf) |
| 脚本 | 带类型 GDScript（项目已开启 untyped/unsafe 警告为错误级） |
| 可执行文件 | `C:/Users/Fiber Memory/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe` |
| 项目根 | `C:/Users/Fiber Memory/Documents/Jingwei` |
| 离线分析 | Python 3.12.10（仅用于校验与校准，不维护第二套模拟核心） |

无界面运行：

```
"$GODOT" --headless --path "C:/Users/Fiber Memory/Documents/Jingwei" --script "res://tools/<脚本>.gd"
```

重放确定性承诺仅在**该固定构建**下成立（见计划书 §12 [8]）。

## 参考电脑（性能门槛的登记基准）

计划书 §17 要求「登记参考电脑后，季度结算中位数低于 0.5 秒、95 分位低于 1 秒」。
本项目的 REF-01 参考机登记如下（登记日期 2026-09-12）：

| 项 | 值 |
|---|---|
| 机器 ID | `REF-01` |
| CPU | Intel Core i7-14650HX，16 物理核 / 24 逻辑核，基准 2.2 GHz |
| 内存 | 32 GB |
| 显卡 | NVIDIA GeForce RTX 5070 Ti Laptop |
| 存储 | YMTC PC41Q 1TB NVMe |
| 系统 | Windows 11 家庭版 build 26200 |
| 渲染后端 | `gl_compatibility` |

性能数字必须标注测得于哪台参考机。**在别的机器上测出的数字不能直接与门槛比较**，
须先在该机上重跑基准并登记为新的 REF-xx。测量协议见 `docs/30_quality_gates.md`。

无界面压力测试（100 种子 × 120 季）与季度结算计时都在 `--headless` 下进行，
以排除渲染开销——门槛约束的是 SimCore，不是绘制。

### 实测记录

每一行都是 `tools/bench_quarter.gd` 的一次真实运行。**只有协议样本**
（docs/30 §7.3：100 种子 × 120 季 × 3 轮，剔除热身与每种子前两季 ⇒ 每轮有效样本 11 800、合计 35 400）
跑出来的中位数才有资格作为登记值与门槛比较；其余档位只作回归信号，本表照样登记，
但「样本」列会写明它不是协议样本。测不出来的那种情况也必须留一行——
一次没跑成的测量，和一次跑成但不达标的测量，是两件不同的事，都不能从记录里消失。

跑法（协议样本）：

```
"$GODOT" --headless --path "C:/Users/Fiber Memory/Documents/Jingwei" \
    --script "res://tools/bench_quarter.gd" -- --profile=full --ref=REF-01
```

| 日期 | 机器 | build_id | 样本 | 中位数 | P95 | P99 | 最大值 | 结论 |
|---|---|---|---|---|---|---|---|---|
| 2026-09-12 | REF-01 | `jingwei-simcore-1` | **0**（测量未能进行） | — | — | — | — | 基准脚本跑通并给出报告，但**没有产生任何季度样本**：`JWContentLoader.load_all("res://content")` 返回 `E_UNKNOWN_FIELD (2005)`（首个位置 `scenarios/chengwan/politics_init.json#/blocs/0/care_metric_id`，共 116 条错误），引擎开不了局。退出码 2 == 「测不了」，既不是通过也不是不通过。加载器与内容包对齐后必须重跑本行。 |

> 空行的纪律：**不得**用估算、外推或「空跑骨架」的数字填这张表。docs/30 §7.4 的判据以
> 有效样本数为前提，样本数为 0 时任何数字都是编的。G0 阶段的空跑基线（12 号文件 §13 要求的
> 那一条）同样要等引擎能开局之后才能建立——在那之前这张表只能有「测量未能进行」这一种记录。
