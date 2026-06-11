/**
 * BrowserPage.ets — 浏览器主页
 * 包含 Web 渲染、地址栏、工具栏、快捷入口、书签、历史记录等核心功能
 *
 * 需要根据当前 DevEco Studio / HarmonyOS SDK 校验：
 * 1. ArkWeb 事件对象字段名（onPageBegin/onPageEnd 的 event.url）
 * 2. onErrorReceive 的 event.error / event.request 结构
 * 3. WebviewController 方法签名（backward/forward/refresh/stop）
 */

import { common, Want } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { AddressBar } from '../components/AddressBar';
import { BrowserToolbar } from '../components/BrowserToolbar';
import { BookmarkPage } from './BookmarkPage';
import { QuickLinks } from '../components/QuickLinks';
import { TabBar } from '../components/TabBar';
import { Bookmark } from '../model/Bookmark';
import { BrowserSetting } from '../model/BrowserSetting';
import { TabInfo } from '../model/BrowserTab';
import { HistoryItem } from '../model/HistoryItem';
import { BookmarkService } from '../service/BookmarkService';
import { BrowserSettingService } from '../service/BrowserSettingService';
import { HistoryService } from '../service/HistoryService';
import { UrlUtils } from '../utils/UrlUtils';

/** 伪装的 Chrome Mobile UA，防止网站降级或拒绝服务 */
const CHROME_MOBILE_UA =
  'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.6778.139 Mobile Safari/537.36';

@Entry
@Component
struct BrowserPage {
  private controller: webview.WebviewController = new webview.WebviewController();
  private abilityContext?: common.UIAbilityContext;

  // --- 标签页管理 ---
  /** 所有标签页 */
  @State private tabs: TabInfo[] = [];
  /** 当前激活的标签页索引 */
  @State private activeIndex: number = 0;
  /** 标签页 ID 自增计数器 */
  private tabIdCounter: number = 0;

  // --- 核心状态（反映当前激活标签） ---
  @State private currentUrl: string = 'about:blank';
  @State private addressText: string = '';
  @State private currentTitle: string = '空白页面';
  @State private progress: number = 0;
  @State private isLoading: boolean = false;
  @State private canGoBack: boolean = false;
  @State private canGoForward: boolean = false;
  @State private isBookmarked: boolean = false;
  @State private errorMessage: string = '';
  @State private hasNavigated: boolean = false;
  @State private setting: BrowserSetting = BrowserSettingService.getDefaultSetting();
  /** 首页「最近访问」列表，取最近 8 条 */
  @State private recentHistory: HistoryItem[] = [];
  /** 首页「我的收藏」列表，取最近 6 条 */
  @State private recentBookmarks: Bookmark[] = [];
  /** 标记正在清空旧页面上下文，抑制中间 about:blank 事件 */
  private flushingContext: boolean = false;
  /** OAuth / window.open() 弹窗覆盖层 */
  @State private showOAuthWindow: boolean = false;
  /** OAuth 弹窗的独立 WebviewController */
  private oauthWebController: webview.WebviewController | null = null;
  /** 自定义协议跳转确认弹窗 */
  @State private showSchemeConfirm: boolean = false;
  /** 待确认的自定义协议 URL */
  @State private pendingSchemeUrl: string = '';
  /** 书签面板是否显示 */
  @State private showBookmarks: boolean = false;

  // ========== 生命周期 ==========

  aboutToAppear(): void {
    this.init();
  }

  private async init(): Promise<void> {
    this.abilityContext = getContext(this) as common.UIAbilityContext;
    this.setting = await BrowserSettingService.getSetting(this.abilityContext!);
    this.addressText = '';
    // 创建第一个标签页
    this.tabIdCounter = 1;
    this.tabs = [new TabInfo(1)];
    this.activeIndex = 0;
    this.syncFromTab(0);
    await this.refreshRecentHistory();
    await this.refreshRecentBookmarks();
  }

  // ========== 导航方法 ==========

  /**
   * 解析用户输入（URL 或关键词）并加载
   */
  private async loadInput(value: string): Promise<void> {
    const nextUrl = UrlUtils.normalizeUrl(value, this.setting.searchEngine);
    await this.loadUrl(nextUrl);
  }

  /**
   * 加载指定 URL — 核心导航方法
   *
   * 关键：只通过 controller.loadUrl() 导航，不改变 Web 的 src 绑定。
   * 这样 Web 组件不会重新创建，导航历史得以保留。
   * currentUrl 由 onPageBegin/onPageEnd 事件更新。
   */
  private async loadUrl(url: string): Promise<void> {
    // 0. 拦截 Android Intent URL（intent://...），转换为普通 HTTPS URL
    const resolvedUrl = this.resolveIntentUrl(url);

    // 0.5 自定义协议处理
    // 策略：已知 scheme → 转 HTTPS 加载；未知 scheme → 静默忽略
    // 支付类 scheme（支付宝/微信支付）才弹确认框让用户选择唤起 App
    if (this.isCustomScheme(resolvedUrl)) {
      const httpsUrl = this.resolveCustomScheme(resolvedUrl);
      if (httpsUrl) {
        // 已知 scheme（知乎、微博等）→ 直接用 HTTPS 版本加载，不弹窗
        console.info(`Custom scheme resolved: ${resolvedUrl} → ${httpsUrl}`);
        await this.loadUrl(httpsUrl);
        return;
      }
      // 未知 scheme：敏感协议弹确认，其余直接返回不做任何处理
      if (this.isSensitiveScheme(resolvedUrl)) {
        this.pendingSchemeUrl = resolvedUrl;
        this.showSchemeConfirm = true;
      }
      return;
    }

    // 1. 立即终止前一个页面的所有进行中请求
    try {
      this.controller.stop();
    } catch (e) {
      // ignore
    }
    this.isLoading = false;
    this.errorMessage = '';

    // 2. 加载 about:blank 清空渲染上下文 —— 彻底终止旧页图片等子资源请求
    if (resolvedUrl !== 'about:blank') {
      this.flushingContext = true;
      try {
        this.controller.loadUrl('about:blank');
        // flush 后重新应用 UA，防止被 about:blank 重置
        this.applyUserAgent();
      } catch (e) {
        // ignore
      }
    }

    // 3. 加载目标 URL
    this.hasNavigated = true;
    this.addressText = resolvedUrl === 'about:blank' ? '' : resolvedUrl;
    // 3.5 立即同步 URL 到 currentUrl，确保 syncToActiveTab 能拿到正确的 url
    if (resolvedUrl !== 'about:blank') {
      this.currentUrl = resolvedUrl;
    }
    try {
      this.controller.loadUrl(resolvedUrl);
      // 确保目标页面也使用正确的 UA
      this.applyUserAgent();
    } catch (error) {
      console.warn(`loadUrl failed: ${JSON.stringify(error)}`);
    }
    // 4. 立即同步标签状态，不依赖 onPageBegin/onPageEnd 事件
    //    解决：Web 事件延迟或丢失时标签仍显示"首页"的问题
    this.syncToActiveTab();
  }

