<p align="center">
  <img src="../screenshots/smart-care-dark.png" alt="Sift" width="760">
</p>

<p align="center">
  <a href="../README.md">English</a> |
  <a href="README.ar.md">العربية</a> |
  <a href="README.es.md">Español</a> |
  <a href="README.ja.md">日本語</a> |
  <a href="README.pt-BR.md">Português (Brasil)</a> |
  <a href="README.zh-Hans.md">简体中文</a> |
  <b>繁體中文</b>
</p>

<h1 align="center">Sift</h1>

<p align="center">
  <b>讓你的 Mac 重獲空間。</b><br>
  免費、開源的 Mac 維護工具：清理、App 管理、儲存空間瀏覽和系統檢查。沒有訂閱，沒有遙測。
</p>

> 這是摘要。完整且最新的說明請參閱[英文 README](../README.md)。

## 從 PureMac 移轉

Sift 最初是 Moamen Basel 的開源清理工具 PureMac 的分支，現已獨立開發。首次啟動時會複製你的 PureMac 設定和歷史紀錄，舊資料保持不變。由於權限屬於舊的識別碼，請重新授予**完整磁碟取用權**。命令列工具現在叫 `sift-cli`。

## 安裝

從[最新版本](https://github.com/BadryansahBangsawan/Sift/releases/latest)下載 `Sift-4.0.2.dmg`，將 Sift 拖到「應用程式」。

此版本尚未經過 Apple 公證，因此第一次打開時 macOS 會阻擋它：

1. 打開 Sift。macOS 顯示無法驗證此 App 時，按一下**完成**。
2. 打開**系統設定 > 隱私權與安全性**，向下捲動，按一下 Sift 旁的**強制打開**。
3. 在 Sift 要求時授予**完整磁碟取用權**。

### 從原始碼建置

```bash
brew install xcodegen
git clone https://github.com/BadryansahBangsawan/Sift.git
cd Sift
xcodegen generate
xcodebuild -project Sift.xcodeproj -scheme Sift -configuration Release \
  -derivedDataPath build build
open build/Build/Products/Release/Sift.app
```

### 命令列

```bash
cd cli
swift build -c release
.build/release/sift-cli
```

## 功能

- **概覽**：儲存空間條、垃圾分布、最大的可清理項目、電池和開機項目。
- **清理**：系統垃圾、AI 工具、開發者快取、安裝檔、大型和舊檔案、郵件檔案和垃圾桶，皆支援篩選、排除和刪除前確認。
- **AI 工具**：Claude、Claude Code、ChatGPT、Cursor、Ollama 等的快取和記錄。聊天和工作階段歷史會列出但絕不預先選取，並移到垃圾桶；memory 檔案夾、設定和憑證永遠不會被觸碰。
- **專案垃圾**：你所選專案檔案夾中的 `node_modules`、`.venv`、`target`、`.build` 等檔案夾，僅在 Sift 能證明它們是產生的且被 git 忽略時才列出。它們會移到垃圾桶，且絕不參與排程清理。
- **Apple Intelligence**：依功能關閉，刪除裝置上的模型，並以你核准的描述檔阻止重新下載。所有變更都會先供你檢查，並可復原（Apple 晶片，macOS 15.1 或以上版本）。
- **解除安裝器和殘留檔案**：找到 App 的相關檔案及已刪除 App 的殘留，檢查後移到垃圾桶。
- **空間瀏覽器、重複檔案和相似照片**，以及**保護**和**效能**。
- **排程清理**（每週可選星期和時間）、13 種語言、淺色/深色外觀和強調色。

## 隱私權與安全

沒有遙測、分析或當機報告。掃描在本機進行，可離線使用。刪除前一切都會供你檢查；部分清理（類別清理）是永久刪除，請閱讀確認訊息。Sift 需要**完整磁碟取用權**才能掃描受保護的位置，首次設定會引導你完成。

## 致謝

以 Moamen Basel 及其貢獻者的 [PureMac](https://github.com/momenbasel/PureMac) 為基礎。Apple Intelligence 工具移植自 Om Lahore 的 [RemoveMacAI](https://github.com/omlahore/RemoveMacAI)，它以 4evy 的 [pared](https://github.com/4evy/pared) 為基礎。皆採用 MIT 授權，詳見 [THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md)。

## 授權

MIT。詳見 [LICENSE](../LICENSE)。
