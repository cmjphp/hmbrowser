/**
 * BrowserTab.ts — 多标签页数据结构
 *
 * TabInfo 用于存储每个标签页的状态信息。
 * 标签切换时保存当前标签的 URL/标题，加载目标标签的 URL。
 *
 * @Observed 让 ArkUI 能追踪属性变化，配合 ForEach 在数据变更时自动刷新标签栏 UI
 */

@Observed
export class TabInfo {
  id: number;
  title: string;
  url: string;
  hasNavigated: boolean;
  /** 自增版本号：每次 syncToActiveTab 时递增，用于 ForEach key 强制刷新 */
  version: number;

  constructor(id: number, title?: string, url?: string, hasNavigated?: boolean) {
    this.id = id;
    this.title = title ?? '新标签页';
    this.url = url ?? 'about:blank';
    this.hasNavigated = hasNavigated ?? false;
    this.version = 0;
  }
}
