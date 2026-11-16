import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { AppCtx } from '../common/AppCtx';

/**
 * 运行时权限申请。
 *
 * 只需要两个权限：
 * - ohos.permission.MICROPHONE      （user_grant，录语音时要弹窗）
 * - ohos.permission.PUBLISH_AGENT_REMINDER （system_grant，装包即授予，无需请求）
 *
 * 读相册不走权限：PhotoViewPicker 是系统 UI，用户选择即授权，
 * 而 READ_IMAGEVIDEO 是 system_basic，普通应用根本申请不到。
 */
export class PermService {
  /** 申请麦克风；已授权直接返回 true */
  static async ensureMicrophone(): Promise<boolean> {
    const perm: Permissions = 'ohos.permission.MICROPHONE';
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(AppCtx.get(), [perm]);
      const codes = result.authResults;
      if (codes.length === 0) {
        return false;
      }
      return codes[0] === 0;
    } catch (e) {
      return false;
    }
  }

  /** 查询是否已授予麦克风（不弹窗） */
  static async hasMicrophone(): Promise<boolean> {
    const perm: Permissions = 'ohos.permission.MICROPHONE';
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const status = await atManager.checkAccessToken(
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION).appInfo.accessTokenId,
        perm);
      return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (e) {
      return false;
    }
  }
}
