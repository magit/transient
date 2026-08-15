((nil
  (copyright-names-regexp
   . "\\(?:Jonas Bernoulli\\|Free Software Foundation, Inc\\.\\)")
  (indent-tabs-mode . nil)
  (lisp-indent-local-overrides
   (cond . 0)
   (cond-let--thread$ . defun)
   (interactive . 0)
   (make-obsolete-variable . 1)
   (thread-first . defun)
   (thread-last . defun)))
 (makefile-mode
  (indent-tabs-mode . t))
 (git-commit-mode
  (git-commit-major-mode . git-commit-elisp-text-mode))
 ("CHANGELOG"
  (nil (fill-column . 70)
       (mode . display-fill-column-indicator))))
