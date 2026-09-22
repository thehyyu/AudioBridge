# 操作說明

這份是「設定都弄好之後，每次要錄音時該做什麼」的說明。一次性的裝置設定教學在 [SETUP.md](./SETUP.md)。

## 目前的狀態（你已經做完的部分）

- ✅ BlackHole 2ch 已安裝並重開機生效
- ✅ 多重輸出裝置已建立：**External Headphones + BlackHole 2ch**（讓你自己聽得到，同時把系統聲音送進 BlackHole）
- ✅ 聚集裝置已建立：**MacBook Air Microphone + BlackHole 2ch**（把你的麥克風和對方的聲音合併成一路輸入）
- ✅ `record.sh` 已設定好要用聚集裝置（`Aggregate Device`，索引 5）錄音
- ✅ 已安裝 `switchaudio-osx`，`record.sh` 現在會自動切換系統輸出：
  - `start` 時自動切到「Multi-Output Device」
  - `stop` 時自動切回你原本用的輸出（例如耳機）

也就是說：**平常不用管音訊輸出切換，也不用管音量鍵會不會卡住**，這些 `record.sh` 都會自動處理。

## 待確認事項（尚未驗證完成）

- ⚠️ 上一次測錄的檔案是**完全靜音**（兩個聲道都是 -91 dB，等於數位零），懷疑是終端機 App 沒有麥克風權限。
  - 檢查方式：**系統設定 → 隱私權與安全性 → 麥克風**，確認你執行 `record.sh` 的那個終端機 App（Terminal / iTerm2 等）有打勾。
  - 如果沒有在清單裡，錄一次音通常會自動跳出授權請求；如果已經在清單但沒勾，手動勾選後**需要重開終端機視窗**才會生效。

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

## 如果錄出來沒聲音

1. 先確認麥克風權限（見上面「待確認事項」）
2. 錄一小段測試，講幾句話，然後檢查音量：
   ```bash
   ffmpeg -i recordings/檔名.wav -af volumedetect -f null - 2>&1 | grep volume
   ```
   如果 `mean_volume` / `max_volume` 都是 -91 dB 左右，代表完全沒收到聲音（權限或裝置選錯）；有正常起伏的數字（例如 -20 ~ -40 dB）就是正常收到聲音。
3. 確認 `./scripts/record.sh setup` 選的是「Aggregate Device」（不是單獨的 BlackHole 或單獨的麥克風）。
4. 確認 Audio MIDI 設定裡，聚集裝置的兩個子裝置（BlackHole 2ch、MacBook Air Microphone）都還在勾選狀態（重開機、拔插裝置後有時候會被系統重置）。

## 如果換了耳機（有線 → 藍牙，或反過來）

多重輸出裝置和聚集裝置裡勾的是**具體的裝置名稱**，換一種耳機接法可能會讓「你現在實際在用的麥克風/喇叭」對應到不同的系統裝置名稱。如果換了耳機類型，回頭檢查：

- 音訊 MIDI 設定裡的多重輸出裝置、聚集裝置，是否還勾著正確的實體裝置
- 需要的話重新勾選並存檔即可，不用重建整個裝置
