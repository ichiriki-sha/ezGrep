# ------------------------------------------------------------------------------
# MagicNumber
# ------------------------------------------------------------------------------

<#
.SYNOPSIS
    マジックナンバー判定・文字コード判定・正規表現生成を提供するユーティリティモジュール。

.DESCRIPTION
    本モジュールは以下の機能を提供します。

    - バイナリファイル判定用マジックナンバー定義
    - マジックナンバーの JSON 入出力
    - ファイルタイプ判定
    - 文字コード自動判定（ASCII / JIS / SJIS / EUC / UTF-8 / UTF-16 / UTF-32）
    - CodePage 情報管理
    - Grep 用 Regex オブジェクト生成

    sgrep の「テキストファイルのみ検索」「AUTO 文字コード判定」の中核を担います。

.NOTES
    - PowerShell 5.1 対応
    - ワイルドカードバイトは -1 として扱う
    - マジックナンバーは Offset 指定に対応
#>

# ==============================================================================
# マジックナンバーマップ定義
# ==============================================================================
# ファイル種別を識別するためのマジックナンバー定義。
# Hex  : 16進数表記（?? はワイルドカード）
# Offset : ファイル先頭からのオフセット位置
$global:MagicNumberMap    = @{
	# 圧縮・アーカイブ
	"ZIP"                 = @{ Hex="50 4B 03 04"                                     ; Offset=0 }
	"ZIP_EMPTY"           = @{ Hex="50 4B 05 06"                                     ; Offset=0 }
	"ZIP_SPANNED"         = @{ Hex="50 4B 07 08"                                     ; Offset=0 }

	"GZIP"                = @{ Hex="1F 8B"                                           ; Offset=0 }
	"RAR4"                = @{ Hex="52 61 72 21 1A 07 00"                            ; Offset=0 }
	"RAR5"                = @{ Hex="52 61 72 21 1A 07 01 00"                         ; Offset=0 }
	"7Z"                  = @{ Hex="37 7A BC AF 27 1C"                               ; Offset=0 }
	"LZ4"                 = @{ Hex="04 22 4D 18"                                     ; Offset=0 }
	"ZSTD"                = @{ Hex="28 B5 2F FD"                                     ; Offset=0 }
	"BZIP2"               = @{ Hex="42 5A 68"                                        ; Offset=0 }
	"XZ"                  = @{ Hex="FD 37 7A 58 5A 00"                               ; Offset=0 }
	"TAR"                 = @{ Hex="75 73 74 61 72"                                  ; Offset=257 } # ustarは257バイト目

	# 画像
	"PNG"                 = @{ Hex="89 50 4E 47 0D 0A 1A 0A"                         ; Offset=0 }
	"JPEG"                = @{ Hex="FF D8 FF"                                        ; Offset=0 }
	"GIF"                 = @{ Hex="47 49 46 38 ?? 61"                               ; Offset=0 }
	"BMP"                 = @{ Hex="42 4D ?? ?? ?? ?? 00 00 00 00 ?? ?? ?? ??"       ; Offset=0 }
	"WEBP"                = @{ Hex="52 49 46 46 ?? ?? ?? ?? 57 45 42 50"             ; Offset=0 }
	"TIFF_LE"             = @{ Hex="49 49 2A 00"                                     ; Offset=0 }
	"TIFF_BE"             = @{ Hex="4D 4D 00 2A"                                     ; Offset=0 }
	"ICO"                 = @{ Hex="00 00 01 00 ?? ??"                               ; Offset=0 }
    "GIMP_XCF"            = @{ Hex="67 69 6D 70 ?? 78 63 66 ??"                      ; Offset=0 }  # gimp

	# 音声 / 動画
	"MP3_ID3"             = @{ Hex="49 44 33"                                        ; Offset=0 }
	"MP3_FRAME"           = @{ Hex="FF FB"                                           ; Offset=0 }
	"WAV"                 = @{ Hex="52 49 46 46 ?? ?? ?? ?? 57 41 56 45"             ; Offset=0 }
	"AVI"                 = @{ Hex="52 49 46 46 ?? ?? ?? ?? 41 56 49 20"             ; Offset=0 }
	"MP4"                 = @{ Hex="?? ?? ?? ?? 66 74 79 70 69 73 6F 6D"             ; Offset=0 }
	"MOV"                 = @{ Hex="?? ?? ?? ?? 66 74 79 70 71 74 20 20"             ; Offset=0 }
	"M4A"                 = @{ Hex="?? ?? ?? ?? 66 74 79 70 4D 34 41 20"             ; Offset=0 }

	# 文書形式
    "PDF"                 = @{ Hex="25 50 44 46 2D ?? ??"                            ; Offset=0 } #%PDF-1.4
	"PS"                  = @{ Hex="25 21 50 53"                                     ; Offset=0 }
	"RTF"                 = @{ Hex="7B 5C 72 74 66"                                  ; Offset=0 }
	"MS_OFFICE"           = @{ Hex="D0 CF 11 E0 A1 B1 1A E1"                         ; Offset=0 }

	# データベース
	"SQLite"              = @{ Hex="53 51 4C 69 74 65 20 66 6F 72 6D 61 74 20 33 00" ; Offset=0 }
	"ORACLE_DATA_PUMP"    = @{ Hex="C2 D0"                                           ; Offset=0 }
	"ORACLE_DUMP"         = @{ Hex="?? ?? ?? 45 58 50 4F 52 54 3A ??"                ; Offset=0 }

	# 実行ファイル
	"EXE_MZ"              = @{ Hex="4D 5A"                                           ; Offset=0 }
	"ELF"                 = @{ Hex="7F 45 4C 46"                                     ; Offset=0 }
	"MACHO_LE"            = @{ Hex="CE FA ED FE"                                     ; Offset=0 }
	"MACHO_BE"            = @{ Hex="FE ED FA CE"                                     ; Offset=0 }
	"JAVA_CLASS"          = @{ Hex="CA FE BA BE ?? ?? ?? ??"                         ; Offset=0 }

	# 中間ファイル
	".NET_PDB_MSF"        = @{ Hex = "4D 69 63 72 6F 73 6F 66 74 20 43 2F 43 2B 2B 20 4D 53 46 20 ?? ?? ??" ; Offset = 0 }
	".NET_PDB_PORTABLE"   = @{ Hex = "42 53 4A 42 ?? ?? ?? ?? ?? ?? ??"                ; Offset=0 }
	".NET_RESOURCES"      = @{ Hex = "CE CA EF BE 01 00 00 00 ?? 00 00 00"             ; Offset=0 }
	".NET_CACHE"          = @{ Hex = "50 4B 47 41 ?? 00 00 00"                         ; Offset=0 }
	".NET_ASM_XAML_CACHE" = @{ Hex = "06 01 02 00 00 00 01 7D"                         ; Offset=0 }
	".NET_ASM_FROM_CACHE" = @{ Hex = "4D 42 52 53 43 01 01 ?? 00 00 00"                ; Offset=0 }
	".NET_BAML"           = @{ Hex = "0C 00 00 00 4D 00 53 00 42 00 41 00 4D 00 4C 00" ; Offset=0 }
	

	# フォント
	"TTF"                 = @{ Hex="00 01 00 00"                                       ; Offset=0 }   # TrueType
	"OTF_PS"              = @{ Hex="4F 54 54 4F"                                       ; Offset=0 }   # OpenType PostScriptベース ("OTTO")
	"OTF_TT"              = @{ Hex="00 01 00 00"                                       ; Offset=0 }   # OpenType TrueTypeベース
	"WOFF"                = @{ Hex="77 4F 46 46"                                       ; Offset=0 }   # Web Open Font Format
	"WOFF2"               = @{ Hex="77 4F 46 32"                                       ; Offset=0 }   # Web Open Font Format 2

	# その他
	"WINDOWS_LNK"         = @{ Hex="4C 00 00 00"                                       ; Offset=0 }   # Windows Link File
}

