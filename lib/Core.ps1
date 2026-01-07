# ------------------------------------------------------------------------------
# グローバル設定
# ------------------------------------------------------------------------------
# CPUコア数
$global:CpuCores = [System.Environment]::ProcessorCount

<#
.SYNOPSIS
    コマンドライン引数から指定された値を取得します。

.DESCRIPTION
    指定されたハッシュテーブルにキーが存在する場合はその値を返し、
    存在しない場合は既定値を返します。

    コマンドライン引数の取得処理を簡潔に記述するための
    ユーティリティ関数です。

.PARAMETER Params
    コマンドライン引数を格納したハッシュテーブル。

.PARAMETER Name
    取得対象の引数名。

.PARAMETER Default
    指定した引数が存在しない場合に返される既定値。

.OUTPUTS
    Object
#>
function Get-ArgumentsValue {
	param(
		[hashtable]$Params,
		[string]$Name,
		$Default = $null
	)

	if ($Params.ContainsKey($Name)) {

		return $Params[$Name]
	}

	return $Default
}

<#
.SYNOPSIS
    コマンドライン引数を内部用オブジェクトに変換します。

.DESCRIPTION
    Param ブロックで取得したコマンドライン引数を解析し、
    既定値を補完した上で内部処理用の PSCustomObject を生成します。

    ExportMagicNumber / Help モードの場合は、
    検索関連パラメータの既定値設定を行いません。

.PARAMETER Params
    $PSBoundParameters から取得した引数ハッシュテーブル。

.OUTPUTS
    PSCustomObject
    内部処理で使用する引数オブジェクト。
#>
function Get-CommandLineArguments {
    [CmdletBinding()]
    param([hashtable]$Params)

	if ($Params.ContainsKey("ExportMagicNumber") -Or $Params.ContainsKey("Help"))  {
		$outputFile		= null
		$searchTarget   = null
		$codePage		= null
		$parallel		= null
	} else {
		$outputFile		= Get-OutputFile
		$searchTarget   = "*"
		$codePage		= "AUTO"
		$parallel		= $global:CpuCores
	}

    $args = [PSCustomObject]@{
		# ------------------------------------------------------------------
		# 検索対象・検索条件
		# ------------------------------------------------------------------
		Path				= Get-ArgumentsValue $Params "Path"
		Pattern				= Get-ArgumentsValue $Params "Pattern"
		SearchTarget		= Get-ArgumentsValue $Params "SearchTarget"			$searchTarget
		# ------------------------------------------------------------------
		# 検索方法
		# ------------------------------------------------------------------
		Recurse				= Get-ArgumentsValue  $Params "Recurse"				$false
		Word				= Get-ArgumentsValue  $Params "Word"				$false
		IgnoreCase			= Get-ArgumentsValue  $Params "IgnoreCase"			$false
		UseRegex			= Get-ArgumentsValue  $Params "UseRegex"			$false
		FirstMatchOnly		= Get-ArgumentsValue  $Params "FirstMatchOnly"		$false
		OutputMatchedPart	= Get-ArgumentsValue  $Params "OutputMatchedPart"	$false
		# ------------------------------------------------------------------
		# 除外・フィルタ
		# ------------------------------------------------------------------
		ExcludeDirs			= Get-ArgumentsValue  $Params "ExcludeDirs"
		ExcludeFiles		= Get-ArgumentsValue  $Params "ExcludeFiles"
		TextOnly			= Get-ArgumentsValue  $Params "TextOnly"			$false
		ImportMagicNumber	= Get-ArgumentsValue  $Params "ImportMagicNumber"
		# ------------------------------------------------------------------
		# 出力・動作制御
		# ------------------------------------------------------------------
		Quiet				= Get-ArgumentsValue $Params "Quiet"				$false
		OutputFile			= Get-ArgumentsValue $Params "OutputFile"			$outputFile
		# ------------------------------------------------------------------
		# 高度な制御
		# ------------------------------------------------------------------
		CodePage			= Get-ArgumentsValue $Params "CodePage"				$codePage
		Parallel			= Get-ArgumentsValue $Params "Parallel"				$parallel
		# ------------------------------------------------------------------
		# ユーティリティ / 制御系
		# ------------------------------------------------------------------
		ExportMagicNumber	= Get-ArgumentsValue $Params "ExportMagicNumber"
		Help				= Get-ArgumentsValue $Params "Help"					$false
		IsDebug				= ($DebugPreference -ne 'SilentlyContinue')
    }

	return $args
}

