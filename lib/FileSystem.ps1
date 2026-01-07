<#
.SYNOPSIS
    実行中スクリプトのパスを取得します。

.DESCRIPTION
    CallStack を解析し、エントリポイントとなる
    スクリプトファイルのパスを取得します。

.OUTPUTS
    System.String
#>
function Get-ScriptPath {

	return (Get-PSCallStack | Select-Object -Last 1).ScriptName
}

<#
.SYNOPSIS
    実行中スクリプトの配置ディレクトリを取得します。

.DESCRIPTION
    実行中スクリプトのパスから
    親ディレクトリを取得します。

.OUTPUTS
    System.String
#>
function Get-CurrntDirectory {

	$scriptPath = Get-ScriptPath
	return [System.IO.Path]::GetDirectoryName($scriptPath)
}

<#
.SYNOPSIS
    実行中スクリプトのベース名を取得します。

.DESCRIPTION
    拡張子を除いたスクリプトファイル名を返します。

.OUTPUTS
    System.String
#>
function Get-ScriptBaseName {

	$scriptPath = Get-ScriptPath
	return  [System.IO.Path]::GetFileNameWithoutExtension($scriptPath)
}

<#
.SYNOPSIS
    実行中スクリプトのファイル名を取得します。

.DESCRIPTION
    拡張子を含むスクリプトファイル名を返します。

.OUTPUTS
    System.String
#>
function Get-ScriptName {

	$scriptPath = Get-ScriptPath
	return  [System.IO.Path]::GetFileName($scriptPath)
}

<#
.SYNOPSIS
    作業用ルートディレクトリを取得します。

.DESCRIPTION
    TEMP 配下にスクリプト名を基にした
    作業用ルートディレクトリのパスを返します。

.OUTPUTS
    System.String
#>
function Get-WorkRootDirectory {

	$scriptBaseName = Get-ScriptBaseName
	
	return Join-Path $Env:TEMP "$scriptBaseName"
}

function Get-WorkCurrntDirectory {

	$workRootDir = Get-WorkRootDirectory
	
	return Join-Path $workRootDir "$PID"
}

<#
.SYNOPSIS
    ライブラリディレクトリのパスを取得します。

.DESCRIPTION
    実行中スクリプトと同階層に存在する
    lib ディレクトリのパスを返します。

.OUTPUTS
    System.String
#>
function Get-LibraryDirectory {

	$curDir = Get-CurrntDirectory
	$libDir = Join-Path $curDir "lib"
	return $libDir
}

<#
.SYNOPSIS
    出力ファイルの既定パスを生成します。

.DESCRIPTION
    実行中スクリプトの配置ディレクトリに、
    スクリプト名とタイムスタンプを含む
    出力ファイル名を生成します。

.OUTPUTS
    System.String
#>
function Get-OutputFile {

	$currntDir      = Get-CurrntDirectory
	$baseScriptName = Get-ScriptBaseName
	$timestamp      = Get-Date -Format "yyyyMMdd`_HHmmss"
	
	return Join-Path $currntDir "$baseScriptName`_$timestamp.txt"
}

<#
.SYNOPSIS
    デバッグログファイルのパスを生成します。

.DESCRIPTION
    出力ファイルと同じディレクトリに、
    拡張子を .log に変更したログファイルパスを返します。

.PARAMETER OutputFile
    出力ファイルのパス。

.OUTPUTS
    System.String
#>
function Get-DebugLogFile {
    param(
        [string]$OutputFile
    )

	$parentDir = [System.IO.Path]::GetDirectoryName($OutputFile)
	$baseName  = [System.IO.Path]::GetFileNameWithoutExtension($OutputFile)
	
	return Join-Path $parentDir "$baseName.log"
}

<#
.SYNOPSIS
    作業ディレクトリを作成します。

.DESCRIPTION
    プロセス ID ごとに一意な作業ディレクトリを作成します。
    既に存在する場合は何も行いません。

