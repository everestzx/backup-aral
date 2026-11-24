param(
    [string]$InputFile = 'test_pptx.pptx',
    [string]$OutputFile = 'test_pptx.pdf'
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $InputFile)) { Write-Error "File not found: $InputFile"; exit 1 }

$inPath  = (Resolve-Path $InputFile).Path
$outPath = if ([IO.Path]::IsPathRooted($OutputFile)) { $OutputFile } else { Join-Path (Get-Location) $OutputFile }
$ppt = $pres = $null
try {
    $ppt  = New-Object -ComObject PowerPoint.Application
    $ppt.Visible = [Microsoft.Office.Core.MsoTriState]::msoTrue
    $pres = $ppt.Presentations.Open(
        $inPath,
        [Microsoft.Office.Core.MsoTriState]::msoTrue,
        [Microsoft.Office.Core.MsoTriState]::msoFalse,
        [Microsoft.Office.Core.MsoTriState]::msoFalse
    )
    $pres.SaveAs($outPath, 32) # 32 = PDF
    $pres.Close()
} finally {
    if ($pres) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($pres) }
    if ($ppt)  { $ppt.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ppt) }
}
if (Test-Path $outPath) { Write-Host "[SUCCESS] Created: $outPath"; exit 0 }
Write-Error "[FAILURE] PDF not created: $outPath"; exit 1
