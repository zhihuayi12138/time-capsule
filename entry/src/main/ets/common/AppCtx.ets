import { common } from '@kit.AbilityKit';

/**
 * 全局 UIAbilityContext 持有者。
 *
 * 数据层（RDB / preferences / 文件）都需要 Context，但 @Component 里拿不到，
 * 所以在 EntryAbility.onCreate 里注入一次，其余地方通过 AppCtx.get() 取。
 */
export class AppCtx {
  private static ctx?: common.UIAbilityContext = undefined;

  static set(context: common.UIAbilityContext): void {
    AppCtx.ctx = context;
  }

  static get(): common.UIAbilityContext {
    const c = AppCtx.ctx;
    if (c === undefined) {
      throw new Error('AppCtx 尚未初始化：EntryAbility.onCreate 必须先调用 AppCtx.set');
    }
    return c;
  }

  static ready(): boolean {
    return AppCtx.ctx !== undefined;
  }

  /** 沙箱内保存图片/音频的目录（绝对路径，不带尾斜杠） */
  static mediaDir(): string {
    return `${AppCtx.get().filesDir}/media`;
  }

  /** 导出备份的临时目录 */
  static exportDir(): string {
    return `${AppCtx.get().cacheDir}/export`;
  }
}
