# =============================================================================
#  ACTUALIZAR CATALOGO DE VINILO
#  Uso: doble clic en "actualizar.bat", o ejecutar este script directamente.
#
#  Que hace:
#   1. Cierra Excel si esta abierto
#   2. Busca el Excel mas reciente en la carpeta configurada
#   3. Convierte los datos a JSON
#   4. Hace commit y push a GitHub -> el sitio se actualiza solo (~1 min)
# =============================================================================

param(
  [string]$ExcelPath = ""
)

$ErrorActionPreference = "Stop"

# -- Configuracion ------------------------------------------------------------
$EXCEL_FOLDER   = "C:\Users\Pablo\Documents\Claude_Trabajo"
$SITE_FOLDER    = $PSScriptRoot
$JSON_OUT       = Join-Path $SITE_FOLDER "data\records.json"

# Las columnas se detectan automáticamente por nombre al abrir el Excel.
# Ver función Build-ColMap más abajo.
$REQUIRED_COLS = @("Id","Título","Descripción","Precio","Estado",
                   "Fecha Creación","Imagen 1","Imagen 10","Visitas",
                   "Nombre del artista","Nombre del artista del album",
                   "Nombre del álbum","Compañía productora",
                   "Año de lanzamiento","Cantidad de canciones",
                   "Origen","Género","Cantidad de piezas")

