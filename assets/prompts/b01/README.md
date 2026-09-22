# B01生成提示词与制作记录

本批使用内置imagegen，每个建筑独立生成。生成原图原样保留，不从图集中裁切，不用外部图库。结构一致的参考图仅用于后续资产的视角、配色与线条风格。

通用规范：建筑卡片用单体设施微缩插图，正方形，三分之四等距视角，相同俯角与占画幅比例；简洁建筑轮廓、清楚的功能部件，适合64px缩略辨识。透明背景优先，若输出不带有效透明通道必须如实登记并修正或标为有底版。无文字、数字、招牌、人物、标志、国旗、渐变和投影。深蓝灰、灰白与青绿，木/砖也使用中性色，不用风险赭色作装饰。

候选资产：irrigation_early / irrigation_industrial / irrigation_modern；workshop_early / workshop_industrial / workshop_modern；education_early / education_industrial / education_modern。时代标签仅用于美术分类，不承诺历史年份或实际解锁条件。

实际完整提示词已逐项保存。生成源文件名、版本、SHA-256 与像素统计见 `docs/_drafts/asset_review/b01/manifest.json`。共 9 次独立生成、1 次现代工厂定点修正；后续 8 张使用 `irrigation_early.png` 作风格参考，修正使用现代工厂 v1 作唯一编辑目标。

实际输出全部为 1254 × 1254 RGBA PNG。保留原生文件，无脚本像素处理；尺寸、深浅底、灰度与边缘例外见审核目录 `docs/_drafts/asset_review/b01/QA.md`。通用规范是生成目标，不冒称输出完全满足纯平涂或 64 px 独立辨识；尤其教育家族必须配文字标签。
