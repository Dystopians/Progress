# 60 · 第七批图片需求（界面可视化改造用，交 Codex 批量生成）

2026-10-01 · Claude · 依据用户 10-01 的八条意见（字号、价格说法、科技树、政令与国家形态、民生、纪事、产业可视化、补齐图片）。用户要求「宁滥勿缺」，这里把新界面用得上的图都列上，按优先级分三档：

- **P0**：新界面的主体，缺了就只能显示占位；
- **P1**：让画面更丰富，缺了也能用；
- **P2**：锦上添花或补齐旧图。

共约 **350 张**。界面代码会先按下面的路径接好，图没到时显示占位；图一到，放进对应路径就生效，不用改代码。

## 0 通用要求

- **画风**与现有资源一致：等距或正面略俯视、清晰轮廓、低饱和、在深色界面上好认；参考 `assets/buildings/b01/`、`assets/advisors/`、`assets/icons/campaign/`。
- **时代感**要对：第一时代明末清初，第二时代清中期（工场、钱庄、远洋），第三时代晚清至民国初（蒸汽、铁路、电报），第四时代二十世纪中后期（电力、汽车、电视、计算机）。人物服饰、器物、建筑都按这个走，不要穿越。
- **不出现文字**（图上不写字、不画可读的招牌字）；不用真实国旗、真实政党标志、宗教符号；暴力与灾难克制表现。
- **尺寸**按每节写的；透明图四周留约 8% 的边，外圈不要有半透明残留像素。
- **文件名**全用小写英文与下划线，放到写明的路径；同一张有修订时另存 `_v2`，并在交付说明里写明选哪张。
- 交付时照旧附审核页、清单与提示词，**待用户初审**；Claude 接入后截图核对。

---

## 1 科技图标（P0，49 张）

用途：新科技树（仿文明 6）的节点图标、科技卡、纪事里「掌握了某项科技」。

规格：**512×512 透明 PNG**，圆形徽章构图：圆底座里一件最能代表这项科技的器物或小场景，四个时代可以用底座边框的质感区分（木、铜、铁、钢）。路径 `assets/techs/t01/tech_<id>.png`。

