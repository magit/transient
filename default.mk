TOP := $(dir $(lastword $(MAKEFILE_LIST)))

DOMAIN ?= magit.vc

PKG = transient

ELS   = $(PKG).el
ELCS  = $(ELS:.el=.elc)

DEPS  = compat
DEPS += cond-let
DEPS += seq

LOAD_PATH     ?= $(addprefix -L ../../,$(DEPS))
LOAD_PATH     += -L .
ORG_LOAD_PATH ?= -L ../../org/lisp

VERSION ?= $(shell test -e $(TOP).git && git describe --tags --abbrev=0 | cut -c2-)
REVDESC := $(shell test -e $(TOP).git && git describe --tags)

EMACS       ?= emacs
EMACS_ARGS  ?=
EMACS_Q_ARG ?= -Q
EMACS_BATCH ?= $(EMACS) $(EMACS_Q_ARG) --batch $(EMACS_ARGS) $(LOAD_PATH)
EMACS_ORG   ?= $(EMACS) $(EMACS_Q_ARG) --batch $(EMACS_ARGS) $(ORG_LOAD_PATH)
EMACS_INTR  ?= $(EMACS) $(EMACS_Q_ARG) $(EMACS_ARGS) $(LOAD_PATH)

INSTALL_INFO     ?= $(shell command -v ginstall-info || printf install-info)
MAKEINFO         ?= makeinfo
MANUAL_HTML_ARGS ?= --css-ref https://magit.vc/assets/page.css

GITSTATS      ?= gitstats
GITSTATS_DIR  ?= $(TOP)docs/stats
GITSTATS_ARGS ?= -c style=https://magit.vc/assets/stats.css -c max_authors=999

RCLONE      ?= rclone
RCLONE_ARGS ?= -v
