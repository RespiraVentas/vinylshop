# =============================================================================
#  GENERAR PAGINAS DE ARTISTA Y DE DECADA
#
#    /artista/<slug>.html   "Vinilos de Charly Garcia"
#    /decada/<anio>.html    "Vinilos de los 70"
#
#  Son paginas de listado que le dan a Google algo que indexar para busquedas
#  por artista o por epoca, que tienen mas volumen que un album puntual.
#  Se generan desde data/records.json, igual que las fichas, y se regeneran
#  solas en cada actualizacion de catalogo: si entra un artista nuevo y llega
#  a 3 discos, su pagina aparece sin trabajo manual.
#
#  IMPORTANTE - este archivo NO se vale por si mismo: usa los helpers de
#  generar-fichas.ps1 (ConvertTo-Slug, Escape-Html, Get-PrecioSitio,
#  Format-Pesos, Write-ArchivoSeguro, Get-FichaNombre...). Hay que cargar
#  primero generar-fichas.ps1 y despues este.
#
#  POLITICA: una pagina de artista, una vez creada, NO se borra nunca.
#  Si el artista baja de 3 discos porque se vendieron, la pagina sigue viva
#  con los que queden. Si se queda en cero, muestra "ahora no tenemos".
#  Asi Google nunca se topa con una pagina que desaparecio.
# =============================================================================

$MIN_DISCOS_ARTISTA = 3        # a partir de cuantos discos se crea la pagina
$DECADAS_VALIDAS    = @(1950, 1960, 1970, 1980, 1990)

# Colecciones que se detectan por el TITULO de la publicacion, no por un
# atributo. Son nichos con busqueda propia (compilados, maxi singles) donde
# el campo "artista" dice "Varios Artistas", o sea que no sirve: la unica
# fuente del dato es el titulo, donde Pablo lo escribe a proposito.
# Para sumar una coleccion nueva (por ejemplo "Promo"), se agrega acá.
$COLECCIONES_TITULO = @(
    @{
        slug     = 'compilados'
        patron   = '(?i)\bcompilado'
        titulo   = 'Compilados en vinilo'
        chip     = 'Compilados'
        encabez  = 'Tenemos <strong>{n} compilados</strong> en vinilo'
        busqueda = 'compilado'
    },
    @{
        slug     = 'maxis'
        patron   = '(?i)\bmaxi\b'
        titulo   = 'Maxi singles en vinilo'
        chip     = 'Maxi singles'
        encabez  = 'Tenemos <strong>{n} maxi singles</strong> en vinilo'
        busqueda = 'maxi'
    }
)

# Artistas que son cajones de sastre, no artistas. No merecen pagina propia.
$ARTISTAS_EXCLUIDOS = @(
    'varios artistas', 'varios', 'varios interpretes', 'varios intérpretes',
    'various', 'varios artistas - compilado', 'compilado', 'varios artistas compilado'
)

# ── Helpers ──────────────────────────────────────────────────────────────────

function Get-ArtistaClave($rec) {
    if (-not $rec.artista) { return $null }
    return $rec.artista.Trim().ToLowerInvariant()
}

function Test-ArtistaValido([string]$clave) {
    if (-not $clave) { return $false }
    if ($ARTISTAS_EXCLUIDOS -contains $clave) { return $false }
    # Nombres que arrancan con "varios" son compilados
    if ($clave -match '^varios\b') { return $false }
    return $true
}

# Devuelve las colecciones a las que pertenece un disco segun su titulo.
# Es la MISMA lista que genera las paginas, asi que el filtro del catalogo y
# las paginas nunca pueden mostrar cosas distintas. Sumar una coleccion nueva
# en $COLECCIONES_TITULO la hace aparecer en los dos lados a la vez.
function Get-TiposDe($rec) {
    $t = @()
    foreach ($col in $COLECCIONES_TITULO) {
        if ("$($rec.titulo)" -match $col.patron) { $t += $col.chip }
    }
    return $t
}

function Get-DecadaDe($rec) {
    $a = "$($rec.anio)".Trim()
    if ($a -notmatch '^\d{4}$') { return $null }
    return [int]([math]::Floor([int]$a / 10) * 10)
}

# ── Tarjetas de disco reutilizables ──────────────────────────────────────────