| 时代 | id | 名称 | 画什么 |
|---|---|---|---|
| 1 | crop_rotation | 轮作与新作物 | 豆麦相间的条田，田边一筐番薯与玉米 |
| 1 | water_management | 水利营造 | 石砌水闸与灌渠，水流分进田垄 |
| 1 | survey | 土地清丈 | 摊开的鱼鳞图册、丈杆与算盘 |
| 1 | granary_system | 常平仓法 | 高脚官仓、粮斗与一方官印 |
| 1 | movable_type | 活字印刷 | 排好的木活字版，刷了墨的印纸 |
| 1 | herbal_medicine | 本草 | 摊开的本草图谱、药碾与几味草药 |
| 1 | craft_guild | 行会工场 | 作坊里分工的几名工匠，墙上挂行会牌 |
| 1 | bookkeeping | 复式记账 | 账簿、算盘与商号印章 |
| 1 | harbor_works | 港务营造 | 石砌码头、吊杆与系泊的木帆船 |
| 1 | navigation | 海图与罗盘 | 海图上放着罗盘与牵星板 |
| 1 | water_power | 水力机械 | 铁箍水轮带动传动轴与木齿轮 |
| 2 | double_cropping | 双季稻 | 一半在收割、一半在插秧的水田 |
| 2 | sugar_refining | 甘蔗制糖 | 甘蔗捆、熬糖大锅与糖块 |
| 2 | water_frame | 水力纺纱 | 水力带动的一排纺锭 |
| 2 | flying_shuttle | 飞梭 | 织机上的飞梭与织好的布匹 |
| 2 | coal_iron | 煤炭冶铁 | 烧煤的炼铁炉与铁锭 |
| 2 | banking | 钱庄汇兑 | 钱庄柜台、银票与银锭 |
| 2 | canal_engineering | 运河营造 | 运河船闸与过闸的漕船 |
| 2 | glassmaking | 玻璃 | 吹玻璃的匠人与几件玻璃器 |
| 2 | chemistry_basic | 皂化 | 皂锅、成块的肥皂与蜡烛 |
| 2 | ocean_navigation | 远洋航海 | 远洋大帆船与六分仪 |
| 2 | steam_principle | 蒸汽原理 | 气缸剖面、活塞与沸腾的锅炉 |
| 2 | precision_mechanics | 精密机械 | 钟表齿轮、卡尺与小车床零件 |
| 3 | steam_engine | 蒸汽机 | 带大飞轮的蒸汽机 |
| 3 | coke_smelting | 焦炭炼铁 | 焦炭堆与冒火的高炉 |
| 3 | bessemer | 转炉炼钢 | 倾倒钢水的转炉，火花四溅 |
| 3 | machine_tools | 机床 | 皮带传动的车床与铣床 |
| 3 | railway | 铁路 | 蒸汽机车、铁轨与臂板信号 |
| 3 | chemistry | 化学工业 | 烧瓶、蒸馏塔与硫磺块 |
| 3 | fertilizer | 化肥 | 化肥麻袋与茁壮的禾苗 |
| 3 | cement | 水泥 | 水泥窑、成袋水泥与混凝土块 |
| 3 | canning | 罐头 | 罐头封装台与成排罐头 |
| 3 | telegraph | 电报 | 电报机、电报纸带与电线杆 |
| 3 | public_health | 公共卫生 | 公共自来水龙头与下水道剖面 |
| 3 | public_education | 新式教育 | 新式学堂的黑板、课桌与地球仪 |
| 3 | sericulture_science | 蚕桑改良 | 显微镜旁的蚕种与改良桑叶 |
| 3 | dynamo | 发电机 | 发电机线圈与转子，小灯泡亮起 |
| 3 | internal_combustion | 内燃机 | 内燃机气缸剖面与火花塞 |
| 4 | power_grid | 电网 | 输电铁塔与高压线 |
| 4 | electrochemistry | 电化学 | 电解槽、铝锭与铜板 |
| 4 | petrochemistry | 石油化工 | 油井井架与炼油塔 |
| 4 | automobile | 汽车 | 二十世纪中期的小汽车 |
| 4 | electronics | 电子管 | 发光的电子管与电路板 |
| 4 | television | 电视 | 显像管电视机 |
| 4 | antibiotics | 抗生素 | 药瓶、注射器与培养皿 |
| 4 | mechanized_farming | 农业机械化 | 拖拉机耕地 |
| 4 | automation | 自动化 | 机械臂与流水线 |
| 4 | computing | 计算机 | 大型计算机机柜与打孔卡 |
| 4 | solar_wind | 新能源 | 风力发电机与太阳能板 |

**P2 · 科技树时代底图（4 张）**：每个时代一条淡淡的横幅底纹，放在科技树对应时代的列后面。**2048×640 不透明**，很淡、不抢节点：第一时代田畴与水车、第二时代运河与工场、第三时代铁路与烟囱、第四时代电网与城市天际线。路径 `assets/techs/bg/tree_era<1-4>.png`。

---

## 2 政令配图与国家形态（P0）

用途：政令卡头图、政令页顶部的「国家形态」评价、纪事里的政令条目。

### 2.1 政令配图（42 张）

规格：**1024×640 不透明横幅**，与事件画同一画风，但构图更简洁、主体居中（会缩成 320×200 的卡片头图）。路径 `assets/decrees/d01/decree_<id>.png`；分档的政令每档一张：`decree_<id>_<档序号>.png`（从 0 开始）。

**开关类与运动类（22 张）**

