// SnapTranslator 产品官网交互脚本
(function () {
  "use strict";

  // FAQ 手风琴：同时只展开一个
  const details = document.querySelectorAll(".faq-list details");
  details.forEach((d) => {
    d.addEventListener("toggle", function () {
      if (this.open) {
        details.forEach((other) => {
          if (other !== this) other.open = false;
        });
      }
    });
  });

  // 导航滚动高亮当前区块
  const sections = ["features", "engines", "install", "faq"];
  const links = document.querySelectorAll(".nav-links a");
  const spy = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          links.forEach((l) => {
            l.style.color = l.getAttribute("href") === "#" + entry.target.id ? "#e7ecf5" : "";
          });
        }
      });
    },
    { rootMargin: "-40% 0px -55% 0px" }
  );
  sections.forEach((id) => {
    const el = document.getElementById(id);
    if (el) spy.observe(el);
  });

  // 为 Code 块增加复制按钮
  document.querySelectorAll(".code-block").forEach((block) => {
    const btn = document.createElement("button");
    btn.textContent = "复制";
    btn.style.cssText =
      "float:right;font-size:12px;padding:4px 10px;border-radius:6px;border:1px solid #232d42;background:transparent;color:#8b96ab;cursor:pointer;";
    btn.addEventListener("click", () => {
      navigator.clipboard
        .writeText(block.querySelector("code").innerText)
        .then(() => {
          btn.textContent = "已复制";
          setTimeout(() => (btn.textContent = "复制"), 1500);
        })
        .catch(() => {});
    });
    block.style.display = "block";
    block.style.clear = "both";
    btn.style.margin = "0 0 8px 8px";
    block.insertBefore(btn, block.firstChild);
  });
})();
