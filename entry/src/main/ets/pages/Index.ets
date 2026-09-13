import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';

@Entry
@Component
struct Index {
  private readonly controller: webview.WebviewController = new webview.WebviewController();
  @State private startupError: string = '';

  private localAsset(url: string): WebResourceResponse {
    // A virtual HTTPS origin lets fetch/WASM work while all bytes stay in the HAP.
    const response = new WebResourceResponse();
    const prefix: string = 'https://careertown.invalid/game/';
    const name: string = url.startsWith(prefix) ? url.substring(prefix.length).split('?')[0] : '';
    const allowed: string[] = ['index.html', 'index.js', 'render-compat.js', 'index.wasm', 'index.pck', 'index.png',
      'index.icon.png', 'index.apple-touch-icon.png', 'index.audio.worklet.js', 'index.audio.position.worklet.js'];
    if (!allowed.includes(name)) {
      response.setResponseCode(404);
      response.setReasonMessage('Not Found');
      response.setResponseMimeType('text/plain');
      response.setResponseData('Not found');
      return response;
    }
    try {
      const data: Uint8Array = this.getUIContext().getHostContext()!.resourceManager.getRawFileContentSync('game/' + name);
      const mime: string = name.endsWith('.wasm') ? 'application/wasm' :
        name.endsWith('.html') ? 'text/html' : name.endsWith('.js') ? 'application/javascript' :
        name.endsWith('.png') ? 'image/png' : 'application/octet-stream';
      response.setResponseData(data.buffer);
      response.setResponseMimeType(mime);
      response.setResponseEncoding('UTF-8');
      response.setResponseCode(200);
      response.setReasonMessage('OK');
      response.setResponseHeader([{ headerKey: 'Content-Type', headerValue: mime },
        { headerKey: 'Content-Length', headerValue: data.byteLength.toString() }]);
    } catch (error) {
      hilog.error(0x0000, 'CareerTownWeb', 'Cannot read local asset: %{public}s', name);
      response.setResponseCode(500);
      response.setReasonMessage('Asset read failed');
      response.setResponseMimeType('text/plain');
      response.setResponseData('Cannot read game asset');
    }
    return response;
  }

  private checkGraphics(): void {
    // Page loading can succeed even when Godot cannot create a WebGL2 context.
    this.controller.runJavaScript(
      "JSON.stringify(typeof Engine === 'undefined' ? ['engine-script'] : Engine.getMissingFeatures({ threads: false }))"
    ).then((result: string) => {
      if (result.includes('WebGL2')) {
        this.startupError = '当前设备的网页图形环境不支持 WebGL2，暂时无法运行办公室场景。模拟器中遇到此问题时，可先在电脑浏览器测试游戏；鸿蒙运行仍需要支持 WebGL2 的设备环境。';
      } else if (result.includes('engine-script')) {
        this.startupError = '游戏启动文件未能加载，请重新构建并安装应用。';
      } else if (result !== '[]' && result !== '"[]"') {
        this.startupError = '当前环境缺少游戏运行能力：' + result;
      }
      hilog.info(0x0000, 'CareerTownWeb', 'Graphics check: %{public}s', result);
    }).catch(() => {
      this.startupError = '无法检查游戏加载状态，请点击重新加载。';
    });
  }

  build() {
    Stack() {
      Web({ src: 'https://careertown.invalid/game/index.html', controller: this.controller })
        .width('100%')
        .height('100%')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .backgroundColor(Color.Black)
        .onInterceptRequest((event) => this.localAsset(event.request.getRequestUrl()))
        .onPageEnd(() => this.checkGraphics())
        .onConsole((event) => {
          const message: string = event.message.getMessage();
          if (message.includes('GL_INVALID_OPERATION') && message.includes('uniform buffers')) {
            if (this.startupError.length === 0) {
              this.startupError = '游戏引擎已启动，但当前环境绘制场景时出现图形缓冲区错误。支持 WebGL2 检测并不代表能正常渲染游戏；需要进一步处理图形兼容性。';
              hilog.error(0x0000, 'CareerTownWeb', '%{public}s', message);
            }
            return true;
          }
          hilog.info(0x0000, 'CareerTownWeb', '%{public}s', message);
          return false;
        })
        .onErrorReceive((event) => {
          const url: string = event.request.getRequestUrl();
          if (event.request.isMainFrame() || /\.(js|wasm|pck)(\?|$)/.test(url)) {
            this.startupError = '游戏资源加载失败：' + event.error.getErrorInfo();
          }
        })
        .onHttpErrorReceive((event) => {
          if (event.request.isMainFrame() || /\.(js|wasm|pck)(\?|$)/.test(event.request.getRequestUrl())) {
            this.startupError = '游戏资源读取失败，请重新构建并安装应用。';
          }
        })
        .onRenderExited(() => {
          this.startupError = '游戏显示进程已退出，请点击重新加载。';
        })
      if (this.startupError.length > 0) {
        Column({ space: 20 }) {
          Text('办公室暂时无法显示')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFF3CE')
          Text(this.startupError)
            .fontSize(17)
            .fontColor('#E0E0E0')
            .lineHeight(28)
          Button('重新加载')
            .onClick(() => {
              this.startupError = '';
              this.controller.refresh();
            })
        }
        .padding(28)
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#242424')
      }
    }
    .width('100%')
    .height('100%')
  }
}
