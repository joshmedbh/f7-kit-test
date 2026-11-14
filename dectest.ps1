param([string]$KeyHex, [string]$BlobHex, [string]$LsPath, [string]$Expect)
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'payload.ps1'
$all = Get-Content -LiteralPath $src -Raw
$m = [regex]::Match($all, '(?s)# --- decifra credenciais.*?\$sqlite = Join-Path \$PSScriptRoot ''sqlite3\.exe''')
if (-not $m.Success) { throw 'bloco de decifragem nao encontrado' }
Invoke-Expression ($m.Value.Replace('$PSScriptRoot', "'" + $PSScriptRoot + "'"))

"gcm_mode=$script:GcmMode"
if (-not $script:GcmMode) { throw 'BouncyCastle nao carregou' }
$k = Hex-ToBytes $KeyHex
if ($LsPath) {
  $mk = Get-MasterKey $LsPath
  if (-not $mk) { throw 'MASTERKEY FALHOU (DPAPI)' }
  $mkHex = (($mk | ForEach-Object { $_.ToString('x2') }) -join '')
  "masterkey_ok=" + ($mkHex -eq $KeyHex)
  if ($mkHex -ne $KeyHex) { throw 'MASTERKEY DIVERGIU' }
}
$b = Hex-ToBytes $BlobHex
$v = Dec-Bytes $k $b ([Text.Encoding]::UTF8.GetBytes('https://exemplo.test'))
if (-not $v) { throw ('GCM FALHOU st=0x{0:x8}' -f [Gcm]::LastStatus) }
$got = [Text.Encoding]::UTF8.GetString($v)
"plain=$got"
"gcm_ok=" + ($got -eq $Expect)
if ($got -ne $Expect) { throw 'GCM DIVERGIU' }
