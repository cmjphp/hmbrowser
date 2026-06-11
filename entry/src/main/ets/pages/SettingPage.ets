@Component
export struct SettingPage {
  build() {
    Column() {
      Text('设置页预留')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
