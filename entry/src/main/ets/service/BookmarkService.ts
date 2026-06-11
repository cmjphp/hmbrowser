/**
 * BookmarkService.ts — 书签服务
 *
 * 使用 Preferences 存储书签 JSON 数组。
 * 支持：添加、删除、查询、切换书签状态。
 *
 * 注意：
 * - 数据序列化为 JSON 字符串存储
 * - JSON 解析异常时有兜底（返回空数组），避免应用崩溃
 * - 同一个 URL 不重复添加（先去重再写入）
 */

import { common } from '@kit.AbilityKit';
import { Bookmark } from '../model/Bookmark';
import { PreferenceStore } from './PreferenceStore';

const BOOKMARKS_KEY = 'bookmarks_json';

/** 安全解析书签 JSON，失败时返回空数组 */
function safeParseBookmarks(raw: string): Bookmark[] {
  try {
    const parsed = JSON.parse(raw) as Bookmark[];
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    console.warn(`Bookmark parse failed: ${JSON.stringify(error)}`);
    return [];
  }
}

export class BookmarkService {
  /** 获取所有书签 */
  static async getBookmarks(context?: common.UIAbilityContext): Promise<Bookmark[]> {
    const raw = await PreferenceStore.getString(context, BOOKMARKS_KEY, '[]');
    return safeParseBookmarks(raw);
  }

  /** 添加书签（同名 URL 先去重） */
  static async addBookmark(
    bookmark: Bookmark,
    context?: common.UIAbilityContext
  ): Promise<void> {
    const bookmarks = await BookmarkService.getBookmarks(context);
    const normalizedUrl = bookmark.url.trim();
    // 移除同 URL 的旧书签
    const filtered = bookmarks.filter(
      (item: Bookmark) => item.url !== normalizedUrl
    );
    // 新书签添加到最前面
    filtered.unshift({
      title: bookmark.title.trim() || normalizedUrl,
      url: normalizedUrl,
      createdAt: bookmark.createdAt || Date.now()
    });
    await PreferenceStore.putString(context, BOOKMARKS_KEY, JSON.stringify(filtered));
  }

  /** 根据 URL 删除书签 */
  static async removeBookmark(
    url: string,
    context?: common.UIAbilityContext
  ): Promise<void> {
    const bookmarks = await BookmarkService.getBookmarks(context);
    const filtered = bookmarks.filter((item: Bookmark) => item.url !== url);
    await PreferenceStore.putString(context, BOOKMARKS_KEY, JSON.stringify(filtered));
  }

  /** 检查 URL 是否已加入书签 */
  static async isBookmarked(
    url: string,
    context?: common.UIAbilityContext
  ): Promise<boolean> {
    const bookmarks = await BookmarkService.getBookmarks(context);
    return bookmarks.some((item: Bookmark) => item.url === url);
  }

  /**
   * 切换书签状态
   * @returns true=已添加, false=已取消
   */
  static async toggleBookmark(
    title: string,
    url: string,
    context?: common.UIAbilityContext
  ): Promise<boolean> {
    const exists = await BookmarkService.isBookmarked(url, context);
    if (exists) {
      await BookmarkService.removeBookmark(url, context);
      return false;
    }
    await BookmarkService.addBookmark(
      { title, url, createdAt: Date.now() },
      context
    );
    return true;
  }
}
