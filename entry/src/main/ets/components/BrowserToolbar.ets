/**
 * BrowserToolbar.ets — 底部浏览器工具栏
 * 支持：返回、前进、首页、刷新/停止、书签、菜单（预留）
 *
 * 注意：使用 layoutWeight(1) 等分空间，避免固定宽度导致的按钮裁切
 */

@Component
export struct BrowserToolbar {
  @Prop canGoBack: boolean = false;
  @Prop canGoForward: boolean = false;
  @Prop isLoading: boolean = false;
  @Prop isBookmarked: boolean = false;
  onBack: () => void = () => {};
  onForward: () => void = () => {};
  onHome: () => void = () => {};
  onRefresh: () => void = () => {};
  onStop: () => void = () => {};
  onBookmark: () => void = () => {};
  onMenu: () => void = () => {};

  build() {
    Row() {
      // ---- 返回按钮 ----
      Column() {
        Text('‹')
          .fontSize(28)
          .fontWeight(FontWeight.Lighter)
          .fontColor(this.canGoBack ? '#1D2129' : '#C5C8CE')
      }
      .layoutWeight(1)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        if (this.canGoBack) {
          this.onBack();
        }
      })

      // ---- 前进按钮 ----
      Column() {
        Text('›')
          .fontSize(28)
          .fontWeight(FontWeight.Lighter)
          .fontColor(this.canGoForward ? '#1D2129' : '#C5C8CE')
      }
      .layoutWeight(1)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        if (this.canGoForward) {
          this.onForward();
        }
      })

      // ---- 首页按钮 ----
      Column() {
        Text('⌂')
          .fontSize(22)
          .fontColor('#1D2129')
      }
      .layoutWeight(1)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.onHome();
      })

      // ---- 刷新 / 停止按钮 ----
      Column() {
        Text(this.isLoading ? '✕' : '↻')
          .fontSize(22)
          .fontColor('#1D2129')
      }
      .layoutWeight(1)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        if (this.isLoading) {
          this.onStop();
        } else {
          this.onRefresh();
        }
      })

      // ---- 书签按钮（收藏后金色实心） ----
      Column() {
        Text(this.isBookmarked ? '★' : '☆')
          .fontSize(22)
          .fontColor(this.isBookmarked ? '#FF9500' : '#1D2129')
      }
      .layoutWeight(1)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.onBookmark();
      })

      // ---- 菜单按钮 ----
      Column() {
        Text('⋯')
          .fontSize(22)
          .fontColor('#1D2129')
      }
      .layoutWeight(1)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.onMenu();
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 4, right: 4 })
    .backgroundColor('#FAFBFC')
    .border({
      width: { top: 0.5 },
      color: '#E5E6EB'
    })
  }
}
