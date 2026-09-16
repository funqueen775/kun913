extends Node

signal time_changed(snapshot: Dictionary)
signal phase_changed(phase_id: String)
signal main_event_reached(event: Dictionary)

const MINUTES_PER_DAY := 24 * 60
const DAYS_PER_MONTH := 30
const MINUTES_PER_REAL_SECOND := 6.0
const PHASES := [
	{"id": "dawn", "name": "清晨", "start": 6 * 60},
	{"id": "day", "name": "白天", "start": 8 * 60},
	{"id": "dusk", "name": "傍晚", "start": 17 * 60},
	{"id": "night", "name": "夜晚", "start": 19 * 60},
]
const MAIN_EVENTS := [
	{
		"id": "M1-E01", "month": 1, "day": 1, "hour": 9,
		"title": "新员工手册", "locationId": "B", "location": "B 科技丘 · 你的工位", "durationMinutes": 45,
		"story": "早上九点，B 区。你按工位号找到自己的位置。桌上只有一台还没开机的显示器，和一本被翻过很多次的册子。",
		"actTitle": "第一幕 · 进入行业",
		"situation": "weak",
		"cast": ["xiaoxiong", "wange"],
		"speakers": {
			"xiaoxiong": {"name": "小熊", "role": "比你早半年", "loadout": "bear_green_cardigan", "pos": "left"},
			"wange": {"name": "王哥", "role": "带你的人", "loadout": "bear_plaid_glasses", "pos": "right"},
		},
		"beats": [
			{"type": "narration", "text": "早上九点，B 区。\n\n你按工位号找到自己的位置。桌上只有一台还没开机的显示器，和一本被翻过很多次的册子。"},
			{"type": "say", "speaker": "xiaoxiong", "text": "你是今天来报到的吧？我叫小熊，比你早来半年。\n\n先别急着装环境。坐了十二个小时车的人我见多了——第一天硬上，第三天就蔫。"},
			{"type": "say", "speaker": "wange", "text": "新来的？"},
			{"type": "narration", "text": "他没停，往前走了两步，又回头。"},
			{"type": "say", "speaker": "wange", "text": "手册第三章别看太早。看了容易想太多。"},
			{"type": "say", "speaker": "xiaoxiong", "text": "别理他，他就是那么个人。\n\n册子在桌上，一共三章。你自己翻——比我嘴上说管用。"},
			{"type": "interact", "target": "handbook", "label": "桌上的《新员工手册》", "hint": "翻开看看（技术规范 / 协作流程 / 晋升通道）"},
			{"type": "choice", "prompt": "三章里，你先翻开哪一章？"},
		],
		"prompt": "三章里，你先翻开哪一章？", "hint": "三章都读得到，先翻哪章只说明你第一天最在意什么",
		"choices": [
			{"id": "option_a", "text": "技术规范。代码怎么写、什么必须标注。"},
			{"id": "option_b", "text": "协作流程。谁拍板、卡住了该找谁。"},
			{"id": "option_c", "text": "晋升通道。在这儿，人是怎么被看见的。"},
		],
		"outcome": {
			"option_a": "你把第一章读了两遍，在「生成式工具参与的代码要标注」那一条旁边画了道线。\n\n小熊瞥了一眼，什么都没说。三个月后你才明白，那道线是给未来的自己划的。",
			"option_b": "你翻到「该找谁」那页，停了一会儿，抬头看了看王哥走掉的方向。\n\n那页上写着：问他「为什么」，他不怕你问，怕你不问。",
			"option_c": "你直接翻到了最后一章。\n\n小熊看见你翻的页码，笑了一下：「挺实际。」他没评价，只是把自己的水杯往你这边推了推。",
		},
		"memoryNote": {
			"option_a": {"text": "第一天先弄懂了规矩", "tone": "gold"},
			"option_b": {"text": "第一天先弄清了人", "tone": "gold"},
			"option_c": {"text": "第一天就问「人怎么被看见」", "tone": "gray"},
		}
	},
	{
		"id": "M1-E02", "month": 3, "day": 1, "hour": 9,
		"title": "技术选型", "locationId": "A", "location": "A 总部 · 评审室", "durationMinutes": 60,
		"story": "Agent 编排层即将进入正式开发。评审会上，自研方案可控但周期较长，开源方案上线快却需要适配现有系统。\n\n负责人请你给出建议，这次决定会影响后续几个月的技术路线和交付节奏。",
		"prompt": "面对两条技术路线，你会怎样推进决策？", "hint": "权衡交付速度、长期控制力和验证成本",
		"choices": [
			{"id": "option_a", "text": "采用成熟开源方案，先完成核心流程，再逐步替换不满足需求的部分。"},
			{"id": "option_b", "text": "坚持完全自研，宁可延长工期，也要从一开始掌握全部技术细节。"},
			{"id": "option_c", "text": "用一周分别做最小原型，按稳定性、成本和扩展性评分后再决定。"},
		],
		"actTitle": "第一幕 · 进入行业",
		"situation": "medium",
		"cast": [
			{"name": "王哥", "role": "带你的人", "loadout": "bear_plaid_glasses", "pos": "left"},
			{"name": "陈工", "role": "直属 Leader", "loadout": "bear_beige_blazer", "pos": "right"},
		],
		"outcome": {
			"option_a": "方案当场就过了。三个月后核心流程上线，而那些「以后再替换」的部分一直留在那里——留到第十四个月。",
			"option_b": "你争取到了工期，也拿到了对每个细节的掌控权。第十六个月，这套底座成了团队里唯一没人敢动、也唯一没人全懂的东西。",
			"option_c": "两份原型摆上会桌，争论变成了看数据。多花的那一周，后面省回来的不止一个月。",
		},
		"memoryNote": {
			"option_a": {"text": "先上线的代价，半年后要还", "tone": "gray"},
			"option_b": {"text": "选了难走的那条路", "tone": "gold"},
			"option_c": {"text": "用数据代替了拍脑袋", "tone": "gold"},
		}
	},
	{
		"id": "M1-E03", "month": 5, "day": 1, "hour": 9,
		"title": "评测集要不要建", "locationId": "B", "location": "B 科技丘 · 工位", "durationMinutes": 60,
		"story": "首个版本距离交付只剩三周，团队却发现 Agent 的表现主要靠人工体验判断。\n\n建立完整评测集至少要投入两周，产品进度和质量保障发生了正面冲突。",
		"prompt": "工期紧张时，你会怎样处理评测问题？", "hint": "决定团队如何平衡短期交付与可验证的质量",
		"choices": [
			{"id": "option_a", "text": "立即投入两周建立完整评测集，必要时主动协商延期。"},
			{"id": "option_b", "text": "先建立覆盖关键场景的最小评测集，交付后再持续补全。"},
			{"id": "option_c", "text": "先按原计划上线，通过用户反馈收集问题，暂时不做评测集。"},
		],
		"actTitle": "第一幕 · 进入行业",
		"situation": "medium",
		"cast": [{"name": "王哥", "role": "带你的人", "loadout": "bear_plaid_glasses", "pos": "right"}],
		"outcome": {
			"option_a": "评测集上线第一周就抓出三个线上问题。交付晚了两周，但从那以后，没人再问「这个改动会不会弄坏什么」。",
			"option_b": "最小集覆盖了最关键的二十个场景。剩下的那一半，交付之后总有更紧急的事排在前面。",
			"option_c": "版本按时上线了。第十四个月那场演示之前，没有人能说清它到底变好了没有——包括你自己。",
		},
		"memoryNote": {
			"option_a": {"text": "为看不见的东西买了单", "tone": "gold"},
			"option_b": {"text": "说好交付后补的那一半", "tone": "gray"},
			"option_c": {"text": "没人知道它到底好不好", "tone": "gray"},
		}
	},
	{
		"id": "M1-E04", "month": 7, "day": 1, "hour": 23,
		"title": "AI 代码标注", "locationId": "B", "location": "B 科技丘 · 深夜工位", "durationMinutes": 50,
		"story": "深夜，你准备提交一个由 AI 辅助完成的关键 PR。代码已经通过本地检查，但团队还没有形成统一的 AI 使用标注规范。\n\n现在需要决定是否主动说明 AI 参与，以及如何对这部分代码负责。",
		"prompt": "提交这次 PR 时，你会怎样处理 AI 参与信息？", "hint": "你的选择会影响代码责任、团队信任和协作规范",
		"choices": [
			{"id": "option_a", "text": "在 PR 中明确标注 AI 辅助范围，并说明自己完成的验证和风险检查。"},
			{"id": "option_b", "text": "只提交代码和测试结果，除非评审者询问，否则不主动提及 AI。"},
			{"id": "option_c", "text": "先暂缓提交，和负责人确认团队的 AI 代码规范后再处理。"},
		],
		"actTitle": "第一幕 · 进入行业",
		"situation": "weak",
		"cast": [],
		"outcome": {
			"option_a": "你在 PR 描述里写清了哪部分是 AI 生成的、你验证了什么、哪一段你还没把握。评审开了二十分钟，其中十五分钟在讨论那个「没把握」。",
			"option_b": "PR 十分钟就过了，没人问起。你合上电脑，心里有个地方轻轻响了一声——像是什么东西被锁进了抽屉。",
			"option_c": "你压到第二天，先去问了规范。团队因此有了第一份 AI 代码标注约定，落款是你的名字。",
		},
		"memoryNote": {
			"option_a": {"text": "写清楚了自己做了什么", "tone": "gold"},
			"option_b": {"text": "那次我没写", "tone": "gray"},
			"option_c": {"text": "替团队定了一条规矩", "tone": "gold"},
		}
	},
	{
		"id":"M2-E05", "month":9, "day":1, "hour":15, "title":"客户临时加需求", "locationId":"C", "location":"C 创意水巷 · 咖啡外摆", "durationMinutes":45, "actTitle":"第二幕 · 真实需求与成本压力", "situation":"medium", "cast":[{"name":"小林","role":"产品","pos":"left"}],
		"story":"客户要求立刻加入情绪识别。你翻完投诉记录后发现，用户真正抱怨的是物流延误，而不是客服语气。", "prompt":"你怎样回应这次临时需求？", "hint":"先找问题，再承诺方案。",
		"choices":[{"id":"option_a","text":"照客户原话排进需求，先把情绪识别做出来。"},{"id":"option_b","text":"带着投诉数据解释根因，建议先修物流反馈链路。"},{"id":"option_c","text":"做一个小范围验证，同时约定下周复盘是否投入。"}],
		"outcome":{"option_a":"功能上线了，投诉却没有明显下降。你第一次看见“做完”和“解决”之间的距离。","option_b":"客户沉默了一会儿，同意先看真实链路。小林把那张投诉分类表存进了项目文件夹。","option_c":"范围被控制住了。下一周的数据没有替你做决定，但让每个人都能说清自己在赌什么。"}, "memoryNote":{"option_a":{"text":"先满足了表面的需求","tone":"gray"},"option_b":{"text":"从投诉里找到了真问题","tone":"gold"},"option_c":{"text":"把争论变成了小验证","tone":"gold"}}
	},
	{
		"id":"M2-E06", "month":11, "day":28, "hour":23, "title":"Token 成本爆了", "locationId":"B", "location":"B 科技丘 · 深夜工位", "durationMinutes":50, "actTitle":"第二幕 · 真实需求与成本压力", "situation":"strong", "cast":[{"name":"王哥","role":"技术导师","pos":"right"}],
		"story":"推理成本已经达到预算的三倍。监控屏上每一条曲线都在提醒你：上线速度背后，账单不会自己消失。", "prompt":"你先从哪里止血？", "hint":"成本、质量和维护债需要一起算。",
		"choices":[{"id":"option_a","text":"直接砍掉上下文，先让成本曲线停下来。"},{"id":"option_b","text":"补缓存和观测管线，再逐步替换高成本链路。"},{"id":"option_c","text":"换成更小模型，接受一部分回答质量下降。"}],
		"outcome":{"option_a":"账单降得很快，几个关键场景也开始失忆。第二天的投诉让你重新打开了被砍掉的上下文。","option_b":"处理不快，但每一步都有记录。王哥说，终于有人把“贵”拆成了能讨论的问题。","option_c":"短期预算过了线，边缘用户先感觉到了回答变钝。你把这件事记进了后续观察项。"}, "memoryNote":{"option_a":{"text":"先砍掉了上下文","tone":"gray"},"option_b":{"text":"把成本拆成了可验证的链路","tone":"gold"},"option_c":{"text":"为预算交换了体验","tone":"gray"}}
	},
	{
		"id":"M2-E07", "month":13, "day":1, "hour":10, "title":"保证不胡说", "locationId":"C", "location":"C 创意水巷 · 客户展厅", "durationMinutes":45, "actTitle":"第二幕 · 真实需求与成本压力", "situation":"medium", "cast":[{"name":"小林","role":"产品","pos":"left"},{"name":"陈工","role":"邻组 Leader","pos":"right"}],
		"story":"客户要求在合同上写“100% 不幻觉”。所有人都知道这句话不能兑现，但项目正等着签字。", "prompt":"面对绝对承诺，你怎么回答？", "hint":"说清边界不是推开责任。",
		"choices":[{"id":"option_a","text":"先答应下来，靠后续测试尽量把风险压低。"},{"id":"option_b","text":"明确不能保证，并提供引用、拒答和人工兜底方案。"},{"id":"option_c","text":"把承诺改为可测指标，约定验收场景和例外处理。"}],
		"outcome":{"option_a":"合同签得很快，团队后来花了更久解释那句“100%”为什么做不到。","option_b":"客户没有立刻点头，却开始认真问兜底流程。你们第一次把风险写进了合作本身。","option_c":"验收条款变长了，但每个人都知道下一次争执该回到哪张表。"}, "memoryNote":{"option_a":{"text":"接受了绝对承诺","tone":"gray"},"option_b":{"text":"把边界说在了签字前","tone":"gold"},"option_c":{"text":"把承诺改成了可验收规则","tone":"gold"}}
	},
	{
		"id":"M2-E08", "month":15, "day":1, "hour":16, "title":"熊熊有招训练对局", "locationId":"E", "location":"E 松风训练谷", "durationMinutes":30, "actTitle":"第二幕 · 真实需求与成本压力", "situation":"weak", "cast":[{"name":"小赵","role":"实习生","pos":"left"}],
		"story":"训练谷的活动本来只是放松。小赵把一叠妙招卡推到你面前，说今天不谈 KPI，试试看谁更会看局势。", "prompt":"这局你怎么打？", "hint":"本事件是节奏调节，不进入职业测评。",
		"choices":[{"id":"option_a","text":"抢先出强牌，尽快结束这局。"},{"id":"option_b","text":"留一张牌观察对方的习惯。"},{"id":"option_c","text":"先问规则边界，再决定怎么配合。"}],
		"outcome":{"option_a":"你赢得干脆，小赵却笑着说下局要换一副牌。","option_b":"你看出了他的假动作。这局结束时，两个人都比开始时更放松。","option_c":"规则讲清后，输赢反而不重要了。你们把这局当成了真正的休息。"}, "memoryNote":{"option_a":{"text":"训练谷里也想抢先","tone":"gray"},"option_b":{"text":"在游戏里先观察","tone":"gold"},"option_c":{"text":"把放松留给了自己","tone":"gold"}}
	},
	{
		"id":"M3-E09", "month":16, "day":1, "hour":23, "title":"连续加班后心悸", "locationId":"G", "location":"G 暖邻康护院", "durationMinutes":40, "actTitle":"第三幕 · 事故与责任", "situation":"strong", "cast":[],
		"story":"连续加班后，你在楼梯间停下来，心跳没有按预想恢复。手机上还有未读的项目消息。", "prompt":"这一晚你怎么处理？", "hint":"身体报警也是项目状态的一部分。",
		"choices":[{"id":"option_a","text":"回到工位，把今晚的任务做完再说。"},{"id":"option_b","text":"暂停工作，去康护院休息并告诉团队。"},{"id":"option_c","text":"把任务拆给同事，约定明早再接手。"}],
		"outcome":{"option_a":"你把任务交了出去，身体却没有因此得到答案。第二天的疲惫比任何告警都诚实。","option_b":"你第一次在项目最忙的时候停下来。团队没有散，反而开始补上原本没人认领的风险。","option_c":"交接并不完美，但你保住了明天继续判断的能力。"}, "memoryNote":{"option_a":{"text":"报警后仍选择硬扛","tone":"gray"},"option_b":{"text":"在最忙时停下来求助","tone":"gold"},"option_c":{"text":"把任务交给了团队","tone":"gold"}}
	},
	{
		"id":"M3-E10", "month":18, "day":1, "hour":14, "title":"客户现场 Demo 翻车", "locationId":"F", "location":"F 观澜会展码头 · 路演台", "durationMinutes":55, "actTitle":"第三幕 · 事故与责任", "situation":"strong", "cast":[{"name":"王哥","role":"技术导师","pos":"left"},{"name":"小林","role":"产品","pos":"right"}],
		"story":"最重要的客户面前，助手开始编造不存在的政策。大屏上的每一句话都把前期技术债推到台前。", "prompt":"你先做什么？", "hint":"公开失误时，先保护用户再保护叙事。",
		"choices":[{"id":"option_a","text":"立刻中止演示，如实说明问题并切到人工流程。"},{"id":"option_b","text":"继续演示，避开出错问题，争取把流程走完。"},{"id":"option_c","text":"现场展示已知边界与引用证据，请客户共同复测。"}],
		"outcome":{"option_a":"场面冷了下来，但错误没有继续扩大。散场后，客户问的是你们怎么复盘。","option_b":"演示被勉强撑完，录屏却留下了每个闪躲的瞬间。","option_c":"风险暴露得很清楚，信任也没有凭空消失。你们终于拥有了一次真实的验收。"}, "memoryNote":{"option_a":{"text":"路演台上先按下了暂停","tone":"gold"},"option_b":{"text":"试着绕过现场错误","tone":"gray"},"option_c":{"text":"把失误变成共同复测","tone":"gold"}}
	},
	{
		"id":"M3-E11", "month":20, "day":1, "hour":10, "title":"压测结果与预期冲突", "locationId":"A", "location":"A 总部 · 汇报室", "durationMinutes":50, "actTitle":"第三幕 · 事故与责任", "situation":"strong", "cast":[{"name":"陈工","role":"邻组 Leader","pos":"right"}],
		"story":"实际只能承受 800 QPS，产品却已对外承诺 2000 QPS。汇报室里每个人都在等一句好听的话。", "prompt":"你怎么汇报压测结果？", "hint":"数字不替你承担责任，但能让责任被看见。",
		"choices":[{"id":"option_a","text":"如实报告 800 QPS，并列出上线条件和补救计划。"},{"id":"option_b","text":"先给乐观预测，等优化完成再更新口径。"},{"id":"option_c","text":"把流量分级，限定首批客户并同步容量风险。"}],
		"outcome":{"option_a":"会议比预计更难开，但没有人再把风险当成意外。","option_b":"承诺暂时保住了，容量问题也开始变成下一个人的倒计时。","option_c":"上线范围变小了，团队却第一次把增长速度和系统能力放进同一张图。"}, "memoryNote":{"option_a":{"text":"把 800 QPS 说在了会上","tone":"gold"},"option_b":{"text":"先给出了乐观数字","tone":"gray"},"option_c":{"text":"用分级上线换取了空间","tone":"gold"}}
	},
	{
		"id":"M3-E12", "month":23, "day":1, "hour":11, "title":"Agent 出错了算谁的", "locationId":"A", "location":"A 总部 · 追责会议室", "durationMinutes":50, "actTitle":"第三幕 · 事故与责任", "situation":"strong", "cast":[{"name":"陈工","role":"邻组 Leader","pos":"left"},{"name":"小林","role":"产品","pos":"right"}],
		"story":"助手误向客户承诺补偿。有人说“模型自己说的”，有人说应该由产品承担。", "prompt":"面对追责，你站在哪个位置？", "hint":"系统没有替人承担责任的能力。",
		"choices":[{"id":"option_a","text":"把问题归到模型输出，建议先修提示词。"},{"id":"option_b","text":"认领流程责任，梳理谁设计、谁审核、谁上线。"},{"id":"option_c","text":"先补偿用户，同时建立高风险回复的审批机制。"}],
		"outcome":{"option_a":"提示词被改了，责任链却仍然空着。下一次问题来得更快。","option_b":"责任没有因此变轻，却第一次被拆成每个人能改的一段。","option_c":"补偿先落地，审批机制也留下来。你们终于把“谁负责”变成了可执行的流程。"}, "memoryNote":{"option_a":{"text":"把问题推回给了模型","tone":"gray"},"option_b":{"text":"认领了流程责任","tone":"gold"},"option_c":{"text":"先补偿再补机制","tone":"gold"}}
	},
	{
		"id":"M4-E13", "month":25, "day":1, "hour":10, "title":"重构路线", "locationId":"A", "location":"A 总部 · 白板室", "durationMinutes":50, "actTitle":"第四幕 · 重构与传承", "situation":"medium", "cast":[{"name":"王哥","role":"技术导师","pos":"left"},{"name":"陈工","role":"邻组 Leader","pos":"right"}],
		"story":"核心服务越来越难改。白板上，一边是三个月的大重构，另一边是能立刻上线的短期修补。", "prompt":"你选择怎样推进重构？", "hint":"重构不是逃离交付，也不能只靠拖延。",
		"choices":[{"id":"option_a","text":"启动完整重构，冻结新功能直到基础稳定。"},{"id":"option_b","text":"继续短期修补，把重构留到下个季度。"},{"id":"option_c","text":"拆出高风险链路，边交付边替换并公开进度。"}],
		"outcome":{"option_a":"速度慢了下来，团队也终于开始理解底座真正承担了什么。","option_b":"每一周都能交付一点，下一次改动却比上一次更害怕。","option_c":"过程不漂亮，但旧系统一点点退出了关键路径。"}, "memoryNote":{"option_a":{"text":"为底座按下了暂停","tone":"gold"},"option_b":{"text":"继续给旧系统打补丁","tone":"gray"},"option_c":{"text":"把重构拆进了交付","tone":"gold"}}
	},
	{
		"id":"M4-E14", "month":27, "day":1, "hour":10, "title":"要不要全自动", "locationId":"A", "location":"A 总部 · 评审室", "durationMinutes":45, "actTitle":"第四幕 · 重构与传承", "situation":"medium", "cast":[{"name":"小林","role":"产品","pos":"left"}],
		"story":"退款建议准确率达到 95%。产品希望关闭人工审核，让用户立刻得到结果。剩下的 5% 却刚好都是最难解释的边缘案例。", "prompt":"你如何划定自动化边界？", "hint":"准确率不等于每个用户都该被自动决定。",
		"choices":[{"id":"option_a","text":"达到指标就全自动，把人工留给投诉处理。"},{"id":"option_b","text":"保留人工审核，优先拦截高金额和低置信度案例。"},{"id":"option_c","text":"先灰度开放，让用户能看到理由并申请复核。"}],
		"outcome":{"option_a":"流程变快了，少数用户却找不到解释自己处境的入口。","option_b":"效率没有拉满，但最难的判断仍有人愿意接住。","option_c":"灰度数据让争论有了依据，复核入口也成了用户真正看得见的承诺。"}, "memoryNote":{"option_a":{"text":"把效率放在了复核前","tone":"gray"},"option_b":{"text":"为边缘案例留下了人工","tone":"gold"},"option_c":{"text":"给自动化留了复核入口","tone":"gold"}}
	},
	{
		"id":"M4-E15", "month":30, "day":1, "hour":14, "title":"实习生的署名", "locationId":"B", "location":"B 科技丘 · 工位", "durationMinutes":45, "actTitle":"第四幕 · 重构与传承", "situation":"medium", "cast":[{"name":"小赵","role":"实习生","pos":"left"},{"name":"老周","role":"资深","pos":"right"}],
		"story":"你发现资深同事把实习生做的工具挂在自己名下申报。小赵说“算了”，但提交记录还摆在仓库里。", "prompt":"你怎么处理署名问题？", "hint":"为弱势同事发声，也要让事实经得起复盘。",
		"choices":[{"id":"option_a","text":"私下提醒资深同事，把署名改回来。"},{"id":"option_b","text":"整理提交证据，在公开复盘中说明贡献归属。"},{"id":"option_c","text":"劝小赵别追究，先把关系维持住。"}],
		"outcome":{"option_a":"署名被悄悄改了，问题也只在几个人之间被看见。","option_b":"会议一度安静，但记录给了小赵一句不必自己争取的证明。","option_c":"事情过去得很快，小赵之后提交代码时却总会多看一眼自己的名字。"}, "memoryNote":{"option_a":{"text":"私下纠正了署名","tone":"gold"},"option_b":{"text":"用记录守住了贡献","tone":"gold"},"option_c":{"text":"把冲突留在了沉默里","tone":"gray"}}
	},
	{
		"id":"M4-E16", "month":32, "day":1, "hour":11, "title":"核心知识文档化", "locationId":"D", "location":"D 树影书院 · 阅览室", "durationMinutes":45, "actTitle":"第四幕 · 重构与传承", "situation":"weak", "cast":[{"name":"老周","role":"资深","pos":"right"}],
		"story":"系统终于稳定下来。你知道哪些坑不能再踩，也知道这些经验大多还只在几个人脑子里。", "prompt":"你怎样沉淀这套知识？", "hint":"传承需要能被新人实际使用。",
		"choices":[{"id":"option_a","text":"写完整手册、故障案例和决策背景，并安排新人演练。"},{"id":"option_b","text":"留一份简短 wiki，后续有人问再补。"},{"id":"option_c","text":"把关键步骤封进脚本，尽量不让人接触细节。"}],
		"outcome":{"option_a":"文档花了时间，新人却第一次能在不叫醒你的情况下排查问题。","option_b":"wiki 很快过期，下一次故障又从口口相传开始。","option_c":"操作变得简单，判断为何这样做仍然只属于少数人。"}, "memoryNote":{"option_a":{"text":"把踩坑写成了路标","tone":"gold"},"option_b":{"text":"留下了一页够用的 wiki","tone":"gray"},"option_c":{"text":"把经验封进了脚本","tone":"gray"}}
	},
	{
		"id":"M5-E17", "month":32, "day":18, "hour":20, "title":"副业边界", "locationId":"H", "location":"H 慢生活园 · 宿舍", "durationMinutes":40, "actTitle":"第五幕 · 边界与答辩", "situation":"medium", "cast":[],
		"story":"朋友邀你参与一个与公司业务擦边的 AI 外包，报酬不错，期限也刚好压在项目冲刺期。", "prompt":"你如何回应这份邀约？", "hint":"边界不只来自合同，也来自精力和信任。",
		"choices":[{"id":"option_a","text":"接下外包，晚上和周末挤时间完成。"},{"id":"option_b","text":"拒绝邀约，并说明与现有业务可能冲突。"},{"id":"option_c","text":"先向公司报备，确认边界后再决定是否参与。"}],
		"outcome":{"option_a":"收入多了一笔，睡眠也少了一截。你开始在两份承诺之间来回切换。","option_b":"你错过了机会，但没有把模糊地带留给未来解释。","option_c":"报备过程不轻松，却让这件事不再只由你一个人猜测。"}, "memoryNote":{"option_a":{"text":"把夜晚也卖给了外包","tone":"gray"},"option_b":{"text":"拒绝了擦边的机会","tone":"gold"},"option_c":{"text":"先让边界被看见","tone":"gold"}}
	},
	{
		"id":"M5-E18", "month":35, "day":1, "hour":14, "title":"Agent 该有人设吗", "locationId":"C", "location":"C 创意水巷 · 产品讨论区", "durationMinutes":45, "actTitle":"第五幕 · 边界与答辩", "situation":"medium", "cast":[{"name":"小林","role":"产品","pos":"left"},{"name":"小赵","role":"实习生","pos":"right"}],
		"story":"产品希望给 Agent 加上萌系人设来提升留存。有人担心用户会把陪伴感误当成真实关系。", "prompt":"你支持怎样的人设方案？", "hint":"体验设计也要对依赖和误解负责。",
		"choices":[{"id":"option_a","text":"强化亲密话术，让用户更愿意留下来。"},{"id":"option_b","text":"保留温度，但明确它是工具并避免排他性表达。"},{"id":"option_c","text":"只做功能型语气，不提供任何人格化表达。"}],
		"outcome":{"option_a":"留存曲线抬起来了，深夜消息里的依赖感也变得更重。","option_b":"语气有温度，边界也在。团队开始给高风险表达做单独检查。","option_c":"风险很低，用户也很难从系统里感到被理解。"}, "memoryNote":{"option_a":{"text":"把亲密感当作留存手段","tone":"gray"},"option_b":{"text":"给温度留了边界","tone":"gold"},"option_c":{"text":"选择了最克制的人设","tone":"gray"}}
	},
	{
		"id":"M5-E19", "month":37, "day":1, "hour":18, "title":"吹哨两难", "locationId":"A", "location":"A 总部 · 楼梯间", "durationMinutes":50, "actTitle":"第五幕 · 边界与答辩", "situation":"strong", "cast":[{"name":"陈工","role":"邻组 Leader","pos":"right"}],
		"story":"你发现另一条业务线夸大了效果数据。若公开指出，团队关系会受冲击；若不说，发布会后的代价可能更大。", "prompt":"你怎样处理这份数据？", "hint":"坚持事实不等于不考虑人。",
		"choices":[{"id":"option_a","text":"先私下找负责人，要求在发布前更正。"},{"id":"option_b","text":"保存证据并走正式渠道提交风险说明。"},{"id":"option_c","text":"不介入，认为不是自己的项目。"}],
		"outcome":{"option_a":"负责人很难堪，但数据在发布前被改回了真实样子。","option_b":"程序启动得很慢，证据却没有再被一句玩笑带过。","option_c":"发布会顺利结束。几周后用户拿着那组数字来问你们，为什么现实不是这样。"}, "memoryNote":{"option_a":{"text":"先把事实摆到负责人面前","tone":"gold"},"option_b":{"text":"为证据走了正式流程","tone":"gold"},"option_c":{"text":"把风险留给了别人","tone":"gray"}}
	},
	{
		"id":"M5-E20", "month":39, "day":1, "hour":10, "title":"终局答辩", "locationId":"A", "location":"A 总部 · 大会议室", "durationMinutes":60, "actTitle":"第五幕 · 边界与答辩", "situation":"strong", "cast":[{"name":"小赵","role":"接手编排层的新人","pos":"left"},{"name":"陈工","role":"答辩评审","pos":"right"}],
		"story":"小赵接手了你当年的编排层。随后，你站上答辩台，屏幕开始回放这些年每次选择留下的轨迹。", "prompt":"你如何讲述自己的成长？", "hint":"答辩不是替过去找借口，而是说明你如何继续负责。",
		"choices":[{"id":"option_a","text":"突出项目成果和关键指标，证明自己能交付。"},{"id":"option_b","text":"讲清失败、修正和团队共同承担的过程。"},{"id":"option_c","text":"强调个人判断，说明关键决定都由自己推动。"}],
		"outcome":{"option_a":"成果被看见，提问也落在那些没有写进指标的代价上。","option_b":"你没有把故事讲得漂亮，却让评审知道团队为什么还能继续往前。","option_c":"掌声很快响起，也有人问：当你离开时，谁还能做出同样的判断？"}, "memoryNote":{"option_a":{"text":"把成长讲成了成果","tone":"gray"},"option_b":{"text":"在答辩里承认了修正","tone":"gold"},"option_c":{"text":"把判断都归给了自己","tone":"gray"}}
	},
	{
		"id":"M6-E21", "month":41, "day":1, "hour":10, "title":"交接人不照做", "locationId":"D", "location":"D 树影书院 · 阅览室", "durationMinutes":45, "actTitle":"第六幕 · 传承与新局", "situation":"medium", "cast":[{"name":"小赵","role":"接班人","pos":"left"},{"name":"王哥","role":"技术导师","pos":"right"}],
		"story":"你带的新人没有照搬旧方案，而是提出一条更慢、却更适合当前业务的路线。你忽然听见自己当年最不愿意听的那句话。", "prompt":"你怎样回应接班人的方案？", "hint":"传承不是复制过去。",
		"choices":[{"id":"option_a","text":"坚持沿用成熟方案，先保证可控交付。"},{"id":"option_b","text":"要求她做最小验证，用证据决定是否转向。"},{"id":"option_c","text":"直接放手，让她按自己的路线承担结果。"}],
		"outcome":{"option_a":"交付很稳，你也看见了新人收起方案时的犹豫。","option_b":"验证没有替谁赢得争论，却让选择第一次真正属于她。","option_c":"她走得很快，团队也需要时间接住那条新路线的风险。"}, "memoryNote":{"option_a":{"text":"把成熟方案交给了新人","tone":"gray"},"option_b":{"text":"让新路线先接受验证","tone":"gold"},"option_c":{"text":"把决定和风险一起放手","tone":"gray"}}
	},
	{
		"id":"M6-E22", "month":43, "day":1, "hour":10, "title":"谁来定义成功", "locationId":"A", "location":"A 总部 · 指标复盘室", "durationMinutes":50, "actTitle":"第六幕 · 传承与新局", "situation":"medium", "cast":[{"name":"小林","role":"产品","pos":"left"},{"name":"陈工","role":"评审","pos":"right"}],
		"story":"项目数据很好看，但投诉集中在被自动拒绝的边缘案例。指标复盘会上，所有人都在问“成功”应该怎么算。", "prompt":"你支持哪种成功标准？", "hint":"指标要解释谁得到了帮助，也要解释谁被落下。",
		"choices":[{"id":"option_a","text":"继续用增长和转化做唯一主指标。"},{"id":"option_b","text":"加入申诉成功率与边缘案例人工复核指标。"},{"id":"option_c","text":"按不同用户群分别定义目标，再公开取舍。"}],
		"outcome":{"option_a":"数字依旧漂亮，被拒绝的人却仍然找不到入口。","option_b":"报表复杂了，边缘案例终于不再只是一行被忽略的备注。","option_c":"争论没有消失，但每个取舍都开始有了被说明的对象。"}, "memoryNote":{"option_a":{"text":"把增长当成唯一成功","tone":"gray"},"option_b":{"text":"把边缘案例放进指标","tone":"gold"},"option_c":{"text":"公开了不同人的取舍","tone":"gold"}}
	},
	{
		"id":"M6-E23", "month":45, "day":1, "hour":17, "title":"把故事说到哪一步", "locationId":"G", "location":"G 暖邻康护院 · 庭院", "durationMinutes":45, "actTitle":"第六幕 · 传承与新局", "situation":"medium", "cast":[{"name":"小林","role":"产品","pos":"left"}],
		"story":"客户想把一位受帮助用户的经历包装成宣传案例。当事人感谢你们，却希望保留距离，不想成为谁的品牌故事。", "prompt":"你怎样处理这份案例？", "hint":"真实经历不是可无限使用的素材。",
		"choices":[{"id":"option_a","text":"在去标识后完整发布，突出项目价值。"},{"id":"option_b","text":"只在获得逐项同意后使用，并保留随时撤回权。"},{"id":"option_c","text":"放弃这个案例，改用匿名汇总数据说明效果。"}],
		"outcome":{"option_a":"故事很打动人，你也知道当事人再难控制它会被讲到哪里。","option_b":"流程慢了些，信任却没有被一次传播透支。","option_c":"宣传少了一个高潮，团队保住了不把个人经历当工具的底线。"}, "memoryNote":{"option_a":{"text":"把故事交给了传播","tone":"gray"},"option_b":{"text":"给同意保留了撤回权","tone":"gold"},"option_c":{"text":"用汇总数据替代个人故事","tone":"gold"}}
	},
	{
		"id":"M6-E24", "month":48, "day":1, "hour":11, "title":"传承与新局终局答辩", "locationId":"F", "location":"F 观澜会展码头 · 公开复盘台", "durationMinutes":70, "actTitle":"第六幕 · 传承与新局", "situation":"strong", "cast":[{"name":"小赵","role":"接班人","pos":"left"},{"name":"陈工","role":"终局评审","pos":"right"}],
		"story":"你与接班人共同面对公开复盘：系统留下了什么、团队学会了什么、下一阶段应由谁负责。六幕选择都在这一天回到你面前。", "prompt":"你把什么交给下一阶段？", "hint":"终局不是结束，而是把可继续的判断交出去。",
		"choices":[{"id":"option_a","text":"交付一套稳定流程，要求团队严格沿用。"},{"id":"option_b","text":"交付原则、证据和复盘机制，让新人继续修正。"},{"id":"option_c","text":"交付个人经验，关键判断仍由自己最后拍板。"}],
		"outcome":{"option_a":"流程很完整，新的问题仍在流程外等待被看见。","option_b":"你留下的不是答案，而是一套愿意承认错误并继续学习的方法。","option_c":"经验被认真记下，团队也还在等什么时候能不再依赖你。"}, "memoryNote":{"option_a":{"text":"把稳定流程交给了未来","tone":"gray"},"option_b":{"text":"把复盘能力交给了未来","tone":"gold"},"option_c":{"text":"把最后判断留在自己手里","tone":"gray"}}
	},
]