| id | 名称 | 画什么 |
|---|---|---|
| land_survey | 清丈田亩 | 官员带丈量队在田间拉绳丈量，一旁士绅面色不悦 |
| single_whip | 一条鞭法 | 县衙前百姓以银完税，书吏合并赋役册 |
| ever_normal_granary | 常平仓 | 官仓开仓平粜，百姓排队买粮 |
| famine_relief | 赈济 | 施粥棚前官员放粮 |
| promote_schools | 兴学 | 书院讲学、乡学里孩童读书 |
| foreign_learning | 遣使译书 | 使节归国，译书馆里对照翻译外文书 |
| tea_horse | 茶马互市 | 边关集市上茶砖换马，马队与驼铃 |
| sell_titles | 捐纳 | 富商捐银换官帽，吏员登记 |
| corvee_works | 征发徭役 | 民夫修河堤，监工在旁（克制，不画打人） |
| reclamation | 招民垦荒 | 流民开垦林地、烧荒开田 |
| tax_remission | 蠲免钱粮 | 官员宣读免税告示，农户欢喜 |
| banking_license | 钱庄准入 | 票号开张、挂匾，柜上一摞银票 |
| industrial_charter | 工场特许 | 官府颁特许状，大工场开工 |
| official_press | 官办书局 | 官书局印刷，书籍成捆外运 |
| navigation_act | 航海条例 | 本国商船满载出港，码头查验外国船 |
| factory_act | 工厂法 | 工厂门口贴工时告示，工人按时下工 |
| income_tax | 所得税 | 税务局窗口前商人申报收入 |
| protective_tariff | 保护关税 | 海关提高税则，外国货在码头堆积 |
| compulsory_school | 初等义务教育 | 孩童背书包走进新式小学 |
| central_bank | 中央银行 | 中央银行大楼与统一的新钞票 |
| social_insurance | 社会保险 | 养老金发放窗口、医院与领救济的人 |
| environment_law | 环境保护法 | 工厂烟囱加装除尘，河水变清、植树 |

**分档的政令（20 张；其中「政体」「劳工」两项是这一轮要新加的政令）**

| id | 档 | 画什么 |
|---|---|---|
| sea_policy | 0 海禁 | 海岸封锁、水师巡逻，商船泊在港里不许出 |
| sea_policy | 1 限开 | 只开一处口岸，海关逐船查验 |
| sea_policy | 2 开海 | 港口繁忙，各国商船进出 |
| commerce_policy | 0 重农抑商 | 官员在田间劝农，集市冷清 |
| commerce_policy | 1 农商并重 | 田野与集市并立，人来人往 |
| commerce_policy | 2 恤商惠工 | 商铺林立、工坊兴旺 |
| salt_policy | 0 商销 | 盐商自运自销，盐船往来 |
| salt_policy | 1 官督商销 | 官员监督下盐商领引运盐 |
| salt_policy | 2 官卖 | 官盐店前百姓买贵盐，暗处有私盐贩 |
| railway_policy | 0 民营 | 铁路公司开业，商人剪彩 |
| railway_policy | 1 官督商办 | 官员与商人共同主持通车 |
| railway_policy | 2 国有 | 统一的国有铁路局与大车站 |
| regime（新） | 0 君主集权 | 金殿上的皇帝与跪拜的群臣 |
| regime（新） | 1 开明君主 | 君主与学者、商人围桌议事 |
| regime（新） | 2 君主立宪 | 议会大厅，君主坐在一侧，宪法卷册在案 |
| regime（新） | 3 议会共和 | 议会辩论与投票箱 |
| regime（新） | 4 社会主义 | 工人与农民代表大会，礼堂里举手表决（不画真实旗帜与标志） |
| labor_policy（新） | 0 严禁罢工 | 巡警驱散罢工工人，墙上贴禁令 |
| labor_policy（新） | 1 不加干预 | 工厂照常开工，工人与东家各忙各的 |
| labor_policy（新） | 2 工会合法 | 工会集会，劳资坐在一张桌前谈判 |

### 2.2 国家形态徽记（15 张）

用途：政令页顶部「当今国家」一栏，按政体和施政风格给一句评价（如「宽容仁厚的帝国」「严刑峻法的帝国」「堕落的工人国家」），配一枚徽记。规格：**768×768 透明**，盾牌或圆章，中间是政体的标志物，边饰表现施政风格。路径 `assets/regime/r01/regime_<政体>_<风格>.png`。

