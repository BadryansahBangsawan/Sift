<p align="center">
  <img src="../screenshots/smart-care-dark.png" alt="Sift" width="760">
</p>

<p align="center">
  <a href="../README.md">English</a> |
  <a href="README.ar.md">العربية</a> |
  <a href="README.es.md">Español</a> |
  <a href="README.ja.md">日本語</a> |
  <a href="README.pt-BR.md">Português (Brasil)</a> |
  <b>简体中文</b> |
  <a href="README.zh-Hant.md">繁體中文</a>
</p>

<h1 align="center">Sift</h1>

<p align="center">
  <b>让你的 Mac 重获空间。</b><br>
  免费、开源的 Mac 维护工具：清理、应用管理、存储空间浏览和系统检查。无订阅，无遥测。
</p>

> 这是摘要。完整且最新的说明请参阅[英文 README](../README.md)。

## 从 PureMac 迁移

Sift 最初是 Moamen Basel 的开源清理工具 PureMac 的分支，现已独立开发。首次启动时会复制你的 PureMac 设置和历史记录，旧数据保持不变。由于权限属于旧的标识符，请重新授予**完全磁盘访问权限**。命令行工具现在叫 `sift-cli`。

## 安装

从[最新版本](https://github.com/BadryansahBangsawan/Sift/releases/latest)下载 `Sift-4.0.2.dmg`，将 Sift 拖到“应用程序”。

此版本尚未经过 Apple 公证，因此第一次打开时 macOS 会阻止它：

1. 打开 Sift。macOS 提示无法验证该应用时，点击**完成**。
2. 打开**系统设置 > 隐私与安全性**，向下滚动，点击 Sift 旁边的**仍要打开**。
3. 在 Sift 请求时授予**完全磁盘访问权限**。

### 从源代码构建

```bash
brew install xcodegen
git clone https://github.com/BadryansahBangsawan/Sift.git
cd Sift
xcodegen generate
xcodebuild -project Sift.xcodeproj -scheme Sift -configuration Release \
  -derivedDataPath build build
open build/Build/Products/Release/Sift.app
```

### 命令行

```bash
cd cli
swift build -c release
.build/release/sift-cli
```

## 功能

- **概览**：存储空间条、垃圾分布、最大的可清理项、电池和启动项。
- **清理**：系统垃圾、AI 工具、开发者缓存、安装包、大型和旧文件、邮件文件和废纸篓，均支持筛选、排除和删除前确认。
- **AI 工具**：Claude、Claude Code、ChatGPT、Cursor、Ollama 等的缓存和日志。聊天和会话历史会列出但从不预先选中，并移到废纸篓；memory 文件夹、设置和凭据永远不会被触碰。
- **项目垃圾**：你所选项目文件夹中的 `node_modules`、`.venv`、`target`、`.build` 等文件夹，仅当 Sift 能证明它们是生成的且被 git 忽略时才列出。它们会移到废纸篓，且从不参与定时清理。
- **Apple Intelligence**：按功能关闭，删除设备上的模型，并通过你批准的描述文件阻止重新下载。所有更改都会先供你检查，并可撤销（Apple 芯片，macOS 15.1 或更高版本）。
- **卸载器和残留文件**：找到应用的相关文件及已删除应用的残留，检查后移到废纸篓。
- **空间浏览器、重复文件和相似照片**，以及**保护**和**性能**。
- **定时清理**（每周可选星期和时间）、13 种语言、浅色/深色外观和强调色。

## 隐私与安全

没有遥测、分析或崩溃报告。扫描在本地进行，可离线使用。删除前一切都会供你检查；部分清理（类别清理）是永久删除，请阅读确认信息。Sift 需要**完全磁盘访问权限**才能扫描受保护的位置，首次设置会引导你完成。

## 致谢

基于 Moamen Basel 及其贡献者的 [PureMac](https://github.com/momenbasel/PureMac)。Apple Intelligence 工具移植自 Om Lahore 的 [RemoveMacAI](https://github.com/omlahore/RemoveMacAI)，它基于 4evy 的 [pared](https://github.com/4evy/pared)。均采用 MIT 许可证，详见 [THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md)。

## 许可证

MIT。详见 [LICENSE](../LICENSE)。
