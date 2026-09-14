/**
 * 五只熊的唯一口径。
 *
 * 剧情与职衔来源：《事件场景与人物对照表 V2》《剧情设计详细方案 V5.27》§3
 * 出场次数（决定谁进「推荐组合」）：小林 13 · 王哥 12 · 老周 12 · 陈工 11 · 小赵 9
 *
 * 立绘：美术组尚未交付，先用同画风的 SVG 头像占位（fur / inner / accessory 三个色与形参数）。
 * 真立绘到位后，把 BearAvatar 换成 <img src={portrait}> 即可，其余布局不用动。
 */

export type BearAccessory = 'glasses' | 'collar' | 'headset' | 'brow' | 'cap'

export type Bear = {
  id: string
  name: string
  role: string
  place: string
  line: string
  /** 机制上的例外，用一枚小徽章说清楚 —— 边界本身就是叙事 */
  note?: string
  /** 占位头像的三个参数：毛色 / 耳内色 / 配件 */
  fur: string
  inner: string
  accessory: BearAccessory
  /** 是否进「推荐组合」 */
  recommended: boolean
  /** 不可选：已定「事务型上级，不进关系系统」 */
  selectable: boolean
}

export const ROSTER: Bear[] = [
  {
    id: 'wange',
    name: '王哥',
    role: '技术 · 你的导师',
    place: '工位右侧走廊',
    line: '爱泼冷水，但认可扎实的调研。他说「别折腾」的时候，一般是真心话。',
    fur: '#C99A63',
    inner: '#F2E3C2',
    accessory: 'glasses',
    recommended: true,
    selectable: true,
  },
  {
    id: 'chengong',
    name: '陈工',
    role: '邻组 Leader',
    place: '长桌主位',
    line: '话少，只问结论和成本。不陪你聊天，但会记住你兑现过什么。',
    note: '不进关系系统',
    fur: '#9A9A93',
    inner: '#E6E6DF',
    accessory: 'collar',
    recommended: false,
    selectable: false,
  },
  {
    id: 'xiaolin',
    name: '小林',
    role: '产品',
    place: '创意水巷',
    line: '被客户催得急，语速偏快。先把需求塞给你，再跟你一起想办法。',
    fur: '#D8B27E',
    inner: '#FBF0D8',
    accessory: 'headset',
    recommended: true,
    selectable: true,
  },
  {
    id: 'laozhou',
    name: '老周',
    role: '资深',
    place: '会议室',
    line: '在听，等着看谁认领。年轻时也被侵占过署名——他知道那是什么滋味。',
    fur: '#8A7A6A',
    inner: '#DCCDB4',
    accessory: 'brow',
    recommended: true,
    selectable: true,
  },
  {
    id: 'xiaozhao',
    name: '小赵',
    role: '实习生',
    place: '走廊 · 看守记忆墙',
    line: '常在被帮助的位置。深夜路过会停一拍：「师兄还没走？」',
    fur: '#E4D3B4',
    inner: '#FFF7E6',
    accessory: 'cap',
    recommended: false,
    selectable: true,
  },
]

/** 开局名额上限 */
export const PICK_LIMIT = 3

export const RECOMMENDED_IDS = ROSTER.filter((b) => b.recommended).map((b) => b.id)
