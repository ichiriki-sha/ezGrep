<#
.SYNOPSIS
    サクラエディタ風 Grep を実装した PowerShell スクリプト

.DESCRIPTION
    本スクリプトは、サクラエディタの Grep 機能に近い挙動を
    PowerShell 5.1 で再現することを目的としています。

    以下の特徴を持ちます。
    - Magic Number によるバイナリ／テキスト判定
    - 文字コード自動判定
      (ASCII / UTF-8 / UTF-16 / UTF-32 / Shift-JIS / JIS / EUC-JP / Binary)
    - テキストファイルのみを検索対象とする安全設計
    - RunspacePool を用いた並列 Grep 処理
    - サクラエディタ互換の検索結果フォーマット出力

    大規模なソースコード検索やログ解析を高速に行うことを目的としています。

.PARAMETER Path
    検索対象のフォルダまたはファイルパスを指定します。
    フォルダを指定した場合は、配下のファイルを検索対象とします。

.PARAMETER Pattern
    検索する文字列または正規表現パターンを指定します。
    -UseRegex を指定した場合は正規表現として扱われます。

.PARAMETER SearchTarget
    検索対象とするファイル名を指定します。
    ワイルドカードが使用可能です。
    省略時は "*"（すべてのファイル）が指定されます。

.PARAMETER Recurse
    サブフォルダを再帰的に検索します。

.PARAMETER Word
    検索文字列を単語単位で検索します。

.PARAMETER IgnoreCase
    大文字・小文字を区別せずに検索します。

.PARAMETER UseRegex
    検索パターンを正規表現として扱います。

.PARAMETER FirstMatchOnly
    各ファイルにつき、最初に一致した行のみを出力します。

.PARAMETER OutputMatchedPart
    一致した部分のみを出力します。

.PARAMETER ExcludeDirs
    検索から除外するフォルダを指定します。
    ワイルドカードが使用可能で、複数指定する場合は「;」で区切ります。

.PARAMETER ExcludeFiles
    検索から除外するファイルを指定します。
    ワイルドカードが使用可能で、複数指定する場合は「;」で区切ります。

.PARAMETER TextOnly
    テキストファイルのみを検索対象とします。
    内蔵のマジックナンバー定義を使用して判定します。

.PARAMETER ImportMagicNumber
    テキストファイル判定に使用する
    カスタムマジックナンバー定義（JSON ファイル）を指定します。
    -TextOnly と同時に指定することはできません。

.PARAMETER Quiet
    進捗表示や補助メッセージの出力を抑止します。

.PARAMETER OutputFile
    検索結果の出力先ファイルを指定します。
    省略時は「<スクリプト名>_yyyyMMdd-HHmmss.txt」が自動生成されます。

.PARAMETER CodePage
    検索対象ファイルの文字コードを指定します。
    指定可能な値:
      UTF8N, UTF8BOM, UTF16LE, UTF16BE,
      UTF32LE, UTF32BE, SJIS, JIS, EUC, AUTO
    省略時は AUTO（自動判定）となります。

.PARAMETER Parallel
    並列処理数（スレッド数）を指定します。
    省略時は CPU の論理コア数が使用されます。

.PARAMETER ExportMagicNumber
    マジックナンバー定義を JSON ファイルとして出力します。
    このオプション指定時は、他の検索関連パラメータは指定できません。

.PARAMETER Help
    使用方法（ヘルプ）を表示します。

.EXAMPLE
    PS> .\gzGrep.ps1 -Path src -Pattern "TODO" -Recurse

.NOTES
    Author      : ichiriki-sha
    Repository  : https://github.com/ichiriki-sha/gzGrep
    License     : MIT License
    PowerShell  : 5.1
    Encoding    : Shift_JIS

.LINK
    サクラエディタ
    https://sakura-editor.github.io/

#>
[CmdletBinding()]
param(
    # ------------------------------------------------------------------
    # 検索対象・検索条件
    # ------------------------------------------------------------------
	[Parameter(Position = 0)][Alias("P")][string]$Path,
	[Parameter(Position = 1)][Alias("E")][string]$Pattern,
	[Alias("S")][string]$SearchTarget,
    # ------------------------------------------------------------------
    # 検索方法
    # ------------------------------------------------------------------
	[Alias("R")][switch]$Recurse,
	[Alias("W")][switch]$Word,
	[Alias("I")][switch]$IgnoreCase,
	[Alias("G")][switch]$UseRegex,
	[Alias("F")][switch]$FirstMatchOnly,
	[Alias("M")][switch]$OutputMatchedPart,
    # ------------------------------------------------------------------
    # 除外・フィルタ
    # ------------------------------------------------------------------
	[Alias("ED")][string]$ExcludeDirs,
	[Alias("EF")][string]$ExcludeFiles,
	[Alias("T")][switch]$TextOnly,
	[Alias("IM")][string]$ImportMagicNumber,
    # ------------------------------------------------------------------
    # 出力・動作制御
    # ------------------------------------------------------------------
	[Alias("Q")][switch]$Quiet,
	[Alias("O")][string]$OutputFile,
    # ------------------------------------------------------------------
    # 高度な制御
    # ------------------------------------------------------------------
	[Alias("CP")][string]$CodePage,
	[Alias("N")][int]$Parallel,
    # ------------------------------------------------------------------
    # ユーティリティ / 制御系
    # ------------------------------------------------------------------
    [Alias("EM")][string]$ExportMagicNumber,
	[Alias("H")][switch]$Help
)

# ==============================================================================
# 初期化
# ==============================================================================

# 開始時間
$StartTime  = Get-Date

# ライブラリルート
$LibDir		= Join-Path $PSScriptRoot "lib"

# --- Load modules ---

. (Join-Path $LibDir "Core.ps1")
. (Join-Path $LibDir "FileSystem.ps1")
. (Join-Path $LibDir "Output.ps1")
. (Join-Path $LibDir "SearchProcessor.ps1")
. (Join-Path $LibDir "Parallel.ps1")

# ==============================================================================
# パラメータ取得・検証
# ==============================================================================

# パラメータを取得
$Params     = Get-CommandLineArguments $PSBoundParameters

# ヘルプ
if ($Params.Help) { Show-Usage }

# 入力チェック
Validate-Parameters -Params $Params

# ==============================================================================
# モード分岐
# ==============================================================================

if ($Params.ExportMagicNumber) {

	Invoke-ExportMagicNumber -Params $Params
} else {

	Invoke-SearchMain -Params $Params -StartTime $StartTime -LibDir $LibDir
}

exit 0
