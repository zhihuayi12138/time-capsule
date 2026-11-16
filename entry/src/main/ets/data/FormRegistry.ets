import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { AppCtx } from '../common/AppCtx';
import { MediaRepo } from './MediaRepo';

/**
 * 桌面卡片的注册表。
 *
 * 卡片是独立进程，主应用想主动刷新卡片就必须知道 cardId，
 * 而 cardId 只在 FormExtensionAbility 的回调里出现过。
 * 所以卡片被添加时把 cardId 记到沙箱文件里，主应用数据一变就读出来批量刷新。
 *
 * 用文件而不是 preferences：两个进程共享同一个 filesDir，
 * 但 preferences 需要各自的 context 初始化，文件更省事也更好调试。
 */
export class FormRegistry {
  private static readonly FILE: string = 'card_ids.txt';

  /** 卡片进程里用 FormExtensionContext，主进程里用 AppCtx */
  private static path(ctx?: common.Context): string {
    const c: common.Context = ctx === undefined ? AppCtx.get() : ctx;
    return `${c.filesDir}/${FormRegistry.FILE}`;
  }

  /** 记下一个 cardId（重复添加不会产生重复项） */
  static register(cardId: string, ctx?: common.Context): void {
    if (cardId.length === 0) {
      return;
    }
    const ids = FormRegistry.list(ctx);
    if (ids.indexOf(cardId) >= 0) {
      return;
    }
    ids.push(cardId);
    FormRegistry.write(ids, ctx);
  }

  static unregister(cardId: string, ctx?: common.Context): void {
    const ids = FormRegistry.list(ctx).filter((s: string) => s !== cardId);
    FormRegistry.write(ids, ctx);
  }

  static list(ctx?: common.Context): string[] {
    try {
      const p = FormRegistry.path(ctx);
      if (!fs.accessSync(p)) {
        return [];
      }
      const raw = MediaRepo.readText(p);
      return raw.split('\n').filter((s: string) => s.trim().length > 0);
    } catch (e) {
      return [];
    }
  }

  private static write(ids: string[], ctx?: common.Context): void {
    try {
      const p = FormRegistry.path(ctx);
      const f = fs.openSync(p, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(f.fd, ids.join('\n'));
      } finally {
        fs.closeSync(f);
      }
    } catch (e) {
      // 写不进去就下次再写，不影响主流程
    }
  }
}