  /** 将 Android Intent URL（intent://...）转换为标准 HTTPS URL */
  private resolveIntentUrl(url: string): string {
    if (!url || !url.startsWith('intent://')) {
      return url;
    }
    // 示例：intent://m.youtube.com/watch?v=xxx&feature=...#Intent;package=...;end
    try {
      // 去掉 intent:// 前缀
      let body = url.substring(8);
      // #Intent; 后面是元数据，截取前面的实际地址部分
      const hashIdx = body.indexOf('#Intent;');
      if (hashIdx !== -1) {
        body = body.substring(0, hashIdx);
      }
      return 'https://' + body;
    } catch (e) {
      console.warn(`resolveIntentUrl failed for ${url}`);
      return url;
    }
  }

  /** 判断 URL 是否为自定义协议（非 http(s) / about / data / javascript） */
  private isCustomScheme(url: string): boolean {
    if (!url || url.length === 0) return false;
    return !url.startsWith('http') &&
           !url.startsWith('https') &&
           url !== 'about:blank' &&
           !url.startsWith('data:') &&
           !url.startsWith('javascript:');
  }

  /**
   * 判断一个字符串是否看起来像自定义协议 URL
   * 用于过滤 onTitleReceive 等回调中可能传入的脏数据
   * 例如："baiduboxapp://V1/browser/open?url=..." 应被视为无效标题
   */
  private looksLikeSchemeUrl(s: string): boolean {
    if (!s || s.length < 5) return false;
    // 包含 :// 但不是 http(s):// → 很可能是自定义协议 URL
    const colonIdx = s.indexOf('://');
    if (colonIdx === -1 || colonIdx === 0) return false;
    const protocol = s.substring(0, colonIdx).toLowerCase();
    // 常见的合法协议前缀
    const knownProtocols = ['http', 'https', 'ftp', 'file', 'data', 'javascript', 'about'];
    if (knownProtocols.includes(protocol)) return false;
    // 其他带 :// 的都当作自定义协议 URL 过滤掉
    return true;
  }

  /**
   * 将已知自定义协议 URL 转换为 HTTPS 版本
   *
   * ⚠️ 只有路径格式与 Web URL 高度一致的 scheme 才在此处转换。
   * App 内部路由（如 baiduboxapp://v1/browser/open）直接拼接域名会产生无效地址。
   * 无法安全转换的统一返回 null，由上层静默忽略。
   */
  private resolveCustomScheme(url: string): string | null {
    const colonIdx = url.indexOf('://');
    if (colonIdx === -1) return null;
    const scheme = url.substring(0, colonIdx).toLowerCase();
    const path = url.substring(colonIdx + 3);

    // 仅保留经过验证可安全映射的 scheme
    switch (scheme) {
      case 'zhihu': {
        // zhihu://questions/123 → https://www.zhihu.com/question/123
        const cleanPath = path.replace(/^\/+/, '');
        return `https://www.zhihu.com/${cleanPath}`;
      }
      case 'weibo': {
        // weibo://... → https://m.weibo.cn/...
        const cleanPath = path.replace(/^\/+/, '');
        return `https://m.weibo.cn/${cleanPath}`;
      }
      case 'bilibili': {
        // bilibili://video/xxx → https://m.bilibili.com/video/xxx
        const cleanPath = path.replace(/^\/+/, '');
        return `https://m.bilibili.com/${cleanPath}`;
      }
      default:
        // baiduboxapp / taobao / jd / qq / dingtalk / meituan 等
        // 内部路由路径与 Web URL 不兼容，强行拼接会出 404
        return null;
    }
  }

  /**
   * 判断是否为敏感 scheme（支付、授权等需要用户明确确认的协议）
   * 只有这些才弹确认框，其他未知 scheme 直接忽略
   */
  private isSensitiveScheme(url: string): boolean {
    if (!url) return false;
    const sensitiveSchemes = [
      'alipay',        // 支付宝支付
      'alipays',       // 支付宝
      'weixin',        // 微信支付/授权
      'wechat',        // 微信
      'upaywallet',    // 银联支付
      'unionpay',      // 银联
    ];
    for (const s of sensitiveSchemes) {
      if (url.toLowerCase().startsWith(s + '://')) {
        return true;
      }
    }
    return false;
  }

  /**
   * 从 App 自定义协议 URL 中提取真实的 HTTPS 目标 URL
   *
   * 很多 App scheme 的路径中嵌入了真实目标地址（如 url=、link= 等参数），
   * 例如：baiduboxapp://V1/browser/open?url=https://www.example.com
   * 提取出 https://www.example.com 后可直接用 WebView 打开。
   *
   * 返回 null 表示无法提取，调用方应忽略或走其他处理流程。
   */
  private extractRealUrlFromAppScheme(url: string): string | null {
    if (!url) return null;

    // 统一提取 URL 参数值（url=、link=、target=、uri= 等）
    const urlParams = ['url=', 'link=', 'target=', 'uri=', 'page='];
    for (const param of urlParams) {
      const idx = url.indexOf(param);
      if (idx !== -1) {
        let value = url.substring(idx + param.length);
        // 截断：参数值到 & 或 # 结束
        const ampIdx = value.indexOf('&');
        const hashIdx = value.indexOf('#');
        if (ampIdx !== -1 && (hashIdx === -1 || ampIdx < hashIdx)) {
          value = value.substring(0, ampIdx);
        } else if (hashIdx !== -1) {
          value = value.substring(0, hashIdx);
        }
        // URL 解码（%3A → :，%2F → / 等）
        try {
          value = decodeURIComponent(value);
        } catch (_e) {
          // 解码失败则使用原始值
        }
        // 只返回有效的 http(s) URL
        if (value.startsWith('http://') || value.startsWith('https://')) {
          return value;
        }
      }
    }

    // 已知安全 scheme 的 HTTPS 转换
    const httpsUrl = this.resolveCustomScheme(url);
    if (httpsUrl) {
      return httpsUrl;
    }

    return null;
  }