var world_minute := 9 * 60
var running := true
var _last_phase := ""
var _minute_remainder := 0.0
var _completed_main_event_ids: Array[String] = []

func _ready() -> void:
	_emit_time_changed()

func _process(delta: float) -> void:
	if not running:
		return
	advance_minutes(delta * MINUTES_PER_REAL_SECOND)

func advance_minutes(minutes: float) -> void:
	_minute_remainder += maxf(0.0, minutes)
	var whole_minutes := floori(_minute_remainder)
	if whole_minutes <= 0:
		return
	_minute_remainder -= whole_minutes
	var target_minute := world_minute + whole_minutes
	var blocker := _first_blocking_event_between(world_minute, target_minute)
	if not blocker.is_empty():
		world_minute = _event_minute(blocker)
		running = false
		_emit_time_changed()
		main_event_reached.emit(blocker)
		return
	world_minute = target_minute
	_emit_time_changed()

func advance_days(days: int = 5) -> void:
	if not running:
		return
	advance_minutes(float(maxi(1, days) * MINUTES_PER_DAY))

## 以「一个月」为单位推进：把时间拨到下一个未完成主线事件的时点。
## 主线事件都挂在每月 1 日（月初即剧情），所以这一跳正好落在下一个月的开头；
## 事件结算后本月剩余的时间留给自由活动（小镇里自己安排）。
## 全部主线完成后退化为直接推进一个月，游戏继续自由漫游。
func advance_month() -> void:
	if not running:
		return
	var next := next_main_event()
	if next.is_empty():
		advance_days(DAYS_PER_MONTH)
		return
	var target := _event_minute(next)
	if target > world_minute:
		advance_minutes(float(target - world_minute))
		return
	# 目标事件时点已过（理论上被睡觉守卫挡住，不会走到这）：直接停在那件事上，绝不吞剧情。
	world_minute = target
	running = false
	_emit_time_changed()
	main_event_reached.emit(next)

