;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets. It is optional.
;; (setq user-full-name "John Doe"
;;       user-mail-address "john@doe.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-symbol-font' -- for symbols
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
;;(setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light)
;;      doom-variable-pitch-font (font-spec :family "Fira Sans" :size 13))
;; Fira Code tamaño 12 (el estándar de Doom).
;; 'semi-light' suele verse muy bien en pantallas Retina,
;; pero puedes cambiarlo a 'medium' o 'regular' si la sientes muy fina.
(setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light)
      ;; Opcional: Fuente para comentarios y docstrings (Cursiva)
      ;; Si no tienes 'Script12 BT', puedes borrar esta línea o usar otra cursiva.
      ;; O simplemente dejar que use Fira Code también.
      doom-variable-pitch-font (font-spec :family "Fira Code" :size 13))
;;
;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-oceanic-next)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type t)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")


;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `with-eval-after-load' block, otherwise Doom's defaults may override your
;; settings. E.g.
;;
;;   (with-eval-after-load 'PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look them up).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.

;;; Transparency
;; Set background transparency to 90% (100 is fully opaque, 0 is fully transparent)
(add-to-list 'default-frame-alist '(alpha-background . 90))
;; To set the transparency for the current frame immediately
(set-frame-parameter nil 'alpha-background 90)
;; Esto intenta activar la barra de título transparente nativa de macOS
(add-to-list 'default-frame-alist '(ns-transparent-titlebar . t))
(add-to-list 'default-frame-alist '(ns-appearance . dark)) ;; o 'light
(add-to-list 'default-frame-alist '(alpha . (90 . 90)))

;;; Performance
;; Optimización del Garbage Collector para archivos grandes y LSP
(setq gc-cons-threshold 100000000) ; 100mb
(setq read-process-output-max (* 1024 1024)) ; 1mb para mejorar el throughput de LSP/Jupyter

;;; Data Science: Jupyter + Org-Babel
(after! org
  (setq org-image-actual-width '(450))
  (add-hook 'org-babel-after-execute-hook #'org-display-inline-images))

(after! jupyter
  (setq jupyter-repl-echo-eval-p t))

;;; LSP & Python (basedpyright en venv)
(after! lsp-pyright
  (setq lsp-pyright-langserver-command (expand-file-name "~/.config/doom/.venv/bin/basedpyright")
        lsp-pyright-venv-path (expand-file-name "~/.config/doom/.venv")))

;;; Formato Python con Ruff (usa ruff del venv)
(after! format
  (set-formatter! 'ruff
    (lambda ()
      (list (expand-file-name "~/.config/doom/.venv/bin/ruff")
            "format" "--stdin-filename" (or (buffer-file-name) "") "-"))
    :modes '(python-mode python-ts-mode)))

;;; SQL / BigQuery
(after! sql
  (setq sql-product 'ansi)
  (sql-set-product-feature 'ansi :prompt-regexp "^.*> "))

;;; Keybindings Data Science (SPC d)
(map! :leader
      :prefix ("d" . "data-science")
      :desc "Ejecutar celda Jupyter"   "j" #'jupyter-eval-line-or-region
      :desc "Reiniciar kernel Jupyter" "r" #'jupyter-repl-restart-kernel
      :desc "Inspeccionar objeto"      "i" #'lsp-describe-thing-at-point
      :desc "Conectar BigQuery (SQL)"  "b" #'sql-connect)

;; asegura transparencia en tema también
(add-hook 'doom-load-theme-hook
          (lambda ()
            (set-frame-parameter nil 'alpha-background 90)))