  /** 尝试使用系统 openLink 唤起对应 App，返回 true 表示成功唤起 */
  private async tryOpenAppLink(url: string): Promise<boolean> {
    const ctx = this.abilityContext;
    if (!ctx) {
      promptAction.showToast({ message: '无法处理此链接' });
      return false;
    }
    try {
      // 检查是否有 App 可处理此协议
      const canOpen = await ctx.openLink(url, {
        parameters: {}
      }).then(() => true).catch(() => false);
      if (canOpen) {
        console.info(`App launched for scheme: ${url}`);
        return true;
      }
    } catch (e) {
      // openLink 失败，尝试用 Want 方式
    }
    // openLink 失败时，尝试 startAbility 兜底
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url
      };
      await ctx.startAbility(want);
      console.info(`App launched via startAbility: ${url}`);
      return true;
    } catch (e2) {
      promptAction.showToast({
        message: '未安装可处理此链接的应用'
      });
      return false;
    }
  }

  /** 通过 controller 重设 User-Agent，兜底防止导航过程中 UA 丢失 */
  private applyUserAgent(): void {
    // UA 已通过组件级 .userAgent() 设置，此处保留空实现作为未来扩展点
    // 如需运行时动态切换 UA，可在此调用 controller 的 setCustomUserAgent 方法
  }

  /**
   * 注入 JavaScript 实现新标签页打开：
   *   - 拦截 target="_blank" 链接点击
   *   - 用 document.title 传递目标 URL（通过 onTitleReceive 接收）
   *   - 不使用 window.open()（会导致死锁）
   */
  private injectBlankTargetHandler(): void {
    const js = `
    (function(){
      if(window.__hmb_blank_handled)return;
      window.__hmb_blank_handled=1;

      // ===== 拦截 target="_blank" 链接点击 =====
      document.addEventListener('click',function(e){
        var el=e.target;
        var a=null;
        var cur=el;
        while(cur && cur!==document.documentElement){
          if(cur.tagName==='A'){a=cur;break;}
          cur=cur.parentElement;
        }
        if(a){
          var href=a.getAttribute('href')||'';
          if(href && (href.indexOf('javascript:')===0 || href.indexOf('#')===0)) return;
          // 只处理有 href 的链接
          if(!href) return;
          // 获取完整 URL
          var fullUrl=href;
          if(href.indexOf('http://')!==0 && href.indexOf('https://')!==0){
            if(href.indexOf('/')===0){
              fullUrl=location.protocol+'//'+location.host+href;
            }else{
              var path=location.pathname;
              var lastSlash=path.lastIndexOf('/');
              var dir=lastSlash>0?path.substring(0,lastSlash+1):'/';
              fullUrl=location.protocol+'//'+location.host+dir+href;
            }
          }
          // 用 document.title 通知原生层打开新标签页
          e.preventDefault();
          e.stopPropagation();
          e.stopImmediatePropagation();
          document.title='__hmb_newtab__|'+fullUrl;
          window.__hmb_pending_url=fullUrl;
          return false;
        }
      },true);
    })();
    `;
    try {
      this.controller.runJavaScript(js);
      console.info('[HMB-TRACE] injectBlankTargetHandler OK');
    } catch (e) {
      console.error('[HMB-TRACE] injectBlankTargetHandler FAILED');
    }
  }

  // ========== 标签页管理 ==========

  /** 同步激活标签数据到 UI 状态 */
  private syncFromTab(index: number): void {
    if (index < 0 || index >= this.tabs.length) {
      return;
    }
    const tab = this.tabs[index];
    this.currentUrl = tab.url;
    this.addressText = tab.hasNavigated && tab.url !== 'about:blank' ? tab.url : '';
    this.currentTitle = tab.title;
    this.hasNavigated = tab.hasNavigated;
    this.errorMessage = '';
    this.isLoading = false;
    this.progress = 0;
  }

  /** 保存当前 UI 状态到激活标签 — 创建新数组确保 @State 触发 ForEach 重绘 */
  private syncToActiveTab(): void {
    if (this.activeIndex < 0 || this.activeIndex >= this.tabs.length) {
      return;
    }
    // 过滤：标题不能是自定义协议 URL（防止 baiduboxapp:// 污染标签名）
    let safeTitle = this.currentTitle || '新标签页';
    if (this.looksLikeSchemeUrl(safeTitle)) {
      // 从 currentUrl 提取域名作为备用标题
      safeTitle = this.extractHost(this.currentUrl) || '新标签页';
    }
    // 过滤：URL 不能是自定义协议
    let safeUrl = this.currentUrl;
    if (this.isCustomScheme(safeUrl)) {
      safeUrl = 'about:blank';
    }
    const newTabs: TabInfo[] = [];
    for (let i = 0; i < this.tabs.length; i++) {
      if (i === this.activeIndex) {
        // 用最新 UI 状态创建新的 TabInfo 对象，递增 version 确保 ForEach key 变化触发重绘
        const updated = new TabInfo(
          this.tabs[i].id,
          safeTitle,
          safeUrl,
          this.hasNavigated
        );
        updated.version = this.tabs[i].version + 1;
        newTabs.push(updated);
      } else {
        newTabs.push(this.tabs[i]);
      }
    }
    this.tabs = newTabs;
  }

  /** 创建新标签页（不切换，后台加载） */
  private openInBackgroundTab(url?: string): void {
    this.tabIdCounter = this.tabIdCounter + 1;
    const id = this.tabIdCounter;
    const hasNav = url !== undefined && url !== 'about:blank';
    const newTab = new TabInfo(id, hasNav ? '新标签页' : '新标签页', url ?? 'about:blank', hasNav);
    // 在激活标签右侧插入
    const insertIdx = this.activeIndex + 1;
    const newTabs: TabInfo[] = [];
    for (let i = 0; i < this.tabs.length; i++) {
      newTabs.push(this.tabs[i]);
      if (i === this.activeIndex) {
        newTabs.push(newTab);
      }
    }
    this.tabs = newTabs;
    // 后台打开时不切换，保持当前标签
    // 新标签将在用户手动切换到它时通过 switchToTab 加载 URL
  }

  /**
   * 创建新标签页并立即切换到它，加载指定 URL
   * 用于 window.open() 拦截——百度搜索结果等在新标签打开的场景
   */
  private openInNewTab(url: string): void {
    console.info('[HMB-TRACE] openInNewTab called, url=' + url);

    this.tabIdCounter = this.tabIdCounter + 1;
    const id = this.tabIdCounter;
    const safeUrl = (url && (url.startsWith('http://') || url.startsWith('https://')))
      ? url : 'about:blank';
    const newTab = new TabInfo(id, '新标签页', safeUrl, safeUrl !== 'about:blank');

    // 1. 保存当前标签状态
    this.syncToActiveTab();

    // 2. 在激活标签右侧插入新标签
    const insertIdx = this.activeIndex + 1;
    const newTabs: TabInfo[] = [];
    for (let i = 0; i < this.tabs.length; i++) {
      newTabs.push(this.tabs[i]);
      if (i === this.activeIndex) {
        newTabs.push(newTab);
      }
    }
    this.tabs = newTabs;

    // 3. 切换到新标签并加载 URL
    const targetIdx = insertIdx < this.tabs.length ? insertIdx : this.tabs.length - 1;
    this.activeIndex = targetIdx;
    this.syncFromTab(targetIdx);
    this.canGoBack = false;
    this.canGoForward = false;

    // 4. 加载目标 URL
    if (safeUrl !== 'about:blank') {
      this.hasNavigated = true;
      this.addressText = safeUrl;
      this.currentUrl = safeUrl;
      this.flushingContext = true;
      try {
        this.controller.loadUrl('about:blank');
      } catch (_e) {
        // ignore
      }
      try {
        this.controller.loadUrl(safeUrl);
        this.applyUserAgent();
      } catch (e) {
        console.warn(`openInNewTab loadUrl failed: ${JSON.stringify(e)}`);
      }
      this.syncToActiveTab();
    }
  }

  /** 判断 URL 是否像 OAuth/第三方登录授权链接 */
  private isOAuthUrl(url: string): boolean {
    if (!url) return false;
    const lower = url.toLowerCase();
    const patterns: string[] = [
      '/oauth', '/oauth2', '/authorize', '/connect/authorize',
      '/login/oauth', '/signin/oauth', '/openid', '/saml',
      'open.weixin.qq.com', 'open.work.weixin.qq.com',
      'graph.qq.com', 'api.weibo.com/oauth2',
      'accounts.google.com/o/oauth2',
      '/auth/authorize', '/dialog/oauth',
    ];
    for (const p of patterns) {
      if (lower.indexOf(p) !== -1) return true;
    }
    return false;
  }

  /** 创建新标签页并切换过去 */
  private createNewTab(url?: string): void {
    this.tabIdCounter = this.tabIdCounter + 1;
    const id = this.tabIdCounter;
    const hasNav = url !== undefined && url !== 'about:blank';
    const newTab = new TabInfo(id, '新标签页', url ?? 'about:blank', hasNav);
    // 在激活标签右侧插入
    const insertIdx = this.activeIndex + 1;
    const newTabs: TabInfo[] = [];
    for (let i = 0; i < this.tabs.length; i++) {
      newTabs.push(this.tabs[i]);
      if (i === this.activeIndex) {
        newTabs.push(newTab);
      }
    }
    this.tabs = newTabs;
    // 切换到新标签
    const targetIdx = insertIdx < this.tabs.length ? insertIdx : this.tabs.length - 1;
    this.switchToTab(targetIdx);
  }

  /** 关闭标签页 */
  private closeTab(index: number): void {
    if (this.tabs.length <= 1) {
      return; // 至少保留一个标签
    }
    const newTabs: TabInfo[] = [];
    for (let i = 0; i < this.tabs.length; i++) {
      if (i !== index) {
        newTabs.push(this.tabs[i]);
      }
    }
    this.tabs = newTabs;
    if (index < this.activeIndex || this.activeIndex >= this.tabs.length) {
      this.activeIndex = this.activeIndex - 1;
      if (this.activeIndex < 0) {
        this.activeIndex = 0;
      }
    }
    this.switchToTab(this.activeIndex);
  }

  /** 切换到指定标签页 */
  private switchToTab(index: number): void {
    if (index < 0 || index >= this.tabs.length || index === this.activeIndex) {
      return;
    }
    // 1. 停止当前加载
    try {
      this.controller.stop();
    } catch (e) {
      // ignore
    }
    // 2. 保存当前标签状态
    this.syncToActiveTab();
    // 3. 切换索引
    this.activeIndex = index;
    // 4. 加载目标标签的 URL
    const tab = this.tabs[index];
    this.syncFromTab(index);
    this.canGoBack = false;
    this.canGoForward = false;
    if (tab.url !== 'about:blank') {
      this.flushingContext = true;
      try {
        this.controller.loadUrl('about:blank');
      } catch (e) {
        // ignore
      }
      try {
        this.controller.loadUrl(tab.url);
        this.applyUserAgent();
      } catch (e) {
        console.warn(`switchToTab loadUrl failed: ${JSON.stringify(e)}`);
      }
    } else {
      try {
        this.controller.loadUrl('about:blank');
      } catch (e) {
        // ignore
      }
    }
  }

  // ========== 错误过滤 ==========

  /** 判断失败的 URL 是否属于当前页面（同域名则显示，否则忽略旧页残留错误） */
  private isErrorForCurrentPage(failedUrl: string): boolean {
    if (!failedUrl || !this.currentUrl || this.currentUrl === 'about:blank') {
      return false;
    }
    // 主文档本身加载失败 → 显示
    if (failedUrl === this.currentUrl) {
      return true;
    }
    // 提取域名比较：同域名的子资源错误才显示，跨域的旧页资源直接忽略
    const currentHost = this.extractHost(this.currentUrl);
    const failedHost = this.extractHost(failedUrl);
    return currentHost !== '' && currentHost === failedHost;
  }

  /** 从 URL 字符串中提取主机名（域名+端口），ArkTS 兼容实现 */
  private extractHost(url: string): string {
    if (!url) {
      return '';
    }
    // 跳过协议部分
    let start = url.indexOf('://');
    if (start === -1) {
      start = 0;
    } else {
      start = start + 3;
    }
    // 找到域名结束位置（/ 或 ? 或 #）
    let end = url.length;
    const slash = url.indexOf('/', start);
    const question = url.indexOf('?', start);
    const hash = url.indexOf('#', start);
    if (slash !== -1 && slash < end) {
      end = slash;
    }
    if (question !== -1 && question < end) {
      end = question;
    }
    if (hash !== -1 && hash < end) {
      end = hash;
    }
    return url.substring(start, end);
  }

  private async goHome(): Promise<void> {
    this.hasNavigated = false;
    this.currentUrl = 'about:blank';
    this.currentTitle = '空白页面';
    this.addressText = '';
    this.errorMessage = '';
    this.isBookmarked = false;
    this.canGoBack = false;
    this.canGoForward = false;
    // 刷新首页最近访问列表
    await this.refreshRecentHistory();
    await this.refreshRecentBookmarks();
    try {
      this.controller.loadUrl('about:blank');
    } catch (error) {
      console.warn(`loadUrl about:blank failed: ${JSON.stringify(error)}`);
    }
  }

  private goBack(): void {
    try {
      this.controller.backward();
      // 导航状态由事件回调刷新，这里不做同步检查
    } catch (error) {
      console.warn(`backward failed: ${JSON.stringify(error)}`);
    }
  }

  private goForward(): void {
    try {
      this.controller.forward();
    } catch (error) {
      console.warn(`forward failed: ${JSON.stringify(error)}`);
    }
  }

  private refreshPage(): void {
    this.errorMessage = '';
    try {
      this.controller.refresh();
    } catch (error) {
      console.warn(`refresh failed: ${JSON.stringify(error)}`);
    }
  }

  private stopLoading(): void {
    try {
      // 需要根据当前 SDK 校验 stop 方法名
      this.controller.stop();
    } catch (error) {
      console.warn(`stop failed: ${JSON.stringify(error)}`);
    }
    this.isLoading = false;
  }

  // ========== 状态刷新 ==========

  /** 刷新前进/后退按钮可用状态 — 由 Web 事件回调驱动 */
  private refreshNavigationState(): void {
    try {
      const back = this.controller.accessBackward();
      const forward = this.controller.accessForward();
      // 仅在值变化时更新，减少不必要的重渲染
      if (this.canGoBack !== back || this.canGoForward !== forward) {
        this.canGoBack = back;
        this.canGoForward = forward;
      }
    } catch (error) {
      console.warn(`navigation state failed: ${JSON.stringify(error)}`);
    }
  }

  /** 检测当前 URL 是否已加入书签 */
  private async refreshBookmarkState(): Promise<void> {
    const bookmarked = await BookmarkService.isBookmarked(this.currentUrl, this.abilityContext);
    this.isBookmarked = bookmarked;
  }

  /** 刷新首页「最近访问」列表（取最近 8 条） */
  private async refreshRecentHistory(): Promise<void> {
    const all = await HistoryService.getHistory(this.abilityContext);
    this.recentHistory = all.slice(0, 8);
  }

  /** 刷新首页「我的收藏」列表（取最近 6 条） */
  private async refreshRecentBookmarks(): Promise<void> {
    const all = await BookmarkService.getBookmarks(this.abilityContext);
    this.recentBookmarks = all.slice(0, 6);
  }

  // ========== 书签操作 ==========

  private async toggleBookmark(): Promise<void> {
    if (this.currentUrl === 'about:blank') {
      promptAction.showToast({ message: '当前页面不能加入书签' });
      return;
    }
    const saved = await BookmarkService.toggleBookmark(
      this.currentTitle, this.currentUrl, this.abilityContext
    );
    this.isBookmarked = saved;
    await this.refreshRecentBookmarks();
    promptAction.showToast({
      message: saved ? '已加入书签' : '已取消书签'
    });
  }

  // ========== 历史记录 ==========

  private async saveHistory(): Promise<void> {
    if (this.setting.incognitoEnabled) {
      return;
    }
    await HistoryService.addHistory({
      title: this.currentTitle,
      url: this.currentUrl,
      visitedAt: Date.now()
    }, this.setting.incognitoEnabled, this.abilityContext);
  }

  // ========== 构建 UI ==========

  build() {
    Column() {
      // ---- 标题栏（居中） ----
      Row() {
        Blank()
        Text(this.setting.incognitoEnabled ? '🕶 无痕浏览' : this.currentTitle)
          .fontSize(14)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .fontColor(this.setting.incognitoEnabled ? '#7C4DFF' : '#4E5969')
        Blank()
      }
      .height(28)
      .width('100%')
      .padding({ left: 40, right: 40 })
      .backgroundColor('#FFFFFF')

      // ---- 标签栏 ----
      TabBar({
        tabs: $tabs,
        activeIndex: $activeIndex,
        onNewTab: () => {
          this.createNewTab();
        },
        onCloseTab: (index: number) => {
          this.closeTab(index);
        },
        onSwitchTab: (index: number) => {
          this.switchToTab(index);
        }
      })

      // ---- 地址栏 ----
      AddressBar({
        text: $addressText,
        isLoading: this.isLoading,
        showNewTabButton: true,
        onSubmit: async (value: string) => {
          await this.loadInput(value);
        },
        onOpenInNewTab: (value: string) => {
          // 在新标签页中打开，后台加载不切换
          const nextUrl = UrlUtils.normalizeUrl(value, this.setting.searchEngine);
          this.openInBackgroundTab(nextUrl);
        }
      })

      // ---- 进度条 ----
      if (this.isLoading && this.progress > 0 && this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color('#0A59F7')
          .backgroundColor('#E8F0FE')
      } else {
        Divider()
          .height(1)
          .color('#F2F3F5')
      }

      // ---- Web 渲染区 + 覆盖层 ----
      Stack() {
        // Web 组件：src 固定为 about:blank，避免重渲染丢失导航历史
        // 所有页面导航只通过 controller.loadUrl() 触发
        Web({ src: 'about:blank', controller: this.controller })
          .width('100%')
          .height('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .multiWindowAccess(true)
          .allowWindowOpenMethod(true)
          .javaScriptOnDocumentStart([{
            script: `(function(){window.__hmb_injected=1;})();`,
            scriptRules: [] as string[]
          }])
          .userAgent(CHROME_MOBILE_UA)
          // 手势：右滑后退、左滑前进（parallelGesture 不拦截 Web 滚动与系统手势）
          .parallelGesture(
            PanGesture({ direction: PanDirection.Horizontal, distance: 15 })
              .onActionEnd((event: GestureEvent) => {
                if (event.offsetX > 100 && this.canGoBack) {
                  this.goBack();
                } else if (event.offsetX < -100 && this.canGoForward) {
                  this.goForward();
                }
              })
          )
          // ---- ArkWeb 事件回调 ----
          // 以下事件名与参数结构需根据当前 SDK 校验
          .onPageBegin((event) => {
            const beginUrl = event?.url || '';
            console.info(`[HMB-TRACE] main onPageBegin: url=${beginUrl}`);
            // ---- 验证 javaScriptOnDocumentStart 是否生效 ----
            this.controller.runJavaScript('window.__hmb_injected || "NOT_INJECTED"', (err: Error | null, result: string) => {
              if (!err && result) {
                console.info(`[HMB-TRACE] JS injection check: ${result}`);
              }
            });
            // ---- 早期注入 JS 拦截脚本（比 onPageEnd 更早，用户点击链接前就已生效）----
            this.injectBlankTargetHandler();

            // ---- target="_blank" 桥接 URL 拦截（跨域链接的 fallback 路径）----
            if (beginUrl.startsWith('__hmb_newtab__:')) {
              // 1. 立即停止桥接 URL 加载，保持当前页面显示
              try { this.controller.stop(); } catch (_e) {}
              // 2. 提取真实目标 URL
              const encodedUrl = beginUrl.substring('__hmb_newtab__:'.length);
              let realUrl = '';
              try {
                realUrl = decodeURIComponent(encodedUrl);
              } catch (_e) {
                realUrl = encodedUrl;
              }
              // 3. 异步恢复原页面 URL
              const js = 'window.__hmb_prev_page_url || ""';
              try {
                this.controller.runJavaScript(js, (err: Error | null, result: string) => {
                  if (!err && result && result.length > 2) {
                    const prevUrl = result.substring(1, result.length - 1);
                    if (prevUrl && prevUrl.startsWith('http')) {
                      try { this.controller.loadUrl(prevUrl); } catch (_e) {}
                    }
                  }
                });
              } catch (_e) {
                // ignore
              }
              // 4. 在新标签页打开真实 URL（前台切换）
              if (realUrl && (realUrl.startsWith('http://') || realUrl.startsWith('https://'))) {
                this.openInNewTab(realUrl);
              } else {
                this.createNewTab();
              }
              return; // 不更新当前页面状态
            }

            // 清空上下文阶段：静默忽略中间 about:blank，不更新 UI 状态
            if (this.flushingContext && event?.url === 'about:blank') {
              this.flushingContext = false;
              return;
            }
            const targetUrl = event?.url || '';
            // ⚠️ 自定义协议拦截：必须在更新任何 UI 状态之前处理
            // 网页内链接可能指向 baiduboxapp://、weixin:// 等 scheme，
            // WebView 无法渲染这些协议，必须提前阻止并转换或忽略
            if (this.isCustomScheme(targetUrl)) {
              console.info(`onPageBegin intercepted custom scheme: ${targetUrl}`);
              const realUrl = this.extractRealUrlFromAppScheme(targetUrl);
              if (realUrl) {
                // 提取到真实 HTTPS 目标 URL → 直接导航过去
                try { this.controller.stop(); } catch (_e) {}
                this.controller.loadUrl(realUrl);
              } else if (!this.isSensitiveScheme(targetUrl)) {
                // 未知且非敏感 scheme → 停止加载，保持当前页面不变
                try { this.controller.stop(); } catch (_e) {}
              }
              // 敏感 scheme（支付等）→ 让 onErrorReceive 弹确认框
              return; // 不更新任何 UI 状态
            }

            this.isLoading = true;
            this.progress = 5;
            this.errorMessage = '';
            if (targetUrl) {
              this.currentUrl = targetUrl;
              if (targetUrl === 'about:blank') {
                // 后退到 about:blank 时自动切回首页覆盖层
                this.hasNavigated = false;
                this.currentTitle = '空白页面';
                this.isBookmarked = false;
                this.addressText = '';
              } else {
                // 导航到真实网页时隐藏首页覆盖层
                this.hasNavigated = true;
                this.addressText = targetUrl;
              }
            }
            this.refreshNavigationState();
            // 立即同步到标签页，确保 hasNavigated 和 URL 生效，标签名不再显示"首页"
            this.syncToActiveTab();
          })
          .onPageEnd(async (event) => {
            // 清空上下文阶段：静默忽略中间 about:blank
            if (this.flushingContext && event?.url === 'about:blank') {
              return;
            }
            const targetUrl = event?.url || '';
            // 自定义协议保护：onPageEnd 不应出现自定义 scheme URL
            // 如果出现说明 onPageBegin 拦截遗漏，此处兜底防止污染 UI 状态
            if (this.isCustomScheme(targetUrl)) {
              return; // 已由 onPageBegin / onErrorReceive 处理，忽略
            }

            this.isLoading = false;
            this.progress = 100;
            if (targetUrl) {
              this.currentUrl = targetUrl;
              if (targetUrl === 'about:blank') {
                // 后退到 about:blank 时自动切回首页覆盖层
                this.hasNavigated = false;
                this.currentTitle = '空白页面';
                this.isBookmarked = false;
                this.addressText = '';
                await this.refreshRecentHistory();
              } else {
                this.hasNavigated = true;
                this.addressText = event.url;
              }
            }
            this.refreshNavigationState();
            await this.refreshBookmarkState();
            if (this.currentUrl !== 'about:blank') {
              await this.saveHistory();
            }
            // 注入 target="_blank" 拦截脚本，使这类链接能触发 onWindowNew
            this.injectBlankTargetHandler();
            // 同步导航结果到激活标签页
            this.syncToActiveTab();
          })
          .onProgressChange((event) => {
            // 需要校验：event.newProgress 字段名
            this.progress = event?.newProgress ?? 0;
            this.isLoading = this.progress > 0 && this.progress < 100;
          })
          .onTitleReceive((event) => {
            const title = event?.title || '';
            // 检测 JS 注入发送的新标签页请求：__hmb_newtab__|URL
            const prefix = '__hmb_newtab__|';
            if (title.startsWith(prefix)) {
              const url = title.substring(prefix.length);
              if (url && (url.startsWith('http://') || url.startsWith('https://'))) {
                console.info('[HMB-TRACE] onTitleReceive new tab: ' + url);
                this.openInNewTab(url);
              }
              return; // 不更新标题
            }
            // 正常标题处理
            if (title.length > 0 && !this.looksLikeSchemeUrl(title)) {
              this.currentTitle = title;
              this.syncToActiveTab();
            }
          })
          .onErrorReceive((event) => {
            // 需要校验：event.request?.getRequestUrl 是否存在
            const failedUrl =
              event?.request?.getRequestUrl ?
                event.request.getRequestUrl() :
                this.currentUrl;
            // 自定义协议：先尝试转 HTTPS，未知且敏感的才弹确认
            if (this.isCustomScheme(failedUrl)) {
              const httpsUrl = this.resolveCustomScheme(failedUrl);
              if (httpsUrl) {
                // 已知 scheme → 用 HTTPS 版本加载
                this.controller.loadUrl(httpsUrl);
              } else if (this.isSensitiveScheme(failedUrl)) {
                // 敏感 scheme（支付等）→ 弹确认
                this.pendingSchemeUrl = failedUrl;
                this.showSchemeConfirm = true;
              }
              // 其他未知 scheme → 静默忽略（不再弹窗或报错）
              return;
            }
            // 只显示当前主页面相关的错误，忽略旧页面的子资源残留错误
            if (!this.isErrorForCurrentPage(failedUrl)) {
              return;
            }
            this.isLoading = false;
            this.progress = 100;
            this.errorMessage = `网页加载失败：${failedUrl}`;
            promptAction.showToast({
              message: '网页加载失败，请检查网络或网址'
            });
          })
          // onWindowNew：只设置空 controller，防止弹窗（实际处理在 onTitleReceive）
          .onWindowNew((event) => {
            event.handler.setWebController(new webview.WebviewController());
          })

        // ---- 首页覆盖层：显示快捷入口 + 最近访问 ----
        if (!this.hasNavigated && !this.errorMessage) {
          Scroll() {
            Column() {
              Blank().height(24)
              Text('Harmony Browser')
                .fontSize(26)
                .fontWeight(FontWeight.Medium)
                .fontColor('#182431')
              Text('输入网址或关键词开始浏览')
                .margin({ top: 8, bottom: 18 })
                .fontSize(14)
                .fontColor('#86909C')

              // 快捷入口
              QuickLinks({
                onOpen: async (url: string) => {
                  await this.loadUrl(url);
                }
              })

              // 最近访问（仅在有历史时展示）
              if (this.recentHistory.length > 0) {
                Column() {
                  Text('最近访问')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#86909C')
                    .margin({ top: 24, bottom: 10 })
                    .alignSelf(ItemAlign.Start)
                    .padding({ left: 16 })

                  List({ space: 2 }) {
                    ForEach(this.recentHistory, (item: HistoryItem, index: number) => {
                      ListItem() {
                        Row() {
                          // 左侧 favicon 占位
                          Text(item.title.charAt(0).toUpperCase())
                            .fontSize(14)
                            .fontColor('#FFFFFF')
                            .textAlign(TextAlign.Center)
                            .width(32)
                            .height(32)
                            .borderRadius(8)
                            .backgroundColor('#0A59F7')
                          // 标题和 URL
                          Column() {
                            Text(item.title || item.url)
                              .fontSize(14)
                              .fontColor('#1D2129')
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                            Text(item.url)
                              .fontSize(11)
                              .fontColor('#86909C')
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .margin({ top: 2 })
                          }
                          .alignItems(HorizontalAlign.Start)
                          .margin({ left: 10 })
                          .layoutWeight(1)
                        }
                        .width('100%')
                        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                      }
                      .onClick(async () => {
                        await this.loadUrl(item.url);
                      })
                    }, (item: HistoryItem) => item.url)
                  }
                  .width('100%')
                  .padding({ bottom: 16 })
                }
              }

              // 我的收藏（仅在书签时展示）
              if (this.recentBookmarks.length > 0) {
                Column() {
                  Row() {
                    Text('我的收藏')
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#86909C')
                    Blank()
                    Text('查看全部')
                      .fontSize(12)
                      .fontColor('#0A59F7')
                      .onClick(() => {
                        this.showBookmarks = true;
                      })
                  }
                  .width('100%')
                  .margin({ top: 16, bottom: 10 })
                  .padding({ left: 16, right: 16 })

                  List({ space: 2 }) {
                    ForEach(this.recentBookmarks, (item: Bookmark) => {
                      ListItem() {
                        Row() {
                          // 左侧星标图标
                          Text('★')
                            .fontSize(13)
                            .fontColor('#FF9500')
                            .textAlign(TextAlign.Center)
                            .width(32)
                            .height(32)
                            .borderRadius(8)
                            .backgroundColor('#FFF8E8')
                          // 标题和 URL
                          Column() {
                            Text(item.title || item.url)
                              .fontSize(14)
                              .fontColor('#1D2129')
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                            Text(item.url)
                              .fontSize(11)
                              .fontColor('#86909C')
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .margin({ top: 2 })
                          }
                          .alignItems(HorizontalAlign.Start)
                          .margin({ left: 10 })
                          .layoutWeight(1)
                        }
                        .width('100%')
                        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                      }
                      .onClick(async () => {
                        await this.loadUrl(item.url);
                      })
                    }, (item: Bookmark) => item.url)
                  }
                  .width('100%')
                  .padding({ bottom: 16 })
                }
              }

              // 底部留白，避免被工具栏遮挡
              Blank().height(12)
            }
            .width('100%')
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .backgroundColor('#FFFFFF')
        }

        // ---- 错误覆盖层 ----
        if (this.errorMessage.length > 0) {
          Column({ space: 12 }) {
            Blank().height(48)
            Text(this.errorMessage)
              .fontSize(15)
              .fontColor('#C7362E')
              .textAlign(TextAlign.Center)
              .width('80%')
            Text('请检查网址是否正确，或网络是否连接')
              .fontSize(13)
              .fontColor('#86909C')
            Row({ space: 12 }) {
              Button('重试')
                .height(38)
                .fontSize(14)
                .backgroundColor('#0A59F7')
                .fontColor('#FFFFFF')
                .borderRadius(19)
                .onClick(() => {
                  this.refreshPage();
                })
              Button('返回首页')
                .height(38)
                .fontSize(14)
                .backgroundColor('#F2F3F5')
                .fontColor('#4E5969')
                .borderRadius(19)
                .onClick(async () => {
                  await this.goHome();
                })
            }
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#FFFFFF')
        }
      }
      .layoutWeight(1)
      .width('100%')

      // ---- 底部工具栏 ----
      BrowserToolbar({
        canGoBack: this.canGoBack,
        canGoForward: this.canGoForward,
        isLoading: this.isLoading,
        isBookmarked: this.isBookmarked,
        onBack: () => this.goBack(),
        onForward: () => this.goForward(),
        onHome: async () => {
          await this.goHome();
        },
        onRefresh: () => this.refreshPage(),
        onStop: () => this.stopLoading(),
        onBookmark: async () => {
          await this.toggleBookmark();
        },
        onMenu: () => {
          this.showBookmarks = true;
        }
      })

      // ---- OAuth / window.open() 弹窗覆盖层 ----
      // 使用 Stack 内嵌而非 CustomDialog，确保 WebView 在同一页面上下文中，
      // Cookie、session、DOM storage 可正常共享
      if (this.showOAuthWindow && this.oauthWebController !== null) {
        Column() {
          // 标题栏
          Row() {
            Text('授权登录')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
            Blank()
            Button('完成')
              .fontSize(13)
              .fontColor('#FFFFFF')
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.showOAuthWindow = false;
                // 通知内核弹窗已关闭
                if (this.oauthWebController !== null) {
                  try {
                    this.oauthWebController.stop();
                  } catch (e) {
                    // ignore
                  }
                }
                this.oauthWebController = null;
              })
          }
          .width('100%')
          .height(44)
          .padding({ left: 16, right: 16 })
          .backgroundColor('#1A1A1A')

          // Progress 指示器
          Progress({ value: 50, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(2)
            .color('#0A59F7')
            .backgroundColor('#333333')

          // 弹窗 WebView
          Web({ src: 'about:blank', controller: this.oauthWebController })
            .width('100%')
            .layoutWeight(1)
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .userAgent(CHROME_MOBILE_UA)
            .onPageBegin((event) => {
              const popupUrl: string = event?.url || '';
              console.info(`[HMB-TRACE] popup onPageBegin: url=${popupUrl}`);
              // 跳过初始 about:blank
              if (popupUrl === 'about:blank') {
                console.info('[HMB-TRACE] popup skipping about:blank');
                return;
              }
              // 如果是普通 HTTP 链接（非 OAuth）→ 关闭弹窗，在新标签页打开
              if (popupUrl && (popupUrl.startsWith('http://') || popupUrl.startsWith('https://'))
                  && !this.isOAuthUrl(popupUrl)) {
                console.info(`[HMB-TRACE] popup detected normal HTTP, will openInNewTab: ${popupUrl}`);
                // 立即停止弹窗加载
                if (this.oauthWebController) {
                  try { this.oauthWebController.stop(); } catch (_e) {}
                }
                // 关闭弹窗
                this.showOAuthWindow = false;
                this.oauthWebController = null;
                // 在新标签页打开
                console.info(`[HMB-TRACE] calling openInNewTab: ${popupUrl}`);
                this.openInNewTab(popupUrl);
              } else {
                console.info(`[HMB-TRACE] popup keeping (isOAuthUrl=${this.isOAuthUrl(popupUrl)}, popupUrl=${popupUrl})`);
              }
              // OAuth URL → 继续在弹窗中显示
            })
            .onPageEnd(() => {
              // OAuth 完成后页面跳转回原站，用户可手动点击「完成」关闭
            })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#1A1A1A')
        .position({ x: 0, y: 0 })
        .zIndex(100)
      }

      // ---- 自定义协议跳转确认弹窗 ----
      if (this.showSchemeConfirm && this.pendingSchemeUrl.length > 0) {
        // 半透明遮罩
        Column() {
          Blank()
          // 弹窗卡片
          Column({ space: 16 }) {
            Text('跳转到外部应用')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor('#182431')

            Text(`此链接将打开其他应用：\n${this.pendingSchemeUrl}`)
              .fontSize(13)
              .fontColor('#4E5969')
              .textAlign(TextAlign.Center)
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .backgroundColor('#F2F3F5')
                .fontColor('#4E5969')
                .borderRadius(20)
                .onClick(() => {
                  this.showSchemeConfirm = false;
                  this.pendingSchemeUrl = '';
                })

              Button('允许')
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .backgroundColor('#0A59F7')
                .fontColor('#FFFFFF')
                .borderRadius(20)
                .onClick(async () => {
                  const url = this.pendingSchemeUrl;
                  this.showSchemeConfirm = false;
                  this.pendingSchemeUrl = '';
                  await this.tryOpenAppLink(url);
                })
            }
            .width('100%')
          }
          .width('80%')
          .padding(20)
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .shadow({
            radius: 20,
            color: 'rgba(0,0,0,0.1)',
            offsetX: 0,
            offsetY: 2
          })
          Blank()
        }
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })
        .zIndex(200)
        .justifyContent(FlexAlign.Center)
      }

      // ---- 书签面板覆盖层 ----
      if (this.showBookmarks) {
        BookmarkPage({
          onNavigate: async (url: string) => {
            this.showBookmarks = false;
            await this.loadUrl(url);
          },
          onClose: () => {
            this.showBookmarks = false;
          }
        })
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })
        .zIndex(150)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