## 睡觉：把时间拨到第二天早上，跨过午夜。
## 有主线事件守卫：如果这一觉会跨过某个未完成主线事件的时点（比如月初 23:00 的事件），
## 时间停在事件上而不是把它睡过去 —— 事件只在月初 1 日出现后，被睡掉一次就永远触不到了。
## 事件都在 9:00 / 23:00；停在 23:00 的事件上结算完，再睡一次就是次日早上。
func sleep_until_next_morning(hour: int) -> void:
	var day_index := world_minute / MINUTES_PER_DAY
	var target_minute := (day_index + 1) * MINUTES_PER_DAY + clampi(hour, 0, 23) * 60
	var blocker := _first_blocking_event_between(world_minute, target_minute)
	if not blocker.is_empty():
		world_minute = _event_minute(blocker)
		running = false
		_minute_remainder = 0.0
		_emit_time_changed()
		main_event_reached.emit(blocker)
		return
	world_minute = target_minute
	_minute_remainder = 0.0
	running = true
	_emit_time_changed()

func next_main_event() -> Dictionary:
	for event in MAIN_EVENTS:
		if not _completed_main_event_ids.has(String(event["id"])):
			return event.duplicate(true)
	return {}

func complete_main_event(event_id: String) -> bool:
	if not MAIN_EVENTS.any(func(event): return String(event["id"]) == event_id):
		return false
	if not _completed_main_event_ids.has(event_id):
		_completed_main_event_ids.append(event_id)
	running = true
	_emit_time_changed()
	return true

