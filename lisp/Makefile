-include ../config.mk
include ../default.mk

lisp: $(ELCS) loaddefs check-declare

loaddefs: $(PKG)-autoloads.el

%.elc: %.el
	@printf "Compiling $<\n"
	@$(EMACS) -Q --batch $(EMACS_ARGS) $(LOAD_PATH) -f batch-byte-compile $<

check-declare:
	@printf " Checking function declarations\n"
	@$(EMACS) -Q --batch $(EMACS_ARGS) $(LOAD_PATH) \
	--eval "(check-declare-directory default-directory)"

CLEAN = $(ELCS) $(PKG)-autoloads.el

clean:
	@printf " Cleaning lisp/*...\n"
	@rm -rf $(CLEAN)

$(PKG)-autoloads.el: $(ELS)
	@printf " Creating $@\n"
	@$(EMACS) -Q --batch -l autoload -l cl-lib --eval "\
(let ((file (expand-file-name \"$@\"))\
      (autoload-timestamps nil) \
      (backup-inhibited t)\
      (version-control 'never)\
      (coding-system-for-write 'utf-8-emacs-unix))\
  (write-region (autoload-rubric file \"package\" nil) nil file nil 'silent)\
  (cl-letf (((symbol-function 'progress-reporter-do-update) (lambda (&rest _)))\
            ((symbol-function 'progress-reporter-done) (lambda (_))))\
    (let ((generated-autoload-file file))\
      (update-directory-autoloads default-directory))))" \
	2>&1 | sed "/^Package autoload is deprecated$$/d"