<#
.SYNOPSIS
    マジックナンバー定義を JSON ファイルに出力します。

.DESCRIPTION
    内部で使用しているマジックナンバーマップを
    外部編集可能な JSON 形式で保存します。

    ExportMagicNumber オプション用の処理です。

.PARAMETER MagicNumbers
    エクスポート対象のマジックナンバーマップ。

.PARAMETER JsonPath
    出力先 JSON ファイルパス。

.NOTES
    - UTF-8 (BOMなし) で出力
    - Offset / Hex のみ保存
#>
function Export-MagicNumbersToJson {
    param(
        [Parameter(Mandatory)]
        [hashtable]$MagicNumbers,
        [Parameter(Mandatory)]
        [string]$JsonPath
    )

    $out = @{}

    foreach ($key in ($MagicNumbers.Keys | Sort-Object)) {
        $item = $MagicNumbers[$key]

        $out[$key] = @{
            Hex    = $item.Hex
            Offset = $item.Offset
        }
    }

    $json = $out | ConvertTo-Json -Depth 5

    # UTF-8 (BOMなし) で保存
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($JsonPath, $json, $utf8NoBom)
}

<#
.SYNOPSIS
    JSON ファイルからマジックナンバー定義を読み込みます。

.DESCRIPTION
    Export-MagicNumbersToJson で出力した JSON を読み込み、
    内部形式（Bytes 配列付き）に変換します。

