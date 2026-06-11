# Portal Assets

認證入口的靜態資源。整個目錄以唯讀 bind mount 進容器 `/etc/caddy/portal/assets`。

```
assets/
├── background.svg   # 頁面背景圖（可替換）
└── icons/           # SVG 圖示，見 icons/README.md
```

> 注意：caddy-security 在**啟動時**把 static_asset 讀進記憶體，
> 所以替換任何 asset 檔案後需要 `docker restart secure-gateway` 才生效
> （目錄掛載沒有 inode 陷阱，restart 即可，不用 rebuild）。

## 更換背景圖

背景由 `custom.css` 的 `--lg-bg-image` 指向 `assets/background.svg`，
以 `cover` 鋪滿、固定不捲動，墊在主題底色 `--lg-bg-base` 之上。

**設計原則**：背景圖建議使用半透明元素（如目前的漸層色塊），
讓亮/暗主題的底色透出來，同一張圖兩種主題都成立。
不透明的照片類背景也可以，但深淺主題會看起來一樣。

### 方式一：直接覆蓋（最簡單）

把新的 SVG 存成 `assets/background.svg` 蓋掉原檔，restart 即可。
Caddyfile 與 CSS 都不用動。

### 方式二：改用 PNG / JPG

1. 把圖放進 `assets/`（例如 `background.png`）
2. Caddyfile `ui` 區塊註冊：
   ```
   static_asset "assets/background.png" "image/png" "/etc/caddy/portal/assets/background.png"
   ```
3. `custom.css` 改一行：
   ```css
   --lg-bg-image: url("../background.png");
   ```

### 小技巧：PNG 包進 SVG

不想動 Caddyfile/CSS 的話，可以把 PNG 以 base64 內嵌進 SVG，仍存成 `background.svg`：

```svg
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
     viewBox="0 0 1600 1000" preserveAspectRatio="xMidYMid slice">
  <image width="1600" height="1000" xlink:href="data:image/png;base64,...."/>
</svg>
```

## 主題切換

點擊 portal 的 logo 可在深/淺色主題間切換（`custom.js` 實作，
偏好存在瀏覽器 localStorage，key `lg-theme`）；未切換過則跟隨系統設定。
