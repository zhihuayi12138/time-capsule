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

  /**
   * 卡片上的倒计时文案。
   * 差一天以内不再说"还有 1 天"——那会让只剩两小时的胶囊看起来还很远。
   */
  static countdown(openAt: number, now: number = Date.now()): string {
    const diff = openAt - now;
    if (diff <= 0) {
      return '';
    }
    const day = TimeUtil.DAY;
    if (diff < 60 * 60 * 1000) {
      const mins = Math.max(1, Math.ceil(diff / (60 * 1000)));
      return `距离开启还有 ${mins} 分钟`;
    }
    if (diff < day) {
      const hours = Math.ceil(diff / (60 * 60 * 1000));
      return `距离开启还有 ${hours} 小时`;
    }
    return `距离开启还有 ${Math.ceil(diff / day)} 天`;
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

  /** 09:00 */
  static formatClock(ts: number): string {
    const d = new Date(ts);
    return `${TimeUtil.pad(d.getHours())}:${TimeUtil.pad(d.getMinutes())}`;
  }

  /** 把秒数格式化成 0:42 / 1:05，用于语音块时长 */
  static clock(seconds: number): string {
    const s = seconds < 0 ? 0 : Math.floor(seconds);
    const m = Math.floor(s / 60);
    const r = s % 60;
    return `${m}:${TimeUtil.pad(r)}`;
  }

  /** 2027.10.19（不含时分，用于胶囊编辑器的开启时间摘要） */
  static formatDate(ts: number): string {
    const d = new Date(ts);
    return `${d.getFullYear()}.${TimeUtil.pad(d.getMonth() + 1)}.${TimeUtil.pad(d.getDate())}`;
  }

  /**
   * 把「今天 / 明天 / N 天后」这类相对说法换算成时间戳的显示文案。
   * 用于详情页与封存弹层的开启时间摘要。
   */
  static relativeDay(ts: number, now: number = Date.now()): string {
    const days = TimeUtil.daysLeft(ts, now);
    if (days <= 0) {
      return '今天';
    }
    if (days === 1) {
      return '明天';
    }
    return `${days} 天后`;
  }

  /** 把「之后 N 天 / N 个月 / N 年」换算成时间戳（从 base 起） */
  static shiftDays(base: number, days: number): number {
    return base + days * TimeUtil.DAY;
  }

  /**
   * 把时间戳规整到当天某个整点分钟：用于「开启时间」的默认值，
   * 避免用户选到 03:47 这种奇怪的时刻。
   */
  static atClock(ts: number, hour: number, minute: number): number {
    const d = new Date(ts);
    d.setHours(hour, minute, 0, 0);
    return d.getTime();
  }
}
