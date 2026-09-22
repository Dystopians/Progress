$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
public static class B01PngInspector {
 public static long[] Inspect(string path) {
  using (var b = new Bitmap(path)) {
   long clear=0,partial=0,solid=0,edge=0;
   int minX=b.Width,minY=b.Height,maxX=-1,maxY=-1;
   for(int y=0;y<b.Height;y++) for(int x=0;x<b.Width;x++){
    byte a=b.GetPixel(x,y).A;
    if(a==0)clear++;else if(a==255)solid++;else partial++;
    if(a>0&&(x==0||y==0||x==b.Width-1||y==b.Height-1))edge++;
    if(a>=16){minX=Math.Min(x,minX);minY=Math.Min(y,minY);maxX=Math.Max(x,maxX);maxY=Math.Max(y,maxY);}
   }
   return new long[]{b.Width,b.Height,clear,partial,solid,edge,minX,minY,maxX,maxY};
  }
 }
}
'@
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
$manifestPath = Join-Path $PSScriptRoot 'manifest.json'
$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
foreach($asset in $manifest.assets) {
 $file = Join-Path $root $asset.file
 $v = [B01PngInspector]::Inspect($file)
 $asset | Add-Member -Force NoteProperty width $v[0]
 $asset | Add-Member -Force NoteProperty height $v[1]
 $asset | Add-Member -Force NoteProperty bytes (Get-Item -LiteralPath $file).Length
 $asset | Add-Member -Force NoteProperty sha256 (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToLowerInvariant()
 $asset | Add-Member -Force NoteProperty alpha ([ordered]@{transparent_pixels=$v[2];partial_pixels=$v[3];opaque_pixels=$v[4];nontransparent_edge_pixels=$v[5];content_bounds_alpha16=@($v[6],$v[7],$v[8],$v[9])})
 if($v[2] -eq 0 -or $v[4] -eq 0){throw "Alpha validation failed: $($asset.id)"}
 if($v[5] -ne 0){Write-Warning "Nonzero edge alpha: $($asset.id), $($v[5]) pixels; visual inspection required."}
 if(!(Test-Path -LiteralPath (Join-Path $root $asset.prompt))){throw "Prompt missing: $($asset.id)"}
}
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
$manifest.assets | Select-Object id,width,height,bytes,@{n='EdgeAlpha';e={$_.alpha.nontransparent_edge_pixels}} | Format-Table
"PASS: $($manifest.assets.Count) PNGs with transparency, prompt sources and hashes; review edge warnings separately."
