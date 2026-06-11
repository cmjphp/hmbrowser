/**
 * HistoryService.ts — 历史记录服务
 *
 * 使用 Preferences 存储历史记录 JSON 数组。
 * 功能：
 * - 添加历史（无痕模式下不记录）
 * - 获取历史列表
 * - 清空历史
 * - 删除单条历史
 * - 最多保留 500 条
 * - 同一 URL 更新访问时间而非重复添加
 */

import { common } from '@kit.AbilityKit';
import { HistoryItem } from '../model/HistoryItem';
import { PreferenceStore } from './PreferenceStore';

const HISTORY_KEY = 'history_json';
const MAX_HISTORY_COUNT = 500;

/** 安全解析历史记录 JSON，失败时返回空数组 */
function safeParseHistory(raw: string): HistoryItem[] {
  try {
    const parsed = JSON.parse(raw) as HistoryItem[];
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    console.warn(`History parse failed: ${JSON.stringify(error)}`);
    return [];
  }
}

export class HistoryService {
  /** 获取所有历史记录（按访问时间倒序） */
  static async getHistory(
    context?: common.UIAbilityContext
  ): Promise<HistoryItem[]> {
    const raw = await PreferenceStore.getString(context, HISTORY_KEY, '[]');
    return safeParseHistory(raw);
  }

  /**
   * 添加历史记录
   * @param item 历史条目
   * @param incognitoEnabled 是否无痕模式（true 则不记录）
   * @param context UIAbilityContext
   */
  static async addHistory(
    item: HistoryItem,
    incognitoEnabled: boolean = false,
    context?: common.UIAbilityContext
  ): Promise<void> {
    // 无痕模式不记录历史
    if (incognitoEnabled) {
      return;
    }
    // 忽略空 URL 和 about:blank
    const normalizedUrl = item.url.trim();
    if (!normalizedUrl || normalizedUrl === 'about:blank') {
      return;
    }
    const history = await HistoryService.getHistory(context);
    // 同 URL 先去重
    const filtered = history.filter(
      (record: HistoryItem) => record.url !== normalizedUrl
    );
    // 添加到最前面并更新访问时间
    filtered.unshift({
      title: item.title.trim() || normalizedUrl,
      url: normalizedUrl,
      visitedAt: item.visitedAt || Date.now()
    });
    // 截断至最大条数
    await PreferenceStore.putString(
      context,
      HISTORY_KEY,
      JSON.stringify(filtered.slice(0, MAX_HISTORY_COUNT))
    );
  }

  /** 清空所有历史记录 */
  static async clearHistory(
    context?: common.UIAbilityContext
  ): Promise<void> {
    await PreferenceStore.putString(context, HISTORY_KEY, '[]');
  }

  /** 删除指定 URL 的历史记录 */
  static async removeHistory(
    url: string,
    context?: common.UIAbilityContext
  ): Promise<void> {
    const history = await HistoryService.getHistory(context);
    const filtered = history.filter(
      (item: HistoryItem) => item.url !== url
    );
    await PreferenceStore.putString(context, HISTORY_KEY, JSON.stringify(filtered));
  }
}
