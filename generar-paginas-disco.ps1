# =============================================================================
#  GENERAR PAGINAS DE VISTA PREVIA POR DISCO
#
#  Crea una paginita HTML minima por cada disco activo (carpeta d/<id>.html)
#  con las etiquetas og:title / og:description / og:image de ESE disco
#  puntual, para que al compartir el link por WhatsApp se vea la foto y el
#  precio en vez de un link pelado. Un humano que la abre rebota automatico
#  al catalogo real (/?id=...).
#
#  La llama actualizar.ps1 despues de cada actualizacion (asi se regeneran
#  solas). Tambien se puede correr suelta para regenerar desde el JSON
#  actual sin tocar Excel: . .\generar-paginas-disco.ps1
#                          $records = Get-Content data\records.json -Raw | ConvertFrom-Json
#                          Sync-DiscPages -Records $records -OutDir "d"
# =============================================================================

function Escape-Html([string]$s) {
    if (-not $s) { return '' }
    return $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
}

function Sync-DiscPages {
    param(
        [Parameter(Mandatory)] $Records,
        [Parameter(Mandatory)] [string] $OutDir
    )

    New-Item -ItemType Directory -Force $OutDir | Out-Null

    $activeIds = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($r in $Records) {
        if (-not $r.url -or $r.url -notmatch 'MLA-?(\d+)') { continue }
        $mlid = $Matches[1]
        $activeIds.Add($mlid) | Out-Null

        $nombre = if ($r.artista -and ($r.album -or $r.titulo)) {
            "$($r.artista) — $(if ($r.album) { $r.album } else { $r.titulo })"
        } elseif ($r.titulo) { $r.titulo } else { "Disco de vinilo" }

        $precioStr = if ($r.precio) { '$ ' + ('{0:N0}' -f [int]$r.precio) -replace ',', '.' } else { '' }
        $desc = "Respira Ventas — Discos de vinilo, Rosario." + $(if ($precioStr) { " $precioStr" } else { '' })
        $img  = if ($r.imagenes -and $r.imagenes.Count -gt 0) { $r.imagenes[0] } else { '' }

        $escNombre = Escape-Html $nombre
        $escDesc   = Escape-Html $desc
        $escImg    = Escape-Html $img

        $imgTag = if ($escImg) { "<meta property=`"og:image`" content=`"$escImg`">" } else { '' }

        $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>$escNombre — Respira Ventas</title>
<meta name="robots" content="noindex">
<meta property="og:title" content="$escNombre">
<meta property="og:description" content="$escDesc">
$imgTag
<meta property="og:url" content="https://respiraventas.com.ar/d/$mlid.html">
<meta property="og:type" content="product">
<script>location.replace('/?id=$mlid');</script>
</head>
<body>
<p><a href="/?id=$mlid">Ver disco en Respira Ventas &rarr;</a></p>
</body>
</html>
"@
        [System.IO.File]::WriteAllText((Join-Path $OutDir "$mlid.html"), $html, [System.Text.Encoding]::UTF8)
    }

    # Limpieza: borra paginas de discos que ya no estan activos (dados de baja)
    $borrados = 0
    Get-ChildItem $OutDir -Filter "*.html" -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not $activeIds.Contains($_.BaseName)) {
            Remove-Item $_.FullName -Force
            $borrados++
        }
    }

    return @{ Generadas = $activeIds.Count; Borradas = $borrados }
}