.PARAMETER JsonPath
    マジックナンバー定義 JSON ファイル。

.OUTPUTS
    Hashtable
    内部用マジックナンバーマップ。
#>
function Load-MagicNumbers {
    param(
        [Parameter(Mandatory)]
        [string]$JsonPath
    )

    $json = Get-Content $JsonPath -Raw | ConvertFrom-Json

    $table = @{}

    foreach ($name in $json.PSObject.Properties.Name) {
        $item = $json.$name

        if (-not $item.Hex) {
            throw "Hex 未定義: $name"
        }

        $bytes = @()
        foreach ($h in ($item.Hex -split '\s+')) {
            if ($h -eq '??') {
                $bytes += -1
            } else {
                $bytes += [Convert]::ToByte($h, 16)
            }
        }

		$offset = 0
		if ($item.PSObject.Properties.Name -contains 'Offset' -and $item.Offset -ne $null) {
		    $offset = [int]$item.Offset
		}

        $table[$name] = @{
            Hex    = $item.Hex
            Offset = $offset
            Bytes  = $bytes
        }
    }

    return $table
}

# ------------------------------------------------------------------------------
# マジックナンバーの初期化
# ------------------------------------------------------------------------------
#function Initialize-MagicNumbers {
#    param([hashtable]$MagicNumbers)
#
#	foreach ($key in $MagicNumbers.Keys) {
#		$hexBytes = @()
#		foreach ($h in ($MagicNumbers[$key].Hex -split '\s+')) {
#			if ($h -eq "??") { $hexBytes += -1 }  # ワイルドカードは -1
#			else { $hexBytes += [Convert]::ToByte($h,16) }
#		}
#		$MagicNumbers[$key].bytes = $hexBytes
#	}
#
#    $max = 0
#	foreach ($item in $MagicNumbers.Values) {
#		$len = $item.bytes.Count
#		$total = $item.Offset + $len
#		if ($total -gt $MaxMagicNumberBytes) { $max = $total }
#	}
#
#    return $max
#}

#function Initialize-MagicNumbers {
#    param($Arguments)
#
#    if ($Arguments.ImportMagicNumber) {
#
#        $magicNumbers = Load-MagicNumbers $Arguments.ImportMagicNumber
#        $Arguments.TextOnly = $true
#    } else {
#
#        $magicNumbers = $Global:MagicNumberMap
#    }
#
#    Convert-MagicNumberHexToBytes -MagicNumbers $magicNumbers
#
#    return @{
#        MagicNumbers        = $magicNumbers
#        MaxMagicNumberBytes = Get-MaxMagicNumberBytes -MagicNumbers $magicNumbers
#    }
#}

<#
.SYNOPSIS
    マジックナンバーの HEX 定義をバイト配列に変換します。

.DESCRIPTION
    Hex 文字列を解析し、比較用の byte 配列に変換します。
    ワイルドカード "??" は -1 として扱います。

.PARAMETER MagicNumbers
    マジックナンバーマップ。