政体 5 种：`empire`（君主集权）、`enlightened`（开明君主）、`constitutional`（君主立宪）、`republic`（议会共和）、`socialist`（社会主义）。
风格 3 种：`benevolent`（宽仁：稻穗、粮仓、书卷一类边饰，暖色）、`steady`（守成：平稳的云纹、方正边框）、`harsh`（严苛：刀戟、锁链、冷色）。

例：`regime_empire_benevolent.png`（龙纹徽配稻穗）、`regime_empire_harsh.png`（龙纹徽配戟与锁链）、`regime_socialist_harsh.png`（齿轮麦穗徽配铁栅，表现「堕落的工人国家」）。

### 2.3 施政取向小图标（11 张）与政令分类图标（6 张）

规格：**256×256 透明**，与托管图标同一画风。路径 `assets/icons/policy/`。

- 取向：`axis_benevolent` 仁政（粥碗与稻穗）、`axis_harsh` 严苛（刑杖与锁）、`axis_central` 集权（官印与令箭）、`axis_laissez` 放任（敞开的城门）、`axis_agrarian` 重农（犁与禾）、`axis_mercantile` 重商（秤与钱袋）、`axis_industrial` 重工（齿轮与烟囱）、`axis_open` 开放（帆船与港口）、`axis_closed` 闭关（关门与铁锁）、`axis_traditional` 守旧（古书与香炉）、`axis_reform` 维新（新式学堂与地球仪）。
- 分类：`cat_fiscal` 税制与财政、`cat_welfare` 民生、`cat_culture` 文教、`cat_trade` 商贸、`cat_industry` 工业、`cat_state` 政体与劳工。

---

## 3 民生（P0 / P1）

### 3.1 阶层画像（P0，48 张）

用途：民生页四个阶层的卡片头像，表情随民心变化；季报与纪事里也会用。规格：**768×768 透明**，半身像，统一朝右三分之四侧面，背景透明；同一阶层、同一时代的三张服装与人物一致，只换表情和姿态。路径 `assets/classes/c01/class_<阶层>_e<时代>_<情绪>.png`。

情绪 3 种：`content`（满意：微笑、舒展）、`calm`（平常）、`angry`（不满：皱眉、握拳或叉腰）。

| 阶层 | 第一时代（e1） | 第二时代（e2） | 第三时代（e3） | 第四时代（e4） |
|---|---|---|---|---|
| peasant 农户 | 斗笠短褐的农夫，肩扛锄头 | 同上，衣着略好，手提稻穗 | 晚清民初的农民，布衣草鞋 | 二十世纪中后期的农民，草帽工装 |
| artisan 工匠 | 系围裙的手工匠人，拿锤凿 | 工场里的织工或冶工 | 产业工人，工装鸭舌帽 | 现代工人，安全帽与工作服 |
| merchant 商贾 | 长衫商人，手持算盘 | 票号东家，绸缎马褂 | 实业家，长衫配礼帽或早期西装 | 企业家，西装领带 |
| gentry 士绅 | 儒巾长袍的士大夫 | 同上，手持书卷 | 新式知识分子，长衫眼镜 | 专业人士，西装或白大褂、公文包 |

### 3.2 需要图标（P0，24 张）

用途：民生页每项需要的满足度（图标外圈按满足度上色）、季报。规格：**256×256 透明**。路径 `assets/icons/needs/need_<id>.png`。

