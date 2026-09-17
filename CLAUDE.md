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

### 5. 每次改完要更新版本號
只要動到 `index.html` 的內容,就把檔頭 `<meta name="app-version" content="...">` 的版本號往上加,格式 `YYYY.MM.DD.N`,同一天第二次改就是 `.2`(2026.08.05 以前用過 `YYYY.MM.DD-N` 的破折號格式,現在一律用點)。

這個值不是裝飾:頁面有更新偵測邏輯會定時抓自己的檔頭比對這個 meta,不一樣才會提示使用者更新,並用 `?v=` 重載破快取。版本號沒動的話,已經開著頁面的人不會收到提示,重整拿到的也可能還是快取裡的舊版,等於改了沒生效。

版本號要跟功能修改放在**同一個 commit**;分兩次推的話,中間載入頁面的人會拿到新程式碼配舊版本號,之後就不會再被提示更新。

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
- **第二個軸:介面風格**。`<html data-skin="botanic">` 是「標本館」風格(日間 = 植物標本館:羊皮紙底、深林綠、襯線標題;夜間 = 實驗室儀表:深墨綠底、螢光薄荷、等寬字標題),同樣存 localStorage(`ui-skin`),與日夜獨立。所有規則都以 `html[data-skin="botanic"]` 為前綴疊在經典版之上,沒有這個屬性就是原本的經典日夜版,不能動到經典版的規則。側欄 emoji 圖示在這個風格下由 CSS mask 的 SVG 線條圖示取代(以 `data-page` 選擇),按鍵浮起、主要按鈕光暈、頁面淡入、彈窗放大、側欄底塊滑動這些動態也只在這個風格下啟用,並尊重 `prefers-reduced-motion`
- 標本館風格的「開場自畫線」:頁首底線用 `.hdr::after` 的 scaleX 畫出;首頁右上角的植物線稿(日)與層析圖(夜)是 `#page-dashboard` 裡的 inline SVG(`.bot-leafmark` / `.bot-ticmark`),用 `pathLength="1"` 加 stroke-dashoffset 描線,每次進首頁重播。夜間版另有同步 LED(`#syncLed`,離線或即時同步失敗轉琥珀色)與統計數字跑動、低庫存數字閃爍(MutationObserver 監看 `.stat .n` 與 `.dash-chip .n`)
- **Ctrl+K / Cmd+K 快速搜尋**(所有風格都有,標本館風格側欄另有按鈕):`cmdkIndex()` 每次開啟時從 items / matItems / smpItems / 儀器 / libraryBooks / todoItems 現算索引,頁面與動作永遠在最前;選到項目會先 `switchPage` 再開該項目的詳細頁

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
- **原始檔跟圖綁在一起**:存入圖譜時,FTIR 與 UV-Vis 把上傳的原始檔、GC 把每個樣品的完整匯出 CSV,用 `uploadSpectrumFiles()` 存到 Storage 的 `lab-photos/spectra-files/{uid}/{specId}/…`(與照片、儀器附件同根目錄、同規則),清單記在文件的 `files` 欄位;詳細頁列出可下載,刪圖譜時一併刪檔。舊文件沒有 `files`,讀取端要容忍

### UV-Vis(圖譜分析頁的 UV-Vis 子標籤)
- 讀 Analytik Jena SPECORD 50 PLUS(WinASPECT)的 `.dat`:ASCII 標頭(NPOINTS、XUNITS、YUNITS…)後接 `XDATA=` / `YDATA=` 各 NPOINTS 個小端序 float32(另有內容相同的 OrgXData / OrgYData);也收兩欄「波長,數值」的 .csv / .txt
- 匯入時一律換算成吸光度保存(%T、%R 用 −log₁₀(v/100)),三種顯示模式(吸收度、%T、KM)都從吸光度算;KM 與 FTIR 共用 `ftirTransform(x,y,'km')`,找峰共用 `ftirDetect`(%T 模式先反相找谷)
- 同軸疊圖(不像 FTIR 會位移堆疊)、λmax 標籤水平放在峰上並高低錯開、可設顯示波長範圍;存入圖譜的 type 是 `uv`,peaks 用 `{sample,wn,val}`,藝廊詳細頁對 uv 顯示「λmax / 數值 / 樣品」欄
- 模組函式全部以 `uv` 開頭,狀態在 `uvState`,暫存光譜在 `UV_LIB`(只在本機記憶體)

