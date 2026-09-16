;;; claude-code-org.el --- View Claude Code chats as Org files -*- lexical-binding: t; -*-

;;; Commentary:
;; Local Doom Emacs integration for converting Claude Code JSON/JSONL session
;; files into generated Org documents.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defgroup claude-code-org nil
  "View Claude Code chats as generated Org files."
  :group 'tools)

(defcustom claude-code-org-source-roots
  (list (expand-file-name "~/.claude/projects"))
  "Directories where Claude Code session files are searched recursively."
  :type '(repeat directory)
  :group 'claude-code-org)

(defcustom claude-code-org-directory
  (expand-file-name ".local/claude-code-chats/" doom-user-dir)
  "Directory where generated Org files are stored."
  :type 'directory
  :group 'claude-code-org)

(defcustom claude-code-org-python-command
  (or (executable-find "python3") "python3")
  "Python executable used to run the Claude Code to Org converter."
  :type 'string
  :group 'claude-code-org)

(defcustom claude-code-org-open-after-sync-all nil
  "Whether `claude-code-org-sync-all' should open the generated index."
  :type 'boolean
  :group 'claude-code-org)

(defconst claude-code-org--script
  (expand-file-name "scripts/claude-code-to-org.py" doom-user-dir)
  "Path to the JSON/JSONL to Org converter script.")

(defun claude-code-org--sessions-dir ()
  "Return the directory where per-session Org files are stored."
  (expand-file-name "sessions/" claude-code-org-directory))

(defun claude-code-org--index-file ()
  "Return the generated index Org file path."
  (expand-file-name "index.org" claude-code-org-directory))

(defun claude-code-org--ensure-directories ()
  "Create local generated-output directories when needed."
  (make-directory (claude-code-org--sessions-dir) t))

(defun claude-code-org--source-files ()
  "Return Claude Code JSON/JSONL source files discovered under configured roots."
  (let (files)
    (dolist (root claude-code-org-source-roots)
      (let ((expanded-root (expand-file-name root)))
        (when (file-directory-p expanded-root)
          (setq files
                (append files
                        (directory-files-recursively
                         expanded-root
                         "\\.jsonl?\\'"))))))
    (sort (delete-dups files)
          (lambda (a b)
            (time-less-p (file-attribute-modification-time (file-attributes b))
                         (file-attribute-modification-time (file-attributes a)))))))

(defun claude-code-org--output-file-for-source (source)
  "Return generated Org file path for SOURCE."
  (expand-file-name
   (concat (secure-hash 'sha1 (expand-file-name source)) ".org")
   (claude-code-org--sessions-dir)))

(defun claude-code-org--file-mtime (file)
  "Return FILE modification time, or nil if FILE does not exist."
  (when (file-exists-p file)
    (file-attribute-modification-time (file-attributes file))))

(defun claude-code-org--needs-sync-p (source output)
  "Return non-nil if SOURCE should be converted to OUTPUT."
  (let ((source-time (claude-code-org--file-mtime source))
        (output-time (claude-code-org--file-mtime output))
        (script-time (claude-code-org--file-mtime claude-code-org--script)))
    (or (not output-time)
        (and source-time (time-less-p output-time source-time))
        (and script-time (time-less-p output-time script-time)))))

(defun claude-code-org--format-time (file)
  "Return FILE modification time as a readable string."
  (if-let* ((mtime (claude-code-org--file-mtime file)))
      (format-time-string "%Y-%m-%d %H:%M" mtime)
    "sin fecha"))

(defun claude-code-org--source-label (source)
  "Return a completion label for SOURCE."
  (let* ((parent (file-name-nondirectory (directory-file-name (file-name-directory source))))
         (name (file-name-nondirectory source))
         (mtime (claude-code-org--format-time source)))
    (format "%s  ·  %s/%s" mtime parent name)))

(defun claude-code-org--assert-ready ()
  "Signal a user-facing error when required components are missing."
  (unless (executable-find claude-code-org-python-command)
    (user-error "No encontré Python: %s" claude-code-org-python-command))
  (unless (file-exists-p claude-code-org--script)
    (user-error "No encontré el conversor: %s" claude-code-org--script)))

(defun claude-code-org--convert (source output)
  "Convert SOURCE JSON/JSONL chat to OUTPUT Org file."
  (claude-code-org--assert-ready)
  (claude-code-org--ensure-directories)
  (let ((buffer (get-buffer-create "*claude-code-org*")))
    (with-current-buffer buffer
      (erase-buffer))
    (let ((status (call-process claude-code-org-python-command
                                nil buffer nil
                                claude-code-org--script
                                "convert"
                                "--input" (expand-file-name source)
                                "--output" (expand-file-name output))))
      (unless (zerop status)
        (pop-to-buffer buffer)
        (user-error "Falló la conversión de %s" source)))))

(defun claude-code-org-sync-source (source &optional force)
  "Synchronize SOURCE chat into its generated Org file.
When FORCE is non-nil, regenerate even if timestamps look current."
  (interactive
   (list (claude-code-org--read-source "Sincronizar chat Claude Code: ") current-prefix-arg))
  (let ((output (claude-code-org--output-file-for-source source)))
    (when (or force (claude-code-org--needs-sync-p source output))
      (claude-code-org--convert source output))
    output))

(defun claude-code-org--read-source (prompt)
  "Read a Claude Code source file using PROMPT and completion."
  (let ((sources (claude-code-org--source-files)))
    (unless sources
      (user-error "No encontré chats en: %s" (string-join claude-code-org-source-roots ", ")))
    (let* ((candidates
            (mapcar (lambda (source)
                      (cons (claude-code-org--source-label source) source))
                    sources))
           (choice (completing-read prompt candidates nil t)))
      (alist-get choice candidates nil nil #'string=))))

(defun claude-code-org--write-index (sources)
  "Write the generated Org index for SOURCES."
  (claude-code-org--ensure-directories)
  (let ((index-file (claude-code-org--index-file)))
    (with-temp-file index-file
      (insert "#+title: Claude Code Chats\n")
      (insert "#+startup: overview\n\n")
      (insert "* Chats\n\n")
      (insert "Este índice es generado automáticamente por `claude-code-org'.\n\n")
      (if sources
          (dolist (source sources)
            (let* ((output (claude-code-org--output-file-for-source source))
                   (label (claude-code-org--source-label source))
                   (relative-output (file-relative-name output claude-code-org-directory)))
              (insert (format "** %s\n" label))
              (insert (format "- Org: [[file:%s][abrir conversación]]\n" relative-output))
              (insert (format "- Fuente: =%s=\n" source))
              (insert (format "- Última modificación fuente: %s\n\n" (claude-code-org--format-time source)))))
        (insert "No se encontraron chats de Claude Code.\n")))
    index-file))

;;;###autoload
(defun claude-code-org-open-chat (&optional force)
  "Select, synchronize, and open a Claude Code chat as an Org document.
With prefix argument FORCE, regenerate the Org file unconditionally."
  (interactive "P")
  (let* ((source (claude-code-org--read-source "Abrir chat Claude Code: "))
         (output (claude-code-org-sync-source source force)))
    (find-file output)
    (org-mode)
    (message "Chat Claude Code sincronizado: %s" output)))

;;;###autoload
(defun claude-code-org-sync-all (&optional force)
  "Synchronize all discovered Claude Code chats.
With prefix argument FORCE, regenerate all Org files unconditionally."
  (interactive "P")
  (let ((sources (claude-code-org--source-files))
        (synced 0))
    (unless sources
      (user-error "No encontré chats en: %s" (string-join claude-code-org-source-roots ", ")))
    (dolist (source sources)
      (let ((output (claude-code-org--output-file-for-source source)))
        (when (or force (claude-code-org--needs-sync-p source output))
          (claude-code-org--convert source output)
          (cl-incf synced))))
    (claude-code-org--write-index sources)
    (message "Claude Code Org: %d chats detectados, %d sincronizados" (length sources) synced)
    (when claude-code-org-open-after-sync-all
      (find-file (claude-code-org--index-file)))))

;;;###autoload
(defun claude-code-org-open-index (&optional sync-first)
  "Open the generated Claude Code chat index.
With prefix argument SYNC-FIRST, synchronize all chats before opening."
  (interactive "P")
  (if sync-first
      (claude-code-org-sync-all)
    (let ((sources (claude-code-org--source-files)))
      (unless (file-exists-p (claude-code-org--index-file))
        (claude-code-org--write-index sources))))
  (find-file (claude-code-org--index-file))
  (org-mode))

(map! :leader
      :prefix ("o c" . "claude-code")
      :desc "Abrir chat Claude Code" "o" #'claude-code-org-open-chat
      :desc "Sincronizar chats Claude Code" "s" #'claude-code-org-sync-all
      :desc "Abrir índice Claude Code" "i" #'claude-code-org-open-index)

(provide 'claude-code-org)
;;; claude-code-org.el ends here