| id | 名称 | 画什么 | id | 名称 | 画什么 |
|---|---|---|---|---|---|
| staple | 口粮 | 一碗米饭与米袋 | salt | 盐 | 盐罐与盐粒 |
| clothes | 衣 | 叠好的布衣 | fuel | 柴炭 | 柴捆与煤块 |
| greens | 蔬果 | 菜篮里的青菜与果子 | protein | 鱼肉 | 一条鱼与一块肉 |
| oil | 油 | 油壶 | wares | 器用 | 陶碗与铁锅 |
| light | 灯火 | 油灯（第四时代也用电灯泡，一张图里可都画） | medicine | 医药 | 药包与药瓶 |
| furniture | 家具 | 方桌与椅子 | tea | 茶 | 茶壶与茶杯 |
| drink | 酒 | 酒坛与酒碗 | letters | 纸墨 | 纸、笔与砚台 |
| books | 书籍 | 一摞线装书 | silk | 丝绸 | 一匹绸缎 |
| porcelain_lux | 瓷器 | 青花瓷瓶 | sugar | 糖 | 糖块与糖罐 |
| soap | 皂 | 几块肥皂 | spice | 香料 | 胡椒、肉桂 |
| power_home | 用电 | 电灯泡与插座 | appliance | 家电 | 电扇与收音机 |
| car | 出行 | 小汽车 | leisure | 游乐与服务 | 戏票与茶馆茶碗 |

### 3.3 情绪图标（P0，5 张）

用途：地区 × 阶层的「民心地图」、列表里的小脸。规格：**256×256 透明**，与画风一致的小人脸或戏曲脸谱式，不要表情包风格。路径 `assets/icons/mood/mood_<n>.png`：0 欢欣、1 满意、2 平静、3 不满、4 愤怒。

### 3.4 阶层生活场景（P1，16 张）

用途：民生页阶层卡展开后的头图，让人一眼看出这个阶层这个时代过得怎样。规格：**1536×1024 不透明**。路径 `assets/scenes/life/life_<阶层>_e<时代>.png`：农户（田间劳作、农家吃饭）、工匠（作坊、工厂车间）、商贾（铺面、商行、写字楼）、士绅（书房、衙署、学堂或医院），四个时代各一张。

---

## 4 纪事（P0 / P1）

### 4.1 纪事分类图标（P0，11 张）

规格：**256×256 透明**。路径 `assets/icons/chronicle/chr_<kind>.png`：`era` 时代、`crisis` 危机、`event` 事件、`build` 营造、`invest` 民间投资、`research` 科技、`decree` 政令、`fiscal` 财政、`trade` 外贸、`landmark` 地标、`steward` 托管。

### 4.2 里程碑画（P0，29 张）

用途：纪事「国史」里大事的配图（按年代排成图文并茂的编年史），也在发生当季弹出。规格：**1536×1024 不透明**，与事件画同一画风。路径 `assets/chronicle/m01/milestone_<id>.png`。

| id | 大事 | 画什么 |
|---|---|---|
| founding | 开局（1600 年） | 都城全景，新年里的街市与城楼 |
| first_waterframe | 第一座水力纺纱工场 | 河边水轮带动纺锭的工场，乡人围看 |
| first_bank | 第一家钱庄 | 钱庄开业挂匾、放鞭炮 |
| canal_open | 运河通航 | 新开运河上第一批漕船过闸 |
| ocean_fleet | 远洋船队启航 | 大帆船队鸣炮出港 |
| first_steam | 第一台蒸汽机 | 工厂里蒸汽机试车，众人围观 |
| first_steel | 第一炉钢 | 转炉出钢，钢水映红厂房 |
| first_railway | 第一条铁路通车 | 披红的火车头开出车站 |
| first_telegraph | 电报通达 | 电报局里发出第一封电报 |
| first_power | 第一座电厂发电 | 夜里城市第一次亮起电灯 |
| first_car | 第一辆汽车上路 | 街上汽车与马车并行 |
| first_tv | 电视进入寻常人家 | 一家人围看电视 |
| first_computer | 第一台计算机 | 机房里的大型计算机与操作员 |
| world_era2 | 世界进入工场时代 | 码头上外国商船卸下新式机器 |
| world_era3 | 世界进入蒸汽时代 | 外国铁甲舰与火车的画报传到茶馆 |
| world_era4 | 世界进入电气时代 | 外国城市灯火、电车的景象 |
| lead_era | 领先世界进入新时代 | 本国新物博览会，外国使节参观 |
| famine | 大饥荒 | 逃荒的人群与干裂的田地（克制） |
| revolt | 民变四起 | 城门外举火把聚集的民众（克制） |
| bankruptcy | 国库告罄 | 空空的银库，账房愁容 |
| mandate_shaken | 朝廷威信动摇 | 朝堂上群臣争执、奏折散落 |
| golden_age | 盛世 | 繁华街市、丰收节庆 |
| pop_milestone | 人口兴旺 | 熙熙攘攘的城镇 |
| treaty | 签订商约 | 与外国使节签约、交换文书 |
| regime_change | 政体更替 | 宣告新制度的广场仪式（不画真实旗帜） |
| complete_2000 | 四百年走完 | 2000 年现代城市俯瞰，古城墙与高楼同框 |
| gameover_fiscal | 终局：国库破产 | 债主堵门、衙门封库 |
| gameover_revolt | 终局：民变四起 | 被攻破的城门 |
| gameover_mandate | 终局：朝廷失去威信 | 空荡的朝堂、落地的冠冕 |

