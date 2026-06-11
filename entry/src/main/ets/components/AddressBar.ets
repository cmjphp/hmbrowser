/**
 * AddressBar.ets — 地址栏组件
 * 支持：URL 显示 / 输入、加载状态、清空按钮、搜索回车提交、聚焦全选
 *
 * 聚焦全选实现原理：
 * ArkUI TextInput 没有直接的 selectAll() API。
 * 通过「改变 key → 销毁并重建 TextInput」的方式，
 * 新创建的 TextInput 会默认选中其初始文本，实现浏览器标准的全选效果。
 */

@Component
export struct AddressBar {
  @Link text: string;
  @Prop isLoading: boolean = false;
  /** 是否显示"新标签页中打开"按钮 */
  @Prop showNewTabButton: boolean = true;
  onSubmit: (value: string) => void = () => {};
  onOpenInNewTab?: (value: string) => void;

  /** 输入框版本号，每 +1 强制重建 TextInput 实现全选 */
  @State private inputSeed: number = 0;

  private handleFocus(): void {
    if (this.text.length > 0) {
      const saved = this.text;
      this.text = '';
      setTimeout(() => {
        this.text = saved;
      }, 100);
    }
  }

  build() {
    Row() {
      // 加载中指示器
      if (this.isLoading) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color('#0A59F7')
          .margin({ right: 6 })
      }

      // URL / 关键词输入框
      // key 基于 inputSeed：聚焦时变化，强制重建组件实现全选
      TextInput({
        text: this.text,
        placeholder: '输入网址或搜索'
      })
        .layoutWeight(1)
        .height(36)
        .backgroundColor('#F2F3F5')
        .borderRadius(18)
        .padding({ left: 14, right: 10 })
        .fontSize(15)
        .maxLines(1)
        .type(InputType.URL)
        .enterKeyType(EnterKeyType.Search)
        .key('addr_input_v' + this.inputSeed.toString())
        .onFocus(() => {
          this.handleFocus();
        })
        .onChange((value: string) => {
          this.text = value;
        })
        .onSubmit(() => {
          this.onSubmit(this.text);
        })

      // 清空按钮：使用 Text 替代 Button，零额外边距
      if (this.text.length > 0) {
        Text('✕')
          .fontSize(16)
          .fontColor('#86909C')
          .textAlign(TextAlign.Center)
          .width(28)
          .height(28)
          .borderRadius(14)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.text = '';
          })

        // 新标签页中打开按钮
        if (this.showNewTabButton) {
          Text('↗')
            .fontSize(16)
            .fontColor('#0A59F7')
            .textAlign(TextAlign.Center)
            .width(28)
            .height(28)
            .borderRadius(14)
            .backgroundColor('#E8F0FE')
            .onClick(() => {
              if (this.text.length > 0 && this.onOpenInNewTab) {
                this.onOpenInNewTab(this.text);
              }
            })
        }
      } else {
        // 空状态占位：保持布局稳定
        Blank().width(this.showNewTabButton ? 56 : 28).height(1)
      }
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 6 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor('#FFFFFF')
  }
}
