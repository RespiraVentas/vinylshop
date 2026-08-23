# =============================================================================
#  GENERAR FICHAS DE DISCO  (/disco/<id>-<artista>-<album>.html)
#
#  Una pagina HTML real e indexable por disco, generada desde data/records.json.
#  Es la Fase 1 del proyecto SEO.
#
#  Politica de discos vendidos (aprobada 22/08/2026):
#    cuando un disco desaparece del catalogo, su ficha NO se borra: queda
#    marcada "Vendido", con noindex, fuera del sitemap, con enlaces a discos
#    parecidos y un boton de WhatsApp para pedir aviso si entra otra copia.
#    Nunca 404, nunca redirecciones (el hosting no las soporta bien).
#
#  IMPORTANTE: este script solo LEE data/records.json. Nunca lo modifica.
#  El unico archivo de datos que escribe es data/vendidos.json (registro
#  propio de discos dados de baja).
#
#  Uso desde actualizar.ps1 (automatico) o suelto para regenerar:
#     . .\generar-fichas.ps1
#     $r = Get-Content data\records.json -Raw -Encoding UTF8 | ConvertFrom-Json
#     Sync-Fichas -Records $r -SiteFolder (Get-Location).Path
# =============================================================================

$SITE_URL  = "https://respiraventas.com.ar"
$WA_NUMBER = "5493416068888"
$MAIL_TO   = "revistarespiraok@gmail.com"

# ── Helpers ──────────────────────────────────────────────────────────────────

function ConvertTo-Slug([string]$s) {
    if (-not $s) { return "" }
    # Quita acentos: descompone y elimina las marcas diacriticas
    $norm = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $norm.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    $out = $sb.ToString().ToLowerInvariant()
    $out = $out -replace '[^a-z0-9]+', '-'
    $out = $out -replace '^-+|-+$', ''
    return $out
}

function Escape-Html([string]$s) {
    if (-not $s) { return '' }
    return $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
}

function Format-Pesos($n) {
    if (-not $n) { return '' }
    return '$ ' + (('{0:N0}' -f [int]$n) -replace ',', '.')
}

# Separa las lineas de condicion (Disco:, Tapa:, etc.) del texto descriptivo
function Split-Descripcion([string]$desc) {
    $cond = @()
    $rest = @()
    $patron = '^(disco|tapa|insert|vinilo|estado|funda)\s*:'
    foreach ($line in ($desc -split "`n")) {
        $l = $line.Trim()
        if ($l -match $patron) {
            $i = $l.IndexOf(':')
            $cond += @{ label = $l.Substring(0, $i).Trim(); value = $l.Substring($i + 1).Trim() }
        } else {
            $rest += $l
        }
    }
    return @{
        Condicion = $cond
        Texto     = (($rest -join "`n") -replace '^\s+', '').Trim()
    }
}

function Get-DiscoId($rec) {
    if ($rec.url -match 'MLA-?(\d+)') { return $Matches[1] }
    return $null
}

function Get-FichaSlug($rec) {
    $partes = @()
    if ($rec.artista) { $partes += (ConvertTo-Slug $rec.artista) }
    if ($rec.album)   { $partes += (ConvertTo-Slug $rec.album) }
    $slug = ($partes | Where-Object { $_ }) -join '-'
    if (-not $slug) { $slug = ConvertTo-Slug $rec.titulo }
    if (-not $slug) { $slug = 'disco' }
    if ($slug.Length -gt 60) {
        $slug = $slug.Substring(0, 60) -replace '-+$', ''
    }
    return $slug
}

function Get-FichaNombre($rec) {
    $id = Get-DiscoId $rec
    if (-not $id) { return $null }
    return "$id-$(Get-FichaSlug $rec).html"
}

# Icono de WhatsApp (inline, para no depender de archivos externos)
$WA_SVG = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z"/></svg>'
$MAIL_SVG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="4" width="20" height="16" rx="2"/><path d="M2 7l10 7 10-7"/></svg>'

