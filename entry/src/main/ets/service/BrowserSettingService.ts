/**
 * BrowserSettingService.ts — 浏览器设置服务
 *
 * 管理：首页地址、搜索引擎、无痕模式、深色模式
 * 使用 Preferences 持久化，JSON 解析异常时使用默认值兜底
 */

import { common } from '@kit.AbilityKit';
import { BrowserSetting } from '../model/BrowserSetting';
import { UrlUtils } from '../utils/UrlUtils';
import { PreferenceStore } from './PreferenceStore';

const SETTING_KEY = 'browser_setting_json';

export class BrowserSettingService {
  /** 获取默认设置（首次使用时的初始值） */
  static getDefaultSetting(): BrowserSetting {
    return {
      homeUrl: 'https://www.bing.com',
      searchEngine: UrlUtils.DEFAULT_SEARCH_ENGINE,
      incognitoEnabled: false,
      darkModeEnabled: false
    };
  }

  /**
   * 读取当前设置
   * 如果 Preferences 中没有数据或解析失败，返回默认设置
   */
  static async getSetting(
    context?: common.UIAbilityContext
  ): Promise<BrowserSetting> {
    const fallback = BrowserSettingService.getDefaultSetting();
    const raw = await PreferenceStore.getString(
      context,
      SETTING_KEY,
      JSON.stringify(fallback)
    );
    try {
      const parsed = JSON.parse(raw) as Partial<BrowserSetting>;
      return {
        homeUrl: parsed.homeUrl || fallback.homeUrl,
        searchEngine: parsed.searchEngine || fallback.searchEngine,
        incognitoEnabled: parsed.incognitoEnabled ?? fallback.incognitoEnabled,
        darkModeEnabled: parsed.darkModeEnabled ?? fallback.darkModeEnabled
      };
    } catch (error) {
      console.warn(`Setting parse failed, using defaults: ${JSON.stringify(error)}`);
      return fallback;
    }
  }

  /**
   * 保存设置
   * 会将传入的 setting 与默认值合并（避免缺少字段）
   */
  static async saveSetting(
    setting: BrowserSetting,
    context?: common.UIAbilityContext
  ): Promise<void> {
    const merged: BrowserSetting = {
      ...BrowserSettingService.getDefaultSetting(),
      ...setting
    };
    await PreferenceStore.putString(
      context,
      SETTING_KEY,
      JSON.stringify(merged)
    );
  }
}
