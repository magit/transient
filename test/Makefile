-include ../config.mk
include ../default.mk

.PHONY: test
test:
	@$(EMACS) -Q --batch $(EMACS_ARGS) $(LOAD_PATH) -L ../lisp -l transient-tests -f ert-run-tests-batch-and-exit
