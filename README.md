# SnapTranslator

轻量级 macOS 截屏翻译应用：全局快捷键 → ScreenCaptureKit 瞬间定格框选 → 离线 Vision OCR 与智能段落排版 → 多引擎流式翻译 → 原文/译文/1:1 覆盖对照 → 生词本与桌面悬浮贴图。

零第三方依赖，纯原生 macOS 框架（SwiftUI / AppKit / ScreenCaptureKit / Vision / Translation / CryptoKit）。

## 核心功能

- **截屏翻译（`⌥S`）**：基于 `ScreenCaptureKit` 瞬间定格，原生排除自身翻译面板不入镜；支持 QQ 式窗口吸附、拖拽框选、顶部快捷模式切换（**翻译 / 仅提文字 / 贴图置顶 / 保存截图**）与可选**选区精调工具栏**（拖拽边角与方向键微调）
- **重截上次区域（`⌥⇧S`）**：一键按上次选区重新截图翻译，适合字幕、终端与日志连续查看
- **静默截屏 OCR（`⌥⇧O`）**：框选后离线识别并直接写入剪贴板 + 轻量 HUD 提示，不弹窗打扰
- **翻译剪贴板（`⌥⇧V`）& 系统右键服务**：支持一键翻译剪贴板中的文本或截图；在任意应用右键选中文本可通过「服务 → 使用 SnapTranslator 翻译」直达（零辅助功能权限）
- **拖放 & 粘贴图片翻译**：直接拖入 PNG/JPG/WebP 或在面板中 `⌘V` 粘贴截图即可 OCR 并翻译
- **四视图对照 & 1:1 覆盖图导出**：
  - `⌘1` **识别**：支持「OCR 智能段落合并 / 保留原始换行」一键切换（自动修复 PDF/网页断行与英文连字符）
  - `⌘2` **翻译**：左侧可编辑实时防抖翻译，右侧支持 **SSE 流式输出** 与 **双引擎并排对比**
  - `⌘3` **对照**：原图 + 译文分栏对照，严格遵循「自适应宽度 / 原图」显示设置
  - `⌘4` **对比（1:1）**：纯 CoreGraphics 后台异步渲染译文覆盖图（多点中位数采样、Retina 精准对齐、AI 编号块对齐），支持**复制译文图 / 保存 PNG / 钉在桌面悬浮贴图**
- **桌面悬浮贴图**：把原图或 1:1 译文图钉在桌面任意位置（拖拽移动、滚轮缩放、`⌥+滚轮` 调透明度、右键复制/保存、ESC 关闭）
- **AI 划词速释**：选中词句右键「AI 速释」即时获得词性、音标与语境释义
- **持久化识别历史（`⌘H`）**：落盘保存原文、译文、压缩缩略图与 OCR 行坐标，支持搜索、星标保留、回看恢复 1:1 译文图
- **生词本增强**：收藏自动保存译文，支持备注、标签、语种筛选，以及 **CSV（UTF-8 BOM）/ JSON 备份导入 / Anki TSV** 多格式导出

## 翻译引擎与隐私

- **纯离线隐私模式**：设置或菜单栏一键开启，严格仅使用端上 Apple Vision OCR 与 Apple 本地翻译，绝不发起任何云端请求或自动降级
- **AI 多配置预设（OpenAI 兼容，支持 SSE 流式）**：内置智谱 GLM-5.2、DeepSeek、OpenAI、OpenRouter、本地 Ollama 模板及自定义端点管理，支持**「测试连接」**与翻译风格切换（通用 / 技术文档 / 学术论文 / 简洁润色）
- **DeepL API v2**：官方 Header 鉴权（`DeepL-Auth-Key`），区分 `ZH-HANS` / `ZH-HANT`
- **Google 免费接口** & **Apple 系统翻译（macOS 15+ 离线）**：自动降级、细粒度语向级熔断器与内存 LRU 缓存（256 条）

## 构建与测试

要求：macOS 14+，完整版 Xcode（macOS 27 SDK 起 SwiftUI 宏插件随完整版 Xcode 分发）。

```bash
# 调试构建
swift build --disable-sandbox

# 运行 XCTest 单元测试套件（17 项覆盖语向策略、OCR 排版、1:1 渲染、取消/离线/熔断/缓存、持久化与无限历史保留）
swift test --disable-sandbox

# 运行 CLI 内建自测（33 项）
.build/debug/SnapTranslator --self-test

# 界面离屏渲染诊断
.build/debug/SnapTranslator --ui-diag

# 打包发布版 .app（build/SnapTranslator.app）
./make-app.sh
# 打包并安装到 /Applications 并启动
./make-app.sh --install
```

## 目录架构

```
Sources/
├── SnapTranslatorCore/         # 纯业务逻辑库 Target（可独立单元测试）
│   ├── Domain/                 # Language / LanguagePolicy / AIProfile / TranslationStyle / OCRModels / AppLogger
│   ├── Capture/                # ScreenCapture (ScreenCaptureKit) / WindowSnapLocator
│   ├── Hotkey/                 # HotkeySpec / HotkeyManager
│   ├── OCR/                    # VisionOCRService / OCRLayoutAnalyzer / LanguageDetector
│   ├── Translation/            # TranslationService / NetworkSessionPool / EngineBreaker / TranslationCache / Providers
│   ├── Rendering/              # ImageTranslationRenderer (纯 CoreGraphics 后台渲染)
│   ├── Persistence/            # SettingsStore / HistoryStore / WordBookStore / WordBookExporter
│   └── Shared/                 # KeychainStore / Extensions
└── SnapTranslator/             # 轻量 AppKit + SwiftUI 壳层 Executable Target
    ├── App/                    # main / AppDelegate / MenuBarController / TranslationPipeline / HUDNotifier / SelfTest / TranslateDiag
    ├── Features/
    │   ├── CaptureOverlay/     # 多屏遮罩 / 窗口吸附 / 精调手柄与快捷动作条
    │   ├── ResultPanel/        # 拆分后的 Toolbar / StatusBar / 4 页签 / 文本与图片交互 / SpeechManager
    │   ├── History/            # 可搜索持久化历史窗口
    │   ├── WordBook/           # 增强生词本窗口
    │   ├── PinWindow/          # 桌面悬浮贴图窗口
    │   └── Settings/           # 设置窗口（通用 / 快捷键 / 多引擎预设 / 隐私与数据）
    └── Shared/                 # DesignSystem / HoverFeedback
Tests/
└── SnapTranslatorTests/        # XCTest 单元测试套件
```
