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

$COL_ID         = 1
$COL_TITULO     = 8
$COL_DESC       = 11
$COL_PRECIO     = 12
$COL_ESTADO     = 20
$COL_FECHA      = 32
$COL_IMG_START  = 36
$COL_IMG_END    = 45
$COL_VISITAS    = 46
$COL_ARTISTA    = 48
$COL_ART_ALB    = 49
$COL_ALBUM      = 50
$COL_COMPANIA   = 51
$COL_ANIO       = 56
$COL_CANCIONES  = 59
$COL_ORIGEN     = 60
$COL_GENERO     = 61
$COL_DISCOS     = 62

function Write-Step($msg) { Write-Host "`n  -> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "    OK $msg" -ForegroundColor Green }
function Write-Err($msg)  { Write-Host "`n  ERROR: $msg" -ForegroundColor Red }

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

        $mlId = "$($ws.Cells.Item($r, $COL_ID).Value2)"
        $url  = if ($mlId -match "^MLA(\d+)") { "https://articulo.mercadolibre.com.ar/MLA-$($Matches[1])" } else { "" }

        $artista = "$($ws.Cells.Item($r, $COL_ARTISTA).Value2)".Trim()
        if (-not $artista) { $artista = "$($ws.Cells.Item($r, $COL_ART_ALB).Value2)".Trim() }

        $precio   = $ws.Cells.Item($r, $COL_PRECIO).Value2
        $visitas  = $ws.Cells.Item($r, $COL_VISITAS).Value2
        $fechaRaw = $ws.Cells.Item($r, $COL_FECHA).Value2
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

Write-OK "Discos activos: $($records.Count)  (omitidos: $skipped)"

New-Item -ItemType Directory -Force (Split-Path $JSON_OUT) | Out-Null
$json = $records | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText($JSON_OUT, $json, [System.Text.Encoding]::UTF8)

$jsonSizeKB = [math]::Round((Get-Item $JSON_OUT).Length / 1KB, 0)
Write-OK "JSON guardado: data/records.json ($jsonSizeKB KB)"

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

    git add data/records.json 2>&1 | Out-Null
    git commit -m $mensaje 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-OK "Commit creado: $mensaje"
    } else {
        Write-Host "    (Sin cambios desde la ultima actualizacion)" -ForegroundColor Yellow
    }

    git push 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        git push --set-upstream origin main 2>&1 | Out-Null
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