### 4.3 纪事装饰（P1，4 张，透明）

路径 `assets/ui/chronicle/`：`scroll_header.png` 卷轴页眉（1600×200）、`seal.png` 史官朱印（512×512，印文用纹样代替文字）、`divider.png` 分隔花纹（1200×80）、`decade_frame.png` 十年题签框（800×160）。

---

## 5 产业（P0 / P1）

- **部门图标（P0，4 张）**：**256×256 透明**，`assets/icons/sector/sector_<id>.png`：`agri` 农林牧渔（稻穗与渔网）、`manu` 手工与制造（铁砧与织机）、`energy` 能源（煤块与电闪）、`serv` 服务（茶馆与秤）。
- **部门横幅（P1，16 张）**：**1536×512 不透明**，`assets/scenes/sector/sector_<id>_e<时代>.png`，四个部门 × 四个时代的产业全景（例：农林牧渔第一时代是水田与牧场，第四时代是机耕农场；能源第一时代是炭窑与水轮，第四时代是电厂与电网）。
- **状态徽章（P0，5 张）**：**128×128 透明**，`assets/icons/status/status_<id>.png`：`short` 紧缺（空货架）、`glut` 积压（堆满的仓库）、`ok` 平稳（天平）、`import` 靠进口（进港的船）、`export` 能出口（出港的船）。
- **价格走势（P0，3 张）**：**128×128 透明**，`assets/icons/status/trend_<id>.png`：`up` 涨、`down` 跌、`flat` 持平。
- **货物层级（P1，4 张）**：**128×128 透明**，`assets/icons/status/tier_<n>.png`：0 原料（原木）、1 半成品（纱锭）、2 成品（衣服）、3 资本品（机器）。

---

## 6 界面通用小图标（P0，38 张）

规格：**128×128 透明**，简洁、在深色底上清楚，与托管图标同一画风。路径 `assets/icons/ui/`。

- 顶栏数值（8）：`stat_treasury` 国库（银锭）、`stat_balance` 每季收支（秤）、`stat_legitimacy` 朝廷威信（官印）、`stat_living` 百姓生活（饭碗与炊烟）、`stat_unemp` 失业（空手）、`stat_pop` 人口（人群）、`stat_gdp` 产值（货堆）、`stat_research` 研究点（书与灯）。
- 页签（9）：`tab_overview` 国情、`tab_map` 舆图、`tab_industry` 产业、`tab_modern` 改造、`tab_tech` 科技、`tab_policy` 政令、`tab_society` 民生、`tab_trade` 外贸、`tab_chronicle` 纪事。
- 按钮（6）：`btn_steward` 托管、`btn_saves` 存档、`btn_help` 怎么玩、`btn_ff` 快进、`btn_end_turn` 结束本季、`btn_undo` 撤回。
- 危机线（3）：`crisis_fiscal` 财政、`crisis_livelihood` 民生、`crisis_mandate` 威信。
- 危机阶段（4）：`stage_0` 平稳、`stage_1` 吃紧、`stage_2` 危急、`stage_3` 崩溃在即（同一图形，颜色由绿到红）。
- 时代（4）：`era_1` 农商、`era_2` 工场与商路、`era_3` 蒸汽与铁路、`era_4` 电气与现代国家。
- 地区徽记（4）：`region_beiyuan` 北原（麦穗与马）、`region_zhongzhou` 中州（京城与大河）、`region_haijia` 海岬（帆船与盐田）、`region_xiling` 西岭（山与矿镐）。

