import { preferences } from '@kit.ArkData';
import { AppCtx } from '../common/AppCtx';
import { StoreKey } from '../common/Constants';

/**
 * 轻量设置存储（preferences）。
 * 只存少量标量：通知开关、是否引导过、上次备份时间、提醒小时。
 */
export class SettingsRepo {
  private static pref?: preferences.Preferences = undefined;

  private static async get(): Promise<preferences.Preferences> {
    if (SettingsRepo.pref === undefined) {
      SettingsRepo.pref = await preferences.getPreferences(AppCtx.get(), StoreKey.PREF);
    }
    return SettingsRepo.pref;
  }

  static async getBool(key: string, defValue: boolean): Promise<boolean> {
    const p = await SettingsRepo.get();
    const v = await p.get(key, defValue);
    return v as boolean;
  }

  static async getNumber(key: string, defValue: number): Promise<number> {
    const p = await SettingsRepo.get();
    const v = await p.get(key, defValue);
    return v as number;
  }

  static async putBool(key: string, value: boolean): Promise<void> {
    const p = await SettingsRepo.get();
    await p.put(key, value);
    await p.flush();
  }

  static async putNumber(key: string, value: number): Promise<void> {
    const p = await SettingsRepo.get();
    await p.put(key, value);
    await p.flush();
  }
}
