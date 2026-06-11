# HarmonyOS NEXT 浏览器 MVP 实施说明

## 一、可行性判断

HarmonyOS NEXT 可以开发自己的轻量浏览器 App。第一阶段建议基于 ArkTS、ArkUI 和 ArkWeb Web 组件实现“应用内网页浏览器”，而不是自研浏览器内核。

ArkWeb / Web 组件适合做网页渲染、页面导航、标题/进度/错误回调、基础 JS 与 DOM Storage 支持，以及应用内网页容器能力。它不是 Android WebView：运行环境、API、权限、工程模型和系统集成均属于 HarmonyOS NEXT / ArkUI 体系。它也不同于自己移植 Chromium：ArkWeb 是系统提供的 Web 能力，开发成本和维护成本低；移植 Chromium 会涉及内核裁剪、多进程、安全沙箱、渲染管线、网络栈和长期维护，第一阶段不现实。

第一阶段最现实的边界是：单 Web 容器、地址栏、搜索、导航控制、加载状态、简单书签、简单历史、设置存储和无痕模式预留。不要第一阶段就做完整 Chromium 内核、多进程内核、复杂扩展系统、完整广告拦截、完整下载管理器、密码管理器、云同步等。

## 二、第一阶段技术路线

- 语言：ArkTS
- UI：ArkUI
- Web 渲染：ArkWeb / Web 组件
- 工程模型：Stage 模型
- 本地存储：Preferences，后续可升级关系型数据库
- 书签：Preferences 保存 JSON 数组
- 历史记录：Preferences 保存 JSON 数组
- 设置：Preferences 保存首页、搜索引擎、无痕模式开关、深色模式开关
- 下载：第一阶段只做设计预留，后续再实现 request.download 或系统下载能力
- 多标签页：第一阶段不做复杂多标签，只预留 BrowserTab 数据结构

## 三、推荐目录结构

```text
entry/src/main/ets/
├── entryability/
│   └── EntryAbility.ets
├── pages/
│   ├── BrowserPage.ets
│   ├── BookmarkPage.ets
│   ├── HistoryPage.ets
│   └── SettingPage.ets
├── components/
│   ├── AddressBar.ets
│   ├── BrowserToolbar.ets
│   └── QuickLinks.ets
├── model/
│   ├── Bookmark.ts
│   ├── HistoryItem.ts
│   ├── BrowserTab.ts
│   └── BrowserSetting.ts
├── service/
│   ├── BookmarkService.ts
│   ├── HistoryService.ts
│   ├── BrowserSettingService.ts
│   ├── DownloadService.ts
│   └── PreferenceStore.ts
└── utils/
    └── UrlUtils.ts
```

文件作用：BrowserPage 是浏览器主页面；BookmarkPage、HistoryPage、SettingPage 是后续页面预留；AddressBar 负责输入网址/关键词；BrowserToolbar 负责返回、前进、首页、刷新/停止、书签、菜单；QuickLinks 展示首页快捷入口；model 定义书签、历史、标签页和设置；service 封装 Preferences 与业务读写；UrlUtils 负责 URL 判断、补全和搜索 URL 生成。

## 四、module.json5 权限片段

```json5
{
  "module": {
    "requestPermissions": [
      {
        "name": "ohos.permission.INTERNET"
      }
    ]
  }
}
```

网络访问权限通常需要 `ohos.permission.INTERNET`，需要根据当前 DevEco Studio / HarmonyOS SDK 校验。第一阶段不需要下载、媒体、文档目录访问权限。后续做下载管理、选择保存路径、媒体保存时，再按当前 SDK 校验 request.download、Picker、文件读写和媒体库相关权限。

## 五、下载功能设计

ArkWeb 是否提供下载拦截事件、事件名和事件对象字段，需要根据当前 SDK 校验。后续可以从 URL、Content-Type、Content-Disposition、文件扩展名或 ArkWeb 下载回调识别下载链接；确认下载后创建下载任务，接入 request.download 或系统下载能力；保存路径通过系统 Picker 或应用沙箱目录决定；下载任务列表用关系型数据库或 Preferences 记录任务状态、进度、文件名、保存路径和失败原因。第一阶段不强行写不确定 API。

## 六、无痕模式设计

第一阶段无痕模式只做“不记录历史 + UI 标识 + 临时状态”。开启后不写入历史记录，尽量不保存搜索输入，关闭页面后清理临时状态。书签是否允许保存可以作为产品策略，当前 MVP 仍允许用户主动加入书签。Cookie / Cache 控制、会话隔离、临时 Profile 需要依赖 ArkWeb 能力，API 名称和可控范围需要根据当前 SDK 校验。

## 七、后续扩展路线

可逐步扩展：多标签页、下载管理器、书签页面、历史记录页面、设置页面、自定义搜索引擎、UA 切换、深色网页模式、JS 注入、广告拦截、代理设置、阅读模式、书签导入导出、WebDAV 或云同步、密码管理器设计、页面截图、长按菜单、分享链接、桌面模式、开发者调试入口。

## 八、SDK 校验点

已参考华为开发者文档中 ArkWeb Web 组件、WebviewController、Preferences 的公开说明。当前代码中以下位置需要在 DevEco Studio 当前 SDK 下校验：`@kit.ArkWeb` / `@kit.ArkData` 导入名，`WebviewController.loadUrl/backward/forward/refresh/stop/accessBackward/accessForward` 签名，`onPageBegin/onPageEnd/onProgressChange/onTitleReceive/onErrorReceive` 事件对象字段，Preferences 的 `getPreferences/get/put/flush` 签名。