#>
function Convert-MagicNumberHexToBytes {
    param (
        [Parameter(Mandatory)]
        [hashtable]$MagicNumbers
    )

    foreach ($key in $MagicNumbers.Keys) {

        $hexBytes = @()

        foreach ($h in ($MagicNumbers[$key].Hex -split '\s+')) {

            if ($h -eq '??') {
                $hexBytes += -1   # ワイルドカード
            }
            else {
                $hexBytes += [Convert]::ToByte($h, 16)
            }
        }

        # bytes プロパティに設定
        $MagicNumbers[$key].Bytes = $hexBytes
    }
}

<#
.SYNOPSIS
    マジックナンバー判定に必要な最大読み込みバイト数を取得します。

.DESCRIPTION
    Offset + バイト長 の最大値を算出し、
    ファイル読み込みサイズ決定に使用します。

.PARAMETER MagicNumbers
    マジックナンバーマップ。

.OUTPUTS
    Int32
#>
function Get-MaxMagicNumberBytes {
    param (
        [Parameter(Mandatory)]
        [hashtable]$MagicNumbers
    )

    $maxBytes = 0

    foreach ($item in $MagicNumbers.Values) {

        if (-not $item.Bytes) { continue }

        $len   = $item.Bytes.Count
        $total = $item.Offset + $len

        if ($total -gt $maxBytes) {
            $maxBytes = $total
        }
    }

    return $maxBytes
}

<#
.SYNOPSIS
    マジックナンバーを用いてファイルタイプを判定します。

.DESCRIPTION
    ファイルの先頭バイト列を読み込み、
    登録済みマジックナンバーと照合します。

.PARAMETER FilePath
    判定対象ファイルパス。

.PARAMETER MagicNumbers
    マジックナンバーマップ。

.PARAMETER MaxMagicNumberBytes
    読み込み最大バイト数。

.OUTPUTS
    String
    一致したマジックナンバー名。未一致時は $null。
#>
function Get-FileType {
	param([string]$FilePath,
          [hashtable]$MagicNumbers,
          [int]$MaxMagicNumberBytes = 0)

	Write-DebugLog "${FilePath}:Get-FileType:Start"

	try {

		if ($MaxMagicNumberBytes -eq 0) { $MaxMagicNumberBytes = Get-MaxMagicNumberBytes -MagicNumbers $MagicNumbers }

		# ファイルを最大バイト数だけ読み込む
		$bytesfer = New-Object byte[] $MaxMagicNumberBytes
		$fs = [System.IO.File]::OpenRead($FilePath)
		try { $bytesRead = $fs.Read($bytesfer, 0, $MaxMagicNumberBytes) } finally { $fs.Close() }
		
		$ret = $null
		
		foreach ($item in $MagicNumbers.GetEnumerator()) {
			$bytes  = $item.Value.bytes
			$offset = $item.Value.Offset
			$match  = $true

			for ($i=0; $i -lt $bytes.Count; $i++) {
				$expected = $bytes[$i]
				if ($expected -eq -1) { continue }  # ワイルドカード
				$actual = if ($offset + $i -lt $bytesRead) { $bytesfer[$offset + $i] } else { 0 }
				if ($expected -ne $actual) { $match = $false; break }
			}

			if ($match) { 
				$ret = $item.Key
				return $ret
			}  # 一致したら即リターン
		}
		return $ret
	} finally {
		Write-DebugLog "${FilePath}:Get-FileType:End:Return:${ret}"
	}
}

# ------------------------------------------------------------------------------
# Encoding
# ------------------------------------------------------------------------------

<#
.SYNOPSIS
    文字コード定義マップ。

.DESCRIPTION
    sgrep 内部で使用する文字コード情報を定義したグローバルマップです。

    各キーは論理的な文字コード識別子であり、
    実際の CodePage 番号や BOM 有無、表示名などの
    メタ情報を保持します。

    - AUTO 指定時の既定文字コード判定
    - 出力時の表示名（[SJIS], [UTF-8] など）
    - BOM 判定処理
    で使用されます。

.NOTES
    - Default = $true のエントリは AUTO 判定失敗時のフォールバックに使用されます
    - PowerShell 5.1 / .NET Framework 環境を前提としています
