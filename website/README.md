# SnapTranslator 产品官网

静态产品介绍网站，用于部署到腾讯云 **EdgeOne Makers**。

## 文件

- `index.html` — 单文件产品官网（CSS 与 JS 已内联，自包含，零外部依赖）

## 本地预览

```bash
cd website && python3 -m http.server 8080
# 打开 http://localhost:8080
```

## 部署到 EdgeOne Makers

1. 进入腾讯云 **EdgeOne Makers** 控制台，创建 Web 应用 / 静态站点。
2. 上传 **`index.html`** 单个文件至根目录。
3. 完成配置后发布，即可通过分配的访问地址访问官网。

> 所有样式和交互脚本已内联到 `index.html` 中，只需上传这一个文件即可完美显示，无需担心外部 CSS/JS 文件丢失或路径错误导致样式不加载。