.OUTPUTS
    System.String
#>
function Create-WorkCurrntDirectory {

	$workCurrntDir = Get-WorkCurrntDirectory 
	New-Item $workCurrntDir -ItemType Directory -ErrorAction SilentlyContinue | Out-Null 
	return  $workCurrntDir
}

<#
.SYNOPSIS
    作業ディレクトリを削除します。

.DESCRIPTION
    実行プロセス用に作成された
    作業ディレクトリを再帰的に削除します。

    削除時にエラーが発生した場合は無視されます。
#>
function Delete-WorkCurrntDirectory {

	$workCurrntDir = Get-WorkCurrntDirectory 

	if (Test-Path $workCurDir) {
		try {
			Remove-Item -Path $workCurDir -Recurse -Force | Out-Null 
		} catch {}
	}
}

<#
.SYNOPSIS
    検索対象となるファイル一覧を取得します。

.DESCRIPTION
    指定されたパス配下から検索対象ファイルを列挙し、
    再帰検索、除外フォルダ、除外ファイルの条件を適用して
    最終的な検索対象ファイル一覧を生成します。

    除外フォルダは階層内のいずれかに一致した場合に除外されます。
    除外ファイルはファイル名のみで判定されます。

.PARAMETER Path
    検索対象のフォルダパス。
    複数指定する場合は「;」で区切ります。

.PARAMETER SearchTarget
    検索対象とするファイル名（ワイルドカード可）。

.PARAMETER Recurse
    サブフォルダを再帰的に検索するかどうか。

.PARAMETER ExcludeDirs
    除外するフォルダ名（ワイルドカード可）。
    複数指定する場合は「;」で区切ります。

.PARAMETER ExcludeFiles
    除外するファイル名（ワイルドカード可）。
    複数指定する場合は「;」で区切ります。

.OUTPUTS
    System.IO.FileInfo[]
#>
function Get-TargetFiles {
    param(
        [string]$Path,
        [string]$SearchTarget,
        [bool]$Recurse,
        [string]$ExcludeDirs,
        [string]$ExcludeFiles
    )

	$paths = $Path -Split ';'

	# ------------------------------------------------------------------------------
	# ファイル列挙
	# ------------------------------------------------------------------------------
	$files  = @()

	foreach ($p in $paths) {

		$f = if ($Recurse) {

			Get-ChildItem -LiteralPath $p -Filter $SearchTarget -Recurse -File
		} else {

			Get-ChildItem -LiteralPath $p -Filter $SearchTarget          -File
		}

		$files += $f
	}

	# -----------------------------
	# ExcludeDirs (セミコロン区切り, ワイルドカード対応, 階層どこかに含まれる場合除外)
	# -----------------------------
	if ($ExcludeDirs) {
	    $patterns = ($ExcludeDirs -split ';') |
	                 ForEach-Object { $_.Trim() } |
	                 Where-Object { $_ -ne "" }

	    $files = $files.Where({
	        # ファイルのフォルダー階層を配列にする
	        $dirs = (Split-Path $_.FullName -Parent) -split '[\\/]' 

	        $matched = $false
	        foreach ($d in $dirs) {
	            foreach ($p in $patterns) {
	                if ($d -like $p) {   # ← フォルダー名とパターンを 1:1 で比較
	                    $matched = $true
	                    break
	                }
	            }
	            if ($matched) { break }
	        }

	        -not $matched
	    })
	}

	# -----------------------------
	# ExcludeFiles (セミコロン区切りワイルドカード、ファイル名のみで判定)
	# -----------------------------
	if ($ExcludeFiles) {
	    $patterns = ($ExcludeFiles -split ';') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

	    $files = $files.Where({
	        $fileName = $_.Name
	        $matched = $false
	        foreach ($p in $patterns) {
	            if ($fileName -like $p) {
	                $matched = $true
	                break
	            }
	        }
	        -not $matched
	    })
	}

    return $files
}
