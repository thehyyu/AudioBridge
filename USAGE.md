# 操作說明

這份是「設定都弄好之後，每次要錄音時該做什麼」的說明。一次性的裝置設定教學在 [SETUP.md](./SETUP.md)。

## 目前的狀態（你已經做完的部分）

- ✅ BlackHole 2ch 已安裝並重開機生效
- ✅ 多重輸出裝置已建立：**External Headphones + BlackHole 2ch**（讓你自己聽得到，同時把系統聲音送進 BlackHole）
  - 注意：這裡勾的是 `External Headphones`，不是 `MacBook Air Speakers`。如果你用的是有線耳麥，macOS 會把耳麥的喇叭/麥克風視為跟內建喇叭/麥克風**不同的裝置**，勾錯會變成「系統聲音沒送到你耳朵裡」。
- ✅ 聚集裝置已建立：**External Microphone + BlackHole 2ch**（把你的麥克風和對方的聲音合併成一路輸入）
  - 同樣道理，勾的是 `External Microphone`（耳麥的線控麥克風），不是 `MacBook Air Microphone`。
- ✅ `record.sh` 已設定好要用聚集裝置（`Aggregate Device`，索引 5）錄音
- ✅ 已安裝 `switchaudio-osx`，`record.sh` 現在會自動切換系統輸出：
  - `start` 時自動切到「Multi-Output Device」
  - `stop` 時自動切回你原本用的輸出（例如耳機）
- ✅ 錄音的聲道混音已修正：聚集裝置會給出 3 個原始聲道（BlackHole 左/右 + 麥克風單聲道），`record.sh` 用 `pan` filter 明確把三軌混成立體聲輸出，並加了 limiter 防止削頂爆音。已實測驗證系統音跟自己的聲音都能同時錄到、沒有失真。
- ✅ 螢幕錄影功能已加上並實測成功：`record.sh screen start/stop` 會把畫面（`Capture screen 0`）+ 系統音 + 麥克風一起錄成 mp4（h264_videotoolbox 硬體編碼），跟純音訊錄音共用同一套聲道混音、同一套輸出裝置自動切換邏輯，但用各自獨立的狀態檔，兩者可以想錄哪個就錄哪個。
  - 第一次用需要在**系統設定 → 隱私權與安全性 → 螢幕錄製**授權終端機 App，剛授權要重開終端機視窗才會生效（跟麥克風權限是分開兩件事）。

也就是說：**平常不用管音訊輸出切換，也不用管音量鍵會不會卡住**，這些 `record.sh` 都會自動處理。

## 日常錄音流程

開會前：

```bash
cd /Users/hubertyu/Documents/AudioBridge
./scripts/record.sh start
```

會自動：
1. 記住你現在的系統輸出（例如耳機）
2. 切到 Multi-Output Device
3. 開始把「你的麥克風 + 對方的系統聲音」錄成一個檔案

會議進行中：正常開會、正常講話，不用管這個終端機視窗。

開完會：

```bash
./scripts/record.sh stop
```

會自動：
1. 停止錄音
2. 把系統輸出切回你原本的耳機
3. 印出錄音檔案路徑

其他指令：

```bash
./scripts/record.sh status   # 看現在有沒有在錄
./scripts/record.sh list     # 列出所有音訊裝置（除錯用）
```

錄音檔會存在 `recordings/`，檔名是時間戳記，例如 `recordings/2026-09-22_14-30-05.m4a`。

## 螢幕錄影流程（推薦：改用 macOS 內建錄製，Cmd+Shift+5）

