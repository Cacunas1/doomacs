;;; gptel-multiagent.el --- Planner/implementer/reviewer gptel sessions -*- lexical-binding: t; -*-

;;; Commentary:
;; Three side-by-side gptel chat buffers, one per role, routed through the local
;; Codeen LiteLLM proxy.  Hand-off between agents is manual (copy/paste).
;; All settings are buffer-local; global gptel defaults are left untouched.

;;; Code:

(defgroup gptel-multiagent nil
  "Planner/implementer/reviewer gptel sessions."
  :group 'tools)

(defcustom gptel-multiagent-host "localhost:8150"
  "Host and port of the local Codeen LiteLLM proxy."
  :type 'string
  :group 'gptel-multiagent)

(defcustom gptel-multiagent-endpoint "/cosmos/genai-gateway/v1/chat/completions"
  "Chat-completions path on the proxy."
  :type 'string
  :group 'gptel-multiagent)

(defcustom gptel-multiagent-roles
  '((planner
     :buffer "*gptel-planner*"
     :model claude-opus-5-5
     :system "You are the PLANNER agent. Produce detailed, step-by-step implementation plans that a less capable model can follow without guessing: name exact files, functions and commands, include code snippets where useful, and end with a verification section. Do not implement the plan yourself. Reply in Spanish (Chilean technical register, no slang); keep code identifiers in English.")
    (implementer
     :buffer "*gptel-implementer*"
     :model gpt-6-luna
     :system "You are the IMPLEMENTER agent. You receive a plan and implement it faithfully. Output complete code (full files or unified diffs) ready to apply, one block per file, with the file path stated before each block. Do not redesign the plan; if a step is ambiguous or wrong, say so explicitly instead of improvising. Reply in Spanish (Chilean technical register, no slang); keep code identifiers in English.")
    (reviewer
     :buffer "*gptel-reviewer*"
     :model gpt-5.6-sol
     :system "You are the REVIEWER agent. You receive a plan and its implementation. Report correctness bugs, deviations from the plan, security issues and missing verification, ordered from most to least severe, each with the exact location and a concrete fix. Do not rewrite the whole implementation. Reply in Spanish (Chilean technical register, no slang); keep code identifiers in English."))
  "Role definitions: buffer name, model and system prompt for each agent."
  :type '(alist :key-type symbol :value-type plist)
  :group 'gptel-multiagent)

(defvar gptel-multiagent--backend nil
  "Cached gptel backend pointing at the Codeen proxy.")

(defun gptel-multiagent--models ()
  "Return the distinct models used by `gptel-multiagent-roles'."
  (delete-dups (mapcar (lambda (role) (plist-get (cdr role) :model))
                       gptel-multiagent-roles)))

(defun gptel-multiagent--backend ()
  "Return the Codeen backend, creating it on first use."
  (require 'gptel)
  (or gptel-multiagent--backend
      (setq gptel-multiagent--backend
            (gptel-make-openai "Codeen"
              :host gptel-multiagent-host
              :protocol "http"
              :endpoint gptel-multiagent-endpoint
              :stream t
              :models (gptel-multiagent--models)))))

;; Register the backend as soon as gptel loads, so saved Org chats can restore
;; it with `gptel-mode' after a restart.  Global defaults are not modified.
(after! gptel
  (gptel-multiagent--backend))

(defun gptel-multiagent--session (role)
  "Return the chat buffer for ROLE, (re)applying its backend, model and system prompt.
Signal a `user-error' if a non-gptel buffer with the same name already has content."
  (let* ((spec (or (alist-get role gptel-multiagent-roles)
                   (user-error "Rol desconocido: %s" role)))
         (name (plist-get spec :buffer))
         (backend (gptel-multiagent--backend))
         (buffer (get-buffer-create name)))
    (with-current-buffer buffer
      (when (and (> (buffer-size) 0)
                 (not (bound-and-true-p gptel-mode)))
        (user-error "El buffer %s existe y no es una sesión gptel; ciérralo o renómbralo" name))
      (unless (derived-mode-p 'org-mode)
        (org-mode))
      ;; Backend, model and system prompt must be set before enabling `gptel-mode'.
      (setq-local gptel-backend backend)
      (setq-local gptel-model (plist-get spec :model))
      (setq-local gptel--system-message (plist-get spec :system))
      (unless (bound-and-true-p gptel-mode)
        (gptel-mode 1))
      (when (= (buffer-size) 0)
        (insert (gptel-prompt-prefix-string))))
    buffer))

(defun gptel-multiagent-open ()
  "Show the planner, implementer and reviewer chats in three side-by-side columns."
  (interactive)
  (let ((buffers (mapcar #'gptel-multiagent--session
                         '(planner implementer reviewer))))
    (delete-other-windows)
    (let* ((left (selected-window))
           (middle (split-window-right))
           (right (with-selected-window middle (split-window-right))))
      (balance-windows)
      (set-window-buffer left (nth 0 buffers))
      (set-window-buffer middle (nth 1 buffers))
      (set-window-buffer right (nth 2 buffers))
      (select-window left)
      (goto-char (point-max)))))

;; Extend the native `SPC o l' (llm) prefix from the :tools llm module with
;; two free keys; the module's own bindings are left as they are.
(map! :leader
      (:prefix "o l"
       :desc "Abrir 3 agentes"   "3" #'gptel-multiagent-open
       :desc "Abortar respuesta" "k" #'gptel-abort))

(provide 'gptel-multiagent)
;;; gptel-multiagent.el ends here
