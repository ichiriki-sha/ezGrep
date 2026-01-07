# ------------------------------------------------------------------------------
# 出力先ファイル
# ------------------------------------------------------------------------------
# 出力用 StreamWriter
$script:OutputFileWriter          = $null

# 一定間隔で Flush を行うためのタイマー
$script:OutputFileFlushTimer      = $null

<#
.SYNOPSIS
    出力ファイルを初期化します。

.DESCRIPTION
    指定されたファイルパスに対して StreamWriter を生成し、
    一定間隔で自動 Flush を行うタイマーを開始します。

    長時間処理や異常終了時でも
    出力内容が失われにくい設計です。

.PARAMETER FilePath
    出力ファイルのパス。

.PARAMETER Encoding
    出力に使用する文字エンコーディング。

.PARAMETER IntervalSeconds
    自動 Flush を行う間隔（秒）。
    既定値は 30 秒です。
#>
function Init-OutputFile {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [System.Text.Encoding]$Encoding,
        [int]$IntervalSeconds = 30
    )

	$script:OutputFileWriter = [System.IO.StreamWriter]::new($FilePath, $true, $Encoding)
	$script:OutputFileFlushTimer = New-Object Timers.Timer
	$script:OutputFileFlushTimer.Interval = $IntervalSeconds * 1000
	$script:OutputFileFlushTimer.AutoReset = $true
	$script:OutputFileFlushTimer.add_Elapsed({
	    if ($script:OutputFileWriter) {
	        try {
	            $script:OutputFileWriter.Flush()
	        } catch {
	            # 無視して次回に
	        }
	    }
	})
	$script:OutputFileFlushTimer.Start()
}

<#
.SYNOPSIS
    出力ファイルに 1 行書き込みます。

.DESCRIPTION
    初期化済みの出力ファイルに対して
    改行付きで文字列を出力します。

.PARAMETER Line
    出力する文字列。
#>
function Write-OutputFile {
    param([string]$Line)
	if ($script:OutputFileWriter) {
		$script:OutputFileWriter.WriteLine($Line)
	}
}

<#
.SYNOPSIS
    出力ファイルをクローズします。

.DESCRIPTION
    Flush タイマーを停止・破棄し、
    StreamWriter を安全にクローズします。
#>
function Close-OutputFile {

    if ($OutputFileFlushTimer) {
        $OutputFileFlushTimer.Stop()
        $OutputFileFlushTimer.Dispose()
        $OutputFileFlushTimer = $null
    }

	if ($script:OutputFileWriter) {
		$script:OutputFileWriter.Flush()
		$script:OutputFileWriter.Close()
		$script:OutputFileWriter = $null
	}
}

# ------------------------------------------------------------------------------
# デバッグログ
# ------------------------------------------------------------------------------
# デバッグログ有効フラグ
$script:EnableDebugLog = $false

# デバッグログ用 StreamWriter
$script:DebugLogWriter = $null

<#
.SYNOPSIS
    デバッグログを初期化します。

.DESCRIPTION
    デバッグログが有効な場合のみ
    ログファイルをオープンします。

.PARAMETER FilePath
    デバッグログファイルのパス。

.PARAMETER Encoding
    出力に使用する文字エンコーディング。

.PARAMETER IsEnable
    デバッグログを有効にするかどうか。
#>
function Init-DebugLog {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [System.Text.Encoding]$Encoding,
        [bool]$IsEnable = $false
    )
    $script:EnableDebugLog = $IsEnable
	if ($script:EnableDebugLog) {
		$script:DebugLogWriter = [System.IO.StreamWriter]::new($FilePath, $true, $Encoding)
	}
}

<#
.SYNOPSIS
    デバッグログを 1 行出力します。

.DESCRIPTION
    タイムスタンプ、PID、スレッド ID を付加して
    デバッグログを出力します。

.PARAMETER Message
    出力するログメッセージ。
#>
function Write-DebugLog {
	param([string]$Message)
	if ($script:EnableDebugLog) {
		if ($script:DebugLogWriter) {
			$tid = [System.Threading.Thread]::CurrentThread.ManagedThreadId
			$timeStamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
			$bytes = "[$timeStamp][PID:$pid][TID:$tid] $Message"
			$script:DebugLogWriter.WriteLine($bytes)
		}
	}
}

<#
.SYNOPSIS
    既存ログをそのまま書き込みます。

.DESCRIPTION
    フォーマット済みのログ行を
    追記するための関数です。

.PARAMETER Message
    書き込むログ行。
#>
function Merge-DebugLog {
	param([string]$Message)
	if ($script:EnableDebugLog) {
		if ($script:DebugLogWriter) {
			$script:DebugLogWriter.WriteLine($Message)
		}
	}
}

