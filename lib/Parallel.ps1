<#
.SYNOPSIS
    RunspacePool を用いた並列 Grep 実行エンジンです。

.DESCRIPTION
    指定されたファイル一覧に対して、
    RunspacePool を利用した並列処理を行います。

    各 Runspace は以下の特徴を持ちます。
    - ファイル単位で完全に独立して処理
    - 共有オブジェクトは SharedArgs のみ（読み取り専用）
    - 出力・ログは一時ファイルに書き込み、親側で統合

    これにより以下を実現します。
    - スレッドセーフな設計
    - 並列実行時の競合回避
    - 大量ファイル処理時の安定性確保

.PARAMETER Files
    Grep 対象となるファイル一覧。

.PARAMETER WorkerScript
    各ファイルを処理するための ScriptBlock。
    -FilePath
    -OutputFile
    -LogFile
    -SharedArgs
    を受け取る必要があります。

.PARAMETER SharedArgs
    すべての Runspace に共有される設定オブジェクト。
    読み取り専用で使用することを前提とします。

.OUTPUTS
    System.Int32
    一致した行数（マッチ件数）。

.NOTES
    - PowerShell 5.1 対応
    - RunspacePool ベースの並列処理
    - SharedArgs は NO MUTATION 前提
#>

Set-StrictMode -Version Latest

function Invoke-GrepParallel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$Files,

        [Parameter(Mandatory)]
        [ScriptBlock]$WorkerScript,

        [Parameter(Mandatory)]
		[PSCustomObject]$SharedArgs
    )

	# 対象ファイルが存在しない場合は何もしない
    if ($Files.Count -eq 0) { return }

    #----------------------------------------
    # RunspacePool
    #----------------------------------------
    # 最小 1、最大 Parallel 数で RunspacePool を作成
    $pool = [RunspaceFactory]::CreateRunspacePool(1, $SharedArgs.Parallel)
    $pool.Open()

    # 実行中ジョブ管理用
	$jobs  = [System.Collections.ArrayList]::new()

    # バッチサイズ（Runspace 数の 2 倍）
    # Runspace 枯渇を防ぎつつ効率を上げるための設計
	$batchSize     = [Math]::Floor($SharedArgs.Parallel * 2)
	$totalJobs     = $Files.Count
	$completedJobs = 0
	$matchCount    = 0
	$percent       = 0

    # ------------------------------------------------------------------
    # ファイルをバッチ単位で処理
    # ------------------------------------------------------------------
	for ($i = 0; $i -le $Files.Count; $i += $batchSize) {

		$batchFiles = $Files[$i..([Math]::Min($i + $batchSize -1 , $Files.Count - 1))]
		$jobs       = [System.Collections.ArrayList]::new()

		# --------------------------------------------------------------------------
		# Runspace 実行
		# --------------------------------------------------------------------------
		foreach ($file in $batchFiles) {

			$ps = [Powershell]::Create()
			$ps.RunspacePool = $pool

            # 各 Runspace 用の一時ファイル
			$tempLog = New-TempLogFile    -FolderPath $SharedArgs.WorkCurDir
			$tempOut = New-TempOutputFile -FolderPath $SharedArgs.WorkCurDir

            # WorkerScript 実行ラッパー
			$ps.AddScript({
				param(
					[string]$FilePath,
					[string]$OutputFile,
					[string]$LogFile,
					[PSCustomObject]$SharedArgs,
					[ScriptBlock]$WorkerScript
				)

				try {
					& $WorkerScript -FilePath	$FilePath	`
									-OutputFile	$OutputFile	`
									-LogFile	$LogFile	`
									-SharedArgs	$SharedArgs
				} catch {
                    # Runspace 内例外は標準出力に流す
					Write-Output $_
				}
			}) | Out-Null

			# パラメータ設定
			$ps.AddParameter('FilePath'            , $file.FullName ) | Out-Null
			$ps.AddParameter('OutputFile'          , $tempOut       ) | Out-Null
			$ps.AddParameter('LogFile'             , $tempLog       ) | Out-Null
			$ps.AddParameter('SharedArgs'          , $sharedArgs    ) | Out-Null
			$ps.AddParameter('WorkerScript'        , $workerScript  ) | Out-Null

			# 非同期実行開始
			$asyncResult	= $ps.BeginInvoke()

			# ジョブ管理オブジェクト
			$jobObj			= [PSCustomObject]@{
				PS			= $ps
				Async		= $asyncResult
				LogFile		= $tempLog
				OutputFile	= $tempOut
			}

			$jobs.Add($jobObj) | Out-Null
		}

		# --------------------------------------------------------------------------
		# Runspace 完了待ち & 結果統合
		# --------------------------------------------------------------------------
		foreach ($job in $jobs) {

            # Runspace 完了待ち
			$results = $job.PS.EndInvoke($job.Async)

            # Runspace 標準出力
			foreach ($line in $results) {
			    Write-Host $line
			}

			$completedJobs++

            # デバッグログ統合
			if (Test-Path $job.LogFile){
				if ($SharedArgs.IsDebug){
					try {
						$reader = [System.IO.StreamReader]::new($job.LogFile, $SharedArgs.OutputEncoding)
						while (($line = $reader.ReadLine()) -ne $null) {
							Merge-DebugLog $line
						}
						$reader.Dispose()
					} catch {}
				}
				Remove-Item $job.LogFile
			}

			# 出力ファイル統合
			if (Test-Path $job.OutputFile){
				try {
					$reader = [System.IO.StreamReader]::new($job.OutputFile, $SharedArgs.OutputEncoding)
					while (($line = $reader.ReadLine()) -ne $null) {
						Write-OutputFile $line
						$matchCount++
					}
					$reader.Dispose()
					Remove-Item $job.OutputFile
				} catch {}
			}

			# Runspace 解放
			$job.PS.Dispose()

			# 進捗表示
			if (-not $SharedArgs.Quiet) {
				$percent = ($completedJobs / $totalJobs) * 100
				Show-ProgressBar -Percent $percent -StartTime $SharedArgs.StartTime
			}
		}
	}

    # ------------------------------------------------------------------
    # RunspacePool 終了処理
    # ------------------------------------------------------------------
	$pool.Close()
	$pool.Dispose()
	
	return $matchCount
}
