import { formBindingData, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Capsule, CapsuleStatus } from '../model/Capsule';
import { TimeUtil } from '../common/TimeUtil';
import { FormRegistry } from './FormRegistry';

/**
 * 桌面服务卡片（F2）的数据与刷新。
 *
 * 卡片只做一件事：把"最近一个约定还有多久"摆在桌面上。
 * 通知可能被系统吞掉，卡片是兜底——用户瞟一眼桌面就知道时间在走。
 *
 * 卡片进程和主进程都可能触发刷新，所以这里只依赖传入的胶囊列表，
 * 不自己读数据库。
 */
export class CardData {
  private static readonly TAG: string = 'CapsuleCard';
  private static readonly DOMAIN: number = 0x0010;

  /** 挑出最早到期的待开启胶囊 */
  static nearest(list: Capsule[]): Capsule | undefined {
    let best: Capsule | undefined = undefined;
    for (const c of list) {
      if (c.status !== CapsuleStatus.Pending) {
        continue;
      }
      if (best === undefined || c.openAt < best.openAt) {
        best = c;
      }
    }
    return best;
  }

  /** 由胶囊列表算出卡片要显示的内容 */
  static compose(list: Capsule[]): Record<string, string | number> {
    const pending: Capsule[] = list.filter((c: Capsule) => c.status === CapsuleStatus.Pending);
    const due: Capsule[] = pending.filter((c: Capsule) => TimeUtil.isDue(c.openAt));
    const near = CardData.nearest(pending);

    const data: Record<string, string | number> = {};
    if (due.length > 0) {
      data['mode'] = 'due';
      data['headline'] = '可以打开了';
      data['title'] = due[0].title;
      data['hint'] = `今天有 ${due.length} 个约定到期`;
      data['count'] = pending.length;
    } else if (near !== undefined) {
      data['mode'] = 'countdown';
      data['headline'] = `还有 ${TimeUtil.daysLeft(near.openAt)} 天`;
      data['title'] = near.title;
      data['hint'] = `${TimeUtil.formatDate(near.openAt)} 开启`;
      data['count'] = pending.length;
    } else {
      data['mode'] = 'empty';
      data['headline'] = '时间在走';
      data['title'] = '还没有和未来约定什么';
      data['hint'] = '点一下，写下此刻';
      data['count'] = 0;
    }
    return data;
  }

  /** 全部卡片都还是"正在读"时的占位，避免白屏 */
  static placeholder(): Record<string, string | number> {
    return {
      'mode': 'empty',
      'headline': '时间在走',
      'title': '正在读你的约定…',
      'hint': ' ',
      'count': 0
    };
  }

  /** 刷新一个卡片 */
  static async push(cardId: string, list: Capsule[]): Promise<void> {
    if (cardId.length === 0) {
      return;
    }
    try {
      const data = CardData.compose(list);
      await formProvider.updateForm(cardId, formBindingData.createFormBindingData(data));
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(CardData.DOMAIN, CardData.TAG, 'push %{public}s failed: %{public}s',
        cardId, JSON.stringify(err));
    }
  }

  /** 刷新全部已注册的卡片（主应用数据变化后调用） */
  static async pushAll(list: Capsule[]): Promise<void> {
    const ids = FormRegistry.list();
    for (const id of ids) {
      await CardData.push(id, list);
    }
  }
}