<#
.SYNOPSIS
    デバッグログをクローズします。
#>
function Close-DebugLog {
	if ($script:EnableDebugLog) {
		if ($script:DebugLogWriter) {
			$script:DebugLogWriter.Flush()
			$script:DebugLogWriter.Close()
			$script:DebugLogWriter = $null
		}
	}
}


# ------------------------------------------------------------------------------
# 一時ファイル作成
# ------------------------------------------------------------------------------

<#
.SYNOPSIS
    一時デバッグログファイルを生成します。

.PARAMETER FolderPath
    作成先フォルダ。

.OUTPUTS
    System.String
#>
function New-TempLogFile {
	param([string]$FolderPath)
	$guid = [Guid]::NewGuid().ToString()
	return Join-Path $FolderPath "$guid.log"
}

<#
.SYNOPSIS
    一時出力ファイルを生成します。

.PARAMETER FolderPath
    作成先フォルダ。

.OUTPUTS
    System.String
#>
function New-TempOutputFile {
	param([string]$FolderPath)
	$guid = [Guid]::NewGuid().ToString()
	return Join-Path $FolderPath "$guid.txt"
}

# ------------------------------------------------------------------------------
# プログレスバー
# ------------------------------------------------------------------------------
<#
.SYNOPSIS
    コンソールに進捗バーを表示します。

.DESCRIPTION
    パーセンテージと経過時間を表示する
    シンプルなテキストベースのプログレスバーです。

.PARAMETER Percent
    進捗率（0～100）。

.PARAMETER StartTime
    処理開始時刻。
#>
function Show-ProgressBar {
	param([Parameter(Mandatory)]
	      [double]$Percent,
	      [Parameter(Mandatory)]
          [DateTime]$StartTime)

	# ProgressBarの設定
	$barLength        = 50
	$percentClamped   = [Math]::Min([Math]::Max($Percent, 0), 100)  # 0～100に制限
	$filled           = [Math]::Floor($barLength * ($percentClamped / 100))
	$empty            = $barLength - $filled
	$bar              = "[" + ("#" * $filled) + ("." * $empty) +"]"

	# 経過時間計算
	$elapsed          = (Get-Date) - $StartTime
	$elapsedFormatted = "{0:hh\:mm\:ss}" -f $elapsed

	Write-Host ("`r{0} {1,5:N1}% Elapsed:{2}" -f $bar, $Percent, $elapsedFormatted) -NoNewline
}

<#
.SYNOPSIS
    検索条件ヘッダー文字列を生成します。

.DESCRIPTION
    サクラエディタ風 grep 出力の
    検索条件ヘッダー部分を生成します。

.PARAMETER Params
    検索パラメータを格納した PSCustomObject。

.OUTPUTS
    System.String
#>
function Build-Header{
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Params
    )

    # Regexの作成
    $regex = [System.Text.RegularExpressions.Regex]::new("abc")
	# Regexのバージョン
	$regexVersion = $regex.GetType().Assembly.GetName().Version.ToString()

	$lines      = @()
	$lines     += ""
	$lines     += "□検索条件     `"$($Params.Pattern)`""
	$lines     += "検索対象       $($Params.SearchTarget)"
	$lines     += "フォルダー     $($Params.Path)"

	if ($Params.ExcludeFiles        ) { $lines += "除外ファイル     $($Params.ExcludeFiles)"                  }
	if ($Params.ExcludeDirs         ) { $lines += "除外フォルダー   $($Params.ExcludeDirs)"                   }
	if ($Params.Recurse             ) { $lines += "    (サブフォルダーも検索)"                                }
	if ($Params.TextOnly            ) { $lines += "    (テキストのみ検索)"                                    }
	if ($Params.Word                ) { $lines += "    (単語単位で探す)"                                      }
	if ($Params.IgnoreCase          ) { $lines += "    (英大文字小文字を区別しない)"                          }
	else                              { $lines += "    (英大文字小文字を区別する)"                            }
	if ($Params.UseRegex            ) { $lines += "    (正規表現:PowerShell Regex Version $regexVersion)"     }
	if ($Params.CodePage -eq "AUTO" ) { $lines += "    (文字コードセットの自動判定)"                          }
	else                              { $lines += "    (文字コード:$CodePage)"                                }
	if ($Params.OutputMatchedPart   ) { $lines += "    (一致した部分を出力)"                                  }
	else                              { $lines += "    (一致した行を出力)"                                    }
	if ($Params.FirstMatchOnly      ) { $lines += "    (ファイル毎最初のみ検索)"                              }

	$lines     += ""
	$lines     += ""

	return ($lines -Join "`r`n")
}