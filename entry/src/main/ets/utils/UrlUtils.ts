/**
 * URL 工具类
 * 负责：URL 判断、自动补全 https://、搜索引擎 URL 构建、全角符号转半角
 */
const DEFAULT_SEARCH_ENGINE = 'https://www.bing.com/search?q={keyword}';
const BAIDU_SEARCH_ENGINE = 'https://www.baidu.com/s?wd={keyword}';

/** 全角符号 → 半角符号映射表（URL 常用） */
const FULL_TO_HALF_MAP: Record<string, string> = {
  '：': ':',   '／': '/',   '．': '.',   '？': '?',
  '；': ';',   '＠': '@',   '＆': '&',   '＝': '=',
  '＋': '+',   '＃': '#',   '％': '%',   '＿': '_',
  '－': '-',   '～': '~',   '！': '!',   '（': '(',
  '）': ')',   '［': '[',   '］': ']',   '｛': '{',
  '｝': '}',   '＼': '\\',
};

/** 将输入中的全角符号替换为对应半角符号 */
function normalizeFullWidth(input: string): string {
  let result = '';
  for (let i = 0; i < input.length; i++) {
    const ch = input.charAt(i);
    result += FULL_TO_HALF_MAP[ch] ?? ch;
  }
  return result;
}

/** 检查是否已有协议头（http:// https:// ftp:// 等） */
function hasScheme(input: string): boolean {
  return /^[a-zA-Z][a-zA-Z\d+\-.]*:\/\//.test(input);
}

/** 检查是否为纯 IPv4 地址 */
function isIpv4(input: string): boolean {
  const host = input.split('/')[0].split(':')[0];
  const parts = host.split('.');
  if (parts.length !== 4) {
    return false;
  }
  return parts.every((part: string) => {
    if (!/^\d+$/.test(part)) {
      return false;
    }
    const value = Number(part);
    return value >= 0 && value <= 255;
  });
}

/** 检查是否为合法域名 */
function isDomain(input: string): boolean {
  const host = input.split('/')[0].split(':')[0];
  if (host === 'localhost') {
    return true;
  }
  // 匹配 xxx.xxx 形式域名
  return /^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$/.test(host);
}

/** 检查是否包含端口号 */
function hasPort(input: string): boolean {
  const hostPart = input.split('/')[0];
  return /:\d{1,5}$/.test(hostPart);
}

export class UrlUtils {
  static readonly DEFAULT_SEARCH_ENGINE: string = DEFAULT_SEARCH_ENGINE;
  static readonly BAIDU_SEARCH_ENGINE: string = BAIDU_SEARCH_ENGINE;

  /**
   * 判断输入是否可能是一个 URL
   */
  static isProbablyUrl(input: string): boolean {
    const value = input.trim();
    if (value.length === 0 || /\s/.test(value)) {
      return false;
    }
    if (hasScheme(value)) {
      return true;
    }
    if (value.startsWith('localhost') || isIpv4(value)) {
      return true;
    }
    return isDomain(value) || hasPort(value);
  }

  /**
   * 规范化 URL：
   * - 如果是 URL，补全 https://
   * - 如果是关键词，转搜索引擎地址
   * - 空输入返回 about:blank
   */
  static normalizeUrl(input: string, searchEngine?: string): string {
    // 1. 去除首尾空白
    let value = input.trim();
    if (value.length === 0) {
      return 'about:blank';
    }
    // 2. 全角符号 → 半角符号（兼容中文输入法下的 // . : 等）
    value = normalizeFullWidth(value);
    // 3. 判断是 URL 还是关键词
    if (!UrlUtils.isProbablyUrl(value)) {
      return UrlUtils.buildSearchUrl(value, searchEngine);
    }
    if (hasScheme(value)) {
      return value;
    }
    // 4. 自动补全 https://
    return `https://${value}`;
  }

  /**
   * 构建搜索引擎 URL
   * 默认使用 Bing，可通过 searchEngine 参数切换
   */
  static buildSearchUrl(keyword: string, searchEngine?: string): string {
    const template = searchEngine && searchEngine.length > 0
      ? searchEngine
      : DEFAULT_SEARCH_ENGINE;
    const encodedKeyword = encodeURIComponent(keyword.trim());
    if (template.includes('{keyword}')) {
      return template.replace('{keyword}', encodedKeyword);
    }
    // 兜底：简单拼接
    const separator = template.includes('?') ? '&' : '?';
    return `${template}${separator}q=${encodedKeyword}`;
  }
}