<#
.SYNOPSIS
    コマンドライン引数の妥当性を検証します。

.DESCRIPTION
    各種排他制御、必須パラメータ、存在チェック、
    MagicNumber・文字コード指定の妥当性を検証します。

    不正な場合は Show-Usage を呼び出し、処理を終了します。

.PARAMETER Params
    Get-CommandLineArguments により生成された引数オブジェクト。
#>
function Validate-Parameters {
    param([PSCustomObject]$Params)

    # ------------------------------------------------------------------
    # ExportMagicNumber 排他チェック
    # ------------------------------------------------------------------
    if ($Params.ExportMagicNumber) {

		$used = $false

        $exclusiveArgs = @(
            "ExportMagicNumber","IsDebug"
        )

		foreach ($key in $Params.PSObject.Properties.Name) {

			if ($key -notin $exclusiveArgs -And
				$Params.$key)
			{

				Write-Host "${key}:$($Params.$key)"
				$used = $true
				break
			}
		}

        if ($used) {
        
            Show-Usage "ExportMagicNumber 実行時に同時指定できないパラメータがあります。"
        }

        return
    }

    # ------------------------------------------------------------------
    # 必須パラメータ
    # ------------------------------------------------------------------
    if (-not $Params.Path -or -not $Params.Pattern) {

        Show-Usage
    }

    # ------------------------------------------------------------------
    # 検索対象フォルダ存在チェック
    # ------------------------------------------------------------------
    $paths = $Params.Path -split ';'
    foreach ($p in $paths) {

        if (-not (Test-Path -LiteralPath $p)) {

            Show-Usage "検索対象フォルダが見つかりません。Path:$p"
        }
    }

    # ------------------------------------------------------------------
    # 正規表現と単語単位の相関チェック
    # ------------------------------------------------------------------
    if ($UseRegex -And $Word)   {

		Show-Usage "UseRegex と Word は同時に指定できません。"
    }

    # ------------------------------------------------------------------
    # MagicNumber チェック
    # ------------------------------------------------------------------
    if ($Params.ImportMagicNumber) {

        if ($Params.TextOnly) {

            Show-Usage "TextOnly と ImportMagicNumber は同時に指定できません。"
        }

        if (-not (Test-Path $Params.ImportMagicNumber)) {

            Show-Usage "MagicNumber ファイルが見つかりません。ImportMagicNumber:$Params.ImportMagicNumber"
        }
    }

    # ------------------------------------------------------------------
    # CodePage チェック
    # ------------------------------------------------------------------
    if ($Params.CodePage) {

        if ( $Params.CodePage.ToUpper() -ne "AUTO" -And
        -not $global:CodePages.ContainsKey($Params.CodePage.ToUpper())) {

            Show-Usage "文字コードが正しくありません。CodePage:$Params.CodePage"
        }
    }
}

<#
.SYNOPSIS
    コマンドライン使用方法を表示します。

.DESCRIPTION
    指定されたメッセージがある場合は先頭に表示し、
    その後コマンドの使用方法を出力します。

    メッセージが指定された場合はエラー終了（exit 1）、
    指定されない場合は正常終了（exit 0）します。

.PARAMETER Message
    表示するエラーメッセージ。
