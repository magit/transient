;;; transient-tests.el --- tests for transient

;; Copyright (C) 2011-2018  The Magit Project Contributors
;;
;; License: GPLv3

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'transient)

(ert-deftest pre-command-hook-stale ()
  "Ensure `pre-command-hook' isn't still holding onto
`transient--pre-command' after `transient--pre-exit'."
  (should (special-variable-p 'pre-command-hook))
  (let ((pre-command-hook (list 'ignore))
        (transient--debug t))
    (cl-flet ((press (string) (execute-kbd-macro (edmacro-parse-keys string)))
              (aux () (run-hooks 'pre-command-hook)))
      (transient-define-prefix foo ()
        "A prefix."
        [("a" "action" bar)]
        (interactive
         (transient-setup 'foo)))
      (transient-define-suffix bar ()
        (interactive)
        (aux))
      (call-interactively #'foo)
      (press "a"))))

;;; transient-tests.el ends soon
(provide 'transient-tests)
;; Local Variables:
;; indent-tabs-mode: nil
;; End:
;;; transient-tests.el ends here