### 比色計算(圖譜分析頁的「比色計算」子標籤)
- 對應實驗室的 Excel 檢量線表:Test = RAW − Blank(各濃度各自的 Blank);檢量線用各濃度 Test 平均值做最小平方回歸,圖上標 y = mx + b 與 R²,誤差棒是三重複 SD
- 樣品當量 = ((Test − b) / m) ÷ (樣品濃度/1000),單位 mg 標準品當量 / g 樣品;SE = SD/√n(原 Excel 的 `STDEV/(3*(1/2))` 是 `^` 打成 `*` 的手誤,已改正)
- 版面照原本的 Excel 做成試算表格(`table.as-sheet`):欄是濃度點 / 樣品,列是濃度、RAW1–3、Blank,底下接自動算的 Test、Mean、SD、當量列。白格直接打字(`input` 事件只重算計算列,不重畫輸入格,焦點不會跑掉),Enter / 上下鍵換列,點一格 Ctrl+V 可貼整塊 Excel 範圍(`assayPasteAt`,左側整欄都不是數字就當標籤欄略過),欄可加減
- 框選:拖曳或 Shift+點選矩形範圍、點列名選整列、點欄號選整欄(`asSel`),Delete 清空、Ctrl+C 以 `copy` 事件寫成 TSV;計算列只換 `tr.calc` 所以框選在重算後仍保留,整張重畫時才清掉
- 輸出:複製結果(跟 Excel 同樣直式排列的 TSV)、CSV(每列一個樣品)、檢量線 PNG/SVG
- **匯出 Excel**(`assayXlsxParts` / `assayExportXlsx`):用 JSZip 直接組 OOXML,不經 SheetJS(社群版不能寫圖表與樣式)。排法與原本範本相同(列 2–11 檢量線、13–29 樣品),格子放活的公式(IF/COUNT 保護空格、AVERAGE、STDEV、SLOPE/INTERCEPT/RSQ 放在資料右邊兩欄外、QT 與 SE 參照斜率截距格),`fullCalcOnLoad` 讓 Excel 開檔即重算;另附原生散佈圖(`xl/charts/chart1.xml`,線性趨勢線顯示方程式與 R²)錨在檢量線右側
- 狀態在 `assayState`,存在 localStorage(`assay-calc`),只在本機

