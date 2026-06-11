import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/BrowserPage', (error) => {
      if (error.code) {
        console.error(`Failed to load BrowserPage. code: ${error.code}, message: ${error.message}`);
      }
    });
  }
}
