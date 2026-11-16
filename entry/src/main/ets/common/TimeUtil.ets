/**
 * 时间工具：胶囊列表里的「距离开启还有 N 天」与「已等待 N 天」都走这里，
 * 保证同一份数据在不同页面显示一致。
 */
export class TimeUtil {
  static readonly DAY: number = 24 * 60 * 60 * 1000;

  /** 距离开启还剩几天，向上取整；已到期返回 0 */
  static daysLeft(openAt: number, now: number = Date.now()): number {
    const diff = openAt - now;
    if (diff <= 0) {
      return 0;
    }
    return Math.ceil(diff / TimeUtil.DAY);
  }

  /** 已经等待了几天，向下取整 */
  static daysWaited(createdAt: number, now: number = Date.now()): number {
    const diff = now - createdAt;
    if (diff <= 0) {
      return 0;
    }
    return Math.floor(diff / TimeUtil.DAY);
  }

  /** 是否已经到期 */
  static isDue(openAt: number, now: number = Date.now()): boolean {
    return now >= openAt;
  }

  private static pad(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  /** 2026.10.19 09:41 */
  static format(ts: number): string {
    const d = new Date(ts);
    const y = d.getFullYear();
    const m = TimeUtil.pad(d.getMonth() + 1);
    const day = TimeUtil.pad(d.getDate());
    const hh = TimeUtil.pad(d.getHours());
    const mm = TimeUtil.pad(d.getMinutes());
    return `${y}.${m}.${day} ${hh}:${mm}`;
  }

  /** 10月19日 */
  static formatCNDate(ts: number): string {
    const d = new Date(ts);
    return `${d.getMonth() + 1}月${d.getDate()}日`;
  }

  /** 顶部胶囊标签文案：已封存 · 还剩 87 天 / 已等待 365 天 · 刚刚开启 */
  static pendingLabel(openAt: number, now: number = Date.now()): string {
    const left = TimeUtil.daysLeft(openAt, now);
    if (left <= 0) {
      return '可以打开了';
    }
    return `还剩 ${left} 天`;
  }
}
