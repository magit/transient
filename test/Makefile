-include ../config.mk
include ../default.mk

LOAD_PATH += -L ../lisp

test: lisp
	@printf "  Testing...\n"
	@$(EMACS_BATCH) -l $(PKG)-test -f ert-run-tests-batch-and-exit

lisp: $(addprefix ../lisp/,$(ELCS)) $(PKG)-test.elc

%.elc: %.el
	@printf "Compiling $<\n"
	@$(EMACS_BATCH) --funcall batch-byte-compile $<

clean:
	@printf " Cleaning test/*...\n"
	@rm -rf $(PKG)-test.elc
