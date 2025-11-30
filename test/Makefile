-include ../config.mk
include ../default.mk

LOAD_PATH += -L $(TOP)test

test: lisp
	@printf "  Testing...\n"
	@$(EMACS_BATCH) --load ert --load $(PKG)-test \
	--funcall ert-run-tests-batch-and-exit

lisp: ../lisp/$(PKG).elc $(PKG)-test.elc

%.elc: %.el
	@printf "Compiling $<\n"
	@$(EMACS_BATCH) --funcall batch-byte-compile $<

clean:
	@printf " Cleaning test/*...\n"
	@rm -rf $(PKG)-test.elc
