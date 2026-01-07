# 🔍 ezGrep

## 📌 概要

サクラエディタ風GrepをPowerShellで実装したスクリプトです。
MagicNumber判定や文字コード判定を行い、テキストファイルを対象に並列処理で高速に検索できます。検索結果はサクラエディタ風形式で出力されます。

## 💻 動作環境

- Windows 10/11
- PowerShell 5.1以上

## 📦 インストール

GitHubからクローンするか、ZIPでダウンロードしてください。

```bat
git clone https://github.com/ichiriki-sha/ezGrep.git
```

## 📁 ファイル構成

```bat
ezGrep.ps1              : メインスクリプト
ezGrep.bat              : バッチファイルから起動する場合
lib\Core.ps1            : 制御関連
lib\FileSystem.ps1      : ファイル関連
lib\Output.ps1          : 出力関連
lib\Parallel.ps1        : 並列関連
lib\SearchProcessor.ps1 : 検索関連
lib\WorkerScript.ps1    : ワーカースクリプト
```

## 🚀 使い方

同梱の `ezGrep.bat` を使用して起動します。PowerShell を意識せずに簡単に検索できます。

## ⚠ 注意事項

- SAKURAエディタとは正規表現エンジンが異なるため、同じ正規表現を使用してもエラーまたは異なる結果になる場合があります。
- 文字コード判定も SAKURAエディタと一致するわけではありません。
- 本スクリプトは PowerShell 環境での動作を想定しており、SakuraGrep風の検索結果出力を目的としています。

---

# 🖥 バッチ経由での起動

```bat
ezGrep.bat -P <検索フォルダ> -E <検索文字列> [オプション]
```

### ▶ PowerShell 直接実行

```powershell
.\ezGrep.ps1 -Path "C:\TargetFolder" -Pattern "検索文字列" -Recurse -OutputFile "result.txt"
```

### 📖 使用例(バッチ経由)

1. **単純検索**

```bat
ezGrep.bat -P "C:\logs" -E "Exception"
```

2. **サブフォルダも検索**

```bat
ezGrep.bat -P "C:\logs" -E "Error" -R
```

3. **正規表現を使った検索**

```bat
ezGrep.bat -P "C:\logs" -E "Error\d{3}" -G
```

4. **テキストファイルのみ検索**

```bat
ezGrep.bat -P "C:\logs" -E "TODO" -T
```

5. **マジックナンバー定義を出力**

```bat
ezGrep.bat -EM "C:\output\magic_numbers.json"
```

現在のマジックナンバー定義を JSON ファイルとして出力します。このオプション使用時は他の検索オプションを同時に指定できません。

6. **カスタムマジックナンバーを使用**

```bat
ezGrep.bat -P "C:\logs" -E "Error" -IM "C:\config\custom_magic_numbers.json"
```

指定した JSON ファイルに定義したマジックナンバーを使用してバイナリファイルを判定できます。`-T` と併用可能ですが、既定のマジックナンバーより優先されます。

### 🛠 主なオプション

- `-P , -Path` : 検索フォルダ
- `-E , -Pattern` : 検索文字列または正規表現
- `-R , -Recurse` : サブフォルダーも検索
- `-W , -Word` : 単語単位で検索
- `-I , -IgnoreCase` : 大文字小文字を無視
- `-G , -UseRegex` : 正規表現を使用
- `-F , -FirstMatchOnly` : ファイル毎初回一致のみ出力
- `-M , -OutputMatchedPart` : 一致部分のみ出力
- `-ED, -ExcludeDirs` : 除外フォルダ（;区切り、ワイルドカード可）
- `-EF, -ExcludeFiles` : 除外ファイル（;区切り、ワイルドカード可）
- `-T , -TextOnly` : テキストファイルのみ検索
- `-IM, -ImportMagicNumber` : カスタムマジックナンバーJSONを使用
- `-O , -OutputFile` : 出力ファイル(未指定時は `ezGrep_yyyyMMdd_HHmmss.txt`）
- `-Q , -Quiet` : 進捗表示を抑止
- `-CP, -CodePage` : 文字コード種別（AUTO/UTF8N/UTF8BOM/UTF16LE/UTF16BE/UTF32LE/UTF32BE/SJIS/JIS/EUC）
- `-N , -Parallel` : 並列処理数（スレッド数）
- `-EM, -ExportMagicNumber` : マジックナンバー定義をJSONに出力
- `-H , -Help` : ヘルプを表示

## 📤 出力

- 指定した `-O` ファイルに検索結果を出力
- 出力ファイル未指定時は `ezGrep_yyyyMMdd_HHmmss.txt`へ出力します
- 検索件数と経過時間も最後に出力されます
- マジックナンバー使用時は該当ファイルをバイナリファイルとして判定されます

## 🧪 マジックナンバー (MagicNumber)

マジックナンバーとは、ファイル先頭の特定バイト列によりファイル種別を判定する方法です。ezGrep はオプションを指定することでマジックナンバーを用いて、テキストファイルとバイナリファイルを判別します。

### 📚 代表例

| ファイル形式 | マジックナンバー (16進) |ASCII文字|
|-------------|------------------------|----------|
| ZIP         | 50 4B 03 04            |`PK\x03\x04`|
| PNG         | 89 50 4E 47 0D 0A 1A 0A |`\x89PNG\x0D\x0A\x1A\x0A`|
| PDF         | 25 50 44 46 2D 31 2E 33 |`%PDF-1.4`|

### ❓ ワイルドカード `??` の使い方

- `??` は「任意の1バイト」を表します。
- 固定されていないバイトを許容する場合に使用します。
- 複数箇所に `??` を使うことも可能です。
- 例: PDF のマジックナンバー `25 50 44 46 2D ?? ?? ??` は `%PDF-1.4` など、バージョン番号の部分が不特定でもマッチします。

#### 例

```json
{
  "CUSTOM_FILE": {
    "Hex": "41 42 ?? 44",
    "Offset": 0
  }
}
```

- 上記では、先頭 0 バイト目から順に `41 42 ?? 44` をチェックします。
- `??` は任意の1バイトにマッチするため、`41 42 00 44` や `41 42 FF 44` も `CUSTOM_FILE` と判定されます。

### カスタムマジックナンバーの指定方法

1. 既存のマジックナンバーを JSON として出力

```bat
ezGrep.bat -EM MagicNumbers.json
```

2. 出力された `MagicNumbers.json` を編集して追加

```json
{
  "CUSTOM_TEXT": {
    "Hex": "41 42 43",
    "Offset": 0
  },
  "CUSTOM_BIN": {
    "Hex": "DE AD BE EF",
    "Offset": 0
  }
}
```

3. 編集した JSON を指定して検索

```bat
ezGrep.bat -P C:\Test -E keyword -MN MagicNumbers.json
```

> 注意: `-T` と `-MN` は同時に指定できません。

### 補足

- カスタムマジックナンバーを使うことで、特定のバイナリを検索対象外にできます。
- JSON 内のキーは任意ですが、重複しない名前を付けてください。

## 📜 ライセンス

MITライセンスを採用しています。詳細は LICENSE ファイルをご覧ください。

## 🤝 貢献方法

PRやIssueは歓迎です。バグ報告、改善案などあればIssueを立ててください。