func _first_blocking_event_between(from_minute: int, to_minute: int) -> Dictionary:
	for event in MAIN_EVENTS:
		if _completed_main_event_ids.has(String(event["id"])):
			continue
		var event_minute := _event_minute(event)
		if event_minute >= from_minute and event_minute <= to_minute:
			return event
	return {}

func _event_minute(event: Dictionary) -> int:
	return ((int(event["month"]) - 1) * DAYS_PER_MONTH + (int(event["day"]) - 1)) * MINUTES_PER_DAY + int(event.get("hour", 9)) * 60

func set_running(value: bool) -> void:
	running = value

func snapshot() -> Dictionary:
	var total_days := world_minute / MINUTES_PER_DAY
	var minute_of_day := posmod(world_minute, MINUTES_PER_DAY)
	var month := total_days / DAYS_PER_MONTH + 1
	var day := posmod(total_days, DAYS_PER_MONTH) + 1
	var hour := minute_of_day / 60
	var minute := posmod(minute_of_day, 60)
	var phase := phase_for_minute(minute_of_day)
	return {
		"worldMinute": world_minute,
		"month": month,
		"day": day,
		"hour": hour,
		"minute": minute,
		"clock": "%02d:%02d" % [hour, minute],
		"phaseId": phase["id"],
		"phaseName": phase["name"],
	}

func phase_for_minute(minute_of_day: int) -> Dictionary:
	if minute_of_day < 6 * 60:
		return PHASES[3]
	if minute_of_day < 8 * 60:
		return PHASES[0]
	if minute_of_day < 17 * 60:
		return PHASES[1]
	if minute_of_day < 19 * 60:
		return PHASES[2]
	return PHASES[3]

func _emit_time_changed() -> void:
	var state := snapshot()
	var phase_id := String(state["phaseId"])
	if phase_id != _last_phase:
		_last_phase = phase_id
		phase_changed.emit(phase_id)
	time_changed.emit(state)