function Build-HubCards($discos, $rutas) {
    $cards = foreach ($x in $discos) {
        $xid = Get-DiscoId $x
        if (-not $xid -or -not $rutas.ContainsKey($xid)) { continue }
        $img = if ($x.imagenes -and $x.imagenes.Count -gt 0) { Escape-Html $x.imagenes[0] } else { '' }
        $alt = Escape-Html "$($x.artista) - $($x.album)"
        $anio = if ("$($x.anio)".Trim()) { "<span class=`"h-card-anio`">$(Escape-Html "$($x.anio)".Trim())</span>" } else { '' }
        @"
      <a class="h-card" href="/disco/$($rutas[$xid])">
        <img src="$img" alt="$alt" loading="lazy">
        <div class="h-card-artista">$(Escape-Html $x.artista)</div>
        <div class="h-card-album">$(Escape-Html $x.album)</div>
        <div class="h-card-fila"><span class="h-card-precio">$(Format-Pesos (Get-PrecioSitio ([double]$x.precio)))</span>$anio</div>
      </a>
"@
    }
    return ($cards -join "`n")
}

# Arma un parrafo de presentacion con datos REALES del artista o la decada.
# No es texto plantilla: cambia segun los sellos, los anios y los generos que
# haya de verdad. Con 285 paginas, un texto identico en todas seria contenido
# duplicado y Google lo castiga.
function Build-IntroDatos($discos, [string]$sujeto, [string]$encabezado = $null) {
    $n = @($discos).Count
    $anios = @($discos | ForEach-Object { "$($_.anio)".Trim() } | Where-Object { $_ -match '^\d{4}$' } | ForEach-Object { [int]$_ })
    $sellos = @($discos | ForEach-Object { "$($_.compania)".Trim() } | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object { $_.Name })
    $generos = @($discos | ForEach-Object { "$($_.genero)".Trim() } | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First 2 | ForEach-Object { $_.Name })
    $origenes = @($discos | ForEach-Object { "$($_.origen)".Trim() } | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First 1 | ForEach-Object { $_.Name })

    $t = if ($encabezado) { $encabezado -replace '\{n\}', "$n" }
         elseif ($n -eq 1) { "Tenemos <strong>1 disco</strong> de $sujeto en vinilo" }
         else { "Tenemos <strong>$n discos</strong> de $sujeto en vinilo" }

    if ($anios.Count -gt 0) {
        $min = ($anios | Measure-Object -Minimum).Minimum
        $max = ($anios | Measure-Object -Maximum).Maximum
        if ($min -eq $max) { $t += ", del $min" } else { $t += ", editados entre $min y $max" }
    }
    $t += "."

    if ($sellos.Count -gt 0) {
        $lista = if ($sellos.Count -eq 1) { $sellos[0] } else { ($sellos[0..($sellos.Count-2)] -join ', ') + " y " + $sellos[-1] }
        $t += " Sellos: $(Escape-Html $lista)."
    }
    if ($generos.Count -gt 0) {
        $lg = if ($generos.Count -eq 1) { $generos[0] } else { ($generos -join ' y ') }
        $t += " Género: $(Escape-Html $lg)."
    }
    if ($origenes.Count -gt 0) {
        $t += " Ediciones mayormente de $(Escape-Html $origenes[0])."
    }
    $t += " Describimos el estado de cada disco con la escala Goldmine y hacemos envíos a todo el país y al exterior."
    return $t
}

# ── Armado de una pagina de listado ──────────────────────────────────────────

function Build-HubHtml {
    param(
        [string]$titulo,        # "Vinilos de Charly García"
        [string]$tituloPag,     # el <title>
        [string]$metaDesc,
        [string]$canonical,
        [string]$intro,         # parrafo de texto propio de esta pagina
        [string]$cardsHtml,
        [string]$migaNombre,
        [string]$extraHtml = '',
        [string]$ldJson = ''
    )

    $ldTag = if ($ldJson) { "<script type=`"application/ld+json`">$ldJson</script>" } else { '' }

    return @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$(Escape-Html $tituloPag)</title>
<meta name="description" content="$(Escape-Html $metaDesc)">
<meta name="robots" content="index, follow">
<link rel="canonical" href="$canonical">
<link rel="icon" href="/assets/logo-icon.jpg">
<meta property="og:type" content="website">
<meta property="og:title" content="$(Escape-Html $titulo)">
<meta property="og:description" content="$(Escape-Html $metaDesc)">
<meta property="og:url" content="$canonical">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=DM+Sans:opsz,wght@9..40,400;9..40,500;9..40,600;9..40,700;9..40,800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/ficha.css?v=4">
$ldTag
</head>
<body>

<header class="f-header">
  <div class="f-header-inner">
    <a class="f-logo" href="/">
      <img src="/assets/logo-icon.jpg" alt="Respira Ventas">
      <span>
        <span class="f-logo-name">Respira Ventas</span>
        <span class="f-logo-sub">Discos de Vinilo - Rosario</span>
      </span>
    </a>
    <a class="f-header-cta" href="/">Ver catálogo completo</a>
  </div>
</header>

<nav class="f-breadcrumb">
  <a href="/">Catálogo</a><span>/</span><span style="opacity:1;margin:0">$(Escape-Html $migaNombre)</span>
</nav>

<main class="f-main">
  <h1 class="h-titulo">$(Escape-Html $titulo)</h1>
  <p class="h-intro">$intro</p>

  <div class="h-grid">
$cardsHtml
  </div>
$extraHtml
</main>

<footer class="f-footer">
  <div class="f-footer-inner">
    <span>&copy; Respira Ventas - Discos de Vinilo - Rosario, Argentina</span>
    <span class="f-footer-links">
      <a href="/">Catálogo</a>
      <a href="/colecciones.html">Colecciones</a>
      <a href="https://wa.me/$WA_NUMBER" target="_blank" rel="noopener">WhatsApp</a>
      <a href="mailto:$MAIL_TO">Mail</a>
    </span>
  </div>
</footer>

</body>
</html>
"@
}

# ── Proceso principal ────────────────────────────────────────────────────────

function Sync-Hubs {
    param(
        [Parameter(Mandatory)] $Records,
        [Parameter(Mandatory)] [string] $SiteFolder
    )

    # Agrupar colaboraciones bajo el artista principal antes de nada
    [void](Set-MapaCanonico $Records)

    $dirArt = Join-Path $SiteFolder "artista"
    $dirDec = Join-Path $SiteFolder "decada"
    New-Item -ItemType Directory -Force $dirArt | Out-Null
    New-Item -ItemType Directory -Force $dirDec | Out-Null

    # Rutas de fichas, para enlazar cada disco
    $rutas = @{}
    foreach ($r in $Records) {
        $id = Get-DiscoId $r
        if ($id) { $rutas[$id] = Get-FichaNombre $r }
    }

    # --- Agrupar por artista y por decada ---
    $porArt = @{}
    $porDec = @{}
    foreach ($r in $Records) {
        $ka = Get-ArtistaClave $r
        if (Test-ArtistaValido $ka) {
            # Se agrupa por la direccion (slug), no por el nombre exacto: asi
            # "José Luis Rodríguez" y "Jose Luis Rodriguez" caen en la misma
            # pagina, que es lo correcto porque son el mismo artista. Agrupar
            # por nombre los dejaba peleando por el mismo archivo y uno pisaba
            # al otro.
            $slugArt = Get-ArtistaSlug $r
            if ($slugArt -and $slugArt -ne 'varios-artistas') {
                if (-not $porArt.ContainsKey($slugArt)) { $porArt[$slugArt] = New-Object System.Collections.Generic.List[object] }
                $porArt[$slugArt].Add($r)
            }
        }
        $d = Get-DecadaDe $r
        if ($d -ne $null -and $DECADAS_VALIDAS -contains $d) {
            if (-not $porDec.ContainsKey($d)) { $porDec[$d] = New-Object System.Collections.Generic.List[object] }
            $porDec[$d].Add($r)
        }
    }

    # --- Paginas de artista ya existentes: nunca se borran ---
    $yaExisten = @{}
    Get-ChildItem $dirArt -Filter "*.html" -ErrorAction SilentlyContinue | ForEach-Object {
        $yaExisten[$_.BaseName] = $true
    }

    $urlsArt = New-Object System.Collections.Generic.List[string]
    $nuevas = 0

    foreach ($ka in $porArt.Keys) {
        $discos = @($porArt[$ka] | Sort-Object { [long](Get-DiscoId $_) })
        $slug   = $ka
        # Si el nombre viene escrito de varias formas, gana la mas usada; a
        # igual cantidad, la mas corta. Asi una colaboracion agrupada muestra
        # "Wynton Marsalis" y no "Wynton Marsalis & Eastman Wind Ensemble...".
        $nombre = ($discos | ForEach-Object { $_.artista.Trim() } | Group-Object |
                   Sort-Object @{Expression='Count';Descending=$true}, @{Expression={$_.Name.Length};Descending=$false} |
                   Select-Object -First 1).Name

        # Se crea si llega al minimo, o si la pagina ya existia (no se borra nunca)
        if ($discos.Count -lt $MIN_DISCOS_ARTISTA -and -not $yaExisten.ContainsKey($slug)) { continue }
        if (-not $yaExisten.ContainsKey($slug)) { $nuevas++ }

        $titulo    = "Vinilos de $nombre"
        $tituloPag = "Vinilos de $nombre — $($discos.Count) discos | Respira Ventas"
        $canonical = "$SITE_URL/artista/$slug.html"
        $metaDesc  = "$($discos.Count) discos de $nombre en vinilo, con el estado descripto disco por disco. Envíos a todo el país y al exterior. Respira Ventas, Rosario."
        if ($metaDesc.Length -gt 300) { $metaDesc = $metaDesc.Substring(0, 297) + '...' }

        $ld = [ordered]@{
            '@context' = 'https://schema.org'
            '@type'    = 'CollectionPage'
            'name'     = $titulo
            'url'      = $canonical
            'about'    = [ordered]@{ '@type' = 'MusicGroup'; 'name' = $nombre }
        }
        $ldJson = ($ld | ConvertTo-Json -Depth 5 -Compress).Replace('</', '<\/')

        $html = Build-HubHtml -titulo $titulo -tituloPag $tituloPag -metaDesc $metaDesc `
            -canonical $canonical -intro (Build-IntroDatos $discos $nombre) `
            -cardsHtml (Build-HubCards $discos $rutas) -migaNombre $nombre -ldJson $ldJson

        [void](Write-ArchivoSeguro (Join-Path $dirArt "$slug.html") $html)
        if ($discos.Count -ge $MIN_DISCOS_ARTISTA) { $urlsArt.Add($canonical) }
    }

    # --- Paginas de decada ---
    $urlsDec = New-Object System.Collections.Generic.List[string]
    foreach ($d in ($porDec.Keys | Sort-Object)) {
        $todos = @($porDec[$d] | Sort-Object { -[int]("0" + "$($_.visitas)") })
        $muestra = @($todos | Select-Object -First 60)
        $decNom = "los $(('' + $d).Substring(2))"     # 1970 -> los 70
        $titulo    = "Vinilos de $decNom"
        $tituloPag = "Vinilos de $decNom — $($todos.Count) discos | Respira Ventas"
        $canonical = "$SITE_URL/decada/$d.html"
        $metaDesc  = "$($todos.Count) discos de vinilo editados en $decNom, con el estado descripto disco por disco. Envíos a todo el país y al exterior. Respira Ventas, Rosario."

        $extra = ''
        if ($todos.Count -gt $muestra.Count) {
            $extra = @"
  <p class="h-mas">Mostramos $($muestra.Count) de $($todos.Count) discos de esta década.
  <a href="/?decada=$d">Ver todos en el catálogo &rarr;</a></p>
"@
        }

        $ld = [ordered]@{
            '@context' = 'https://schema.org'
            '@type'    = 'CollectionPage'
            'name'     = $titulo
            'url'      = $canonical
        }
        $ldJson = ($ld | ConvertTo-Json -Depth 5 -Compress).Replace('</', '<\/')

        $html = Build-HubHtml -titulo $titulo -tituloPag $tituloPag -metaDesc $metaDesc `
            -canonical $canonical -intro (Build-IntroDatos $todos "$decNom") `
            -cardsHtml (Build-HubCards $muestra $rutas) -migaNombre $titulo `
            -extraHtml $extra -ldJson $ldJson

        [void](Write-ArchivoSeguro (Join-Path $dirDec "$d.html") $html)
        $urlsDec.Add($canonical)
    }

    # --- Colecciones detectadas por el titulo (compilados, maxis...) ---
    $urlsCol = New-Object System.Collections.Generic.List[string]
    $resumenCol = New-Object System.Collections.Generic.List[string]
    foreach ($col in $COLECCIONES_TITULO) {
        $todos = @($Records | Where-Object { $_.titulo -match $col.patron } | Sort-Object { -[int]("0" + "$($_.visitas)") })
        if ($todos.Count -eq 0) { continue }
        $muestra = @($todos | Select-Object -First 60)

        $canonical = "$SITE_URL/$($col.slug).html"
        $tituloPag = "$($col.titulo) — $($todos.Count) discos | Respira Ventas"
        $metaDesc  = "$($todos.Count) $($col.chip.ToLower()) en vinilo, con el estado descripto disco por disco. Envíos a todo el país y al exterior. Respira Ventas, Rosario."

        $extra = ''
        if ($todos.Count -gt $muestra.Count) {
            $extra = @"
  <p class="h-mas">Mostramos $($muestra.Count) de $($todos.Count).
  <a href="/?tipo=$([Uri]::EscapeDataString($col.chip))">Ver todos en el catálogo &rarr;</a></p>
"@
        }

        $ld = [ordered]@{
            '@context' = 'https://schema.org'; '@type' = 'CollectionPage'
            'name' = $col.titulo; 'url' = $canonical
        }
        $ldJson = ($ld | ConvertTo-Json -Depth 5 -Compress).Replace('</', '<\/')

        $html = Build-HubHtml -titulo $col.titulo -tituloPag $tituloPag -metaDesc $metaDesc `
            -canonical $canonical -intro (Build-IntroDatos $todos '' $col.encabez) `
            -cardsHtml (Build-HubCards $muestra $rutas) -migaNombre $col.chip `
            -extraHtml $extra -ldJson $ldJson

        [void](Write-ArchivoSeguro (Join-Path $SiteFolder "$($col.slug).html") $html)
        $urlsCol.Add($canonical)
        $resumenCol.Add("$($col.chip): $($todos.Count)")
    }

    return @{
        Artistas       = $urlsArt.Count
        ArtistasNuevas = $nuevas
        Decadas        = $urlsDec.Count
        Colecciones    = $resumenCol -join ', '
        UrlsArtista    = $urlsArt
        UrlsDecada     = $urlsDec
        UrlsColeccion  = $urlsCol
    }
}
# Escribe el sitemap de artistas/decadas y reescribe el indice para que
# incluya los tres. Se llama despues de Sync-Fichas, que ya dejo escritos
# sitemap-paginas.xml y sitemap-discos.xml.
function Build-SitemapHubs {
    param([string]$SiteFolder, $Urls)

    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$sb.AppendLine('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">')
    foreach ($u in $Urls) { [void]$sb.AppendLine("  <url><loc>$u</loc></url>") }
    [void]$sb.AppendLine('</urlset>')
    [void](Write-ArchivoSeguro (Join-Path $SiteFolder "sitemap-hubs.xml") $sb.ToString())

    # El indice lo arma una sola funcion, que mira que sitemaps existen
    Build-SitemapIndice -SiteFolder $SiteFolder
}
# Devuelve un mapa  slug -> nombre  de los artistas que TIENEN pagina propia.
# Lo usan tanto Sync-Hubs (para generarlas) como Sync-Fichas y actualizar.ps1
# (para enlazarlas). Tiene que haber una sola definicion de "quien tiene
# pagina", o las fichas enlazarian a paginas que no existen.
function Get-ArtistasConPagina {
    param([Parameter(Mandatory)] $Records, [string] $SiteFolder = $null)

    $porArt = @{}
    foreach ($r in $Records) {
        $ka = Get-ArtistaClave $r
        if (-not (Test-ArtistaValido $ka)) { continue }
        $slug = Get-ArtistaSlug $r
        if (-not $slug -or $slug -eq 'varios-artistas') { continue }
        if (-not $porArt.ContainsKey($slug)) { $porArt[$slug] = New-Object System.Collections.Generic.List[object] }
        $porArt[$slug].Add($r)
    }

    # Paginas que ya existen: cuentan aunque el artista haya bajado de 3 discos
    $yaExisten = @{}
    if ($SiteFolder) {
        $d = Join-Path $SiteFolder "artista"
        Get-ChildItem $d -Filter "*.html" -ErrorAction SilentlyContinue | ForEach-Object { $yaExisten[$_.BaseName] = $true }
    }

    $mapa = @{}
    foreach ($slug in $porArt.Keys) {
        if ($porArt[$slug].Count -lt $MIN_DISCOS_ARTISTA -and -not $yaExisten.ContainsKey($slug)) { continue }
        $mapa[$slug] = ($porArt[$slug] | ForEach-Object { $_.artista.Trim() } | Group-Object |
                        Sort-Object Count -Descending | Select-Object -First 1).Name
    }
    return $mapa
}

# Clave con la que se agrupa un disco por artista en el catalogo.
# Todas las variantes de "Varios" ("Varios Artistas", "Varios intérpretes",
# "Various", "Varios - Fiesta De Cuartetos"...) caen en la misma clave, que es
# lo correcto: no son artistas distintos, es la ausencia de artista.
$SEP_COLAB = '\s+(?:&|/|\+|y|con|feat\.?|featuring)\s+'

# Mapa de nombres compuestos -> artista principal. Se calcula UNA vez sobre
# todo el catalogo con Set-MapaCanonico.
$script:MAPA_CANONICO = $null

function Get-ArtistaSlugBase($rec) {
    if (-not $rec.artista) { return '' }
    $n = $rec.artista.Trim()
    if ($n -match '(?i)^(varios|various)\b') { return 'varios-artistas' }
    $slug = ConvertTo-Slug $n
    if ($slug.Length -gt 70) { $slug = ($slug.Substring(0, 70) -replace '-+$', '') }
    return $slug
}

# Agrupa las colaboraciones bajo el artista principal:
#   "Wynton Marsalis & Eastman Wind Ensemble"  ->  "Wynton Marsalis"
#   "Juan D'Arienzo y su Orquesta Típica"      ->  "Juan D'Arienzo"
#
# La regla es conservadora a proposito: SOLO agrupa si el primer nombre ya
# existe por su cuenta en el catalogo, con un disco propio. Sin esa condicion,
# partir por "y" o "&" fusionaria artistas distintos (por ejemplo "Juan Carlos
# Baglietto" no debe caer en un supuesto "Juan Carlos"). Verificado sobre el
# catalogo del 25/08/2026: 53 discos agrupados, cero fusiones incorrectas.
function Set-MapaCanonico($Records) {
    $solos = @{}
    foreach ($r in $Records) {
        $n = "$($r.artista)".Trim()
        if (-not $n -or ($n -match $SEP_COLAB)) { continue }
        $s = Get-ArtistaSlugBase $r
        if ($s -and $s -ne 'varios-artistas') { $solos[$s] = $true }
    }

    $mapa = @{}
    foreach ($r in $Records) {
        $n = "$($r.artista)".Trim()
        if (-not $n) { continue }
        $sc = Get-ArtistaSlugBase $r
        if (-not $sc -or $mapa.ContainsKey($sc)) { continue }
        if ($sc -ne 'varios-artistas' -and $n -match $SEP_COLAB) {
            $primero = ([regex]::Split($n, $SEP_COLAB))[0].Trim()
            $sp = ConvertTo-Slug $primero
            if ($sp -and $solos.ContainsKey($sp)) { $mapa[$sc] = $sp; continue }
        }
        $mapa[$sc] = $sc
    }
    $script:MAPA_CANONICO = $mapa
    return $mapa
}

function Get-ArtistaSlug($rec) {
    $s = Get-ArtistaSlugBase $rec
    if (-not $s) { return '' }
    if ($script:MAPA_CANONICO -and $script:MAPA_CANONICO.ContainsKey($s)) {
        return $script:MAPA_CANONICO[$s]
    }
    return $s
}

# A donde lleva el nombre del artista cuando se hace clic:
#   - tiene pagina propia            -> /artista/<slug>.html
#   - es "Varios Artistas"           -> el catalogo filtrado (565 discos)
#   - tiene 2 discos y no da pagina  -> el catalogo filtrado (sus 2)
#   - tiene 1 solo disco             -> sin enlace: llevaria al mismo disco
function Get-ArtistaUrl($rec, $mapaArtistas, $conteoPorSlug = $null) {
    $slug = Get-ArtistaSlug $rec
    if (-not $slug) { return '' }

    if ($mapaArtistas -and $mapaArtistas.ContainsKey($slug)) { return "/artista/$slug.html" }
    if ($slug -eq 'varios-artistas') { return "/?artista=varios-artistas" }
    if ($conteoPorSlug -and $conteoPorSlug.ContainsKey($slug) -and $conteoPorSlug[$slug] -ge 2) {
        return "/?artista=$slug"
    }
    return ''
}

# Cuantos discos hay por cada clave de artista. Sirve para decidir cuales
# valen un enlace al catalogo y cuales no.
function Get-ConteoPorArtista($Records) {
    $c = @{}
    foreach ($r in $Records) {
        $s = Get-ArtistaSlug $r
        if (-not $s) { continue }
        if ($c.ContainsKey($s)) { $c[$s]++ } else { $c[$s] = 1 }
    }
    return $c
}