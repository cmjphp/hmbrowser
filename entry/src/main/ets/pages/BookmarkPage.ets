/**
 * BookmarkPage.ets — 书签列表页面
 *
 * 以全屏面板形式展示所有书签，支持：
 * - 点击书签导航到对应网页
 * - 左滑删除书签
 * - 空状态提示
 *
 * 作为 @Component 被 BrowserPage 导入，通过 overlay 方式显示
 */

import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { Bookmark } from '../model/Bookmark';
import { BookmarkService } from '../service/BookmarkService';

/** 根据域名生成稳定的伪随机颜色 */
function domainColor(url: string): string {
  const palette: string[] = [
    '#0A59F7', '#FF6B35', '#34C759', '#AF52DE',
    '#FF2D55', '#FF9500', '#5AC8FA', '#5856D6',
    '#007AFF', '#FF3B30', '#4CD964', '#FFCC00'
  ];
  let hash = 0;
  // 提取域名部分做 hash
  let start = url.indexOf('://');
  if (start !== -1) {
    start = start + 3;
  } else {
    start = 0;
  }
  let end = url.indexOf('/', start);
  if (end === -1) {
    end = url.length;
  }
  const domain = url.substring(start, end);
  for (let i = 0; i < domain.length; i++) {
    hash = ((hash << 5) - hash) + domain.charCodeAt(i);
    hash = hash & hash; // Convert to 32bit integer
  }
  return palette[Math.abs(hash) % palette.length];
}

/** 从 URL 提取简短域名用于显示 */
function shortDomain(url: string): string {
  let start = url.indexOf('://');
  if (start !== -1) {
    start = start + 3;
  } else {
    start = 0;
  }
  // 去掉 www. 前缀
  if (url.substring(start, start + 4) === 'www.') {
    start = start + 4;
  }
  let end = url.indexOf('/', start);
  if (end === -1) {
    end = url.length;
  }
  return url.substring(start, end);
}

/** 格式化时间戳为简短日期 */
function formatDate(timestamp: number): string {
  if (!timestamp || timestamp <= 0) {
    return '';
  }
  const d = new Date(timestamp);
  const month = d.getMonth() + 1;
  const day = d.getDate();
  return `${month}月${day}日`;
}

@Component
export struct BookmarkPage {
  private abilityContext?: common.UIAbilityContext;
  @State private bookmarks: Bookmark[] = [];
  @State private isLoading: boolean = true;
  /** 点击书签后回调，传入 URL */
  onNavigate: (url: string) => void = () => {};
  /** 关闭面板回调 */
  onClose: () => void = () => {};

  aboutToAppear(): void {
    try {
      this.abilityContext = getContext(this) as common.UIAbilityContext;
    } catch (e) {
      // ignore
    }
    this.loadBookmarks();
  }

  private async loadBookmarks(): Promise<void> {
    this.isLoading = true;
    this.bookmarks = await BookmarkService.getBookmarks(this.abilityContext);
    this.isLoading = false;
  }

  private async deleteBookmark(url: string): Promise<void> {
    await BookmarkService.removeBookmark(url, this.abilityContext);
    // 重新加载列表
    await this.loadBookmarks();
    promptAction.showToast({ message: '已删除书签' });
  }

  build() {
    Column() {
      // ---- 顶部标题栏 ----
      Row() {
        Text('书签')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#182431')

        Blank()

        // 关闭按钮
        Text('✕')
          .fontSize(18)
          .fontColor('#86909C')
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 12 })

      Divider()
        .height(0.5)
        .color('#F2F3F5')

      // ---- 书签数量统计 ----
      if (!this.isLoading && this.bookmarks.length > 0) {
        Text(`共 ${this.bookmarks.length} 个书签`)
          .fontSize(12)
          .fontColor('#C9CDD4')
          .width('100%')
          .padding({ left: 16, top: 8, bottom: 4 })
      }

      // ---- 内容区域 ----
      if (this.isLoading) {
        // 加载中
        Column() {
          Blank()
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#0A59F7')
          Blank()
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.bookmarks.length === 0) {
        // 空状态
        Column({ space: 12 }) {
          Blank()
          Text('☆')
            .fontSize(48)
            .fontColor('#E5E6EB')
          Text('暂无书签')
            .fontSize(16)
            .fontColor('#86909C')
          Text('浏览网页时点击 ☆ 即可添加书签')
            .fontSize(13)
            .fontColor('#C9CDD4')
          Blank()
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 书签列表
        List({ space: 0 }) {
          ForEach(this.bookmarks, (item: Bookmark) => {
            ListItem() {
              Row() {
                // 左侧域名首字图标
                Text(shortDomain(item.url).charAt(0).toUpperCase())
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#FFFFFF')
                  .textAlign(TextAlign.Center)
                  .width(36)
                  .height(36)
                  .borderRadius(10)
                  .backgroundColor(domainColor(item.url))

                // 标题和 URL
                Column() {
                  Text(item.title || item.url)
                    .fontSize(15)
                    .fontColor('#1D2129')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row() {
                    Text(shortDomain(item.url))
                      .fontSize(12)
                      .fontColor('#86909C')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    if (item.createdAt > 0) {
                      Text(formatDate(item.createdAt))
                        .fontSize(11)
                        .fontColor('#C9CDD4')
                        .margin({ left: 8 })
                    }
                  }
                  .width('100%')
                  .margin({ top: 3 })
                }
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 12 })
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .backgroundColor('#FFFFFF')
            }
            .onClick(() => {
              this.onNavigate(item.url);
            })
            // 左滑显示删除按钮
            .swipeAction({ end: this.deleteAction(item.url) })
          }, (item: Bookmark) => item.url)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .divider({
          strokeWidth: 0.5,
          color: '#F2F3F5',
          startMargin: 64,
          endMargin: 0
        })
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  /** 左滑删除按钮 */
  @Builder
  deleteAction(url: string) {
    Row() {
      Text('删除')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .width(72)
        .height('100%')
        .backgroundColor('#FF3B30')
        .onClick(async () => {
          await this.deleteBookmark(url);
        })
    }
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
