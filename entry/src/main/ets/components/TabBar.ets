/**
 * TabBar.ets — 多标签页切换栏
 * 横向可滚动的标签列表，支持切换、关闭、新建标签
 */

import { TabInfo } from '../model/BrowserTab';

@Component
export struct TabBar {
  @Link tabs: TabInfo[];
  @Link activeIndex: number;
  onNewTab: () => void = () => {};
  onCloseTab: (index: number) => void = () => {};
  onSwitchTab: (index: number) => void = () => {};

  build() {
    Row() {
      Scroll() {
        Row({ space: 4 }) {
          ForEach(this.tabs, (tab: TabInfo, index: number) => {
            Row() {
              Text(this.getTabLabel(this.tabs[index]))
                .fontSize(11)
                .maxLines(1)
                .fontColor(index === this.activeIndex ? '#0A59F7' : '#4E5969')
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 80 })
                .padding({ left: 10, right: 2 })

              // 关闭按钮：只有多于 1 个标签时才显示
              if (this.tabs.length > 1) {
                Text('✕')
                  .fontSize(9)
                  .fontColor('#86909C')
                  .width(16)
                  .height(16)
                  .borderRadius(8)
                  .textAlign(TextAlign.Center)
                  .onClick(() => {
                    this.onCloseTab(index);
                  })
              }
            }
            .height(30)
            .borderRadius(15)
            .backgroundColor(index === this.activeIndex ? '#E8F0FE' : '#F2F3F5')
            .border({
              width: index === this.activeIndex ? 1.5 : 0,
              color: '#0A59F7'
            })
            .padding({ right: 6 })
            .onClick(() => {
              this.onSwitchTab(index);
            })
          }, (tab: TabInfo) => `${tab.id}_${tab.version}`)

          // 新建标签按钮 "+"
          Row() {
            Text('+')
              .fontSize(18)
              .fontColor('#0A59F7')
              .fontWeight(FontWeight.Medium)
          }
          .width(30)
          .height(30)
          .borderRadius(15)
          .backgroundColor('#E8F0FE')
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.onNewTab();
          })
        }
        .padding({ left: 6, right: 6 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)

      // 右侧标签数量徽章
      Text(this.tabs.length.toString())
        .fontSize(10)
        .fontColor('#86909C')
        .width(22)
        .height(22)
        .borderRadius(11)
        .backgroundColor('#F2F3F5')
        .textAlign(TextAlign.Center)
        .margin({ right: 8 })
    }
    .width('100%')
    .height(38)
    .backgroundColor('#FFFFFF')
    .border({ width: { bottom: 0.5 }, color: '#E5E6EB' })
  }

  /** 获取标签显示文字 */
  private getTabLabel(tab: TabInfo): string {
    // 未导航且无有效 URL → 显示"首页"
    if (!tab.hasNavigated && (!tab.url || tab.url === 'about:blank')) {
      return '首页';
    }
    // 有有效 URL 时（hasNavigated=true 或 url 非 about:blank），优先用标题
    let label = tab.title;
    // ⚠️ 兜底：标题看起来像自定义协议 URL 时，丢弃并从 URL 提取域名
    if (label && this.looksLikeSchemeUrl(label)) {
      label = '';
    }
    // 标题无效或为默认值时，从 URL 提取简短标识
    if (!label || label === '空白页面' || label === '新标签页') {
      const host = this.extractHostFromUrl(tab.url);
      if (host) {
        label = host;
      }
    }
    // 最终兜底
    if (!label) {
      return tab.hasNavigated ? '新标签页' : '首页';
    }
    if (label.length > 10) {
      label = label.substring(0, 9) + '…';
    }
    return label;
  }

  /**
   * 判断字符串是否像自定义协议 URL（如 "baiduboxapp://..."）
   * 用于 getTabLabel 最后防线，防止标签栏显示乱码
   */
  private looksLikeSchemeUrl(s: string): boolean {
    if (!s || s.length < 5) return false;
    const colonIdx = s.indexOf('://');
    if (colonIdx <= 0) return false; // 无 :// 或 :// 在开头 → 不是 scheme URL
    const protocol = s.substring(0, colonIdx).toLowerCase();
    const knownProtocols = ['http', 'https', 'ftp', 'file', 'data', 'javascript', 'about'];
    return !knownProtocols.includes(protocol);
  }

  /** 从 URL 提取主机名（简化版），非 http(s) URL 返回空 */
  private extractHostFromUrl(url: string): string {
    if (!url || !url.startsWith('http')) {
      // 自定义协议如 baiduboxapp:// 不显示为标签名
      return '';
    }
    let start = url.indexOf('://');
    start = start === -1 ? 0 : start + 3;
    let end = url.length;
    for (const ch of ['/', '?', '#']) {
      const idx = url.indexOf(ch, start);
      if (idx !== -1 && idx < end) end = idx;
    }
    return url.substring(start, end) || '';
  }
}