---

## 7 补齐建筑图（P2，20 张）

现在这些建筑在某个时代借的是别家的图，补一张专属的。规格同现有建筑图（**1254×1254 透明**）。路径 `assets/buildings/b20/<建筑 id>_<档>.png`，档为 `early` / `industrial` / `modern`。

| 建筑 | 档 | 现在借的 | 画什么 |
|---|---|---|---|
| paddy 水田 | industrial | 通用农田 | 水田里的抽水机与改良稻 |
| paddy 水田 | modern | 通用农田 | 插秧机与机耕水田 |
| coppermine 铜矿 | industrial | 铁矿 | 竖井铜矿、绿色矿脉 |
| coppermine 铜矿 | modern | 铁矿 | 露天铜矿与电铲 |
| kaolinpit 瓷土采场 | industrial | 铁矿 | 机械淘洗高岭土 |
| kaolinpit 瓷土采场 | modern | 铁矿 | 现代瓷土矿与传送带 |
| sandpit 砂场 | industrial | 铁矿 | 蒸汽筛砂机 |
| sandpit 砂场 | modern | 铁矿 | 挖砂船与传送带 |
| weaving 织布坊 | industrial | 纺纱坊 | 蒸汽动力织布厂 |
| weaving 织布坊 | modern | 纺纱坊 | 现代织布车间 |
| silkweave 织绸坊 | early | 纺纱坊 | 提花织机与绸匹 |
| silkreel 缫丝坊 | industrial | 桑园 | 蒸汽缫丝厂 |
| silkreel 缫丝坊 | modern | 桑园 | 现代缫丝车间 |
| sawmill 锯木坊 | industrial | 伐木场 | 蒸汽锯木厂 |
| sawmill 锯木坊 | modern | 伐木场 | 现代木材加工厂 |
| carrier 车马行 | industrial | 汽车厂 | 铁路货运站与货车厢 |
| carrier 车马行 | modern | 汽车厂 | 货运卡车场 |
| watermill 水力动力坊 | early | 蒸汽动力站 | 木水轮带动的碾坊 |
| steamplant 蒸汽动力站 | modern | 通用动力 | 二十世纪的锅炉房 |
| servicehall 服务行 | early | 通用作坊 | （可选）明清茶楼戏园，备将来提前开放 |

---

## 8 汇总

| 类别 | 张数 | 档 |
|---|---|---|
| 科技图标 | 49 | P0 |
| 科技树时代底图 | 4 | P2 |
| 政令配图 | 42 | P0 |
| 国家形态徽记 | 15 | P0 |
| 施政取向与政令分类图标 | 17 | P0 |
| 阶层画像 | 48 | P0 |
| 需要图标 | 24 | P0 |
| 情绪图标 | 5 | P0 |
| 阶层生活场景 | 16 | P1 |
| 纪事分类图标 | 11 | P0 |
| 里程碑画 | 29 | P0 |
| 纪事装饰 | 4 | P1 |
| 部门图标、状态徽章、价格走势 | 12 | P0 |
| 部门横幅、货物层级 | 20 | P1 |
| 界面通用小图标 | 38 | P0 |
| 补齐建筑图 | 20 | P2 |
| **合计** | **354** | P0 共 290 张 |

接入顺序建议（Codex 可以按这个顺序交付，Claude 收到一批接一批）：科技图标 → 阶层画像与需要图标 → 政令配图与国家形态 → 纪事 → 界面小图标 → 产业 → P1、P2。
