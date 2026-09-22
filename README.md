# AudioBridge

用 [BlackHole](https://github.com/ExistentialAudio/BlackHole)（免費、開源的 macOS 虛擬音效卡）把會議中雙方的聲音（系統聲音 + 麥克風）合併成一路輸入，再用 macOS 內建的螢幕錄製／音訊錄製功能錄下來。

不需要額外常駐的商業錄音軟體：BlackHole 是系統層級的虛擬音訊路由裝置，錄製本身就用 `Cmd+Shift+5` 或 QuickTime Player，不依賴任何第三方錄音程式。

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

錄音端還缺一步：要把「你的麥克風」和「BlackHole 裡對方的聲音」合併成**一個**輸入裝置，這樣錄製工具才能用一路輸入同時收到雙方的聲音。

聚集裝置就是做這件事：把麥克風和 BlackHole 2ch 綁在一起，變成一個 3 聲道的虛擬輸入裝置（BlackHole 左、BlackHole 右、麥克風單聲道）：

```
麥克風（你講話）──┐
                   ├─→ 聚集裝置（3 聲道）──→ 錄製工具讀取這個裝置當麥克風輸入
BlackHole（對方）──┘
```

### 整體流程

```
系統聲音（對方）──┐
                   ├─→ 多重輸出裝置（耳機 + BlackHole）→ 你聽得到
麥克風（你）    ──┘
                   ↓
             聚集裝置（麥克風 + BlackHole）
                   ↓
             Cmd+Shift+5 / QuickTime Player（麥克風輸入選這個裝置）
```

## 安裝與環境設定

第一次使用請照 [SETUP.md](./SETUP.md) 做完：安裝 BlackHole、建立多重輸出裝置與聚集裝置。

設定做完之後，每次要錄音的操作流程看 [USAGE.md](./USAGE.md)。

## 需求

- macOS
- [Homebrew](https://brew.sh/)
- `brew install blackhole-2ch`
