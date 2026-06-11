@Component
export struct BookmarkPage {
  build() {
    Column() {
      Text('书签页预留')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