# ── Discos relacionados ──────────────────────────────────────────────────────

function Get-Relacionados($rec, $porArtista, $porGenero, $rutas, $cantidad = 5) {
    $id = Get-DiscoId $rec
    $elegidos = New-Object System.Collections.Generic.List[object]
    $usados = New-Object System.Collections.Generic.HashSet[string]
    [void]$usados.Add($id)

    # Nivel 1: mismo artista
    $claveArt = ($rec.artista + '').ToLowerInvariant().Trim()
    if ($claveArt -and $porArtista.ContainsKey($claveArt)) {
        foreach ($o in $porArtista[$claveArt]) {
            if ($elegidos.Count -ge 3) { break }
            $oid = Get-DiscoId $o
            if ($oid -and -not $usados.Contains($oid)) { [void]$usados.Add($oid); $elegidos.Add($o) }
        }
    }
    # Nivel 2: mismo genero
    $claveGen = ($rec.genero + '').Trim()
    if ($claveGen -and $porGenero.ContainsKey($claveGen)) {
        foreach ($o in $porGenero[$claveGen]) {
            if ($elegidos.Count -ge $cantidad) { break }
            $oid = Get-DiscoId $o
            if ($oid -and -not $usados.Contains($oid)) { [void]$usados.Add($oid); $elegidos.Add($o) }
        }
    }
    return $elegidos
}

function Build-RelacionadosHtml($relacionados, $rutas) {
    if (-not $relacionados -or $relacionados.Count -eq 0) { return '' }
    $cards = foreach ($x in $relacionados) {
        $xid = Get-DiscoId $x
        if (-not $rutas.ContainsKey($xid)) { continue }
        $href  = "/disco/$($rutas[$xid])"
        $img   = if ($x.imagenes -and $x.imagenes.Count -gt 0) { Escape-Html $x.imagenes[0] } else { '' }
        $alt   = Escape-Html "$($x.artista) - $($x.album)"
        $art   = Escape-Html $x.artista
        $alb   = Escape-Html $x.album
        $prec  = Format-Pesos $x.precio
        @"
      <a class="f-rel-card" href="$href">
        <img src="$img" alt="$alt" loading="lazy">
        <div class="f-rel-artist">$art</div>
        <div class="f-rel-album">$alb</div>
        <div class="f-rel-price">$prec</div>
      </a>
"@
    }
    if (-not $cards) { return '' }
    return @"
  <section class="f-section">
    <h2 class="f-section-title">Discos relacionados</h2>
    <div class="f-related-grid">
$($cards -join "`n")
    </div>
  </section>
"@
}

# ── Render de una ficha ──────────────────────────────────────────────────────