#>
function Show-Usage {
    param(
        [string]$Message
    )

    if ($Message) {
         Write-Host ""
         Write-Host ">>> $Message"
         Write-Host ""
    }

	$scriptName = Get-ScriptName

	if ($Help -Or (-not $Quiet)) {

		Write-Host "Usage:"
		Write-Host "  Keyword Search:"
		Write-Host "    .\$scriptName -P <検索フォルダ> -E <検索文字> [オプション]"
		Write-Host ""
		Write-Host "  Export MagicNumber:"
		Write-Host "    .\$scriptName -EM <出力JSONファイル>"
		Write-Host ""
        Write-Host "Required:"
		Write-Host "    -P   , -Path               : 検索フォルダ"
		Write-Host "    -E   , -Pattern            : 検索文字列または正規表現"
		Write-Host ""
		Write-Host "Search Options:"
		Write-Host "    -S   , -SearchTarget       : 検索ファイル(既定: *)"
		Write-Host "    -R   , -Recurse            : サブフォルダーも検索"
		Write-Host "    -W   , -Word               : 単語単位で検索"
		Write-Host "    -I   , -IgnoreCase         : 大文字小文字を無視"
		Write-Host "    -G   , -UseRegex           : 正規表現を使用"
		Write-Host "    -F   , -FirstMatchOnly     : ファイル毎初回の一致のみ"
		Write-Host "    -M   , -OutputMatchedPart  : 一致部分のみ出力"
		Write-Host ""
        Write-Host "Exclude / Filter:"
		Write-Host "    -ED  , -ExcludeDirs        : 除外するフォルダ(ワイルドカード可／複数指定は;で区切る)"
		Write-Host "    -EF  , -ExcludeFiles       : 除外するファイル(ワイルドカード可／複数指定は;で区切る)"
		Write-Host "    -T   , -TextOnly           : テキストファイルのみ検索(デフォルトマジックナンバーで判定)"
		Write-Host "    -IM  , -ImportMagicNumber  : テキストファイルのみ検索(カスタムマジックナンバー JSON を使用)"
		Write-Host "                                 ※ -TextOnly と同時に指定できません"
		Write-Host ""
        Write-Host "Output / Control:"
		Write-Host "    -O   , -OutputFile         : 出力ファイル"
		Write-Host "                                 ※ 出力ファイルを指定しない場合は、"
		Write-Host "                                    $scriptName`_yyyyMMdd_HHmmss.txtへ出力されます。"
		Write-Host "    -Q   , -Quiet              : 進捗・メッセージを抑止"
		Write-Host ""
        Write-Host "Advanced:"
		Write-Host "    -CP  , -CodePage           : 文字コード種別(既定: AUTO)"
		Write-Host "                                 UTF8N     : UTF-8(BOMなし)"
		Write-Host "                                 UTF8BOM   : UTF-8(BOMあり)"
		Write-Host "                                 UTF16LE   : UTF-16LE"
		Write-Host "                                 UTF16BE   : UTF-16BE"
		Write-Host "                                 UTF32LE   : UTF-32LE"
		Write-Host "                                 UTF32BE   : UTF-32BE"
		Write-Host "                                 SJIS      : SJIS"
		Write-Host "                                 JIS       : JIS"
		Write-Host "                                 EUC       : EUC"
		Write-Host "                                 AUTO      : 自動判定"
		Write-Host "    -N   , -Parallel           : 並列数(スレッド数, 既定: $global:CpuCores)"
        Write-Host ""
        Write-Host "Utility:"
		Write-Host "    -EM  , -ExportMagicNumber  : マジックナンバー定義を JSON に出力"
		Write-Host "                                 ※ このオプション指定時は他のパラメータは指定できません"
		Write-Host "    -H   , -Help               : このヘルプを表示"
    }

	if ($Message) {

		exit 1
	} else {

		exit 0
	}
}

<#
.SYNOPSIS
    マジックナンバー定義を JSON ファイルに出力します。

.DESCRIPTION
    内部で保持しているマジックナンバー定義を
    JSON 形式でファイルに出力します。

.PARAMETER Params
    コマンドライン引数オブジェクト。
#>
function Invoke-ExportMagicNumber {
    param([PSCustomObject]$Params)

    Export-MagicNumbersToJson `
        -MagicNumbers $Global:MagicNumberMap `
        -JsonPath     $Params.ExportMagicNumber

	if (-not $Params.Quit) {

		Write-Host "MagicNumber 定義を出力しました: $($Params.ExportMagicNumber)"
	}
}

<#
.SYNOPSIS
    Grep 処理のメインロジックを実行します。

.DESCRIPTION
    検索条件の初期化、正規表現生成、マジックナンバー設定、
    ファイル列挙、並列 Grep 実行、結果出力までの
    一連の処理を統括します。

.PARAMETER Params
    コマンドライン引数オブジェクト。

.PARAMETER StartTime
    処理開始時刻。

.PARAMETER LibDir
    ライブラリディレクトリのパス。
