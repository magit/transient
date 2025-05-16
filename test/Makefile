-include ../config.mk
include ../default.mk

LOAD_PATH  += -L $(TOP)test

test: lisp
	@printf "  Testing...\n"
	@$(EMACS) -Q --batch $(EMACS_ARGS) $(LOAD_PATH) \
	-l ert -l $(PKG)-test -f ert-run-tests-batch-and-exit

lisp: ../lisp/$(PKG).elc $(PKG)-test.elc

clean:
	@printf " Cleaning test/*...\n"
	@rm -rf $(PKG)-test.elc
