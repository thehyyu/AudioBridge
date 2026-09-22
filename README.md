# AudioBridge

用 [BlackHole](https://github.com/ExistentialAudio/BlackHole)（免費、開源的 macOS 虛擬音效卡）+ 一個輕量的 `ffmpeg` 錄音腳本，把會議中雙方的聲音（系統聲音 + 麥克風）錄成一個檔案，也可以連畫面一起錄成 mp4。

不需要額外常駐的商業錄音軟體，也不是黑箱工具：BlackHole 是系統層級的虛擬音訊路由裝置，錄音邏輯就是這個 repo 裡的一個 shell script。

## 原理

macOS 沒有內建「錄下對方的系統聲音 + 我自己的麥克風」這個功能：系統輸出的聲音，麥克風錄不到（除非拿喇叭對著麥克風錄，音質很差，還會回授）。這個專案用兩個虛擬音訊裝置，把「你聽到什麼」和「錄音要收什麼」這兩條路徑分開解決。

### BlackHole：一條看不見的音訊管線

[BlackHole](https://github.com/ExistentialAudio/BlackHole) 是一個虛擬音效卡（Core Audio driver）。行為上就像一條軟體音源線：送進它「輸出端」的聲音，會原封不動立刻出現在它的「輸入端」，可以被其他程式讀走。它不發出聲音、也不佔用實體硬體，純粹是系統裡的一條聲音管線，用來把系統聲音「複製一份」轉給錄音用。

### 多重輸出裝置（Multi-Output Device）——讓你「聽得到」的同時也能「被錄到」

macOS 同一時間只能選一個系統音效輸出。如果直接把輸出設成 BlackHole，聲音確實能被錄到，但你自己耳機就沒聲音了。

多重輸出裝置把「你平常的輸出（耳機/喇叭）」和「BlackHole」綁成系統設定裡的單一個輸出選項，聲音會同時送到兩邊：

```
系統聲音（Zoom / Meet 對方講話）
        │
        ▼
   多重輸出裝置
   ├─→ 耳機 / 喇叭   → 你聽得到
   └─→ BlackHole     → 同一份聲音被複製一份，等著被錄音端讀走
```

### 聚集裝置（Aggregate Device）——把兩個音源合併成一路輸入

錄音端還缺一步：要把「你的麥克風」和「BlackHole 裡對方的聲音」合併成**一個**輸入裝置，這樣 ffmpeg 才能用一行指令同時讀到雙方的聲音。

聚集裝置就是做這件事：把麥克風和 BlackHole 2ch 綁在一起，變成一個 3 聲道的虛擬輸入裝置（BlackHole 左、BlackHole 右、麥克風單聲道）：

```
麥克風（你講話）──┐
                   ├─→ 聚集裝置（3 聲道）──→ scripts/record.sh 讀取這個裝置
BlackHole（對方）──┘
```

`record.sh` 用 ffmpeg 的 `pan` filter 把這 3 個聲道明確混成立體聲（麥克風混進左右聲道，並加 limiter 防止削頂爆音），輸出成一個檔案，錄出來的就是完整的雙向對話。螢幕錄影（`screen start`）也是讀同一個聚集裝置，只是額外多接一路螢幕擷取畫面。

> 聚集裝置裡會有一個子裝置被指定為「時脈來源」（Clock Source），其他子裝置要靠系統做「飄移校正」（Drift Correction）去對齊時脈，沒設好的話錄音可能會斷斷續續。設定細節見 [SETUP.md](./SETUP.md)。

### 整體流程

```
系統聲音（對方）──┐
                   ├─→ 多重輸出裝置（耳機 + BlackHole）→ 你聽得到
麥克風（你）    ──┘
                   ↓
             聚集裝置（麥克風 + BlackHole）
                   ↓
             scripts/record.sh（讀取這個裝置錄音，可選是否連螢幕一起錄）
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
