<#
.SYNOPSIS
    sgrep 並列処理用ワーカースクリプト。

.DESCRIPTION
    RunspacePool から呼び出され、1ファイル単位で grep 処理を実行します。

    本スクリプトは以下の処理を担当します。
    - ファイル存在確認
    - MagicNumber によるバイナリ判定（TextOnly 指定時）
    - 文字コード判定（AUTO 対応）
    - 正規表現検索
    - 検索結果のファイル出力
    - デバッグログ出力

    本スクリプトは単体実行を想定しておらず、
    Invoke-GrepParallel から Runspace 経由で呼び出されます。

.PARAMETER FilePath
    検索対象となるファイルのフルパス。

.PARAMETER OutputFile
    Grep 結果を書き出す一時出力ファイルのパス。
    Runspace 完了後に呼び出し元で集約されます。

.PARAMETER LogFile
    デバッグログの出力先ファイルパス。
    IsDebug が有効な場合のみ使用されます。

.PARAMETER SharedArgs
    Runspace 間で共有される設定オブジェクト。

    以下のプロパティを含みます：
      - LibDir                : 共通ライブラリ配置ディレクトリ
      - Regex                 : 検索用正規表現オブジェクト
      - TextOnly              : テキストファイルのみ検索するかどうか
      - OutputMatchedPart     : マッチ部分のみを出力するか
      - FirstMatchOnly        : 最初の一致のみ出力するか
      - CodePage              : 文字コード指定（AUTO 可）
      - MagicNumbers          : バイナリ判定用 MagicNumber 定義
      - MaxMagicNumberBytes   : MagicNumber 判定に使用する最大バイト数
      - OutputEncoding        : 出力エンコーディング
      - IsDebug               : デバッグログ出力有無

.NOTES
    - 本スクリプトは Runspace 専用ワーカーです
    - 1 実行につき 1 ファイルのみを処理します
    - グローバル状態を持たず再入可能です
#>

# ------------------------------------------------------------------------------
# 並列処理用パラメータ
# ------------------------------------------------------------------------------
param (
	[string]$FilePath,
	[string]$OutputFile,
	[string]$LogFile,
	[PSCustomObject]$SharedArgs
)

# ------------------------------------------------------------------------------
# SharedArgs 展開
# ------------------------------------------------------------------------------
$LibDir 				= $SharedArgs.LibDir
$Regex					= $SharedArgs.Regex
$TextOnly				= $SharedArgs.TextOnly
$OutputMatchedPart		= $SharedArgs.OutputMatchedPart
$FirstMatchOnly			= $SharedArgs.FirstMatchOnly
$CodePage				= $SharedArgs.CodePage
$MagicNumbers			= $SharedArgs.MagicNumbers
$MaxMagicNumberBytes	= $SharedArgs.MaxMagicNumberBytes
$OutputEncoding			= $SharedArgs.OutputEncoding
$IsDebug				= $SharedArgs.IsDebug

# --- Load modules ---
. (Join-Path $LibDir "Output.ps1")
. (Join-Path $LibDir "FileSystem.ps1")
. (Join-Path $LibDir "SearchProcessor.ps1")

# ------------------------------------------------------------------------------
# メイン処理
# ------------------------------------------------------------------------------
try {

	Init-DebugLog -FilePath $LogFile -Encoding $OutputEncoding -IsEnable $IsDebug

	Write-DebugLog "$FilePath Start"

	# ファイルの存在確認
	if (-not (Test-Path $FilePath)) { 
		Write-DebugLog "${FilePath}:File not Found"
		return
	}

	# バイナリ判定
	if ($TextOnly) {
		$fileType = Get-FileType -FilePath				$FilePath `
								 -MagicNumbers			$MagicNumbers `
								 -MaxMagicNumberBytes	$MaxMagicNumberBytes
		Write-DebugLog "${FilePath}:FileType:${fileType}"
		if ($fileType) {
			return
		}
	}

	# 文字コード判定
	$cp = $CodePage
	if ($cp  -eq "AUTO") {
		$cp = Get-FileCodePage $FilePath
		Write-DebugLog "${FilePath}:Get-FileCodePage:CodePage:${cp}"
		if (-not $cp) { 
			$cp = ($global:CodePages.GetEnumerator() |
				Where-Object { $_.Value.Default } |
				Select-Object -First 1
			).Key
		}
	}

	Write-DebugLog "${FilePath}:CodePage:${cp}"

	$inputEncoding = Get-EncodingByKey $cp
	$cpName        = $global:CodePages[$cp].Name

	$rowIndex = 0

	$reader = [System.IO.StreamReader]::new($FilePath  , $inputEncoding)
	$writer = [System.IO.StreamWriter]::new($OutputFile, $false, $OutputEncoding)

	try {
		while (($line = $reader.ReadLine()) -ne $null) {

			$rowIndex++

			$m = $Regex.Match($line)
			if ($m.Success) {
				$colIndex = $m.Index + 1
				$result   = "$FilePath($rowIndex,$colIndex)  [$cpName]: "
				if ($OutputMatchedPart) {
					$result = $result + $m.Value
				} else {
					$result = $result + $line
				}
				$writer.WriteLine($result)
				if ($FirstMatchOnly) { break }
			}
		}
	} catch {
		Write-DebugLog "$FilePath:Error:$_"
	} finally {
		$reader.Close()
		$writer.Close()
		$reader.Dispose()
		$writer.Dispose()
	}
} catch {
	Write-DebugLog "$FilePath:Error:$_"
} finally {
	Write-DebugLog "$FilePath End"
	Close-DebugLog
}

return
