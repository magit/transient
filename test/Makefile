-include ../config.mk
include ../default.mk

.PHONY: test
test:
	@$(EMACS) -Q $(EMACS_ARGS) $(LOAD_PATH) -L ../lisp -l transient-tests --eval "(ert-run-tests-interactively t)"