#>

# ------------------------------------------------------------------------------
# 文字コードマップ
# ------------------------------------------------------------------------------
# Key        : 内部識別子
# CodePage  : .NET / Windows CodePage 番号
# Bom       : BOM 有無
# Name      : 表示用名称（grep 出力などで使用）
# Default   : AUTO 判定失敗時の既定値
# ------------------------------------------------------------------------------
$global:CodePages = @{
    "UTF8BOM" = @{ CodePage = 65001 ; Bom = $true  ; Name = "UTF-8"  ; Default = $false }
    "UTF8N"   = @{ CodePage = 65001 ; Bom = $false ; Name = "UTF-8"  ; Default = $false }
    "UTF16LE" = @{ CodePage =  1200 ; Bom = $true  ; Name = "UTF-16" ; Default = $false }
    "UTF16BE" = @{ CodePage =  1201 ; Bom = $true  ; Name = "UTF-16" ; Default = $false }
    "UTF32LE" = @{ CodePage = 12000 ; Bom = $true  ; Name = "UTF-32" ; Default = $false }
    "UTF32BE" = @{ CodePage = 12001 ; Bom = $true  ; Name = "UTF-32" ; Default = $false }
    "SJIS"    = @{ CodePage =   932 ; Bom = $false ; Name = "SJIS"   ; Default = $true  }
    "JIS"     = @{ CodePage = 50220 ; Bom = $false ; Name = "JIS"    ; Default = $false }
    "EUC"     = @{ CodePage = 51932 ; Bom = $false ; Name = "EUC"    ; Default = $false }
    "ASCII"   = @{ CodePage = 20127 ; Bom = $false ; Name = "ASCII"  ; Default = $false }
}

<#
.SYNOPSIS
    CodePage キーから Encoding オブジェクトを取得します。

.DESCRIPTION
    UTF-8 は BOM 有無を考慮して生成します。
    その他は CodePage 番号から取得します。

.PARAMETER Key
    CodePage キー（UTF8N / SJIS など）。

.OUTPUTS
    System.Text.Encoding
#>
function Get-EncodingByKey {
	param(
		[Parameter(Mandatory)]
		[string]$Key
	)

	Write-DebugLog "${FilePath}:Get-EncodingByKey:Start"

	# --- Hashtable から直接取り出す ---
	if (-not $global:CodePages.ContainsKey($Key)) {
		throw "Encoding Key '$Key' は登録されていません。"
	}

	$info = $global:CodePages[$Key]

	if ($info.CodePage -eq 65001) {
		# --- UTF-8 は BOM の有無でコンストラクタを使う ---
		$ret = New-Object System.Text.UTF8Encoding($info.Bom)
	} else {
		# --- それ以外は CodePage で生成 ---
		$ret = [System.Text.Encoding]::GetEncoding($info.CodePage)
	}

	Write-DebugLog "${FilePath}:Get-EncodingByKey:End:Return:${ret}"

	return $ret
}

<#
.SYNOPSIS
    ファイルの文字コードを自動判定します。

.DESCRIPTION
    BOM 判定、ASCII 判定、JIS エスケープ判定、
    SJIS / EUC / UTF-8 の出現頻度をもとに判定します。

.PARAMETER FilePath
    判定対象ファイル。

.PARAMETER SampleSizeKB
    判定用に読み込む最大サイズ(KB)。

.OUTPUTS
    String
    CodePage キー。判定不能時は $null。
