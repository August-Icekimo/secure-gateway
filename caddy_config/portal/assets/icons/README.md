# Portal Icons

caddy-security 認證入口使用的 SVG 圖示，取代原本的 Line Awesome 字型圖示。

## 目錄結構

```
assets/icons/
├── ui/      # 介面圖示：單色線條風格，stroke="currentColor"，由 CSS 填色
└── brand/   # 品牌圖示：自帶填色（logo 漸層、Google G 等），不靠 CSS 上色
```

## 上色機制（CSS 填 SVG 色）

`ui/` 圖示不直接以 `<img>` 嵌入，而是在 `custom.css` 中以 **CSS mask** 套用：

```css
.la-desktop { --icon: url("../icons/ui/desktop.svg"); }
/* 共用規則將 background-color: currentColor 透過 mask 裁切成圖示形狀 */
```

因此圖示顏色完全跟隨文字的 `color`（含 dark theme 切換），SVG 檔本身不需要任何色彩資訊。

## 新增圖示步驟

1. 將 SVG 放入 `ui/`（24×24 viewBox、`stroke="currentColor"`、`fill="none"`、stroke-width 2）
   或 `brand/`（自帶填色）。
2. 在 `caddy_config/Caddyfile` 的 `ui` 區塊註冊 static_asset（URI 必須以 `assets/` 開頭）：
   ```
   static_asset "assets/icons/ui/foo.svg" "image/svg+xml" "/etc/caddy/portal/assets/icons/ui/foo.svg"
   ```
3. 在 `custom.css` 的 ICON 區段加上對應的 `--icon` 規則（沿用 Line Awesome class 名稱
   `la-foo`，這樣 Caddyfile `links` 的 `icon "las la-foo"` 寫法不用改）。
4. 整個 `assets/` 目錄已透過 docker-compose 掛載進容器，新增檔案後 `docker restart secure-gateway` 即生效。

## 命名對應

檔名沿用 Line Awesome 的語意名稱（`la-sign-out-alt` → `sign-out.svg`），
對應表見 `custom.css` 的 ICON 區段。