#>
function Invoke-SearchMain {
    param(
        [PSCustomObject]$Params,
        [datetime]$StartTime,
        [string]$LibDir
    )

	# 作業ディレクトリ作成　&　取得 
    $workCurDir = Create-WorkCurrntDirectory

    try {

		# ------------------------------------------------------------------------------
		# 初期値／既定値の設定
		# ------------------------------------------------------------------------------

		# 出力ファイル文字コード(UTF-8BOMなし)
		$outputEncoding = New-Object System.Text.UTF8Encoding($false)
		$debugLogFile   = Get-DebugLogFile -OutputFile $Params.OutputFile

		# Regexの設定
		try {

			$regex = Create-Regexp	-Pattern	$Params.Pattern		`
									-UseRegex	$Params.UseRegex	`
									-IgnoreCase	$Params.IgnoreCase 	`
									-Word		$Params.Word

			# Regexのバージョン
			$regexVersion = $regex.GetType().Assembly.GetName().Version.ToString()
		} catch {

		    Show-Usage "正規表現が正しくありません。Pattern:$($Params.Pattern)"
		}

		# マジックナンバーの設定
		if ($Params.ImportMagicNumber) {
			# マジックナンバーを読み込み
			
			try {

				$magicNumbers = Load-MagicNumbers $Params.ImportMagicNumber
			} catch {

			    Show-Usage "マジックナンバーが正しくありません。ImportMagicNumber:$($Params.ImportMagicNumber)"
			}

			$Params.TextOnly = $true #テキスト検索をONにする
		} else {
			# 標準のマジックナンバーを使用

			$magicNumbers = $global:MagicNumberMap
		}

		# マジックナンバーの HEX をバイト配列に変換
		Convert-MagicNumberHexToBytes -MagicNumbers $magicNumbers

		# 最大読み込みバイト数
		$maxMagicNumberBytes = Get-MaxMagicNumberBytes -MagicNumbers $magicNumbers

		# ------------------------------------------------------------------------------
		# 共通パラメータ設定
		# ------------------------------------------------------------------------------

		$sharedArgs = [PSCustomObject]@{
		    LibDir              = $LibDir
		    WorkCurDir          = $workCurDir
		    Regex               = $regex
		    TextOnly            = $Params.TextOnly
		    OutputMatchedPart   = $Params.OutputMatchedPart
		    FirstMatchOnly      = $Params.FirstMatchOnly
		    CodePage            = $Params.CodePage
		    MagicNumbers        = $magicNumbers
		    MaxMagicNumberBytes = $maxMagicNumberBytes
		    OutputEncoding      = $outputEncoding
		    Quiet               = $Params.Quiet
		    Parallel            = $Params.Parallel 
		    StartTime           = $StartTime
		    IsDebug             = $Params.IsDebug
		}

		# ------------------------------------------------------------------------------
		# 出力ファイル／作業フォルダの初期化
		# ------------------------------------------------------------------------------

		# 出力ファイルを削除
		if (Test-Path $Params.OutputFile) { Remove-Item $Params.OutputFile }

		# ファイルオープン
		Init-DebugLog   -FilePath $debugLogFile      -Encoding $outputEncoding -IsEnable $Params.IsDebug
		Init-OutputFile -FilePath $Params.OutputFile -Encoding $outputEncoding

		# ------------------------------------------------------------------------------
		# ヘッダー出力
		# ------------------------------------------------------------------------------

		$headers = Build-Header -Params $Params
		Write-OutputFile $headers

		# ------------------------------------------------------------------------------
		# ファイル列挙
		# ------------------------------------------------------------------------------

		$files  = Get-TargetFiles	-Path			$Params.Path			`
									-SearchTarget	$Params.SearchTarget	`
									-Recurse		$Params.Recurse			`
									-ExcludeDirs	$Params.ExcludeDirs		`
									-ExcludeFiles	$Params.ExcludeFiles

		# ------------------------------------------------------------------------------
		# WorkerScript 読み込み
		# ------------------------------------------------------------------------------

		$workerFile		= Join-Path $libDir "WorkerScript.ps1"
		$workerScript	= [ScriptBlock]::Create((Get-Content $workerFile -Raw)) 

		# ------------------------------------------------------------------------------
		# 並列処理
		# ------------------------------------------------------------------------------

		$matchCount = Invoke-GrepParallel	-Files			$files 			`
											-WorkerScript	$workerScript	`
											-SharedArgs		$sharedArgs

		$elapsed = (Get-Date) - $StartTime
		$elapsedFormatted = "{0:hh\:mm\:ss}" -f $elapsed

		Write-OutputFile "$matchCount 個が検索されました。 - 経過時間:$elapsedFormatted"
    } finally {
        Delete-WorkCurrntDirectory
        Close-OutputFile
        Close-DebugLog
    }
}
