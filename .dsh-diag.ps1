$ErrorActionPreference = "Continue"
$ws = "C:\Users\Administrator\Desktop\正式项目\源文件\AgentSystem"
Set-Location $ws

Write-Output "=== PWD ==="
(Get-Location).Path

Write-Output "=== GIT REPO? ==="
git rev-parse --is-inside-work-tree 2>&1

Write-Output "=== GIT DIR ==="
git rev-parse --git-dir 2>&1

Write-Output "=== REMOTES ==="
git remote -v 2>&1

Write-Output "=== CURRENT BRANCH ==="
git branch --show-current 2>&1

Write-Output "=== LOCAL BRANCHES ==="
git branch -a 2>&1

Write-Output "=== LOG ==="
git log --oneline -5 2>&1

Write-Output "=== STATUS COUNT ==="
$st = git status --porcelain 2>&1
if ($st -is [array]) { Write-Output ("changed entries: " + $st.Count) } else { Write-Output ("status line: " + $st) }
Write-Output "--- first 40 status ---"
$st | Select-Object -First 40

Write-Output "=== USER CONFIG ==="
git config user.name 2>&1
git config user.email 2>&1

Write-Output "=== GLOBAL USER CONFIG ==="
git config --global user.name 2>&1
git config --global user.email 2>&1

Write-Output "=== TOP LEVEL ==="
Get-ChildItem -Force | Select-Object Mode, Name | Format-Table -AutoSize | Out-String -Width 200

Write-Output "=== .gitignore head ==="
if (Test-Path ".gitignore") { Get-Content ".gitignore" -TotalCount 40 } else { Write-Output "NO .gitignore" }

Write-Output "=== SIZE ==="
$files = Get-ChildItem -Recurse -File -Force -ErrorAction SilentlyContinue
$total = ($files | Measure-Object -Property Length -Sum).Sum
Write-Output ("total files: " + $files.Count + "  total MB: " + [math]::Round($total/1MB,2))

Write-Output "=== LARGE FILES > 30MB ==="
$files | Where-Object { $_.Length -gt 30MB } | Sort-Object Length -Descending | Select-Object -First 30 @{n='MB';e={[math]::Round($_.Length/1MB,1)}}, FullName | Format-Table -AutoSize | Out-String -Width 250

Write-Output "=== ENV / SECRET CANDIDATES ==="
$files | Where-Object { $_.Name -match '^\.env' -or $_.Name -match 'secret|credential|token' } | Select-Object -First 40 @{n='KB';e={[math]::Round($_.Length/1KB,1)}}, FullName | Format-Table -AutoSize | Out-String -Width 250

Write-Output "=== .git SIZE ==="
if (Test-Path ".git") {
  $g = Get-ChildItem ".git" -Recurse -File -Force -ErrorAction SilentlyContinue
  Write-Output ("git files: " + $g.Count + "  MB: " + [math]::Round((($g | Measure-Object Length -Sum).Sum)/1MB,2))
}

Write-Output "=== EXISTING TOKEN IN CONFIG? ==="
if (Test-Path ".git\config") {
  (Get-Content ".git\config") -replace '(ghp_|github_pat_)[A-Za-z0-9_]+','<REDACTED>'
} else { Write-Output "no .git/config" }

Write-Output "=== DONE ==="