function Build-FichaHtml {
    param($rec, [string]$id, [string]$archivo, [bool]$vendido, $relacionadosHtml)

    $artista = if ($rec.artista) { $rec.artista } else { 'Artista desconocido' }
    $album   = if ($rec.album)   { $rec.album }   else { $rec.titulo }
    $anio    = "$($rec.anio)".Trim()
    $genero  = "$($rec.genero)".Trim()
    $origen  = "$($rec.origen)".Trim()
    $sello   = "$($rec.compania)".Trim()
    $precio  = [int]$rec.precio
    $directo = if ($precio) { [math]::Round($precio * 0.9) } else { 0 }
    $ahorro  = $precio - $directo

    $partes = Split-Descripcion "$($rec.desc)"
    $condicion = $partes.Condicion
    $textoDesc = $partes.Texto

    $condResumen = ($condicion | ForEach-Object { "$($_.label) $($_.value)" }) -join ', '

    # --- Titulo y descripcion para buscadores ---
    $tituloPag = "$artista — $album"
    if ($anio) { $tituloPag += " · Vinilo $anio" }
    $tituloPag += " | Respira Ventas"

    $metaPartes = @("Vinilo original")
    if ($sello)  { $metaPartes += "sello $sello" }
    if ($origen) { $metaPartes += "edición $origen" }
    if ($anio)   { $metaPartes += $anio }
    if ($condResumen) { $metaPartes += "estado $condResumen" }
    $metaDesc = "$artista — $album. " + ($metaPartes -join ', ') + ". "
    $metaDesc += if ($vendido) { "Vendido — consultanos si entra otra copia." }
                 else { "Comprando directo por WhatsApp pagás 10% menos que en Mercado Libre." }
    if ($metaDesc.Length -gt 300) { $metaDesc = $metaDesc.Substring(0, 297) + '...' }

    # --- Galeria ---
    $imgs = @($rec.imagenes)
    $altTxt = Escape-Html "$artista - $album - vinilo$(if ($anio) { " $anio" })"
    $galeriaMain = if ($imgs.Count -gt 0) {
        "<div class=`"f-gallery-main`"><img src=`"$(Escape-Html $imgs[0])`" alt=`"$altTxt`"></div>"
    } else { '<div class="f-gallery-main"></div>' }

    $thumbs = ''
    if ($imgs.Count -gt 1) {
        $t = foreach ($im in $imgs[1..($imgs.Count - 1)]) {
            "      <img src=`"$(Escape-Html $im)`" alt=`"$altTxt`" loading=`"lazy`">"
        }
        $thumbs = "    <div class=`"f-thumbs`">`n$($t -join "`n")`n    </div>"
    }

    # --- Etiquetas ---
    $tags = @()
    if ($genero) { $tags += "<a href=`"/?genero=$([Uri]::EscapeDataString($genero))`">$(Escape-Html $genero)</a>" }
    foreach ($v in @($origen, $sello, $anio)) {
        if ($v) { $tags += "<span>$(Escape-Html $v)</span>" }
    }
    if ($rec.canciones) { $tags += "<span>$(Escape-Html "$($rec.canciones) canciones")</span>" }
    # Ojo: este campo puede traer texto ("N/A"), no siempre es un numero
    $nDiscos = 0
    if ([int]::TryParse("$($rec.discos)".Trim(), [ref]$nDiscos) -and $nDiscos -gt 1) {
        $tags += "<span>$(Escape-Html "$nDiscos discos")</span>"
    }

    # --- Condicion ---
    $condHtml = ''
    if ($condicion.Count -gt 0) {
        $items = foreach ($c in $condicion) {
            "      <div class=`"f-cond-item`"><span class=`"f-cond-label`">$(Escape-Html $c.label)</span><span class=`"f-cond-value`">$(Escape-Html $c.value)</span></div>"
        }
        $condHtml = @"
  <section class="f-section">
    <h2 class="f-section-title">Estado del disco (escala Goldmine)</h2>
    <div class="f-condition">
$($items -join "`n")
    </div>
  </section>
"@
    }

    $descHtml = ''
    if ($textoDesc) {
        $descHtml = @"
  <section class="f-section">
    <h2 class="f-section-title">Sobre este disco</h2>
    <div class="f-desc">$(Escape-Html $textoDesc)</div>
  </section>
"@
    }

    # --- Bloque de compra / vendido ---
    if ($vendido) {
        $waTexto = "Hola! Vi que este disco ya se vendió:`n*$artista — $album*$(if ($anio) { " ($anio)" })`n`n¿Me avisás si entra otra copia?"
        $waHref  = "https://wa.me/$WA_NUMBER`?text=$([Uri]::EscapeDataString($waTexto))"
        $mailAsunto = "Aviso si entra otra copia: $artista — $album"
        $mailHref = "mailto:$MAIL_TO`?subject=$([Uri]::EscapeDataString($mailAsunto))"
        $precioHtml = if ($precio) { "<span class=`"f-price f-price-sold`">$(Format-Pesos $precio)</span>" } else { '' }
        $bloqueCompra = @"
      <div class="f-sold-banner">
        <div class="f-sold-title">Este disco ya se vendió</div>
        <p class="f-sold-text">Trabajamos con discos usados, así que puede volver a entrar otra copia. Dejanos tu consulta y te avisamos apenas aparezca.</p>
        <div class="f-cta-buttons">
          <a class="f-btn-wa" href="$waHref" target="_blank" rel="noopener">$WA_SVG Avisame si entra otra copia</a>
          <a class="f-btn-mail" href="$mailHref">$MAIL_SVG Avisame por mail</a>
        </div>
      </div>
"@
        $disponibilidad = 'https://schema.org/SoldOut'
    } else {
        $waTexto = "Hola! Me interesa este disco:`n*$artista — $album*$(if ($anio) { " ($anio)" })"
        if ($precio)  { $waTexto += "`nPrecio en Mercado Libre: $(Format-Pesos $precio)" }
        if ($directo) { $waTexto += "`nPrecio comprando directo (10% off): $(Format-Pesos $directo) (¡Ahorro $(Format-Pesos $ahorro)!)" }
        $waTexto += "`n`nLink: $SITE_URL/disco/$archivo`n`n¿Está disponible?"
        $waHref  = "https://wa.me/$WA_NUMBER`?text=$([Uri]::EscapeDataString($waTexto))"

        $mailAsunto = "Consulta: $artista — $album"
        $mailCuerpo = "Hola,`n`nMe interesa este disco:`n$artista — $album$(if ($anio) { " ($anio)" })`n"
        if ($precio) { $mailCuerpo += "Precio en Mercado Libre: $(Format-Pesos $precio)`n" }
        $mailCuerpo += "`n$SITE_URL/disco/$archivo`n`n¿Está disponible con el 10% de descuento por compra directa?`n`nGracias!"
        $mailHref = "mailto:$MAIL_TO`?subject=$([Uri]::EscapeDataString($mailAsunto))&body=$([Uri]::EscapeDataString($mailCuerpo))"

        $precioHtml = if ($precio) {
            "<span class=`"f-price`">$(Format-Pesos $precio)</span><span class=`"f-price-direct`">-> $(Format-Pesos $directo) comprando directo</span>"
        } else { '' }

        $mlHtml = if ($rec.url) {
            @"
      <div class="f-sep"><span>o si preferís</span></div>
      <a class="f-btn-ml" href="$(Escape-Html $rec.url)" target="_blank" rel="noopener">Ver en Mercado Libre</a>
"@
        } else { '' }

        $bloqueCompra = @"
      <div class="f-cta">
        <p class="f-cta-label">Comprá directo y pagás <strong>10% menos</strong> que en Mercado Libre</p>
        <div class="f-cta-buttons">
          <a class="f-btn-wa" href="$waHref" target="_blank" rel="noopener">$WA_SVG Consultar por WhatsApp</a>
          <a class="f-btn-mail" href="$mailHref">$MAIL_SVG Consultar por mail</a>
        </div>
      </div>
$mlHtml
"@
        $disponibilidad = 'https://schema.org/InStock'
    }

    # --- Datos estructurados (Schema.org Product) ---
    $ld = [ordered]@{
        '@context'      = 'https://schema.org'
        '@type'         = 'Product'
        'name'          = "$artista — $album"
        'sku'           = "MLA$id"
        'category'      = $genero
        'description'   = $(if ($textoDesc) { if ($textoDesc.Length -gt 500) { $textoDesc.Substring(0,500) } else { $textoDesc } } else { $metaDesc })
        'itemCondition' = 'https://schema.org/UsedCondition'
        'offers'        = [ordered]@{
            '@type'         = 'Offer'
            'url'           = "$SITE_URL/disco/$archivo"
            'priceCurrency' = 'ARS'
            'price'         = $precio
            'itemCondition' = 'https://schema.org/UsedCondition'
            'availability'  = $disponibilidad
            'seller'        = [ordered]@{ '@type' = 'Organization'; 'name' = 'Respira Ventas' }
        }
    }
    if ($imgs.Count -gt 0) { $ld['image'] = @($imgs) }
    if ($sello) { $ld['brand'] = [ordered]@{ '@type' = 'Brand'; 'name' = $sello } }
    if ($anio)  { $ld['releaseDate'] = $anio }

    $ldJson = ($ld | ConvertTo-Json -Depth 6 -Compress)
    # Evita que un "</script>" dentro del texto rompa la pagina
    $ldJson = $ldJson.Replace('</', '<\/')

    # --- Migas de pan (tambien como datos estructurados) ---
    $migas = [ordered]@{
        '@context' = 'https://schema.org'
        '@type'    = 'BreadcrumbList'
        'itemListElement' = @(
            [ordered]@{ '@type'='ListItem'; 'position'=1; 'name'='Catálogo'; 'item'="$SITE_URL/" }
            [ordered]@{ '@type'='ListItem'; 'position'=2; 'name'=$(if ($genero) { $genero } else { 'Discos' }); 'item'="$SITE_URL/?genero=$([Uri]::EscapeDataString($genero))" }
            [ordered]@{ '@type'='ListItem'; 'position'=3; 'name'="$artista — $album" }
        )
    }
    $migasJson = ($migas | ConvertTo-Json -Depth 6 -Compress).Replace('</', '<\/')

    $robots = if ($vendido) { '<meta name="robots" content="noindex, follow">' } else { '<meta name="robots" content="index, follow">' }
    $ogImg  = if ($imgs.Count -gt 0) { "<meta property=`"og:image`" content=`"$(Escape-Html $imgs[0])`">" } else { '' }
    $vendidoBadge = if ($vendido) { '<span class="f-sold-badge">Vendido</span>' } else { '' }

    $migaGenero = if ($genero) {
        "<a href=`"/?genero=$([Uri]::EscapeDataString($genero))`">$(Escape-Html $genero)</a><span>/</span>"
    } else { '' }

    # --- HTML final ---
    return @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$(Escape-Html $tituloPag)</title>
<meta name="description" content="$(Escape-Html $metaDesc)">
$robots
<link rel="canonical" href="$SITE_URL/disco/$archivo">
<link rel="icon" href="/assets/logo-icon.jpg">
<meta property="og:type" content="product">
<meta property="og:title" content="$(Escape-Html "$artista — $album")">
<meta property="og:description" content="$(Escape-Html $metaDesc)">
<meta property="og:url" content="$SITE_URL/disco/$archivo">
$ogImg
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=DM+Sans:opsz,wght@9..40,400;9..40,500;9..40,600;9..40,700;9..40,800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/ficha.css?v=1">
<script type="application/ld+json">$ldJson</script>
<script type="application/ld+json">$migasJson</script>
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
  <a href="/">Catálogo</a><span>/</span>$migaGenero<span style="opacity:1;margin:0">$(Escape-Html "$artista — $album")</span>
</nav>

<main class="f-main">
  <div class="f-top">
    <div>
$galeriaMain
$thumbs
    </div>
    <div>
      <p class="f-artist">$(Escape-Html $artista)</p>
      <h1 class="f-title">$(Escape-Html $album)$vendidoBadge</h1>
      <div class="f-tags">$($tags -join '')</div>
      <div class="f-price-row">$precioHtml</div>
$bloqueCompra
    </div>
  </div>

$condHtml
$descHtml
$relacionadosHtml
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

# ── Paginas de compartir (/d/<id>.html) ──────────────────────────────────────
#
#  Son las direcciones que se compartieron por WhatsApp desde antes de que
#  existieran las fichas. NUNCA se borran: si el disco se vendio, el que hace
#  clic tiene que ver "Vendido", no un error 404. Ahora rebotan a la ficha.
#
function Build-SharePageHtml {
    param($rec, [string]$id, [string]$fichaArchivo, [bool]$vendido)

    $artista = if ($rec.artista) { $rec.artista } else { 'Artista desconocido' }
    $album   = if ($rec.album)   { $rec.album }   else { $rec.titulo }
    $destino = "/disco/$fichaArchivo"

    $titulo = "$artista — $album"
    $desc = if ($vendido) {
        "Vendido — consultanos si entra otra copia. Respira Ventas, discos de vinilo en Rosario."
    } else {
        $p = if ($rec.precio) { ' ' + (Format-Pesos $rec.precio) } else { '' }
        "Respira Ventas — Discos de vinilo, Rosario.$p"
    }

    $img = if ($rec.imagenes -and $rec.imagenes.Count -gt 0) {
        "<meta property=`"og:image`" content=`"$(Escape-Html $rec.imagenes[0])`">"
    } else { '' }

    return @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>$(Escape-Html $titulo) — Respira Ventas</title>
<meta name="robots" content="noindex">
<meta property="og:title" content="$(Escape-Html $titulo)">
<meta property="og:description" content="$(Escape-Html $desc)">
$img
<meta property="og:url" content="$SITE_URL/d/$id.html">
<meta property="og:type" content="product">
<script>location.replace('$destino');</script>
</head>
<body>
<p><a href="$destino">Ver disco en Respira Ventas &rarr;</a></p>
</body>
</html>
"@
}

# ── Proceso principal ────────────────────────────────────────────────────────

function Sync-Fichas {
    param(
        [Parameter(Mandatory)] $Records,
        [Parameter(Mandatory)] [string] $SiteFolder,
        # Catalogo de la corrida anterior. Lo que estaba ahi y ya no esta en
        # $Records se considera vendido. actualizar.ps1 lo pasa leyendo
        # data/records.json ANTES de sobrescribirlo.
        $PreviousRecords = $null
    )

    $outDir      = Join-Path $SiteFolder "disco"
    $shareDir    = Join-Path $SiteFolder "d"
    $vendidosOut = Join-Path $SiteFolder "data\vendidos.json"
    New-Item -ItemType Directory -Force $outDir   | Out-Null
    New-Item -ItemType Directory -Force $shareDir | Out-Null

    # --- Vendidos ya conocidos de corridas anteriores ---
    $vendidos = @{}
    if (Test-Path $vendidosOut) {
        try {
            $prev = Get-Content $vendidosOut -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($v in @($prev)) { if ($v.id) { $vendidos[$v.id] = $v } }
        } catch {
            Write-Warning "No se pudo leer vendidos.json, se empieza de cero: $($_.Exception.Message)"
        }
    }

    # --- Indices de los discos activos ---
    $activos   = @{}
    $rutas     = @{}
    $porArtista = @{}
    $porGenero  = @{}

    foreach ($r in $Records) {
        $id = Get-DiscoId $r
        if (-not $id) { continue }
        $activos[$id] = $r
        $rutas[$id]   = Get-FichaNombre $r
        # Si volvio a entrar, deja de estar vendido
        if ($vendidos.ContainsKey($id)) { $vendidos.Remove($id) }

        $ka = ($r.artista + '').ToLowerInvariant().Trim()
        if ($ka) {
            if (-not $porArtista.ContainsKey($ka)) { $porArtista[$ka] = New-Object System.Collections.Generic.List[object] }
            $porArtista[$ka].Add($r)
        }

        $kg = ($r.genero + '').Trim()
        if ($kg) {
            if (-not $porGenero.ContainsKey($kg)) { $porGenero[$kg] = New-Object System.Collections.Generic.List[object] }
            $porGenero[$kg].Add($r)
        }
    }

    # Orden fijo por id: asi los "discos relacionados" no dependen del orden en
    # que venga el Excel. Sin esto, un reordenamiento del export cambiaria las
    # 3900 fichas de golpe en cada actualizacion.
    foreach ($k in @($porArtista.Keys)) {
        $porArtista[$k] = [System.Collections.Generic.List[object]]@($porArtista[$k] | Sort-Object { [long](Get-DiscoId $_) })
    }
    foreach ($k in @($porGenero.Keys)) {
        $porGenero[$k] = [System.Collections.Generic.List[object]]@($porGenero[$k] | Sort-Object { [long](Get-DiscoId $_) })
    }

    # --- Detectar bajas: fichas que existen en disco/ pero ya no estan activas ---
    $existentes = @{}
    Get-ChildItem $outDir -Filter "*.html" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.BaseName -match '^(\d+)-') {
            $fid = $Matches[1]
            if (-not $existentes.ContainsKey($fid)) { $existentes[$fid] = New-Object System.Collections.Generic.List[string] }
            $existentes[$fid].Add($_.Name)
        }
    }

    # --- Detectar bajas nuevas comparando contra el catalogo anterior ---
    $nuevasBajas = 0
    if ($PreviousRecords) {
        $hoy = Get-Date -Format 'yyyy-MM-dd'
        foreach ($b in $PreviousRecords) {
            $bid = Get-DiscoId $b
            if (-not $bid) { continue }
            if ($activos.ContainsKey($bid)) { continue }
            if ($vendidos.ContainsKey($bid)) { continue }
            $copia = $b | Select-Object *
            # El id se guarda explicitamente: es la clave con la que se vuelve
            # a leer este registro en las corridas siguientes.
            $copia | Add-Member -NotePropertyName 'id' -NotePropertyValue $bid -Force
            $copia | Add-Member -NotePropertyName 'vendidoDesde' -NotePropertyValue $hoy -Force
            $vendidos[$bid] = $copia
            $nuevasBajas++
        }
    }

    # --- Aviso por fichas sin datos para clasificar ---
    # (existe el archivo pero el disco no esta ni activo ni registrado como
    #  vendido; se conserva el archivo tal cual para no generar un 404)
    foreach ($fid in $existentes.Keys) {
        if ($activos.ContainsKey($fid)) { continue }
        if ($vendidos.ContainsKey($fid)) { continue }
        Write-Warning "Ficha sin datos para marcar vendida (se deja como esta): $($existentes[$fid][0])"
    }

    # --- Rutas de los vendidos (para enlazarlos si hiciera falta) ---
    foreach ($vid in $vendidos.Keys) {
        if (-not $rutas.ContainsKey($vid)) { $rutas[$vid] = Get-FichaNombre $vendidos[$vid] }
    }

    # --- Generar fichas activas ---
    $escritas = 0
    foreach ($id in $activos.Keys) {
        $r = $activos[$id]
        $archivo = $rutas[$id]
        $rel = Get-Relacionados $r $porArtista $porGenero $rutas
        $relHtml = Build-RelacionadosHtml $rel $rutas
        $html = Build-FichaHtml -rec $r -id $id -archivo $archivo -vendido $false -relacionadosHtml $relHtml
        [System.IO.File]::WriteAllText((Join-Path $outDir $archivo), $html, [System.Text.Encoding]::UTF8)
        $share = Build-SharePageHtml -rec $r -id $id -fichaArchivo $archivo -vendido $false
        [System.IO.File]::WriteAllText((Join-Path $shareDir "$id.html"), $share, [System.Text.Encoding]::UTF8)
        $escritas++
    }

    # --- Generar fichas vendidas ---
    foreach ($id in $vendidos.Keys) {
        $r = $vendidos[$id]
        $archivo = $rutas[$id]
        if (-not $archivo) { continue }
        $rel = Get-Relacionados $r $porArtista $porGenero $rutas
        $relHtml = Build-RelacionadosHtml $rel $rutas
        $html = Build-FichaHtml -rec $r -id $id -archivo $archivo -vendido $true -relacionadosHtml $relHtml
        [System.IO.File]::WriteAllText((Join-Path $outDir $archivo), $html, [System.Text.Encoding]::UTF8)
        # La pagina de compartir del vendido se reescribe (no se borra): quien
        # tenga el link viejo de WhatsApp va a ver "Vendido", no un error.
        $share = Build-SharePageHtml -rec $r -id $id -fichaArchivo $archivo -vendido $true
        [System.IO.File]::WriteAllText((Join-Path $shareDir "$id.html"), $share, [System.Text.Encoding]::UTF8)
        $escritas++
    }

    # --- Limpiar archivos viejos del mismo disco (si cambio el texto del slug) ---
    $validos = @{}
    foreach ($id in $rutas.Keys) { if ($rutas[$id]) { $validos[$rutas[$id]] = $true } }
    $renombradas = 0
    Get-ChildItem $outDir -Filter "*.html" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.BaseName -match '^(\d+)-') {
            $fid = $Matches[1]
            # Solo borra si el disco sigue existiendo pero con otro nombre de archivo
            if (($activos.ContainsKey($fid) -or $vendidos.ContainsKey($fid)) -and -not $validos.ContainsKey($_.Name)) {
                Remove-Item $_.FullName -Force
                $renombradas++
            }
        }
    }

    # --- Guardar registro de vendidos ---
    $listaVendidos = @($vendidos.Values)
    $jsonVendidos = if ($listaVendidos.Count -eq 0) { '[]' } else { $listaVendidos | ConvertTo-Json -Depth 4 }
    [System.IO.File]::WriteAllText($vendidosOut, $jsonVendidos, [System.Text.Encoding]::UTF8)

    # --- Sitemaps ---
    Build-Sitemaps -SiteFolder $SiteFolder -Activos $activos -Rutas $rutas

    return @{
        Fichas      = $escritas
        Activas     = $activos.Count
        Vendidas    = $vendidos.Count
        NuevasBajas = $nuevasBajas
        Renombradas = $renombradas
    }
}

