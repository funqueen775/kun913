/**
 * 前端只上报原始行为，一切计算在服务端 —— 《后端开发方案 V1》§1 红线。
 *
 * 纪律：这个文件里不出现任何分数字段。客户端一旦能算出分（六维、能力雷达、大五……），
 * 抓包就能拿到标定答案，整套测评直接被破解。
 * 前端要做的只有两件事：把玩家看到的渲染出来、把玩家做的原样记下来。
 */

export type RawEvent = {
  type: string
  at: number
  payload?: Record<string, unknown>
}

const buffer: RawEvent[] = []

/** 记一条原始行为。开发期打到控制台，正式环境由 flush() 批量提交。 */
export function report(type: string, payload?: Record<string, unknown>) {
  const evt: RawEvent = { type, at: Date.now(), payload }
  buffer.push(evt)
  if (import.meta.env.DEV) {
    console.debug('[report]', evt)
  }
}

/** 取走并清空缓冲区 —— TODO(M4)：POST /api/events 批量上报，失败要重试 */
export function flush(): RawEvent[] {
  return buffer.splice(0, buffer.length)
}
