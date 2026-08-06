# SFPLAB 實驗室管理系統 — 專案指引

這份檔案給 Claude Code 開場時讀。目的是讓你(另一個 Claude)不必重問就能理解這個專案的架構、慣例與已知地雷,直接接手開發。

---

## 專案是什麼

森林化學研究室的實驗室管理系統,部署為 GitHub Pages 上的**單一 HTML 檔** (`index.html`),後端用 Firebase Firestore。UI 全程使用繁體中文。

- 部署位置:`tung-beauregard.github.io/LabManagement_SFP/`
- 後端:Firebase Firestore(專案 `labmanagementapp-d5b03`),Firebase SDK 10.13.2+
- 前端:單一 HTML,inline CSS 與 JavaScript,無建置步驟
- 檔案規模:約 9000 行

系統管理:藥品清單、試材清單、樣品清單、儀器管理、值週生輪值、圖書借閱、採購與報修流程、圖譜分析工具。

---

## 最重要的工作原則

### 1. 單一檔案、無建置
整個系統就是一個 `index.html`。不要拆檔、不要引入打包工具、不要改成需要 build 的架構。單檔部署 GitHub Pages 的優勢是零建置、零快取問題、備份就是一個檔。這是刻意的架構選擇。

### 2. 權威來源永遠是 git 上的版本
**絕對不要**用瀏覽器「另存網頁」匯出的檔案當基底。另存的檔案會被瀏覽器凍結當下的動態 DOM 內容(例如把 JS 執行後填入的清單變成靜態 HTML),而且常被瀏覽器外掛(如翻譯外掛 immersive-translate)注入雜訊、把 CDN 資源路徑改成本地路徑。這在過去造成過整段「幽靈靜態內容」殘留的問題。一律以 repo 裡的 `index.html` 為準。

### 3. 改動要精準、不擅自加東西
使用者偏好嚴格照要求改,不要加未要求的功能。若某個改動有副作用或牽涉架構決策,先說明、先討論,不要直接做。有新功能構想時先提出討論,範圍確定再實作。

### 4. 每次改完要驗證
改完至少做:CSS 大括號平衡檢查、抽出所有 inline `<script>` 跑 `node --check` 語法檢查、確認沒有未定義的 CSS 變數。有 Playwright 可用時,對關鍵流程做 headless 測試(這個專案已有這個測試慣例)。

---

## UI 與文案慣例

- 全程繁體中文
- UI 文案用分號和逗號,**不要用破折號(em-dash)**
- 不要用破折號是通用偏好,回覆使用者時也一樣
- `roomLabel()` helper:只對數字型房號(602/603)加「室」,不對「經德」「林場」加(避免「經德室」「林場室」)

---

## 主題系統

- 日間模式:實驗紀錄簿風格(近直角圓角 2px、細格線、無陰影)
- 夜間模式:深墨綠底配薄荷綠重點
- 兩套主題字體、圓角、版面完全一致,切換時只有顏色變
- 切換靠 `<html data-theme="day|night">`,設定存在該裝置的 localStorage(不共用、不佔 Firestore)
- 主題在 `<head>` 最前面用一小段 script 先套用,避免夜間模式先閃白底
- 所有顏色都走 CSS 變數(`--panel`, `--ink`, `--pine`, `--line` 等),日夜兩套變數對稱定義。新增 UI 時**務必用變數,不要硬編碼顏色**,否則夜間模式會出現亮塊

---

## Firestore 資料架構

- **每個項目一份文件**,分散在各 collection(不是每個 collection 一份大文件)。原因:embedded base64 照片會讓單一文件逼近 1MB 上限
- 共用設定用 blob 文件存在 `lab-data/` 底下(如 `system-settings-data`),用 `window.storage.set(KEY, JSON.stringify(data), true)` 寫入、`watchBlob(KEY, cb)` 即時同步
- 扣庫存、值週打勾、圖書借還都用 `runTransaction`,避免並發覆蓋
- 整批覆蓋(`fsReplaceAll`)只用於匯入備份,平常新增編輯都是單筆 `fsSetItem`

### 權限模型
- 權限採 role 判斷(member / admin / super_admin),用戶端與規則層雙重把關
- Firestore 規則檔在這個 repo 之外另行維護。新增 collection 時要同步在規則檔補上對應段落,位置插在 `system-settings-data` 之後、`match /{document=**}` catch-all 之前
- 規則檔用到的 helper 命名:`isActive()`, `isAdmin()`, `isSuperAdmin()`, `createdByRequester()`, `creatorUnchanged()`
- 交付規則時給**完整檔案**可直接貼上,不是只給新增片段

> 這個 repo 是公開的,所以安全現況、已知取捨與待補強項目都不寫在這裡。要處理相關工作時直接問使用者,他手上有本機筆記。

---

## 主要模組現況

- **採購流程**:看板(6 欄含「已審核待訂購」)、比價工具(SheetJS 匯入 Excel)、支援藥品與耗材/儀器維修兩種類型
- **儀器管理**:緊湊格狀卡片、房號色碼(602/603/經德/林場)、軟體備份記錄、使用步驟頁
- **值週生**:逐項完成追蹤(記錄誰完成)、進度條、可展開明細
- **儀表板**:預設首頁,狀態藥丸與警示彙整卡
- **圖譜分析(圖譜分析頁)**:五個子標籤(LC/GC/FTIR/TGA/DSC)
- **圖譜(藝廊頁)**:存好的圖譜縮圖牆,可綁定試材/樣品,可回 FTIR 編輯
- **總管理員功能**:側邊欄頁籤排序(Firestore 同步)、儀器與存放位置的新增/編輯/刪除