### GC-MS(圖譜分析頁的 GC 子標籤)
- **用 iframe 完全隔離**。這個工具(TIC Bench)有大量 CSS class 與主系統撞名(drop、row、sp、card、lab、ctl…)。試過 scope 隔離(`.gcms-root` 前綴 + id 加 `gc_`),但主系統的全域規則(如 `.sp{flex:1}`)會反向洩漏到 GC 元素,造成版面錯亂、按鈕點不到。**iframe 是唯一乾淨解法**
- iframe 內容是原封不動的 GC-MS 原始碼,以 base64 存在主檔的 `GC_IFRAME_B64` 常數,執行時 `atob` 解出寫入 `srcdoc`
- 橋接:父窗用 postMessage 傳主題(日夜同步)、iframe 用 ResizeObserver 回報高度自動撐高
- **iframe 高度回報只量 `.top` + `.wrap`,不可量 `body`**。KI 候選選單這類浮層掛在 body 上會把 body 撐高,父層跟著加高 iframe,浮層又重新定位,形成無限來回跳動(踩過的坑)。另外底部固定多報 250px,因為選單是 `position:fixed`,不留空間會被 iframe 邊界切掉
- 功能:CSV 解析(Agilent/Shimadzu/Thermo)、ALS 基線、積分找峰、Kovats KI、萜類 KI 資料庫、成分表編輯、烷類 RT 組合、疊圖(樣品列多選)、局部放大插圖、峰標籤拖曳、單檔完整匯出入(自帶 TIC 與所有設定)、存入圖譜藝廊
- 修改 GC-MS 的流程:解出 base64 → 改 → 語法檢查 iframe 內 JS → 重新 base64 → 回填 `GC_IFRAME_B64`
- **匯出 Word(期刊格式)**:iframe 的「匯出 Word」只送 `{gcExportDocx, rows, svg, title}` 給主系統,主系統用 JSZip(cdnjs)直接組 OOXML(`gcExportDocx` / `gdxBuildParts`):A4、字 12pt、中文標楷體英數 Times New Roman、三線表 0.75pt、E-/Z- 斜體、Area% 前二高差距 <5 兩列紅粗否則只標最高、≥10 未標紅整列紫、右下「精油量/鮮重/萃取率」註記。重量可從樣品清單帶入
- 圖上標題框字體為 Times New Roman + 標楷體(依字元自動落字),`s.showTitle` 可整個關掉(含 PNG 與存入圖譜)
- **手動積分表**(峰表上方可收合的面板,`parseTabulate` / `manualPeaks` / `tabulateText`):格式就是 MSD ChemStation「Tabulate → Copy」的內容(Peak #、Ret Time、Type、Width、Area、Start Time、End Time,Tab 或空白分隔,標題列略過)。套用後該樣品 `s.manualOn=true`,`activePeaks()` 改回傳表內的峰,自動積分與 rtMin / minPct 篩選都不再作用(刪峰 `s.dropped` 仍有效);Area(%)、KI、圖上編號、Word / CSV 匯出、存入圖譜全部跟著走。Area 留空或填 `-` 的列,用 Start–End 兩端連成的直線基線重新積分;相鄰兩列 End / Start 相接(≤1.5 個取樣點)視為連峰,共用一條基線、交界處垂直切開。面積單位比照 ChemStation(abundance × 0.1 秒,即 abundance·min × 600,`CS_AREA`),用實際檔案對過大峰比值 594–601
- 成分名、標記、標籤位置都以峰頂 RT `toFixed(3)` 為鍵;ChemStation 的峰頂 RT 與本工具會差 0.001–0.003 min,所以切換手動 / 自動時用 `carryEdits()` 把 ±0.03 min 內最近那支的標註抄到新鍵,不要改成直接搬移(兩邊都要留)
- 「圖上顯示積分基線」(`s.showInt`)會畫出每支峰的基線與兩端切線(自動模式畫 ALS 基線),勾著的時候 PNG 與存入圖譜也會帶著線
- 已知的自動積分限制(尚未改,動了會讓既有樣品重新編號,要先跟使用者確認):ALS 基線 λ 固定 1e5,取樣密時基線會爬進拖尾峰底下;峰的邊界門檻是全圖最高峰的 0.2%,有超大主峰時小峰會被切掉或漏掉;突出度只跟相鄰谷比,峰頂有雜訊的寬峰會整支漏掉
- Agilent 的 `CHROMTAB.CSV` 檔名全都一樣,樣品名在檔頭的欄名列 / 值列(`"Path","File","Date Acquired","Sample","Misc"`),`parseCSV` 會從那裡取名

#### GC-MS 的資料層(分兩種,不要搞混)

**共用資料**走 Firestore 的 `lab-data/` blob,由主系統代讀寫:

| blob key | 內容 | 誰能改 |
|---|---|---|
| `gc-ki-database-data` | KI 資料庫 | 只有管理員 |
| `gc-ki-pending-data` | 待審提案佇列 | 誰都能提案;只有管理員能核准/退回/移除 |
| `gc-alkane-sets-data` | 烷類 RT 組合 | 誰都能新增;改與刪限建立者本人或管理員 |

**本機資料**留在 iframe 的 localStorage(`tb.samples`、`tb.params`、`tb.cur`、`tb.overlaid`、`tb.kitol`)。
樣品綁哪一組烷類(`alkSetId`)也是本機設定,不影響別人。

橋接協定:iframe 碰不到 Firestore,所以**只送出意圖**(`{gcRequest:{op,payload}}`),
主系統驗權限後套用到自己手上的最新內容再寫回,避免兩人同時編輯互相蓋掉;
寫完由 `watchBlob` 推回 `{gcShared:{...}}`。身分與 role 由主系統用 `{gcIdentity:...}` 推進去。

- **不要在 iframe 裡自己判斷權限就寫入**。iframe 端的隱藏按鈕只是 UI,真正的把關在主系統的 `gcDeny()` 與 `gcOwns()`
- 雲端還沒有這幾份 blob 時會自動建立第一版(KI 資料庫限管理員建,烷類組合誰先開誰建)
- 升級前留在各人瀏覽器的 `tb.kidb` 已凍結不再寫入,管理員可用 KI 面板的「併入本機舊清單」把它併上雲端

---

## 開發模式偏好

- 務實漸進:先穩定一個模組再加下一個
- 改檔案前先確認拿到的是最新 live 版(使用者會在 session 開始時上傳,或從 git 拉)
- 複雜架構決策前先給清楚說明與誠實的風險評估
- 大功能拆階段做,每階段獨立可驗證(GC-MS 就是分「搬進來能用」與「接 Firestore」兩階段)

---

## 待辦 / 未實作(依規劃)

- 認證與權限的強化工作(內容不列在這裡,開工前問使用者)
- 毒性化學品自動偵測(比對台灣法規 PDF 的 CAS 號,紅色警告標籤)
- 點數/獎勵系統(需先討論)
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
