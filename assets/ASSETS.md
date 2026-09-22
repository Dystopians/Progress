# 经纬资源登记

所有条目在用户初审通过前均不得接入 UI、project.godot 或导出预设。

## B01 · 2026-09-22 · 完成，待用户初审

- 范围：水利、工场、教育三个家族各三个时代，共 9 张独立建筑插图。
- 作者／来源：Codex 提示词设计，OpenAI 内置 imagegen；9 次生成、1 次定点修正，无外部下载素材，无参考游戏素材复制。
- 授权：AI 生成输出按生成服务适用条款使用；不声称独占版权或已完成第三方权利审查。
- 用途：400 年改造版的建筑卡片／列表插图候选；时代是美术分类，不代表科技资格、等级、解锁日期或生产能力。
- 风格：等距微缩建筑，深蓝灰、灰白、青绿，无内嵌文字。实际输出有轻微材质与体积明暗，并非纯平涂；新增美术方向待用户初审。
- 原图：全部 1254 × 1254 RGBA PNG，均有实际透明通道。保留原生尺寸，未伪称 1024／512 px；仅浏览器缩放预览。
- 状态：全部「待初审，未接入」。引擎生成了导入元数据，但未改 UI、工程配置或导出预设；可导入不等于审核通过。
- [元数据与 SHA-256](../docs/_drafts/asset_review/b01/manifest.json) · [九图总览](../docs/_drafts/asset_review/b01/overview.html) · [尺寸与底色检查](../docs/_drafts/asset_review/b01/index.html) · [QA记录](../docs/_drafts/asset_review/b01/QA.md)。
- [批次提示词说明](prompts/b01/README.md)。后续 8 张以渠系水轮为风格参考；未使用游戏版权素材。

| Asset ID／文件 | 名称 | 家族／时代 | 字节 | 提示词 | 状态 |
|---|---|---|---:|---|---|
| [irrigation_early](buildings/b01/irrigation_early.png) | 渠系水轮 | 水利／早期 | 1212314 | [原始](prompts/b01/irrigation_early.txt) | 待初审，未接入 |
| [irrigation_industrial](buildings/b01/irrigation_industrial.png) | 工业泵站 | 水利／工业期 | 1150204 | [原始](prompts/b01/irrigation_industrial.txt) | 待初审，未接入 |
| [irrigation_modern](buildings/b01/irrigation_modern.png) | 电动灌溉站 | 水利／现代期 | 1016283 | [原始](prompts/b01/irrigation_modern.txt) | 待初审，未接入 |
| [workshop_early](buildings/b01/workshop_early.png) | 手工工场 | 工场／早期 | 1203350 | [原始](prompts/b01/workshop_early.txt) | 待初审，未接入 |
| [workshop_industrial](buildings/b01/workshop_industrial.png) | 蒸汽工厂 | 工场／工业期 | 1307451 | [原始](prompts/b01/workshop_industrial.txt) | 待初审，未接入 |
| [workshop_modern](buildings/b01/workshop_modern.png) | 电动制造厂 | 工场／现代期 | 1206982 | [原始](prompts/b01/workshop_modern.txt) · [修正](prompts/b01/workshop_modern_edit.txt) | 待初审，未接入 |
| [education_early](buildings/b01/education_early.png) | 地方学舍 | 教育／早期 | 1259624 | [原始](prompts/b01/education_early.txt) | 待初审，未接入 |
| [education_industrial](buildings/b01/education_industrial.png) | 工程学校 | 教育／工业期 | 1355472 | [原始](prompts/b01/education_industrial.txt) | 待初审，未接入 |
| [education_modern](buildings/b01/education_modern.png) | 研究中心 | 教育／现代期 | 1220825 | [原始](prompts/b01/education_modern.txt) | 待初审，未接入 |

## 接入约定与限制

- 插图代表设施家族与技术形态，可用于同类设施聚合卡，不代表逐栋可摆放对象。
- 等级、所有者、生产方式、停工原因由界面数据与文字表达，不烧进图像。同一建筑切换生产方式不必每次换图。
- 推荐 128–216 px 卡片；64 px 列表必须保留名称和生产方式标签，尤其教育家族。不用于 14 px 功能图标。
- 等比居中 contain，不拉伸、不裁掉部件。未制作低分辨率衍生文件；Claude 接入时按实际控件与缩放测试选取纹理策略。
- 9 张都有透明背景。蒸汽工厂左边缘 6 个像素 alpha=1/255，属近透明残留，主体未截断；浅底检查未见明显黑边。保留原图并公开例外，不能称为外圈全零。
- 现代工厂选用 v2，黄黑条已由 imagegen 修正为中性灰。v1 只在审核目录追溯，不作为交付候选。
- 本批不含应用图标、启动图、字体、状态图标或完整六阶段建筑全集。后续批次沿用经用户审定的风格与语义 ID。
