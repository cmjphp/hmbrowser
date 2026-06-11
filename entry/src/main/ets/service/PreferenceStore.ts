/**
 * PreferenceStore.ts — 本地存储封装
 *
 * 封装 @kit.ArkData 的 preferences API，提供 getString / putString。
 * 同时维护内存 Map 作为兜底（当 context 不可用时）。
 *
 * 需要根据当前 DevEco Studio / HarmonyOS SDK 校验：
 * 1. 导入路径：新版用 @kit.ArkData，旧版可能用 @ohos.data.preferences
 * 2. getPreferences 参数结构与返回值
 * 3. flush() 是否仍然可用
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

export class PreferenceStore {
  private static readonly STORE_NAME = 'hm_browser_store';
  private static memory: Map<string, string> = new Map();

  /**
   * 读取字符串值
   * @param context UIAbilityContext，为空时使用内存兜底
   * @param key 键名
   * @param fallback 默认值
   */
  static async getString(
    context: common.UIAbilityContext | undefined,
    key: string,
    fallback: string
  ): Promise<string> {
    if (!context) {
      return PreferenceStore.memory.get(key) ?? fallback;
    }
    try {
      const store = await preferences.getPreferences(context, {
        name: PreferenceStore.STORE_NAME
      });
      const value = await store.get(key, fallback);
      return typeof value === 'string' ? value : fallback;
    } catch (error) {
      console.warn(`PreferenceStore getString fallback for key="${key}": ${JSON.stringify(error)}`);
      return PreferenceStore.memory.get(key) ?? fallback;
    }
  }

  /**
   * 保存字符串值
   * @param context UIAbilityContext，为空时仅写内存
   * @param key 键名
   * @param value 值
   */
  static async putString(
    context: common.UIAbilityContext | undefined,
    key: string,
    value: string
  ): Promise<void> {
    // 内存兜底：总是先写内存
    PreferenceStore.memory.set(key, value);
    if (!context) {
      return;
    }
    try {
      const store = await preferences.getPreferences(context, {
        name: PreferenceStore.STORE_NAME
      });
      await store.put(key, value);
      // 需要根据 SDK 校验 flush() 是否仍为推荐持久化方式
      await store.flush();
    } catch (error) {
      console.warn(`PreferenceStore putString failed for key="${key}": ${JSON.stringify(error)}`);
    }
  }
}
