# SnapTranslator 产品官网

静态产品介绍网站，用于部署到腾讯云 **EdgeOne Makers**。

## 文件

- `index.html` — 首页（单页产品官网）
- `styles.css` — 样式
- `app.js` — 交互脚本（FAQ 手风琴、导航高亮、代码复制）

## 本地预览

```bash
cd website && python3 -m http.server 8080
# 打开 http://localhost:8080
```

## 部署到 EdgeOne Makers

1. 进入腾讯云 **EdgeOne Makers** 控制台，创建 Web 应用 / 静态站点。
2. 上传本站点三个文件（`index.html`、`styles.css`、`app.js`）至根目录。
3. 完成配置后发布，即可通过分配的访问地址访问官网。

> 纯静态资源，无构建步骤，部署配置项按 EdgeOne Makers 默认即可。
