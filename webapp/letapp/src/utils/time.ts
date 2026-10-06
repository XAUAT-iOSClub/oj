// 统一以 UTC+8（Asia/Shanghai）展示时间，避免按浏览器本地时区偏移。
// 后端数据库与应用进程均使用 Asia/Shanghai（UTC+8），但部分接口返回的 datetime 是
// 不带时区的“墙钟”字符串；为让所有访客（无论所在时区）看到一致的 UTC+8 时间，
// 这里把 naive 字符串按 Asia/Shanghai 解释，并强制以 Asia/Shanghai 格式化输出。

const TIME_ZONE = 'Asia/Shanghai';

function toDate(value: unknown): Date | null {
  if (value == null || value === '') return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (typeof value === 'number') {
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  let s = String(value).trim();
  // 已带时区（Z 或 ±HH:MM）的绝对时间，直接解析
  if (/z$/i.test(s) || /[+-]\d{2}:?\d{2}$/.test(s)) {
    const d = new Date(s);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  // 后端返回的是“Asia/Shanghai 墙钟”的 naive 字符串，补 +08:00 以保证按 UTC+8 解释
  if (/^\d{4}-\d{2}-\d{2}/.test(s)) {
    s = s.replace(' ', 'T') + '+08:00';
    const d = new Date(s);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? null : d;
}

export function formatDate(value: unknown, options?: Intl.DateTimeFormatOptions): string {
  const d = toDate(value);
  if (!d) return '';
  return d.toLocaleDateString('zh-CN', { timeZone: TIME_ZONE, ...options });
}

export function formatDateTime(value: unknown, options?: Intl.DateTimeFormatOptions): string {
  const d = toDate(value);
  if (!d) return '';
  return d.toLocaleString('zh-CN', { timeZone: TIME_ZONE, ...options });
}

export function formatTime(value: unknown, options?: Intl.DateTimeFormatOptions): string {
  const d = toDate(value);
  if (!d) return '';
  return d.toLocaleTimeString('zh-CN', { timeZone: TIME_ZONE, ...options });
}

// 判断当前时间是否处于比赛设定的时间范围内（开始时间 <= 现在 <= 结束时间）。
// 仅设置开始时间：开始后可进入；仅设置结束时间：结束前可进入；
// 两者都未设置：视为无时间限制，允许进入。
// 传入 nowMs 可基于指定时刻判定（用于随时间实时刷新）。
export function isWithinTimeRange(start?: string | null, end?: string | null, nowMs: number = Date.now()): boolean {
  const s = toDate(start)?.getTime();
  const e = toDate(end)?.getTime();
  if (s != null && nowMs < s) return false;
  if (e != null && nowMs > e) return false;
  return true;
}

// 一周内的相对时间标签（今天 / 昨天 / N 天前），超过一周退回具体月日。
// 学习资料的目录列表与"最近浏览"共用，避免两处各写一份且慢慢不一致。
export function formatRelativeTime(
  value: unknown,
  options?: Intl.DateTimeFormatOptions,
): string {
  const d = toDate(value);
  if (!d) return '';
  const diff = Date.now() - d.getTime();
  const DAY = 86_400_000;
  if (diff < DAY) return '今天';
  if (diff < 2 * DAY) return '昨天';
  if (diff < 7 * DAY) return `${Math.floor(diff / DAY)} 天前`;
  return formatDate(value, options ?? { month: 'short', day: 'numeric' });
}
