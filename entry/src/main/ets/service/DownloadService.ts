/**
 * DownloadService.ts — 下载能力设计预留
 *
 * 第一阶段不做实际实现，仅提供数据结构与接口说明。
 *
 * ============================================================
 * 后续实现指南（需要按当前 SDK 校验所有 API）：
 * ============================================================
 *
 * 1. ArkWeb 下载拦截：
 *    - Web 组件提供 onDownloadStart / onDownload 事件（需校验事件名）
 *    - 拦截后可获取下载 URL、文件名、MIME 类型等
 *
 * 2. 识别下载链接：
 *    - 在 onLoadIntercept / onDownloadStart 中检查 URL
 *    - 匹配常见文件扩展名：.apk .zip .pdf .doc .mp4 等
 *    - 检查 Content-Type 响应头
 *
 * 3. 接入 request.download：
 *    - import { request } from '@kit.BasicServicesKit';
 *    - 使用 request.downloadFile() 执行下载
 *    - 需要权限：ohos.permission.WRITE_USER_STORAGE（需校验）
 *
 * 4. 保存路径选择：
 *    - 使用 Picker / FilePicker 让用户选择保存目录
 *    - 或默认保存到应用沙箱 /download 目录
 *
 * 5. 下载任务列表：
 *    - 使用 @State 维护下载任务数组
 *    - 监听下载进度、状态变更
 *    - 支持暂停、恢复、取消
 *
 * 6. 第一阶段暂不做的：
 *    - 完整下载管理器 UI
 *    - 断点续传
 *    - 多任务并发控制
 *    - 下载通知栏进度
 *    - MD5/SHA 校验
 * ============================================================
 */

export interface DownloadTaskDraft {
  url: string;
  fileName?: string;
  mimeType?: string;
}

export class DownloadService {
  /** 创建下载任务草稿（仅供预留） */
  static createTaskDraft(
    url: string,
    fileName?: string,
    mimeType?: string
  ): DownloadTaskDraft {
    return { url, fileName, mimeType };
  }

  // TODO: 后续实现
  // static async startDownload(task: DownloadTaskDraft): Promise<void> {}
  // static async pauseDownload(taskId: string): Promise<void> {}
  // static async resumeDownload(taskId: string): Promise<void> {}
  // static async cancelDownload(taskId: string): Promise<void> {}
}