> ⚠️ `record.sh screen start`（下面舊流程）實測會讓錄音斷斷續續，原因跟裝置設定無關，是 ffmpeg 本身的問題，細節見 [SETUP.md 常見問題](./SETUP.md#常見問題)。**目前錄螢幕請改用這一段的做法**，不要再用 `screen start`。

這個做法用的是 macOS 系統內建的螢幕錄製工具（Cmd+Shift+5 叫出來的那個工具列，跟 QuickTime Player 選單裡「新增螢幕錄製」是同一個東西），優點是它讀取聚集裝置完全不會斷斷續續。

### 開始錄之前：把系統輸出切到多重輸出裝置

這樣你自己才聽得到聲音，同時聲音也會被送進 BlackHole 供錄音使用（原本 `record.sh` 是自動做這件事，現在要自己手動切）。

1. 按住鍵盤上的 **`Option`** 鍵不放
2. 用滑鼠點螢幕右上角選單列的**喇叭圖示** 🔊
3. 選單裡選 **Multi-Output Device**（多重輸出裝置）

> 如果按 Option 點喇叭圖示沒有跳出裝置清單：改到 **系統設定 → 聲音 → 輸出**，手動點選「Multi-Output Device」。

### 開始錄

1. 按 **`Cmd + Shift + 5`**，畫面下方會跳出一條工具列
2. 工具列上選 **「錄製整個畫面」**（一個方框圖示）或 **「錄製選取範圍」**（一個虛線框圖示），依你需求
3. 點工具列上的 **「選項」（Options）** 文字/按鈕，會跳出選單：
   - **麥克風**：選你的 **Aggregate Device**（聚集裝置）—— 這一步最重要，沒選對就完全收不到聲音
   - **儲存位置**：可以順手改成 `recordings/` 資料夾（Desktop、Documents 等選項下面有「其他位置...」可以自己選），跟現在習慣的存放位置一致
4. 選好「錄製整個畫面」的話，直接點畫面任一處就開始倒數並開始錄；選「錄製選取範圍」的話，先拖出要錄的範圍，再點 **「錄製」** 按鈕

### 停止錄

- 點螢幕右上角選單列出現的**停止方塊圖示** ⏹️
- 或再按一次 `Cmd + Shift + 5`，工具列上會有停止按鈕

停止後幾秒會自動彈出一個縮圖，點一下可以打開影片確認，檔案會存在你剛剛選的資料夾。

### 錄完之後：把系統輸出切回來

跟開始錄之前的步驟一樣，按住 `Option` 點喇叭圖示，切回你原本平常用的輸出（例如耳機）。**這步現在不會自動做，容易忘記**，忘記的話下次聽音樂/看影片聲音會怪怪的（因為還送到多重輸出裝置），發現不對勁回來切一下就好，不影響已經錄好的檔案。

---

## 舊流程：`record.sh screen start`（已知會斷斷續續，不建議使用）

跟純音訊錄音是分開的指令、分開的狀態，兩者互不影響：

```bash
./scripts/record.sh screen start    # 開始錄螢幕
./scripts/record.sh screen stop     # 停止，印出 mp4 檔案路徑
./scripts/record.sh screen status   # 看現在有沒有在錄螢幕
./scripts/record.sh screen list     # 列出所有視訊/螢幕擷取裝置（除錯用）
```

輸出檔在 `recordings/`，檔名例如 `recordings/2026-09-22_14-30-05_screen.mp4`。

**如果 `screen start` 之後整個卡住、log（`.run/screen_ffmpeg.log`）停在裝置設定訊息後就沒動靜、沒有出現 `Output #0 ...` / `Press [q] to stop`**：這是螢幕錄製權限沒給終端機 App 的典型症狀（不會直接報錯，而是卡住等畫面授權）。到系統設定 → 隱私權與安全性 → 螢幕錄製確認終端機 App 已勾選；剛授權的話要完全重開終端機視窗才會生效。

## 如果錄出來沒聲音

1. 先確認麥克風權限（見上面「待確認事項」）
2. 錄一小段測試，講幾句話，然後檢查音量：
   ```bash
   ffmpeg -i recordings/檔名.wav -af volumedetect -f null - 2>&1 | grep volume
   ```
   如果 `mean_volume` / `max_volume` 都是 -91 dB 左右，代表完全沒收到聲音（權限或裝置選錯）；有正常起伏的數字（例如 -20 ~ -40 dB）就是正常收到聲音。
3. 確認 `./scripts/record.sh setup` 選的是「Aggregate Device」（不是單獨的 BlackHole 或單獨的麥克風）。
4. 確認 Audio MIDI 設定裡，聚集裝置的兩個子裝置（BlackHole 2ch、你實際在用的麥克風，例如 External Microphone）都還在勾選狀態（重開機、拔插裝置後有時候會被系統重置）。

## 如果錄出來有爆音/斷斷續續

`max_volume` 如果接近或等於 0.0 dB，代表訊號削頂（clipping）失真，聽起來會像斷斷續續或雜音：

```bash
ffmpeg -i recordings/檔名.wav -af volumedetect -f null - 2>&1 | grep volume
```

`scripts/record.sh` 裡混音的增益係數（`0.5*c0+0.7*c2` 那段）已經加了 limiter 防削頂，正常不會再發生；如果之後又出現，可以把係數再調低一點。

## 如果換了耳機（有線 → 藍牙，或反過來）

多重輸出裝置和聚集裝置裡勾的是**具體的裝置名稱**，換一種耳機接法可能會讓「你現在實際在用的麥克風/喇叭」對應到不同的系統裝置名稱。如果換了耳機類型，回頭檢查：

- 音訊 MIDI 設定裡的多重輸出裝置、聚集裝置，是否還勾著正確的實體裝置
- 需要的話重新勾選並存檔即可，不用重建整個裝置
