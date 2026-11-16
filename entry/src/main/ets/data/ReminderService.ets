import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { Capsule, CapsuleStatus } from '../model/Capsule';
import { TimeUtil } from '../common/TimeUtil';
import { AppCtx } from '../common/AppCtx';

/**
 * 到期提醒服务。
 *
 * 两条腿走路：
 * 1. reminderAgentManager 日历提醒 —— 系统级闹钟，应用被杀掉也会准时弹，是主路径。
 *    （立项书里写的"通知送达单点失败风险"就靠它兜底）
 * 2. notificationManager 即时通知 —— 应用在前台时用，给到期的胶囊立刻补一条。
 *
 * 提醒文案刻意不透露内容：只写"有一个胶囊到时间了"，避免锁屏上泄露。
 */
export class ReminderService {
  /**
   * 为待开启胶囊排程系统提醒。
   * reminderAgent 只支持未来时间点，所以已到期的不排（改走即时通知）。
   * 返回分配到的 reminderId（失败返回 undefined）。
   */
  static async schedule(c: Capsule): Promise<number | undefined> {
    if (c.status !== CapsuleStatus.Pending) {
      return undefined;
    }
    const at = c.openAt;
    if (at <= Date.now() + 60 * 1000) {
      // 一分钟内到期的不排程，直接靠前台刷新
      return undefined;
    }
    const d = new Date(at);
    const request: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: {
        year: d.getFullYear(),
        month: d.getMonth() + 1,
        day: d.getDate(),
        hour: d.getHours(),
        minute: d.getMinutes(),
        second: 0
      },
      title: '有一个胶囊到时间了',
      content: '你有个约定，可以打开了',
      expiredContent: '这个胶囊已经可以打开了',
      notificationId: 1000 + (Math.abs(ReminderService.hash(c.id)) % 1000),
      wantAgent: {
        pkgName: AppCtx.get().applicationInfo.name,
        abilityName: 'EntryAbility',
        uri: `timecapsule://detail/${c.id}`
      }
    };
    try {
      const id = await reminderAgentManager.publishReminder(request);
      return id;
    } catch (e) {
      return undefined;
    }
  }

  /** 取消已排程的提醒（胶囊被提前打开或删除时） */
  static async cancel(reminderId: number | undefined): Promise<void> {
    if (reminderId === undefined) {
      return;
    }
    try {
      await reminderAgentManager.cancelReminder(reminderId);
    } catch (e) {
      // 已过期/已消失，忽略
    }
  }

  /** 应用内的即时通知（前台补发） */
  static async notifyNow(c: Capsule): Promise<void> {
    const request: notificationManager.NotificationRequest = {
      id: 1000 + (Math.abs(ReminderService.hash(c.id)) % 1000),
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: '有一个胶囊到时间了',
          text: '你有个约定，可以打开了',
          additionalText: '时间胶囊'
        }
      }
    };
    try {
      await notificationManager.publish(request);
    } catch (e) {
      // 用户关了通知权限，静默失败
    }
  }

  /** 撤销即时通知 */
  static async cancelNotify(c: Capsule): Promise<void> {
    try {
      await notificationManager.cancel(1000 + (Math.abs(ReminderService.hash(c.id)) % 1000));
    } catch (e) {
      // 没有也正常
    }
  }

  /** 请求通知权限（首次进入时调用） */
  static async requestPermission(): Promise<boolean> {
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      if (enabled) {
        return true;
      }
      await notificationManager.requestEnableNotification(AppCtx.get());
      return await notificationManager.isNotificationEnabled();
    } catch (e) {
      return false;
    }
  }

  /** 简单的字符串散列，用来把胶囊 id 稳定映射到通知 id 段 */
  private static hash(s: string): number {
    let h = 0;
    for (let i = 0; i < s.length; i++) {
      h = (h * 31 + s.charCodeAt(i)) | 0;
    }
    return h;
  }

  /**
   * 启动时对齐一次：给所有待开启且还没排程的胶囊补排程。
   * 不处理已到期的（那条由首页到期卡与即时通知承担）。
   */
  static async syncAll(list: Capsule[]): Promise<Capsule[]> {
    const now = Date.now();
    for (const c of list) {
      if (c.status !== CapsuleStatus.Pending) {
        continue;
      }
      if (c.openAt <= now || c.openAt <= now + 60 * 1000) {
        continue;
      }
      if (c.reminderId === undefined) {
        const id = await ReminderService.schedule(c);
        if (id !== undefined) {
          c.reminderId = id;
        }
      }
    }
    return list;
  }

  /** 供 UI 展示的提醒描述（与「我的」页一致） */
  static describe(c: Capsule): string {
    if (c.status === CapsuleStatus.Pending) {
      return `到期当天 ${TimeUtil.formatClock(c.openAt)} 提醒`;
    }
    return '不提醒';
  }
}
