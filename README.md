# AudioBridge

用 [BlackHole](https://github.com/ExistentialAudio/BlackHole)（免費、開源的 macOS 虛擬音效卡）+ 一個輕量的 `ffmpeg` 錄音腳本，把會議中雙方的聲音（系統聲音 + 麥克風）錄成一個檔案，也可以連畫面一起錄成 mp4。

不需要額外常駐的商業錄音軟體，也不是黑箱工具：BlackHole 是系統層級的虛擬音訊路由裝置，錄音邏輯就是這個 repo 裡的一個 shell script。

## 架構

```
系統聲音（對方）──┐
                   ├─→ 多重輸出裝置（耳機 + BlackHole）→ 你聽得到
麥克風（你）    ──┘
                   ↓
             聚集裝置（麥克風 + BlackHole）
                   ↓
             scripts/record.sh（讀取這個裝置錄音）
```

## 安裝與環境設定

第一次使用請照 [SETUP.md](./SETUP.md) 做完：安裝 BlackHole、建立多重輸出裝置與聚集裝置、安裝 ffmpeg。

設定做完之後，每次要錄音的操作流程看 [USAGE.md](./USAGE.md)。

## 使用方式

```bash
# 第一次使用：選擇要用哪個裝置錄音（只需做一次）
./scripts/record.sh setup

# 開始錄音（預設輸出 m4a，也可以指定 wav）
./scripts/record.sh start
./scripts/record.sh start wav

# 停止錄音
./scripts/record.sh stop

# 查看目前是否正在錄音
./scripts/record.sh status

# 列出所有可用的音訊輸入裝置
./scripts/record.sh list
```

錄音檔會存在 `recordings/`，檔名自動加上時間戳記，例如 `recordings/2026-09-22_14-30-05.m4a`。

### 螢幕錄影（畫面 + 系統音 + 麥克風）

```bash
# 第一次使用：選擇要用哪個視訊裝置錄螢幕（只需做一次）
./scripts/record.sh screen setup

# 開始/停止/查看狀態
./scripts/record.sh screen start
./scripts/record.sh screen stop
./scripts/record.sh screen status

# 列出所有可用的視訊/螢幕擷取裝置
./scripts/record.sh screen list
```

輸出是 `recordings/2026-09-22_14-30-05_screen.mp4`（h264 + aac），跟純音訊錄音共用同一套聲道混音邏輯與輸出裝置自動切換。第一次使用需要授權「螢幕錄製」權限，見 [SETUP.md](./SETUP.md)。

## 需求

- macOS
- [Homebrew](https://brew.sh/)
- `brew install blackhole-2ch ffmpeg`
- 螢幕錄影功能：需在**系統設定 → 隱私權與安全性 → 螢幕錄製**授權你執行 `record.sh` 的終端機 App
