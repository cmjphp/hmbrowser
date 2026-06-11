# HM Browser

HarmonyOS NEXT ArkTS + ArkUI + ArkWeb browser MVP.

## Open in DevEco Studio

1. Close DevEco Studio.
2. Open DevEco Studio and choose **File > Open**.
3. Select this project root directory:

   `/Users/chenmeijun/Documents/hmbrowser`

4. Wait for OHPM/Hvigor sync. If DevEco asks to migrate or update Hvigor model version, follow the IDE prompt.
5. If the IDE still opens a blank or unresponsive project, close DevEco and delete the generated `.idea` directory in this project, then open the root directory again.

## Important SDK Checks

This project is a minimal skeleton. The following items may need to be adjusted to match the locally installed DevEco Studio / HarmonyOS SDK:

- `oh-package.json5` and `hvigor/hvigor-config.json5` `modelVersion`
- `@ohos/hvigor` and `@ohos/hvigor-ohos-plugin` versions
- ArkWeb imports and Web component event object fields
- Preferences import and `getPreferences` overload
