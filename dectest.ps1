param([string]$KeyHex, [string]$BlobHex, [string]$LsPath, [string]$Expect)
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'payload.ps1'
$all = Get-Content -LiteralPath $src -Raw
$m = [regex]::Match($all, '(?s)# --- decifra credenciais.*?\$sqlite = Join-Path \$PSScriptRoot ''sqlite3\.exe''')
if (-not $m.Success) { throw 'bloco de decifragem nao encontrado' }
Invoke-Expression ($m.Value.Replace('$PSScriptRoot', "'" + $PSScriptRoot + "'"))

$k = Hex-ToBytes $KeyHex
if ($LsPath) {
  $mk = Get-MasterKey $LsPath
  $mkHex = (($mk | ForEach-Object { $_.ToString('x2') }) -join '')
  "masterkey_ok=" + ($mkHex -eq $KeyHex)
}
$b = Hex-ToBytes $BlobHex
$v = Dec-Bytes $k $b ([Text.Encoding]::UTF8.GetBytes('https://exemplo.test'))
if (-not $v) { throw 'GCM FALHOU' }
$got = [Text.Encoding]::UTF8.GetString($v)
"plain=$got"
"gcm_ok=" + ($got -eq $Expect)
