# Configuración inicial — Catálogo de Vinilo

Esto se hace **una sola vez**. Después, para actualizar el sitio, solo ejecutás `actualizar.bat`.

---

## Paso 1 — Crear el repositorio en GitHub

1. Andá a **github.com** → iniciá sesión → botón verde **New**
2. Dale un nombre, por ejemplo: `catalogo-vinilo`
3. Dejalo en **Public** (necesario para GitHub Pages gratuito)
4. **No** marques ningún checkbox de inicialización
5. Hacé clic en **Create repository**
6. Copiá la URL que aparece, algo como: `https://github.com/TU_USUARIO/catalogo-vinilo.git`

---

## Paso 2 — Conectar esta carpeta al repositorio

Abrí PowerShell o el símbolo del sistema en la carpeta `vinylshop/` y ejecutá:

```powershell
cd "C:\Users\Pablo\Documents\Claude_Trabajo\vinylshop"

git init
git add .
git commit -m "Primera versión del catálogo"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/catalogo-vinilo.git
git push -u origin main
```

> Reemplazá `TU_USUARIO` con tu usuario de GitHub.
> Si te pide credenciales, usá tu usuario y un **Personal Access Token**
> (GitHub → Settings → Developer settings → Personal access tokens → Classic → New token,
> marcá el scope `repo`, copiá el token y usalo como contraseña).

---

## Paso 3 — Activar GitHub Pages con Actions

1. En tu repositorio de GitHub, andá a **Settings → Pages**
2. En *Source*, elegí **GitHub Actions**
3. Listo — el workflow `.github/workflows/deploy.yml` ya está incluido

El primer deploy se ejecuta automáticamente al hacer el push del paso 2.
Tu sitio quedará en: **`https://TU_USUARIO.github.io/catalogo-vinilo`**

---

## Uso diario — Actualizar el catálogo

Una vez configurado, el proceso es:

```
1. Drapi baja el Excel actualizado desde ML  →  guardalo en Claude_Trabajo/
2. Doble clic en  actualizar.bat
3. El script lee el Excel, genera el JSON, hace commit y push
4. GitHub Pages actualiza el sitio en ~1 minuto  ✓
```

El script detecta automáticamente el Excel más nuevo con nombre `RV*.xlsx`
en la carpeta `Claude_Trabajo`. No hay que hacer nada más.

---

## Alternativa: Netlify (más rápido aún)

Si preferís Netlify en lugar de GitHub Pages:

1. Andá a **netlify.com** → **Add new site → Import an existing project**
2. Conectá tu repo de GitHub
3. Build command: *(dejar vacío)*
4. Publish directory: `.`
5. Hacé clic en **Deploy**

Con Netlify el sitio se actualiza en **~30 segundos** después del push,
y la URL queda algo como `https://catalogo-vinilo.netlify.app`.

---

## Preguntas frecuentes

**¿Qué pasa si Drapi guarda el Excel con otro nombre?**
El script busca cualquier archivo `RV*.xlsx`. Si el nombre cambió mucho,
editá `actualizar.ps1` y cambiá el filtro `"RV*.xlsx"` en la línea
`Get-ChildItem $EXCEL_FOLDER -Filter "RV*.xlsx"`.

**¿Puedo apuntar a una carpeta diferente?**
Sí — editá la línea `$EXCEL_FOLDER` en `actualizar.ps1`.

**¿El script tarda mucho?**
Con 3500 discos tarda ~2 minutos en leer el Excel vía COM.
Es normal, Excel tiene que abrir el archivo y leer cada celda.
