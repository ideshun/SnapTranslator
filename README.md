# SnapTranslator

轻量级 macOS 截屏翻译应用：全局快捷键 → 框选区域 → 离线 OCR → 离线优先翻译 → 原文/译文对照 → 选词收藏生词本。

对标有道截屏翻译的核心体验，去掉词典、文档翻译、背单词、广告等一切冗余。零第三方依赖，纯系统框架。

## 功能

- **截屏翻译**：`⌥S` 唤起框选（每屏遮罩、尺寸提示、ESC 取消），松开自动 OCR（Apple Vision，端上离线）并翻译；首次鼠标即可框选，无需二次点击
- **重截上次区域**：`⌥⇧S` 直接按上次选区截图，适合字幕/日志等连续翻译
- **原文/译文对照**：原图 / 译文 / 并排三种视图切换；并排模式左右皆为图片形式（左原图、右译文渲染图），直观对照
- **语种切换**：支持中译英等 12 种语言双向互译；结果面板一键「交换源/目标语言」立即重译
- **屏幕置顶**：结果面板常驻最上层（可关，钉图标即时生效），失焦自动降透明度（可调），拖动、缩放、位置记忆
- **选词收藏**：选中文字右键「收藏到生词本」，工具条「收藏」「收藏整句」按钮快捷收藏；结果面板工具条新增「生词本」按钮，随时查看；生词本支持搜索、删除、CSV 导出（UTF-8 BOM）
- **一键复制** / 快速关闭
- **菜单栏驻留**：关闭窗口不退出应用（含右上角红绿灯/⌘W），菜单栏访问全部功能，可开机自启
- **程序坞图标**：默认在程序坞中显示图标，应用名和菜单显示在系统菜单栏左上角；可在设置或菜单栏中关闭「在程序坞中显示」切换为纯菜单栏驻留
- **远程桌面适配**：结果面板支持右上角关闭/最小化/全屏（macOS 红绿灯），方便 VNC 远程操作

## 翻译引擎（离线优先）

| 顺序 | 引擎 | 配置 |
|------|------|------|
| 1 | Apple 系统翻译（完全离线，macOS 15+） | 首次使用前在设置中点「下载 Apple 翻译语言包」 |
| 2 | Google 免费接口 | 零配置 |
| 3 | OpenAI 兼容（OpenAI / new-api / OpenRouter） | 设置中填 Base URL + 模型 + API Key（存 Keychain） |
| 4 | DeepL | 设置中填 API Key（Free 档以 `:fx` 结尾） |

单引擎失败/超时（15 秒）自动降级到下一个。源语言自动检测（NLLanguageRecognizer），目标语言在设置中配置（12 种）。

> **「仅离线」模式**：设置 → 引擎 → 主引擎选「仅离线（纯本地，永不联网）」，则只使用 Apple 系统翻译，**绝不联网降级**到 Google/OpenAI/DeepL，适合网络受限（无法访问 Google 等）环境。需 macOS 15+ 并已下载 Apple 语言包，否则会提示当前系统不支持离线翻译。若你希望翻译结果可回退，选「自动（离线优先）」即可，Apple 失败时再联网兜底。

## 构建与安装

要求：macOS 14+，Xcode Command Line Tools（`xcodebuild` 完整版 Xcode 亦可）。

```bash
./make-app.sh
# 产物：build/SnapTranslator.app（约 1 MB，ad hoc 签名）
cp -R build/SnapTranslator.app /Applications/
open /Applications/SnapTranslator.app
```

首次截屏会请求**屏幕录制**权限（系统设置 → 隐私与安全性 → 屏幕录制 → 勾选 SnapTranslator 后重启应用）。仅此一项权限，无辅助功能、无网络权限要求（云引擎按需联网）。

> 本机 CLT 环境下 SwiftPM 内置 `sandbox-exec` 与外层沙箱冲突，构建命令统一带 `--disable-sandbox`。

## 开发

```bash
# 构建（debug）
swift build --disable-sandbox

# 自测（31 项：快捷键/语种检测/Google 解析/生词本/CSV）
.build/debug/SnapTranslator --self-test

# 打包 .app
./make-app.sh
```

### 技术栈

Swift + SwiftUI/AppKit 混合 · Vision OCR · Translation 框架 · Carbon HotKey · CGDisplayCreateImage · JSON 生词本（Application Support）· Keychain（API Key）· SPM 单 target 模块化目录。

### 目录结构

```
Sources/SnapTranslator/
├── App/            # main / AppDelegate / SelfTest
├── Core/
│   ├── Hotkey/     # Carbon 快捷键 + 录制控件
│   ├── Capture/    # 框选遮罩 + 屏幕截图 + 坐标转换
│   ├── OCR/        # Vision OCR + 语种检测
│   ├── Translation/# 引擎协议 + Apple/OpenAI 兼容/DeepL/Google + 调度降级
│   └── WordBook/   # 生词模型 + JSON 存储 + CSV 导出
├── Features/
│   ├── ResultPanel/# NSPanel 置顶面板（对照视图、失焦透明）
│   ├── WordBook/   # 生词本窗口
│   └── Settings/   # 设置窗口（通用/快捷键/引擎）
└── Shared/         # Language / Keychain / Extensions
```

设计文档见 `../SnapTranslator-功能方案与架构设计.md`。
