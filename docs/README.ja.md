<p align="center">
  <img src="../screenshots/smart-care-dark.png" alt="Sift" width="760">
</p>

<p align="center">
  <a href="../README.md">English</a> |
  <a href="README.ar.md">العربية</a> |
  <a href="README.es.md">Español</a> |
  <b>日本語</b> |
  <a href="README.pt-BR.md">Português (Brasil)</a> |
  <a href="README.zh-Hans.md">简体中文</a> |
  <a href="README.zh-Hant.md">繁體中文</a>
</p>

<h1 align="center">Sift</h1>

<p align="center">
  <b>Mac の空き容量を取り戻す。</b><br>
  無料のオープンソース Mac ケア：クリーンアップ、アプリ管理、ストレージの確認、システムチェック。サブスクリプションもテレメトリもありません。
</p>

> これは概要です。完全で最新の情報は[英語の README](../README.md) を参照してください。

## PureMac から移行する場合

Sift は Moamen Basel によるオープンソースのクリーナー PureMac のフォークとして始まり、現在は独立して開発されています。初回起動時に PureMac の設定と履歴をコピーし、元のデータには手を加えません。権限は以前の識別子に属しているため、**フルディスクアクセス**をもう一度許可してください。コマンドラインツールは `sift-cli` になりました。

## インストール

[最新リリース](https://github.com/BadryansahBangsawan/Sift/releases/latest)から `Sift-4.0.1.dmg` をダウンロードし、Sift を「アプリケーション」にドラッグします。

このリリースはまだ Apple の公証を受けていないため、初回は macOS に止められます：

1. Sift を開きます。アプリを検証できないと表示されたら **完了** をクリックします。
2. **システム設定 > プライバシーとセキュリティ** を開き、下にスクロールして Sift の横の **このまま開く** をクリックします。
3. Sift に求められたら **フルディスクアクセス** を許可します。

### ソースからビルド

```bash
brew install xcodegen
git clone https://github.com/BadryansahBangsawan/Sift.git
cd Sift
xcodegen generate
xcodebuild -project Sift.xcodeproj -scheme Sift -configuration Release \
  -derivedDataPath build build
open build/Build/Products/Release/Sift.app
```

### コマンドライン

```bash
cd cli
swift build -c release
.build/release/sift-cli
```

## できること

- **概要**：ストレージメーター、不要ファイルの内訳、効果の大きい項目、バッテリー、起動項目。
- **クリーンアップ**：システムの不要ファイル、AI ツール、開発者キャッシュ、インストーラ、大きく古いファイル、メールのファイル、ゴミ箱。フィルタ、除外設定、削除前の確認付き。
- **AI ツール**：Claude、Claude Code、ChatGPT、Cursor、Ollama などのキャッシュとログ。チャットやセッションの履歴は表示されますが既定では選択されず、ゴミ箱に移動されます。memory フォルダ、設定、認証情報には一切触れません。
- **プロジェクトの不要ファイル**：選んだプロジェクトフォルダ内の `node_modules`、`.venv`、`target`、`.build` など。Sift が生成物だと証明でき、git が無視している場合だけ表示されます。ゴミ箱に移動され、スケジュール実行には含まれません。
- **Apple Intelligence**：機能ごとにオフにし、デバイス上のモデルを削除し、あなたが承認するプロファイルで再ダウンロードを止めます。変更はすべて事前に確認でき、元に戻せます（Apple シリコン、macOS 15.1 以降）。
- **アンインストーラと残りファイル**：アプリの関連ファイルや削除済みアプリの残りを見つけ、確認してゴミ箱へ移動します。
- **容量エクスプローラ、重複ファイル、類似写真**、**保護**、**パフォーマンス**。
- **スケジュールクリーンアップ**（週ごとに曜日と時刻を指定）、13 言語、ライト/ダーク表示とアクセントカラー。

## プライバシーと安全性

テレメトリ、分析、クラッシュレポートはありません。スキャンはローカルでオフラインでも動作します。削除前にすべて確認でき、一部のクリーンアップ（カテゴリとスケジュール実行）は完全に削除するため、確認内容を読んでください。保護された場所をスキャンするには **フルディスクアクセス** が必要です。初回設定で案内します。

## クレジット

Moamen Basel と貢献者による [PureMac](https://github.com/momenbasel/PureMac) をもとにしています。Apple Intelligence ツールは Om Lahore の [RemoveMacAI](https://github.com/omlahore/RemoveMacAI) から移植したもので、RemoveMacAI は 4evy の [pared](https://github.com/4evy/pared) を基盤としています。いずれも MIT ライセンスです。[THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md) を参照してください。

## ライセンス

MIT。[LICENSE](../LICENSE) を参照してください。
