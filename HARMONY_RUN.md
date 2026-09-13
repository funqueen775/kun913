# 鸿蒙运行验证记录

2026-09-08：已修复 API 23 模拟器的渲染兼容问题，办公室成功显示，并完成触控移动、进入产品研发区放大、NPC 巡游与对话测试。

| 环境 | 实测结果 |
| --- | --- |
| HarmonyOS 7 / API 26 | Godot 启动检测无法创建 WebGL2 |
| HarmonyOS 6.1.0.115 / API 23（Pura X View2） | 已安装运行并验证游戏渲染、触控移动、区域放大、NPC 对话 |

已完成的调整：

- `build-profile.json5` 最低兼容版本为 `6.1.0(23)`，目标 SDK 保持 26。
- `Index.ets` 使用虚拟 HTTPS 地址，并通过 `onInterceptRequest` 从 HAP 内读取白名单中的游戏文件。`careertown.invalid` 无需服务器、DNS 或部署；资源均在包内。
- 该方式修复 API 23 下 Fetch 无法读取 `resource://rawfile` 的问题，并返回 WASM 所需 MIME 类型。
- 原生错误提示覆盖能力不足、资源读取失败、图形缓冲区错误和渲染进程退出。
- `render-compat.js` 修复模拟器的 uniform block 反射异常：返回的名称被内部改名且带 NUL，原名索引查询失败，所有数据块因此使用默认绑定 0。补丁仅在原查询失败且检测到这一异常时，通过单数据块探测着色器获得对应内部名称，再恢复真实索引。不会扩大缓冲区或修改游戏的绘制数据。
- 正常 WebGL 实现直接使用原查询结果；探测资源及时释放，每个上下文缓存名称映射，不在每帧绘制中做兼容查询。
- `export_presets.cfg` 的 `html/head_include` 会在后续 Web 导出中保留兼容脚本入口。保留 `rawfile/game/render-compat.js`，构建 HAP 前先导出最新 Godot 场景。

构建命令（PowerShell）：

```powershell
$env:DEVECO_SDK_HOME = 'D:\deveco\DevEco Studio\sdk'
& 'D:\deveco\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p product=default -p module=entry@default assembleHap
```

产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`。

修复前的日志见 `output/playwright/api23-startup.log`，原错误：

```text
GL_INVALID_OPERATION : glDrawElementsInstancedANGLE: uniform buffers : buffer or buffer range at index 0 not large enough
```

定位和修复日志见 `output/playwright/render-compat.log`。修复后出现 `CT_COMPAT restored uniform block CanvasData at index 0` 与 `GlobalShaderUniformData at index 1`，该次运行未再出现缓冲区绘制错误。

模拟器实测截图：`output/playwright/ct-render.png`（办公室总览）、`ct-walk.png`（触控入区放大）、`ct-talk.png`（NPC 对话）。

在 DevEco 顶部选择 `entry` 和 API 23 的 `Pura X View2`，点击 Run。不要选预览器或已知缺少 WebGL2 的 API 26 环境。

验证边界：目前验证的是本机 API 23 模拟器，并非所有鸿蒙真机；尚未做全区碰撞、长期稳定性和性能验收。竖屏留白、摇杆布局及只显示当前房间等原有布局问题不属于这次渲染修复。
