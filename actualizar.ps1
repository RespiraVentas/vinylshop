# ─────────────────────────────────────────────────────────────────────────────
#  ACTUALIZAR CATÁLOGO DE VINILO
#  Uso: doble clic en "actualizar.bat", o ejecutar este script directamente.
#
#  Qué hace:
#   1. Busca el Excel más reciente en la carpeta configurada
#   2. Convierte los datos a JSON
#   3. Hace commit y push a GitHub → el sitio se actualiza solo (~1 min)
# ─────────────────────────────────────────────────────────────────────────────

param(
  [string]$ExcelPath = ""   # opcional: ruta exacta al Excel
)

$ErrorActionPreference = "Stop"

# ── Configuración ─────────────────────────────────────────────────────────────
# Carpeta donde Drapi guarda los Excel descargados de ML.
# Cambiá esta ruta si Drapi guarda en otro lado.
$EXCEL_FOLDER   = "C:\Users\Pablo\Documents\Claude_Trabajo"
$SITE_FOLDER    = $PSScriptRoot          # carpeta donde está este script (vinylshop/)
$JSON_OUT       = Join-Path $SITE_FOLDER "data\records.json"

# Columnas del Excel (índice 1-based) — mapeadas sobre RV.05.27.2026
# Si ML cambia la plantilla y algo falla, verificar con el script de diagnóstico
$COL_ID         = 1
$COL_TITULO     = 8
$COL_DESC       = 11
$COL_PRECIO     = 12
$COL_ESTADO     = 20
$COL_FECHA      = 32   # Fecha de creación de la publicación
$COL_IMG_START  = 36   # Imagen 1..10 = cols 36..45
$COL_IMG_END    = 45
$COL_VISITAS    = 46   # Visitas totales
$COL_ARTISTA    = 50   # Nombre del artista
$COL_ART_ALB    = 51   # Nombre del artista del álbum (fallback si artista vacío)
$COL_ALBUM      = 52
$COL_COMPANIA   = 53
$COL_ANIO       = 58
$COL_CANCIONES  = 61
$COL_ORIGEN     = 62
$COL_GENERO     = 63
$COL_DISCOS     = 64

# ── Funciones helper ──────────────────────────────────────────────────────────
function Write-Step($msg) { Write-Host "`n  → $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "    ✓ $msg" -ForegroundColor Green }
function Write-Err($msg)  { Write-Host "`n  ✗ ERROR: $msg" -ForegroundColor Red }

# ── Paso 1: localizar el Excel ────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "  ║   ACTUALIZAR CATÁLOGO DE VINILO   ║" -ForegroundColor Yellow
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Yellow

Write-Step "Buscando el Excel más reciente…"

if ($ExcelPath -and (Test-Path $ExcelPath)) {
    $xlFile = $ExcelPath
} else {
    # Busca el Excel más nuevo en la carpeta (por fecha de modificación)
    $xlFile = Get-ChildItem $EXCEL_FOLDER -Filter "RV*.xlsx" -Recurse -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending |
              Select-Object -ExpandProperty FullName -First 1

    if (-not $xlFile) {
        Write-Err "No se encontró ningún archivo RV*.xlsx en: $EXCEL_FOLDER"
        Write-Host "  Podés pasarlo como argumento: .\actualizar.ps1 -ExcelPath 'C:\ruta\al\archivo.xlsx'"
        Read-Host "`n  Presioná Enter para salir"
        exit 1
    }
}

$xlName = Split-Path $xlFile -Leaf
Write-OK "Excel encontrado: $xlName"
Write-OK "Fecha: $((Get-Item $xlFile).LastWriteTime.ToString('dd/MM/yyyy HH:mm'))"

# ── Paso 2: abrir Excel y exportar JSON ───────────────────────────────────────
Write-Step "Leyendo datos del Excel (puede tardar 1–2 minutos)…"

$excel = New-Object -ComObject Excel.Application
$excel.Visible       = $false
$excel.DisplayAlerts = $false

try {
    $wb = $excel.Workbooks.Open($xlFile)
    $ws = $wb.Sheets.Item(1)
    $rows = $ws.UsedRange.Rows.Count

    Write-OK "Filas en el Excel: $($rows - 1)"

    $records = [System.Collections.Generic.List[object]]::new()
    $skipped = 0

    for ($r = 2; $r -le $rows; $r++) {
        $estado = $ws.Cells.Item($r, $COL_ESTADO).Value2
        if ($estado -ne "Activa") { $skipped++; continue }

        $imgs = @()
        for ($c = $COL_IMG_START; $c -le $COL_IMG_END; $c++) {
            $v = $ws.Cells.Item($r, $c).Value2
            if ($v) { $imgs += "$v" }
        }

        # URL construida desde el ID del producto
        $mlId = "$($ws.Cells.Item($r, $COL_ID).Value2)"
        $url  = if ($mlId -match "^MLA(\d+)") { "https://articulo.mercadolibre.com.ar/MLA-$($Matches[1])" } else { "" }

        # Artista: col 50 primero, fallback col 51
        $artista = "$($ws.Cells.Item($r, $COL_ARTISTA).Value2)".Trim()
        if (-not $artista) { $artista = "$($ws.Cells.Item($r, $COL_ART_ALB).Value2)".Trim() }

        $precio  = $ws.Cells.Item($r, $COL_PRECIO).Value2
        $visitas = $ws.Cells.Item($r, $COL_VISITAS).Value2
        $fechaRaw = $ws.Cells.Item($r, $COL_FECHA).Value2
        # Fecha puede venir como número serial de Excel o como string "dd/mm/yyyy hh:mm"
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
            titulo    = "$($ws.Cells.Item($r, $COL_TITULO).Value2)".Trim()
            artista   = $artista
            album     = "$($ws.Cells.Item($r, $COL_ALBUM).Value2)".Trim()
            compania  = "$($ws.Cells.Item($r, $COL_COMPANIA).Value2)".Trim()
            anio      = "$($ws.Cells.Item($r, $COL_ANIO).Value2)".Trim()
            canciones = "$($ws.Cells.Item($r, $COL_CANCIONES).Value2)".Trim()
            origen    = "$($ws.Cells.Item($r, $COL_ORIGEN).Value2)".Trim()
            genero    = "$($ws.Cells.Item($r, $COL_GENERO).Value2)".Trim()
            discos    = "$($ws.Cells.Item($r, $COL_DISCOS).Value2)".Trim()
            precio    = if ($precio)  { [int]$precio  } else { 0 }
            visitas   = if ($visitas) { [int]$visitas } else { 0 }
            fecha     = $fechaStr
            url       = $url
            imagenes  = $imgs
            desc      = "$($ws.Cells.Item($r, $COL_DESC).Value2)".Trim()
        }
        $records.Add($rec)
    }

    $wb.Close($false)
} finally {
    $excel.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
}

