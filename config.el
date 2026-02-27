;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Identidad (Opcional)
;; (setq user-full-name "Tu Nombre"
;;       user-mail-address "tu@email.com")

;;; 1. Fuentes y Tema
;; -------------------
(setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light)
      doom-variable-pitch-font (font-spec :family "Fira Code" :size 13))

(setq doom-theme 'doom-oceanic-next)
(setq display-line-numbers-type 'relative)
(setq org-directory "~/org/")

;;; 2. UI y Transparencia
;; -----------------------
;; Emacs 29+ usa alpha-background. Mantenemos alpha por compatibilidad.
(add-to-list 'default-frame-alist '(alpha-background . 90))
(add-to-list 'default-frame-alist '(ns-transparent-titlebar . t))
(add-to-list 'default-frame-alist '(ns-appearance . dark))
(add-to-list 'default-frame-alist '(alpha . (90 . 90)))

;; Hook para asegurar transparencia al cambiar de tema o recargar
(add-hook! 'doom-load-theme-hook
  (set-frame-parameter nil 'alpha-background 90))

;;; 3. Performance (LSP / Data Science)
;; -------------------------------------
(setq gc-cons-threshold 100000000) ; 100mb
(setq read-process-output-max (* 1024 1024)) ; 1mb

;;; 4. Python & Data Science Configuration
;; ----------------------------------------

;; Direnv: Auto-load .envrc del proyecto para usar venv local
(after! direnv
  (direnv-mode +1))

;; Configurar emacs-jupyter para buscar kernels en el proyecto
(after! jupyter
  ;; Buscar kernels en el venv del proyecto actual
  (defun my-get-project-jupyter-data-dir ()
    (let* ((root (locate-dominating-file (buffer-file-name) ".venv"))
           (data-dir (if root (expand-file-name ".venv/share/jupyter" root) nil)))
      (when (and data-dir (file-exists-p data-dir))
        data-dir)))

  ;; Agregar data-dir del proyecto a la búsqueda
  (add-hook 'find-file-hook
            (lambda ()
              (let ((proj-data-dir (my-get-project-jupyter-data-dir)))
                (when proj-data-dir
                  (setq jupyter-data-dir proj-data-dir))))))


;; Code-Cells: La magia para # %%
(after! code-cells
  ;; Usamos el hook para activar el modo solo si detecta celdas o es .py
  (add-hook 'python-mode-hook #'code-cells-mode-maybe)
  ;; Opcional: Visualización de los headers de celda
  (add-hook 'code-cells-mode-hook #'code-cells-convert-ipyb-hook))

;; LSP Pyright / BasedPyright
;; NO hardcodeamos rutas. Confiamos en que 'direnv' o el 'hook' activaron el venv.
(after! lsp-pyright
  ;; Si usas basedpyright, asegúrate de que esté instalado en tu entorno
  (setq lsp-pyright-langserver-command "basedpyright"))

;; Formateador (Ruff)
;; Si tienes :editor format habilitado en init.el, esto suele ser automático.
;; Pero si quieres forzar ruff:
(set-formatter! 'ruff '("ruff" "format" "-") :modes '(python-mode))

;; Configuración del REPL (para que se abra a la derecha y use IPython)
(after! python
  (set-popup-rule! "^\\*Python*" :side 'right :size 0.5 :quit nil :ttl nil)
  (setq python-shell-interpreter "ipython"
        python-shell-interpreter-args "--simple-prompt --classic"))

;;; 5. Keybindings Personalizados (SPC d ...)
;; -------------------------------------------
(map! :leader
      :prefix ("d" . "data-science")
      :desc "Ejecutar celda (Code Cells)" "x" #'code-cells-eval
      :desc "Ejecutar y saltar"           "j" #'code-cells-eval-and-step
      :desc "Reiniciar REPL"              "r" #'python-shell-restart
      :desc "Inspeccionar objeto"         "i" #'lsp-describe-thing-at-point
      :desc "Conectar BigQuery (SQL)"     "b" #'sql-connect
      :desc "Toggle vista HTML xwidget"   "v" #'org-preview-html-mode)

;;; 6. Visualizacion HTML con xwidget-webkit
;; ------------------------------------------
(after! org-preview-html
  (setq org-preview-html-viewer 'xwidget
        org-preview-html-refresh-configuration 'save))

;; Popup rule para que xwidget se abra a la derecha
(set-popup-rule! "^\\*xwidget" :side 'right :size 0.5 :quit nil :ttl nil)

;;; 6. Soporte para archivos Log (Python logging, syslog, etc.)
;; ----------------------------------------
;; Nota: log-view-mode (built-in) es para CVS/version control.
;; Usamos el paquete 'logview' para logs de aplicaciones (Python logger, etc.)
(add-to-list 'auto-mode-alist '("\\.log\\'" . logview-mode))
(add-to-list 'auto-mode-alist '("\\.log\\.[0-9]+\\'" . logview-mode))

;;; 7. Auto-activación de entorno UV (El snippet que te di antes)
;; Si NO usas direnv, descomenta esto para que detecte .venv automáticamente
;; (defun my-activar-venv ()
;;   "Busca y activa el entorno virtual .venv del proyecto automáticamente."
;;   (let* ((root (locate-dominating-file buffer-file-name ".venv"))
;;          (venv-path (if root (expand-file-name ".venv" root) nil)))
;;     (when (and venv-path (file-exists-p venv-path))
;;       (pyvenv-activate venv-path)
;;       (message "Entorno UV activado: %s" venv-path))))
;; (add-hook 'python-mode-hook 'my-activar-venv)
(setq scroll-margin 10
      scroll-step 1
      scroll-conservatively 101) ;; Un valor > 100 asegura que el cursor nunca salte al centro
