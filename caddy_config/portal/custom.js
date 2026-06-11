/* Icekimo Secure Gateway — 主題切換
   點擊 logo 在深/淺色間切換，偏好存於 localStorage（key: lg-theme）。
   未手動切換前跟隨系統 prefers-color-scheme；切換機制是改變
   <html data-theme>，由 custom.css 的 color-scheme 覆寫接手。
   修改本檔後 docker restart secure-gateway 即生效。 */

(function () {
  "use strict";

  var KEY = "lg-theme";
  var root = document.documentElement;

  function getSaved() {
    try {
      return localStorage.getItem(KEY);
    } catch (e) {
      return null;
    }
  }

  function save(theme) {
    try {
      localStorage.setItem(KEY, theme);
    } catch (e) {
      /* 隱私模式下僅本頁有效 */
    }
  }

  var saved = getSaved();
  if (saved === "light" || saved === "dark") {
    root.setAttribute("data-theme", saved);
  }

  function effectiveTheme() {
    var forced = root.getAttribute("data-theme");
    if (forced === "light" || forced === "dark") {
      return forced;
    }
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }

  document.addEventListener("click", function (ev) {
    var target = ev.target;
    var logo = target.closest ? target.closest(".logo-img") : null;
    if (!logo) {
      return;
    }
    var next = effectiveTheme() === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", next);
    save(next);
  });

  Array.prototype.forEach.call(document.querySelectorAll(".logo-img"), function (el) {
    el.title = "切換深/淺色主題";
  });
})();
