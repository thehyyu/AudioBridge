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

## 螢幕錄影流程（畫面 + 系統音 + 麥克風）

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
