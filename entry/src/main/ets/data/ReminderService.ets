import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Capsule, CapsuleStatus } from '../model/Capsule';
import { TimeUtil } from '../common/TimeUtil';
import { AppCtx } from '../common/AppCtx';

const TAG = 'TimeCapsule';
const DOMAIN = 0x0001;

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
   * 上一次排程失败的原因。空串表示上次是成功的。
   * 排程失败不该静默吞掉 —— 用户「以为设了提醒，其实没设」比"没有提醒"更糟，
   * 界面要能据此提示"系统提醒没排上，打开应用时仍会标到期"。
   */
  static lastError: string = '';
  /**
   * 提醒时间（24 小时制），由「我的 → 提醒时间」写入。
   * 之前这里直接用 openAt 的时分，等于用户没法选择什么时候被提醒；
   * 现在按设置里定的时刻提醒，但仍然保证不早于胶囊可打开的时间。
   */
  static remindHour: number = 9;
  static remindMinute: number = 0;

  /**
   * 算出这条胶囊实际该在什么时候提醒。
   *
   * 规则：取「开启那天的 remindHour:remindMinute」；
   * 若那一刻早于 openAt（例如 15:00 开启、提醒设在 09:00），
   * 就退回到 openAt 本身 —— 提前提醒一个还打不开的胶囊是噪音。
   */
  static fireAt(openAt: number): number {
    const d = new Date(openAt);
    const at = new Date(d.getFullYear(), d.getMonth(), d.getDate(),
      ReminderService.remindHour, ReminderService.remindMinute, 0, 0).getTime();
    return at < openAt ? openAt : at;
  }

  /**
   * 为待开启胶囊排程系统提醒。
   * reminderAgent 只支持未来时间点，所以已到期的不排（改走即时通知）。
   * 返回分配到的 reminderId（失败返回 undefined）。
   */
  static async schedule(c: Capsule): Promise<number | undefined> {
    if (c.status !== CapsuleStatus.Pending) {
      return undefined;
    }
    const at = ReminderService.fireAt(c.openAt);
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
      ReminderService.lastError = '';
      return id;
    } catch (e) {
      const err = e as BusinessError;
      ReminderService.lastError = `publishReminder ${err.code}: ${err.message}`;
      hilog.error(DOMAIN, TAG, 'publishReminder failed: %{public}d %{public}s', err.code, err.message);
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

  /**
   * 请求通知权限。
   *
   * requestEnableNotification 在多数情况下只弹一次，用户在弹窗里拒绝过之后
   * 系统就不再弹了（直接返回成功但实际仍关闭）。所以这里不用它的返回值判断，
   * 而是弹完再查一次真实状态；仍然是关的就说明用户拒过，
   * 交给界面引导用户去系统设置里打开（openNotificationSettings）。
   */
  static async requestPermission(): Promise<boolean> {
    try {
      if (await notificationManager.isNotificationEnabled()) {
        return true;
      }
      try {
        await notificationManager.requestEnableNotification(AppCtx.get());
      } catch (e) {
        const err = e as BusinessError;
        hilog.warn(DOMAIN, TAG, 'requestEnableNotification %{public}d: %{public}s', err.code, err.message);
      }
      const ok = await notificationManager.isNotificationEnabled();
      ReminderService.lastError = ok ? '' : '通知未授权';
      return ok;
    } catch (e) {
      return false;
    }
  }

  /** 当前系统是否允许发通知（开应用、从设置页回来时都查一次） */
  static async isGranted(): Promise<boolean> {
    try {
      return await notificationManager.isNotificationEnabled();
    } catch (e) {
      return false;
    }
  }

  /** 打开系统的通知设置页，用于用户拒绝过之后重新授权 */
  static async openSettings(): Promise<void> {
    try {
      await notificationManager.openNotificationSettings(AppCtx.get());
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'openNotificationSettings %{public}d: %{public}s', err.code, err.message);
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
      const f = ReminderService.fireAt(c.openAt);
      const early = f > c.openAt;
      const hh = ReminderService.remindHour < 10 ? `0${ReminderService.remindHour}` : `${ReminderService.remindHour}`;
      const mm = ReminderService.remindMinute < 10 ? `0${ReminderService.remindMinute}` : `${ReminderService.remindMinute}`;
      return early ? `到期当天 ${hh}:${mm} 提醒` : `可以打开时提醒（${TimeUtil.formatClock(f)}）`;
    }
    return '不提醒';
  }
}