Write-OK "Discos activos exportados: $($records.Count)  (omitidos: $skipped)"

# Guardar JSON
New-Item -ItemType Directory -Force (Split-Path $JSON_OUT) | Out-Null
$json = $records | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText($JSON_OUT, $json, [System.Text.Encoding]::UTF8)

$jsonSizeKB = [math]::Round((Get-Item $JSON_OUT).Length / 1KB, 0)
Write-OK "JSON guardado: data/records.json  ($jsonSizeKB KB)"

# ── Paso 3: commit y push ─────────────────────────────────────────────────────
Write-Step "Subiendo cambios a GitHub…"

Push-Location $SITE_FOLDER
try {
    # Verificar que hay un repo git inicializado
    $gitCheck = git rev-parse --is-inside-work-tree 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Esta carpeta no es un repositorio git."
        Write-Host "  Seguí las instrucciones de SETUP.md para configurarlo la primera vez."
        Read-Host "`n  Presioná Enter para salir"
        exit 1
    }

    $fecha   = Get-Date -Format "dd/MM/yyyy HH:mm"
    $mensaje = "Actualización catálogo — $fecha ($($records.Count) discos)"

    git add data/records.json 2>&1 | Out-Null
    git commit -m $mensaje 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-OK "Commit creado: $mensaje"
    } else {
        Write-Host "    (Sin cambios desde la última actualización)" -ForegroundColor Yellow
    }

    git push 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        # Intentar push con upstream si falla
        git push --set-upstream origin main 2>&1 | Out-Null
    }

    if ($LASTEXITCODE -eq 0) {
        Write-OK "Push exitoso a GitHub"
    } else {
        Write-Err "No se pudo hacer push. ¿Está configurado el remote? Revisá SETUP.md"
        Pop-Location; Read-Host "`n  Presioná Enter para salir"; exit 1
    }
} finally {
    Pop-Location
}

# ── Listo ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║   ✓  CATÁLOGO ACTUALIZADO CON ÉXITO  ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  El sitio estará disponible en ~1 minuto." -ForegroundColor White
Write-Host "  GitHub Actions está procesando el deploy ahora." -ForegroundColor Gray
Write-Host ""

Read-Host "  Presioná Enter para cerrar"