function Build-Sitemaps {
    param([string]$SiteFolder, $Activos, $Rutas)

    $paginas = @(
        "$SITE_URL/", "$SITE_URL/colecciones.html", "$SITE_URL/rock-nacional.html",
        "$SITE_URL/cumbia-cuarteto.html", "$SITE_URL/melodico.html", "$SITE_URL/brasil.html",
        "$SITE_URL/tango.html", "$SITE_URL/folklore.html"
    )
    $sbP = New-Object Text.StringBuilder
    [void]$sbP.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$sbP.AppendLine('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">')
    foreach ($u in $paginas) { [void]$sbP.AppendLine("  <url><loc>$u</loc></url>") }
    [void]$sbP.AppendLine('</urlset>')
    [System.IO.File]::WriteAllText((Join-Path $SiteFolder "sitemap-paginas.xml"), $sbP.ToString(), [System.Text.Encoding]::UTF8)

    # Solo discos activos: los vendidos salen del sitemap a proposito
    $sbD = New-Object Text.StringBuilder
    [void]$sbD.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$sbD.AppendLine('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">')
    foreach ($id in $Activos.Keys) {
        if ($Rutas[$id]) { [void]$sbD.AppendLine("  <url><loc>$SITE_URL/disco/$($Rutas[$id])</loc></url>") }
    }
    [void]$sbD.AppendLine('</urlset>')
    [System.IO.File]::WriteAllText((Join-Path $SiteFolder "sitemap-discos.xml"), $sbD.ToString(), [System.Text.Encoding]::UTF8)

    $hoy = Get-Date -Format 'yyyy-MM-dd'
    $indice = @"
<?xml version="1.0" encoding="UTF-8"?>
<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <sitemap><loc>$SITE_URL/sitemap-paginas.xml</loc><lastmod>$hoy</lastmod></sitemap>
  <sitemap><loc>$SITE_URL/sitemap-discos.xml</loc><lastmod>$hoy</lastmod></sitemap>
</sitemapindex>
"@
    [System.IO.File]::WriteAllText((Join-Path $SiteFolder "sitemap.xml"), $indice, [System.Text.Encoding]::UTF8)
}