#>
function Get-FileCodePage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [int]$SampleSizeKB = 4 
    )

	$fs = [System.IO.File]::OpenRead($FilePath)
	try {

		if ($fs.Length -eq 0) { return "ASCII" }
		
		# BOM判定
		$bomBytes = New-Object byte[] 4
		$fs.Read($bomBytes, 0, 4)                  | Out-Null
		$fs.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
		
		if ($bomBytes[0] -eq 0xEF -and $bomBytes[1] -eq 0xBB -and $bomBytes[2] -eq 0xBF                            ) { return "UTF8BOM" }
		if ($bomBytes[0] -eq 0xFF -and $bomBytes[1] -eq 0xFE -and $bomBytes[2] -eq 0x00 -and $bomBytes[3] -eq 0x00 ) { return "UTF32LE" }
		if ($bomBytes[0] -eq 0x00 -and $bomBytes[1] -eq 0x00 -and $bomBytes[2] -eq 0xFE -and $bomBytes[3] -eq 0xFF ) { return "UTF32BE" }
		if ($bomBytes[0] -eq 0xFF -and $bomBytes[1] -eq 0xFE                                                       ) { return "UTF16LE" }
		if ($bomBytes[0] -eq 0xFE -and $bomBytes[1] -eq 0xFF                                                       ) { return "UTF16BE" }
		
		# サンプル読み込み
		$total = $fs.Length
		$sampleSize = [Math]::Min($total, $SampleSizeKB * 1024)
		$bytes = New-Object byte[] $sampleSize
		
		# 先頭
		$fs.Read($bytes, 0, [Math]::Floor($sampleSize / 3)) | Out-Null

		# 中間
		if ($sampleSize -gt 2048 -and $total -gt $sampleSize) {
			$midStart = [Math]::Floor(($total - $sampleSize) / 2)
			$fs.Seek($midStart, [System.IO.SeekOrigin]::Begin) | Out-Null
			$fs.Read($bytes, [Math]::Floor($sampleSize / 3), [Math]::Floor($sampleSize / 3)) | Out-Null
		}

		# 末尾
		if ($sampleSize -gt 1024 -and $total -gt $sampleSize) {
			$tailStart = $total - [Math]::Floor($sampleSize / 3)
			$fs.Seek($tailStart, [System.IO.SeekOrigin]::Begin) | Out-Null
			$fs.Read($bytes, [Math]::Floor($sampleSize * 2 / 3), [Math]::Ceiling($sampleSize / 3)) | Out-Null
		}
		
	} finally {
		$fs.Close()
		$fs.Dispose()
	}

    # 定数
    $bEscape = 0x1B
    $bAt     = 0x40
    $bDollar = 0x24
    $bAnd    = 0x26
    $bOpen   = 0x28
    $bB      = 0x42
    $bD      = 0x44
    $bJ      = 0x4A
    $bI      = 0x49

    $len = $bytes.Length

    # バイナリ判定
    #$isBinary = $false
    #for ($i = 0; $i -lt $len; $i++) {
    #    $b1 = $bytes[$i]
    #    if ($b1 -le 0x06 -or $b1 -eq 0x7F -or $b1 -eq 0xFF) {
    #        $isBinary = $true
    #        if ($b1 -eq 0x00 -and $i -lt $len - 1 -and $bytes[$i+1] -le 0x7F) {
    #            return [System.Text.Encoding]::Unicode
    #        }
    #    }
    #}
    #if ($isBinary) { return $null }

    # ASCII 判定
    $notJapanese = $true
    for ($i = 0; $i -lt $len; $i++) {
        $b1 = $bytes[$i]
        if ($b1 -eq $bEscape -or $b1 -ge 0x80) {
            $notJapanese = $false
            break
        }
    }
    if ($notJapanese) { return "ASCII" }

    # JIS 判定
    for ($i = 0; $i -lt $len - 2; $i++) {
        $b1 = $bytes[$i]
        $b2 = $bytes[$i + 1]
        $b3 = $bytes[$i + 2]
        if ($b1 -eq $bEscape) {
            if (($b2 -eq $bDollar -and ($b3 -eq $bAt -or $b3 -eq $bB)) -or
                ($b2 -eq $bOpen   -and ($b3 -eq $bB -or $b3 -eq $bJ )) -or
                ($b2 -eq $bOpen   -and $b3 -eq $bI)) {
                return "JIS"
            }
            if ($i -lt $len - 3) {
                $b4 = $bytes[$i + 3]
                if ($b2 -eq $bDollar -and $b3 -eq $bOpen -and $b4 -eq $bD) {
                    return "JIS"
                }
                if ($i -lt $len - 5 -and $b2 -eq $bAnd -and $b3 -eq $bAt -and $b4 -eq $bEscape -and
                    $bytes[$i+4] -eq $bDollar -and $bytes[$i+5] -eq $bB) {
                    return "JIS"
                }
            }
        }
    }

    # SJIS / EUC / UTF-8 判定
    $sjis = 0
    $euc  = 0
    $utf8 = 0

    for ($i = 0; $i -lt $len - 1; $i++) {
        $b1 = $bytes[$i]
        $b2 = $bytes[$i + 1]
        if ((($b1 -ge 0x81 -and $b1 -le 0x9F) -or ($b1 -ge 0xE0 -and $b1 -le 0xFC)) -and
            (($b2 -ge 0x40 -and $b2 -le 0x7E) -or ($b2 -ge 0x80 -and $b2 -le 0xFC))) {
            $sjis += 2
            $i++
        }
    }

    for ($i = 0; $i -lt $len - 1; $i++) {
        $b1 = $bytes[$i]
        $b2 = $bytes[$i + 1]
        if ((($b1 -ge 0xA1 -and $b1 -le 0xFE) -and ($b2 -ge 0xA1 -and $b2 -le 0xFE)) -or
            ($b1 -eq 0x8E -and ($b2 -ge 0xA1 -and $b2 -le 0xDF))) {
            $euc += 2
            $i++
        } elseif ($i -lt $len - 2) {
            $b3 = $bytes[$i + 2]
            if ($b1 -eq 0x8F -and ($b2 -ge 0xA1 -and $b2 -le 0xFE) -and ($b3 -ge 0xA1 -and $b3 -le 0xFE)) {
                $euc += 3
                $i += 2
            }
        }
    }

    for ($i = 0; $i -lt $len - 1; $i++) {
        $b1 = $bytes[$i]
        $b2 = $bytes[$i + 1]
        if ($b1 -ge 0xC0 -and $b1 -le 0xDF -and $b2 -ge 0x80 -and $b2 -le 0xBF) {
            $utf8 += 2
            $i++
        } elseif ($i -lt $len - 2) {
            $b3 = $bytes[$i + 2]
            if ($b1 -ge 0xE0 -and $b1 -le 0xEF -and $b2 -ge 0x80 -and $b2 -le 0xBF -and $b3 -ge 0x80 -and $b3 -le 0xBF) {
                $utf8 += 3
                $i += 2
            }
        }
    }

    # 判定結果に応じて返す
        if ($euc  -gt $sjis -and $euc  -gt $utf8) { return "EUC"   } # EUC-JP 
    elseif ($sjis -gt $euc  -and $sjis -gt $utf8) { return "SJIS"  } # Shift-JIS 
    elseif ($utf8 -gt $euc  -and $utf8 -gt $sjis) { return "UTF8N" } # UTF-8(BOMなし)

    return $null
}

