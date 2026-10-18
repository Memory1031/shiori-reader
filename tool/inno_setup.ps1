param([string]$Destination = (Join-Path $PSScriptRoot '../.tooling/inno-6.7.3'))
$ErrorActionPreference = 'Stop'
$Destination = [IO.Path]::GetFullPath($Destination)
$compiler = Join-Path $Destination 'ISCC.exe'
if (!(Test-Path -LiteralPath $compiler)) {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $download = Join-Path $Destination 'innosetup-6.7.3.exe'
    Invoke-WebRequest 'https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-6.7.3.exe' -OutFile $download
    if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne '9C73C3BAE7ED48D44112A0F48E66742C00090BDB5BEF71D9D3C056C66E97B732') {
        throw 'Inno Setup download digest mismatch'
    }
    $process = Start-Process -FilePath $download -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER', '/NOICONS', ('/DIR="' + $Destination + '"')) -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw 'Inno Setup installation failed' }
}
if ((Get-FileHash -LiteralPath $compiler -Algorithm SHA256).Hash -ne '0A8757031B33777E4C9CBFFEE40F11A5062B36D25CBE144C1DB73B6102B80AD7') { throw 'Unexpected Inno Setup compiler' }
Write-Output $compiler
