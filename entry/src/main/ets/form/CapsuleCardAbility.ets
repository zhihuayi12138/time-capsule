import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Capsule } from '../model/Capsule';
import { CapsuleRepo } from '../data/CapsuleRepo';
import { CardData } from '../data/CardData';
import { FormRegistry } from '../data/FormRegistry';

/**
 * 桌面服务卡片（F2）的 ExtensionAbility。
 *
 * 职责很窄：接住系统给的 cardId，读一遍本地胶囊，把数据推给卡片。
 * 业务逻辑都在 CardData 里，主应用复用同一份，避免两边文案/判断走样。
 */
export default class CapsuleCardAbility extends FormExtensionAbility {
  private static readonly TAG: string = 'CapsuleCard';
  private static readonly DOMAIN: number = 0x0010;

  onAddForm(want: Want): formBindingData.FormBindingData {
    const cardId = CapsuleCardAbility.cardIdOf(want);
    FormRegistry.register(cardId, this.context);
    CapsuleCardAbility.refresh(cardId, this.context);
    return formBindingData.createFormBindingData(CardData.placeholder());
  }

  onUpdateForm(cardId: string): void {
    CapsuleCardAbility.refresh(cardId, this.context);
  }

  onFormEvent(cardId: string, message: string): void {
    CapsuleCardAbility.refresh(cardId, this.context);
  }

  onRemoveForm(cardId: string): void {
    FormRegistry.unregister(cardId, this.context);
    hilog.info(CapsuleCardAbility.DOMAIN, CapsuleCardAbility.TAG, 'card removed %{public}s', cardId);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  /** 读库 → 算数据 → 推卡片。失败只记日志，卡片保留上一次的内容 */
  private static async refresh(cardId: string, ctx: common.Context): Promise<void> {
    try {
      await CapsuleRepo.init(ctx);
      const list: Capsule[] = await CapsuleRepo.listAll();
      await CardData.push(cardId, list);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(CapsuleCardAbility.DOMAIN, CapsuleCardAbility.TAG,
        'refresh failed: %{public}s', JSON.stringify(err));
    }
  }

  private static cardIdOf(want: Want): string {
    const p = want.parameters;
    if (p === undefined) {
      return '';
    }
    const id = p[formInfo.FormParam.IDENTITY_KEY];
    return typeof id === 'string' ? id : '';
  }
}