# ------------------------------------------------------------------------------
# Regex
# ------------------------------------------------------------------------------

<#
.SYNOPSIS
    Grep 用の Regex オブジェクトを生成します。

.DESCRIPTION
    正規表現／通常検索を切り替え、
    大文字小文字無視、単語単位検索に対応します。

.PARAMETER Pattern
    検索パターン。

.PARAMETER UseRegex
    正規表現を使用するか。

.PARAMETER IgnoreCase
    大文字小文字を無視するか。

.PARAMETER Word
    単語単位で検索するか。

.OUTPUTS
    System.Text.RegularExpressions.Regex
#>
function Create-Regexp {
    param(
    	[string]$Pattern,
    	[bool]$UseRegex,
    	[bool]$IgnoreCase,
    	[bool]$Word
    )

    # regexOptionsの設定
    $regexOptions  = [System.Text.RegularExpressions.RegexOptions]::None
    if ($IgnoreCase) {

        $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    }
    $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::Compiled

    # patternStringの設定
    if ($UseRegex)   {

        $patternString = $Pattern
    } else {

        $patternString = [System.Text.RegularExpressions.Regex]::Escape($Pattern)
    }
    if ($Word)       { 

        $patternString = "\b$patternString\b"
    }

    # Regexの作成
    $regex = [System.Text.RegularExpressions.Regex]::new($patternString, $regexOptions)
	
	return $regex
}