---

## 圖譜分析模組細節(近期重點)

### FTIR(圖譜分析頁的 FTIR 子標籤)
- 完整功能:上傳 .asp/.spc、找峰、官能基指認、KM/ATR 轉換、疊圖比對、匯出 PNG/SVG/CSV
- 官能基對照表 `FTIR_BANDS`:英文短標(如 `C-H (CH₂ asym)`、`Aromatic C-H`)+ 中英雙語詳細。以不含氮有機物為主,含氮官能基收錄但不加權
- **峰標籤對齊**:垂直排列(rotate -90)、`text-anchor="end"` + `dominant-baseline="middle"`,x 對齊峰尖。**不要用 `dominant-baseline="central"`**,那會讓標籤系統性偏左(踩過的坑)
- 密集峰的標籤仍會與鄰峰交疊,這是垂直標籤的空間限制;若要徹底解決需做引線法(標籤拉到圖頂 + 細線接回峰尖),尚未實作
- **存圖譜**:存繪好的 SVG + 峰表(不是原始數據),因為原始數千點會逼近 1MB。單譜額外存原始數據與設定供「回圖譜分析編輯」;疊圖不存原始數據(不可回編輯)

### GC-MS(圖譜分析頁的 GC 子標籤)
- **用 iframe 完全隔離**。這個工具(TIC Bench)有大量 CSS class 與主系統撞名(drop、row、sp、card、lab、ctl…)。試過 scope 隔離(`.gcms-root` 前綴 + id 加 `gc_`),但主系統的全域規則(如 `.sp{flex:1}`)會反向洩漏到 GC 元素,造成版面錯亂、按鈕點不到。**iframe 是唯一乾淨解法**
- iframe 內容是原封不動的 GC-MS 原始碼,以 base64 存在主檔的 `GC_IFRAME_B64` 常數,執行時 `atob` 解出寫入 `srcdoc`
- 橋接:父窗用 postMessage 傳主題(日夜同步)、iframe 用 ResizeObserver 回報高度自動撐高
- 資料層目前仍是 iframe 內的 localStorage(**第二階段才接 Firestore**:KI 資料庫、烷類組合改共用,待審核接權限系統,樣品可存進圖譜藝廊)
- 功能:CSV 解析(Agilent/Shimadzu/Thermo)、ALS 基線、積分找峰、Kovats KI、萜類 KI 資料庫、成分表編輯、烷類 RT 組合、疊圖(樣品列多選)、局部放大插圖
- 修改 GC-MS 的流程:解出 base64 → 改 → 語法檢查 iframe 內 JS → 重新 base64 → 回填 `GC_IFRAME_B64`

---

## 開發模式偏好

- 務實漸進:先穩定一個模組再加下一個
- 改檔案前先確認拿到的是最新 live 版(使用者會在 session 開始時上傳,或從 git 拉)
- 複雜架構決策前先給清楚說明與誠實的風險評估
- 大功能拆階段做,每階段獨立可驗證(GC-MS 就是分「搬進來能用」與「接 Firestore」兩階段)

---

## 待辦 / 未實作(依規劃)

- **GC-MS 第二階段**:KI 資料庫、烷類組合、待審核佇列從 localStorage 遷到 Firestore
- 認證與權限的強化工作(內容不列在這裡,開工前問使用者)
- 毒性化學品自動偵測(比對台灣法規 PDF 的 CAS 號,紅色警告標籤)
- 藥品使用登記頁(選藥品→記錄用途與危害警告;管理員看完整記錄)
- 點數/獎勵系統(需先討論)
- QR code 編碼完整 deep-link URL(`?item=type:id`)供登入後跳到特定項目
- FTIR 密集峰標籤引線法(選配)
- 平面圖 + 財產清單 + 儀器 icon 拖曳定位(桌機限定,已討論,未做)

---

## 技術棧速查

- 前端:單一 HTML + inline CSS/JS,GitHub Pages
- 後端:Firebase Firestore + Storage
- 函式庫:SheetJS(Excel 匯入)、qrcodejs、SVG 手繪(圖譜工具)
- 字體:Noto Sans TC + IBM Plex Mono(Google Fonts,擋外網時退回系統字體)
- 測試:Playwright headless
- 網路限制:Google Fonts、Firebase SDK、App Check(若啟用)需外網;實驗室網路若擋外網要注意

### 開發輔助腳本(`tools/`)

不參與部署,只給開發用:

- `tools/gc-extract.ps1 -Out <檔案>`:把 `GC_IFRAME_B64` 解出成可編輯的 HTML
- `tools/gc-inject.ps1 -Source <檔案>`:改完後重新編碼寫回 `index.html`
- `tools/check-syntax.ps1`:抽出主檔與 GC iframe 的 inline script 跑 `node --check`,並檢查 CSS 大括號平衡

改完 `index.html` 至少要跑一次 `check-syntax.ps1`。

---

## 這份檔案的維護

改動架構或加重要模組後,順手更新這份 CLAUDE.md,讓它一直反映最新現況。它跟著 git 走,所以在任何一台機器開 Claude Code 都會讀到同一份。

**這個 repo 是公開的**,任何人都看得到這份檔案。不要在這裡寫安全弱點、現有取捨、憑證或內部風險評估;那類內容留在使用者的本機筆記。