function Write-Step($msg) { Write-Host "`n  -> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "    OK $msg" -ForegroundColor Green }
function Write-Err($msg)  { Write-Host "`n  ERROR: $msg" -ForegroundColor Red }

# Construye un mapa nombre-de-columna -> número-de-columna leyendo la fila 1.
# Los headers con prefijo "Atributo + salto de linea" quedan solo con el nombre real.
function Build-ColMap($ws) {
    $map  = @{}
    $last = $ws.UsedRange.Columns.Count
    for ($c = 1; $c -le $last; $c++) {
        $raw = "$($ws.Cells.Item(1, $c).Value2)".Trim()
        $key = ($raw -replace "(?s)^Atributo[\r\n\s]+", "").Trim()
        if ($key -and -not $map.ContainsKey($key)) { $map[$key] = $c }
        if ($raw -and -not $map.ContainsKey($raw))  { $map[$raw] = $c }
    }
    return $map
}

function Get-Col($map, $name) {
    $trimmed = $name.Trim()
    if ($map.ContainsKey($trimmed)) { return $map[$trimmed] }
    # búsqueda tolerante a acentos/espacios extra
    foreach ($k in $map.Keys) { if ($k.Trim() -ieq $trimmed) { return $map[$k] } }
    return 0
}

# -- Encabezado ---------------------------------------------------------------
Write-Host ""
Write-Host "  ================================================" -ForegroundColor Yellow
Write-Host "     ACTUALIZAR CATALOGO DE VINILO               " -ForegroundColor Yellow
Write-Host "  ================================================" -ForegroundColor Yellow

# -- Paso 1: localizar el Excel -----------------------------------------------
Write-Step "Buscando el Excel mas reciente..."

if ($ExcelPath -and (Test-Path $ExcelPath)) {
    $xlFile = $ExcelPath
} else {
    $xlFile = Get-ChildItem $EXCEL_FOLDER -Filter "RV*.xlsx" -Recurse -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending |
              Select-Object -ExpandProperty FullName -First 1

    if (-not $xlFile) {
        Write-Err "No se encontro ningun archivo RV*.xlsx en: $EXCEL_FOLDER"
        Read-Host "`n  Presiona Enter para salir"
        exit 1
    }
}

$xlName = Split-Path $xlFile -Leaf
Write-OK "Excel encontrado: $xlName"
Write-OK "Fecha: $((Get-Item $xlFile).LastWriteTime.ToString('dd/MM/yyyy HH:mm'))"

Write-Host ""
$confirmar = Read-Host "  Es este el archivo correcto? (S para continuar, cualquier otra tecla cancela)"
if ($confirmar -notmatch '^[sS]$') {
    Write-Host "`n  Cancelado. No se hizo ningun cambio." -ForegroundColor Yellow
    Read-Host "`n  Presiona Enter para cerrar"
    exit 0
}

# -- Paso 2: cerrar Excel y exportar JSON -------------------------------------
Write-Step "Cerrando Excel si esta abierto..."
Stop-Process -Name "EXCEL" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Step "Leyendo datos del Excel (puede tardar 1-2 minutos)..."

$excel = New-Object -ComObject Excel.Application
$excel.Visible       = $false
$excel.DisplayAlerts = $false

try {
    $wb = $excel.Workbooks.Open($xlFile)
    $ws = $wb.Sheets.Item(1)
    $rows = $ws.UsedRange.Rows.Count

    # --- Detectar columnas por nombre ---
    Write-Step "Detectando columnas en el Excel..."
    $map = Build-ColMap $ws

    $C_ID       = Get-Col $map "Id"
    $C_TITULO   = Get-Col $map "Título"
    $C_DESC     = Get-Col $map "Descripción"
    $C_PRECIO   = Get-Col $map "Precio"
    $C_ESTADO   = Get-Col $map "Estado"
    $C_FECHA    = Get-Col $map "Fecha Creación"
    $C_IMG1     = Get-Col $map "Imagen 1"
    $C_IMG10    = Get-Col $map "Imagen 10"
    $C_VISITAS  = Get-Col $map "Visitas"
    $C_ARTISTA  = Get-Col $map "Nombre del artista"
    $C_ART_ALB  = Get-Col $map "Nombre del artista del album"
    $C_ALBUM    = Get-Col $map "Nombre del álbum"
    $C_COMPANIA = Get-Col $map "Compañía productora"
    $C_ANIO     = Get-Col $map "Año de lanzamiento"
    $C_CANCIONES= Get-Col $map "Cantidad de canciones"
    $C_ORIGEN   = Get-Col $map "Origen"
    $C_GENERO   = Get-Col $map "Género"
    $C_DISCOS   = Get-Col $map "Cantidad de piezas"

    # Validar que ninguna columna crítica falte
    $missing = @()
    $colCheck = @{
        "Id"=$C_ID; "Título"=$C_TITULO; "Precio"=$C_PRECIO; "Estado"=$C_ESTADO
        "Fecha Creación"=$C_FECHA; "Imagen 1"=$C_IMG1; "Imagen 10"=$C_IMG10
        "Visitas"=$C_VISITAS; "Nombre del artista"=$C_ARTISTA
        "Nombre del álbum"=$C_ALBUM; "Año de lanzamiento"=$C_ANIO
        "Origen"=$C_ORIGEN; "Género"=$C_GENERO
    }
    foreach ($entry in $colCheck.GetEnumerator()) {
        if ($entry.Value -eq 0) { $missing += $entry.Key }
    }
    if ($missing.Count -gt 0) {
        Write-Err "No se encontraron estas columnas en el Excel:"
        $missing | ForEach-Object { Write-Host "      - $_" -ForegroundColor Red }
        Write-Host "`n  Revisa que el Excel sea el correcto y que tenga la configuracion de Drapi habitual." -ForegroundColor Yellow
        $wb.Close($false)
        Read-Host "`n  Presiona Enter para salir"
        exit 1
    }

    Write-OK "Columnas detectadas correctamente ($($map.Count) columnas en total)"
    Write-OK "Filas en el Excel: $($rows - 1)"

    $records = [System.Collections.Generic.List[object]]::new()
    $skipped = 0

    for ($r = 2; $r -le $rows; $r++) {
        $estado = $ws.Cells.Item($r, $C_ESTADO).Value2
        if ($estado -ne "Activa") { $skipped++; continue }

        $imgs = @()
        for ($c = $C_IMG1; $c -le $C_IMG10; $c++) {
            $v = $ws.Cells.Item($r, $c).Value2
            # Drapi exporta las imagenes con http:// -> se fuerza https para
            # evitar advertencias de contenido mixto en el sitio
            if ($v) { $imgs += "$v" -replace '^http://', 'https://' }
        }

        $mlId = "$($ws.Cells.Item($r, $C_ID).Value2)"
        $url  = if ($mlId -match "^MLA(\d+)") { "https://articulo.mercadolibre.com.ar/MLA-$($Matches[1])" } else { "" }

        $artista = "$($ws.Cells.Item($r, $C_ARTISTA).Value2)".Trim()
        if (-not $artista) { $artista = "$($ws.Cells.Item($r, $C_ART_ALB).Value2)".Trim() }

        $precio   = $ws.Cells.Item($r, $C_PRECIO).Value2
        $visitas  = $ws.Cells.Item($r, $C_VISITAS).Value2
        $fechaRaw = $ws.Cells.Item($r, $C_FECHA).Value2
        $fechaStr = ""
        if ($fechaRaw) {
            try {
                if ($fechaRaw -is [double] -or $fechaRaw -is [int]) {
                    $fechaStr = [DateTime]::FromOADate($fechaRaw).ToString("yyyy-MM-ddTHH:mm:ss")
                } else {
                    $fechaStr = "$fechaRaw".Trim()
                }
            } catch { $fechaStr = "$fechaRaw".Trim() }
        }

        $rec = [ordered]@{
            titulo    = "$($ws.Cells.Item($r, $C_TITULO).Value2)".Trim()
            artista   = $artista
            album     = "$($ws.Cells.Item($r, $C_ALBUM).Value2)".Trim()
            compania  = "$($ws.Cells.Item($r, $C_COMPANIA).Value2)".Trim()
            anio      = "$($ws.Cells.Item($r, $C_ANIO).Value2)".Trim()
            canciones = "$($ws.Cells.Item($r, $C_CANCIONES).Value2)".Trim()
            origen    = "$($ws.Cells.Item($r, $C_ORIGEN).Value2)".Trim()
            genero    = "$($ws.Cells.Item($r, $C_GENERO).Value2)".Trim()
            discos    = "$($ws.Cells.Item($r, $C_DISCOS).Value2)".Trim()
            precio    = if ($precio)  { [int]$precio  } else { 0 }
            visitas   = if ($visitas) { [int]$visitas } else { 0 }
            fecha     = $fechaStr
            url       = $url
            imagenes  = $imgs
            desc      = "$($ws.Cells.Item($r, $C_DESC).Value2)".Trim()
        }
        $records.Add($rec)
    }

    $wb.Close($false)
} finally {
    $excel.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
}

Write-OK "Discos activos: $($records.Count)  (omitidos: $skipped)"

New-Item -ItemType Directory -Force (Split-Path $JSON_OUT) | Out-Null

# Catalogo de la corrida anterior, ANTES de pisarlo. Lo que estaba aca y ya no
# esta en $records son los discos que se vendieron: con eso se marcan sus fichas.
$recordsPrevios = $null
if (Test-Path $JSON_OUT) {
    try {
        $recordsPrevios = Get-Content $JSON_OUT -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Host "    (No se pudo leer el catalogo anterior; no se marcaran bajas esta vez)" -ForegroundColor Yellow
    }
}

# --- Mantiene al dia el "Mas de N discos" que Google muestra como subtitulo ---
# Se redondea para abajo a la centena, asi el numero nunca miente (si hay 3929
# dice "mas de 3.900") y solo cambia el archivo cuando se cruza una centena.
$indexPath = Join-Path $SITE_FOLDER "index.html"
if (Test-Path $indexPath) {
    $redondeado = [math]::Floor($records.Count / 100) * 100
    $textoNuevo = "Más de " + ('{0:N0}' -f $redondeado -replace ',', '.') + " discos"
    $indexHtml  = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)
    $patron     = 'Más de [\d\.]+ discos'
    $coincidencias = ([regex]::Matches($indexHtml, $patron)).Count
    if ($coincidencias -gt 0) {
        $indexNuevo = [regex]::Replace($indexHtml, $patron, $textoNuevo)
        if ($indexNuevo -ne $indexHtml) {
            [System.IO.File]::WriteAllText($indexPath, $indexNuevo, [System.Text.Encoding]::UTF8)
            Write-OK "Subtitulo de Google actualizado: `"$textoNuevo`""
        }
    } else {
        Write-Host "    (No se encontro el texto del subtitulo en index.html; se deja como esta)" -ForegroundColor Yellow
    }
}

# Guarda en cada disco el nombre de archivo de su ficha, para que el catalogo
# pueda enlazarla directamente (asi el clic derecho / abrir en pestana nueva
# funciona, y Google encuentra las fichas siguiendo enlaces del sitio).
. (Join-Path $SITE_FOLDER "generar-fichas.ps1")
foreach ($rec in $records) {
    $rec.ficha = Get-FichaNombre $rec
}

$json = $records | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText($JSON_OUT, $json, [System.Text.Encoding]::UTF8)

$jsonSizeKB = [math]::Round((Get-Item $JSON_OUT).Length / 1KB, 0)
Write-OK "JSON guardado: data/records.json ($jsonSizeKB KB)"

# Las paginas de compartir (/d/*.html) ya NO se generan aca: las escribe
# generar-fichas.ps1 junto con las fichas. El generador viejo las borraba
# cuando el disco se vendia, y eso dejaba en error 404 los links que ya se
# habian mandado por WhatsApp. Ahora nunca se borran: rebotan a la ficha,
# que muestra "Vendido".

# Fichas indexables por disco (/disco/*.html) + sitemaps.
# Va dentro de try/catch a proposito: si esto fallara, el catalogo se publica
# igual. Nunca debe impedir que se actualice el sitio.
Write-Step "Generando fichas de disco y sitemaps (puede tardar ~1 minuto)..."
try {
    . (Join-Path $SITE_FOLDER "generar-fichas.ps1")
    $fichas = Sync-Fichas -Records $records -SiteFolder $SITE_FOLDER -PreviousRecords $recordsPrevios
    Write-OK "Fichas: $($fichas.Activas) a la venta, $($fichas.Vendidas) vendidas ($($fichas.NuevasBajas) nuevas)"
    Write-OK "Sitemaps actualizados"
} catch {
    Write-Host "`n  AVISO: no se pudieron generar las fichas de disco." -ForegroundColor Yellow
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "  El catalogo se publica igual. Avisale a Claude para que lo revise." -ForegroundColor Yellow
}

# -- Paso 3: commit y push ----------------------------------------------------
Write-Step "Subiendo cambios a GitHub..."

Push-Location $SITE_FOLDER
try {
    $gitCheck = git rev-parse --is-inside-work-tree 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Esta carpeta no es un repositorio git."
        Read-Host "`n  Presiona Enter para salir"
        exit 1
    }

    $fecha   = Get-Date -Format "dd/MM/yyyy HH:mm"
    $mensaje = "Actualizacion catalogo $fecha ($($records.Count) discos)"

    git add data/records.json data/vendidos.json d disco index.html sitemap.xml sitemap-paginas.xml sitemap-discos.xml | Out-Null
    git commit -m $mensaje | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-OK "Commit creado: $mensaje"
    } else {
        Write-Host "    (Sin cambios desde la ultima actualizacion)" -ForegroundColor Yellow
    }

    git push origin main
    if ($LASTEXITCODE -ne 0) {
        git push --set-upstream origin main
    }

    if ($LASTEXITCODE -eq 0) {
        Write-OK "Push exitoso a GitHub"
    } else {
        Write-Err "No se pudo hacer push. Revisa HOWTO.txt"
        Pop-Location; Read-Host "`n  Presiona Enter para salir"; exit 1
    }
} finally {
    Pop-Location
}

# -- Listo --------------------------------------------------------------------
Write-Host ""
Write-Host "  ================================================" -ForegroundColor Green
Write-Host "     CATALOGO ACTUALIZADO CON EXITO              " -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  El sitio estara disponible en ~1 minuto." -ForegroundColor White
Write-Host "  Verificar en: https://respiraventas.com.ar" -ForegroundColor Gray
Write-Host ""

Read-Host "  Presiona Enter para cerrar"