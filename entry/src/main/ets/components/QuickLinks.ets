/**
 * QuickLinks.ets — 首页快捷入口组件
 * 以网格形式展示常用网站，点击后回调父组件加载 URL
 */

export interface QuickLink {
  title: string;
  url: string;
}

const DEFAULT_QUICK_LINKS: QuickLink[] = [
  { title: '百度', url: 'https://www.baidu.com' },
  { title: 'Bing', url: 'https://www.bing.com' },
  { title: '华为开发者', url: 'https://developer.huawei.com' },
  { title: '知乎', url: 'https://www.zhihu.com' },
  { title: 'GitHub', url: 'https://github.com' },
  { title: '鸿蒙官网', url: 'https://www.harmonyos.com' },
  { title: '哔哩哔哩', url: 'https://www.bilibili.com' },
  { title: '微博', url: 'https://m.weibo.cn' }
];

@Component
export struct QuickLinks {
  @Prop links: QuickLink[] = DEFAULT_QUICK_LINKS;
  onOpen: (url: string) => void = () => {};

  build() {
    Column({ space: 16 }) {
      Text('快捷入口')
        .width('100%')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor('#182431')

      Grid() {
        ForEach(this.links, (item: QuickLink, index: number) => {
          GridItem() {
            Column({ space: 8 }) {
              // 圆形图标（取标题首字）
              Text(item.title.substring(0, 1))
                .width(44)
                .height(44)
                .fontSize(20)
                .fontWeight(FontWeight.Medium)
                .textAlign(TextAlign.Center)
                .fontColor('#0A59F7')
                .backgroundColor('#E8F0FE')
                .borderRadius(22)

              Text(item.title)
                .fontSize(12)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontColor('#4E5969')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.onOpen(item.url);
            })
          }
        }, (item: QuickLink) => item.url)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .rowsGap(16)
      .columnsGap(8)
      .width('100%')
      .height(180)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }
}
