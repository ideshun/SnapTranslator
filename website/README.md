# SnapTranslator 产品官网

[SnapTranslator](../README.md) 的静态产品介绍单页，线上地址：<https://snaptranslator.ideshun.com/>。

单文件自包含：CSS 与 JavaScript 全部内联在 `index.html` 中，**零外部依赖、零构建步骤、零网络请求**（字体走系统栈、图标为内联 SVG），可直接上传到任意静态托管。

## 页面结构

| 区块 | 说明 |
|------|------|
| 导航 | 锚点导航 + 滚动高亮当前区块；中/英切换、明/暗主题切换；移动端折叠为汉堡菜单 |
| Hero | 主标题 + 双 CTA + 核心指标（快捷键 / 语种数 / 本地 OCR）；右侧为模拟真实应用面板的演示卡（页签 / 原文 / 译文 / 引擎徽标） |
| 使用流程 | 四步卡片（快捷键 → 框选 → 看译文 → 常驻），桌面端卡片间有连接线 |
| 功能 | 九宫格功能卡（截屏翻译、窗口吸附、重截区域、对照视图、多语言、置顶、生词本、隐私、轻量） |
| 翻译引擎 | GLM / Apple / Google / DeepL 四引擎与自动降级说明、离线使用建议 |
| 安装 | 三步说明 + 可一键复制的终端命令块（`make-app.sh --install`） |
| FAQ | 手风琴问答（差异、离线、权限、引擎容错、语言列表） |
| 页脚 | 站内导航、GitHub 链接、技术栈、版权 |

## 内置能力

- **双语 i18n**：中/英字典切换（`localStorage` 记忆 + 按浏览器语言自动初始化），`<html lang>` 随之更新
- **明暗主题**：跟随 `prefers-color-scheme`，可手动切换并记忆，全站 CSS 变量驱动
- **响应式**：1120px 容器，920px / 640px 两档断点，移动端汉堡菜单
- **可访问性**：键盘焦点环（`:focus-visible`）、`aria-*` 标注、`prefers-reduced-motion` 降级、锚点 `scroll-margin-top` 防导航遮挡
- **SEO**：meta description / Open Graph / Twitter Card / canonical / JSON-LD（SoftwareApplication）
- **排版细节**：标题 `text-wrap: balance`、正文 `text-wrap: pretty`（渐进增强）

## 本地预览

```bash
# 方式一：任意静态服务器
python3 -m http.server 8080 --directory website
# 打开 http://localhost:8080

# 方式二：直接用浏览器打开文件也可（无外部资源依赖）
open website/index.html
```

## 修改文案 / 新增语言

所有文案集中在 `index.html` 底部 `<script>` 的 `I18N` 对象中：

```js
const I18N = {
  zh: { "hero.title": "…", "feat.f1p": "…" },
  en: { "hero.title": "…", "feat.f1p": "…" }
};
```

- HTML 中 `data-i18n="key"` 做纯文本替换，`data-i18n-html="key"` 做 HTML 替换（可含 `<kbd>` 等标签）
- 修改文案时 **zh / en 两个字典都要同步改**，并同步更新 HTML 内联的中文默认值（无 JS 时的兜底显示）
- 新增语言：复制一份字典（如 `ja`）、在 `.lang-switch` 加按钮、在 `setLang` 的合法值中加入即可

## 修改主题色

颜色全部走 CSS 变量（`:root` 深色 / `[data-theme="light"]` 浅色两套），改 `--accent` / `--accent-2` / `--gradient` 即可换品牌色。

## 部署

### EdgeOne Makers（当前托管）

1. 进入腾讯云 **EdgeOne Makers** 控制台，创建 Web 应用 / 静态站点
2. 上传 **`index.html`** 单个文件至根目录
3. 发布后即可通过分配的地址访问

### 其他静态托管

单文件特性意味着任何静态服务都能直接托管：

- **GitHub Pages**：push 到 `gh-pages` 分支或配置 Actions 直接发布 `website/` 目录
- **Netlify / Vercel / Cloudflare Pages**：构建命令留空，输出目录指向 `website/`
- **自建 nginx**：`root` 指向 `website/` 即可，无需任何特殊配置

## 维护注意事项

改主仓库功能后，记得同步检查本页面的**事实一致性**：

- [ ] 快捷键（`⌥S` / `⌥⇧S`）与应用默认值一致
- [ ] 支持的语言数量与列表（当前 12 种，含乌克兰语）与 `Shared/Language.swift` 一致
- [ ] 引擎默认顺序与说明（默认 GLM、Apple 离线、自动降级）与 README 一致
- [ ] 安装命令与 `make-app.sh` 用法一致（当前主推 `--install`）
- [ ] JSON-LD 中的 `softwareVersion` 与 `Resources/Info.plist` 一致

已知限制：出于单文件约束，`og:image` / `twitter:image` 未提供（社交分享卡片无预览图）；如需可引入一张外链图片并在 `<head>` 中补充对应 meta。
