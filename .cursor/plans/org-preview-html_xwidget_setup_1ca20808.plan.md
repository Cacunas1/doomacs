---
name: org-preview-html xwidget setup
overview: Configurar org-preview-html con xwidget-webkit para previsualizar automaticamente la salida HTML de Jupyter (DataFrames, graficos Plotly) en un panel lateral dentro de Emacs.
todos:
  - id: add-package
    content: Declarar org-preview-html en packages.el
    status: pending
  - id: configure
    content: Configurar org-preview-html, popup rule y keybinding en config.el
    status: pending
  - id: doom-sync
    content: Ejecutar doom sync
    status: pending
isProject: false
---

# Configurar org-preview-html con xwidget para Data Science

## Que se va a hacer

Instalar y configurar `org-preview-html` para que al ejecutar bloques Jupyter en Org-mode, un panel lateral con xwidget-webkit muestre automaticamente la salida renderizada (tablas HTML de pandas, graficos interactivos de Plotly).

## Dependencias externas

Ninguna nueva. Tu Emacs (emacs-plus@31) ya tiene xwidgets.

## Cambios

### 1. Declarar paquete en `[packages.el](packages.el)`

Anadir al final de la seccion de Data Science:

```elisp
(package! org-preview-html)   ; preview HTML con xwidget-webkit
```

### 2. Configurar en `[config.el](config.el)`

Anadir despues de la seccion 4 (Python & Data Science):

```elisp
;;; 7. Visualizacion HTML con xwidget-webkit
(after! org-preview-html
  (setq org-preview-html-viewer 'xwidget
        org-preview-html-refresh-configuration 'save))
```

- `org-preview-html-viewer 'xwidget` -- usa WebKit en vez de eww
- `org-preview-html-refresh-configuration 'save` -- refresca el panel cada vez que guardas el archivo Org (lo cual ocurre automaticamente despues de ejecutar un bloque con `C-c C-c`, porque Org inserta el resultado y marca el buffer como modificado)

Tambien anadir popup rule para que el panel se abra a la derecha:

```elisp
(set-popup-rule! "^\\*xwidget" :side 'right :size 0.5 :quit nil :ttl nil)
```

Anadir keybinding para activar/desactivar la preview:

```elisp
;; En el bloque map! existente, anadir:
:desc "Toggle vista HTML"      "v" #'org-preview-html-mode
```

### 3. Ejecutar doom sync

```bash
doom sync
```

## Flujo de uso resultante

1. Abrir un archivo `.org` con bloques `jupyter-python`
2. Activar preview: `SPC d v` (toggle)
3. Se abre un panel xwidget-webkit a la derecha
4. Ejecutar bloque con `C-c C-c`
5. Guardar (`SPC f s` o se auto-guarda)
6. El panel se refresca mostrando el HTML exportado (tablas, graficos Plotly)

## Nota sobre Plotly

Para que los graficos de Plotly se rendericen correctamente en el panel xwidget, en tus bloques Python debes usar:

```python
import plotly.io as pio
pio.renderers.default = "iframe"
```

Esto hace que Plotly genere archivos HTML que se incluyen en la exportacion Org y el panel xwidget puede renderizar con interactividad completa (zoom, hover, etc.).

## Tiempo estimado

10-15 minutos (incluye doom sync).