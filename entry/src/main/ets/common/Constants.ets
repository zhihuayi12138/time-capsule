/** 应用级常量：路由名、通知 ID 段、存储键。集中放置，避免各处硬编码字符串漂移。 */
export class Routes {
  static readonly HOME: string = 'Home';
  static readonly EDITOR: string = 'Editor';
  static readonly DETAIL: string = 'Detail';
  static readonly MINE: string = 'Mine';
  static readonly NOTIFY_SETTINGS: string = 'NotifySettings';
  static readonly BACKUP: string = 'Backup';
  static readonly ABOUT: string = 'About';
}

export class StoreKey {
  static readonly DB_NAME: string = 'timecapsule.db';
  static readonly PREF: string = 'timecapsule_pref';
  static readonly KEY_NOTIFY_ENABLED: string = 'notify_enabled';
  static readonly KEY_NOTIFY_GUIDED: string = 'notify_guided';
  static readonly KEY_LAST_BACKUP: string = 'last_backup_at';
  /** 到期当天的提醒钟点（时 / 分），默认 09:00 */
  static readonly KEY_REMIND_HOUR: string = 'remind_hour';
  static readonly KEY_REMIND_MINUTE: string = 'remind_minute';
}

export class NotifyId {
  /** 到期提醒的 notification id 基址，实际 id = BASE + capsule 序号 */
  static readonly BASE: number = 1000;
}
