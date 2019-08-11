;;; transient.el --- Transient commands          -*- lexical-binding: t; -*-

;; Copyright (C) 2018-2019  Jonas Bernoulli

;; Author: Jonas Bernoulli <jonas@bernoul.li>
;; Homepage: https://github.com/magit/transient
;; Package-Requires: ((emacs "25.1") (dash "2.15.0"))
;; Keywords: bindings

;; This file is not part of GNU Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation; either version 3 of the License,
;; or (at your option) any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU GPL see http://www.gnu.org/licenses.

;;; Commentary:

;; Taking inspiration from prefix keys and prefix arguments, Transient
;; implements a similar abstraction involving a prefix command, infix
;; arguments and suffix commands.  We could call this abstraction a
;; "transient command", but because it always involves at least two
;; commands (a prefix and a suffix) we prefer to call it just a
;; "transient".

;; When the user calls a transient prefix command, then a transient
;; (temporary) keymap is activated, which binds the transient's infix
;; and suffix commands, and functions that control the transient state
;; are added to `pre-command-hook' and `post-command-hook'.  The
;; available suffix and infix commands and their state are shown in
;; the echo area until the transient is exited by invoking a suffix
;; command.

;; Calling an infix command causes its value to be changed, possibly
;; by reading a new value in the minibuffer.

;; Calling a suffix command usually causes the transient to be exited
;; but suffix commands can also be configured to not exit the
;; transient state.

;;; Code:

(require 'cl-lib)
(require 'dash)
(require 'eieio)
(require 'format-spec)

(eval-when-compile
  (require 'subr-x))

(declare-function info 'info)
(declare-function Man-find-section 'man)
(declare-function Man-next-section 'man)
(declare-function Man-getpage-in-background 'man)

(defvar Man-notify-method)

;;; Options

(defgroup transient nil
  "Transient commands."
  :group 'bindings)

(defcustom transient-show-popup t
  "Whether to show the current transient in a popup buffer.

- If t, then show the popup as soon as a transient prefix command
  is invoked.

- If nil, then do not show the popup unless the user explicitly
  requests it, by pressing an incomplete prefix key sequence.

- If a number, then delay displaying the popup and instead show
  a brief one-line summary.  If zero or negative, then suppress
  even showing that summary and display the pressed key only.

  Show the popup when the user explicitly requests it by pressing
  an incomplete prefix key sequence.  Unless zero, then also show
  the popup after that many seconds of inactivity (using the
  absolute value)."
  :package-version '(transient . "0.1.0")
  :group 'transient
  :type '(choice (const  :tag "instantly" t)
                 (const  :tag "on demand" nil)
                 (const  :tag "on demand (no summary)" 0)
                 (number :tag "after delay" 1)))

(defcustom transient-enable-popup-navigation nil
  "Whether navigation commands are enabled in the transient popup.

While a transient is active the transient popup buffer is not the
current buffer, making it necesary to use dedicated commands to
act on that buffer itself.  If this non-nil, then the following
features are available:

- \"<up>\" moves the cursor to the previous suffix.
  \"<down>\" moves the cursor to the next suffix.
  \"RET\" invokes the suffix the cursor is on.
- \"<mouse-1>\" invokes the clicked on suffix.
- \"C-s\" and \"C-r\" start isearch in the popup buffer."
  :package-version '(transient . "0.2.0")
  :group 'transient
  :type 'boolean)

(defcustom transient-display-buffer-action
  '(display-buffer-in-side-window (side . bottom))
  "The action used to display the transient popup buffer.

The transient popup buffer is displayed in a window using

  \(display-buffer buf transient-display-buffer-action)

The value of this option has the form (FUNCTION . ALIST),
where FUNCTION is a function or a list of functions.  Each such
function should accept two arguments: a buffer to display and
an alist of the same form as ALIST.  See `display-buffer' for
details.

The default is (display-buffer-in-side-window (side . bottom)).
This displays the window at the bottom of the selected frame.
Another useful value is (display-buffer-below-selected).  This
is what `magit-popup' used by default.  For more alternatives
see info node `(elisp)Display Action Functions'.

It may be possible to display the window in another frame, but
whether that works in practice depends on the window-manager.
If the window manager selects the new window (Emacs frame),
then it doesn't work.

If you change the value of this option, then you might also
want to change the value of `transient-mode-line-format'."
  :package-version '(transient . "0.2.0")
  :group 'transient
  :type '(cons (choice function (repeat :tag "Functions" function))
               alist))

(defcustom transient-mode-line-format 'line
  "The mode-line format for the transient popup buffer.

If nil, then the buffer has no mode-line.  If the buffer is not
displayed right above the echo area, then this probably is not
a good value.

If `line' (the default), then the buffer also has no mode-line,
but a thin line is drawn instead, using the background color of
the face `transient-separator'.

Otherwise this can be any mode-line format.
See `mode-line-format' for details."
  :package-version '(transient . "0.2.0")
  :group 'transient
  :type '(choice (const :tag "hide mode-line" nil)
                 (const :tag "substitute thin line" line)
                 (const :tag "name of prefix command"
                        ("%e" mode-line-front-space
                         mode-line-buffer-identification))
                 (sexp  :tag "custom mode-line format")))

(defcustom transient-show-common-commands nil
  "Whether to show common transient suffixes in the popup buffer.

These commands are always shown after typing the prefix key
\"C-x\" when a transient command is active.  To toggle the value
of this variable use \"C-x t\" when a transient is active."
  :package-version '(transient . "0.1.0")
  :group 'transient
  :type 'boolean)

(defcustom transient-read-with-initial-input t
  "Whether to use the last history element as initial minibuffer input."
  :package-version '(transient . "0.2.0")
  :group 'transient
  :type 'boolean)

(defcustom transient-highlight-mismatched-keys nil
  "Whether to highlight keys that do not match their argument.

This only affects infix arguments that represent command-line
arguments.  When this option is non-nil, then the key binding
for infix argument are highlighted when only a long argument
\(e.g. \"--verbose\") is specified but no shor-thand (e.g \"-v\").
In the rare case that a short-hand is specified but does not
match the key binding, then it is highlighed differently.

The highlighting is done using using `transient-mismatched-key'
and `transient-nonstandard-key'."
  :package-version '(transient . "0.1.0")
  :group 'transient
  :type 'boolean)

(defcustom transient-substitute-key-function nil
  "Function used to modify key bindings.

This function is called with one argument, the prefix object,
and must return a key binding description, either the existing
key description it finds in the `key' slot, or a substitution.

This is intended to let users replace certain prefix keys.  It
could also be used to make other substitutions, but that is
discouraged.

For example, \"=\" is hard to reach using my custom keyboard
layout, so I substitute \"(\" for that, which is easy to reach
using a layout optimized for lisp.

  (setq transient-substitute-key-function
        (lambda (obj)
          (let ((key (oref obj key)))
            (if (string-match \"\\\\`\\\\(=\\\\)[a-zA-Z]\" key)
                (replace-match \"(\" t t key 1)
              key)))))"
  :package-version '(transient . "0.1.0")
  :group 'transient
  :type '(choice (const :tag "Transform no keys (nil)" nil) function))

(defcustom transient-detect-key-conflicts nil
  "Whether to detect key binding conflicts.

Conflicts are detected when a transient prefix command is invoked
and results in an error, which prevents the transient from being
used."
  :package-version '(transient . "0.1.0")
  :group 'transient
  :type 'boolean)

(defcustom transient-default-level 4
  "Control what suffix levels are made available by default.

Each suffix command is placed on a level and each prefix command
has a level, which controls which suffix commands are available.
Integers between 1 and 7 (inclusive) are valid levels.

The levels of individual transients and/or their individual
suffixes can be changed individually, by invoking the prefix and
then pressing \"C-x l\".

The default level for both transients and their suffixes is 4.
This option only controls the default for transients.  The default
suffix level is always 4.  The author of a transient should place
certain suffixes on a higher level if they expect that it won't be
of use to most users, and they should place very important suffixes
on a lower level so that the remain available even if the user
lowers the transient level.

\(Magit currently places nearly all suffixes on level 4 and lower
levels are not used at all yet.  So for the time being you should
not set a lower level here and using a higher level might not
give you as many additional suffixes as you hoped.)"
  :package-version '(transient . "0.1.0")
  :group 'transient
  :type '(choice (const :tag "1 - fewest suffixes" 1)
                 (const 2)
                 (const 3)
                 (const :tag "4 - default" 4)
                 (const 5)
                 (const 6)
                 (const :tag "7 - most suffixes" 7)))

(defcustom transient-levels-file
  (locate-user-emacs-file (convert-standard-filename "transient/levels.el"))
  "File used to save levels of transients and their suffixes."
  :package-version '(transient . "0.1.0")
  :group 'transient
  :type 'file)

(defcustom transient-values-file
  (locate-user-emacs-file (convert-standard-filename "transient/values.el"))
  "File used to save values of transients."
  :package-version '(transient . "0.1.0")
  :group 'transient
  :type 'file)

(defcustom transient-history-file
  (locate-user-emacs-file (convert-standard-filename "transient/history.el"))
  "File used to save history of transients and their infixes."
  :package-version '(transient . "0.1.0")
  :group 'transient
  :type 'file)

(defcustom transient-history-limit 10
  "Number of history elements to keep when saving to file."
  :package-version '(transient . "0.1.0")
  :group 'transient
  :type 'integer)

(defcustom transient-save-history t
  "Whether to save history of transient commands when exiting Emacs."
  :package-version '(transient . "0.1.0")
  :group 'transient
  :type 'boolean)

;;; Faces

(defgroup transient-faces nil
  "Faces used by Transient."
  :group 'transient)

(defface transient-heading '((t :inherit font-lock-keyword-face))
  "Face used for headings."
  :group 'transient-faces)

(defface transient-key '((t :inherit font-lock-builtin-face))
  "Face used for keys."
  :group 'transient-faces)

(defface transient-argument '((t :inherit font-lock-warning-face))
  "Face used for enabled arguments."
  :group 'transient-faces)

(defface transient-value '((t :inherit font-lock-string-face))
  "Face used for values."
  :group 'transient-faces)

(defface transient-inactive-argument '((t :inherit shadow))
  "Face used for inactive arguments."
  :group 'transient-faces)

(defface transient-inactive-value '((t :inherit shadow))
  "Face used for inactive values."
  :group 'transient-faces)

(defface transient-unreachable '((t :inherit shadow))
  "Face used for suffixes unreachable from the current prefix sequence."
  :group 'transient-faces)

(defface transient-active-infix '((t :inherit secondary-selection))
  "Face used for the infix for which the value is being read."
  :group 'transient-faces)

(defface transient-unreachable-key '((t :inherit shadow))
  "Face used for keys unreachable from the current prefix sequence."
  :group 'transient-faces)

(defface transient-nonstandard-key '((t :underline t))
  "Face optionally used to highlight keys conflicting with short-argument.
Also see option `transient-highlight-mismatched-keys'."
  :group 'transient-faces)

(defface transient-mismatched-key '((t :underline t))
  "Face optionally used to highlight keys without a short-argument.
Also see option `transient-highlight-mismatched-keys'."
  :group 'transient-faces)

(defface transient-enabled-suffix
  '((t :background "green" :foreground "black" :weight bold))
  "Face used for enabled levels while editing suffix levels.
See info node `(transient)Enabling and Disabling Suffixes'."
  :group 'transient-faces)

(defface transient-disabled-suffix
  '((t :background "red" :foreground "black" :weight bold))
  "Face used for disabled levels while editing suffix levels.
See info node `(transient)Enabling and Disabling Suffixes'."
  :group 'transient-faces)

(defface transient-separator
  '((((class color) (background light)) :background "grey80")
    (((class color) (background  dark)) :background "grey30"))
  "Face used to draw line below transient popup window.
This is only used if `transient-mode-line-format' is `line'.
Only the background color is significant."
  :group 'transient-faces)

;;; Persistence

(defun transient--read-file-contents (file)
  (with-demoted-errors "Transient error: %S"
    (and (file-exists-p file)
         (with-temp-buffer file
           (insert-file-contents file)
           (read (current-buffer))))))

(defun transient--pp-to-file (object file)
  (make-directory (file-name-directory file) t)
  (setq object (cl-sort object #'string< :key #'car))
  (with-temp-file file
    (let ((print-level nil)
          (print-length nil))
      (pp object (current-buffer)))))

(defvar transient-values
  (transient--read-file-contents transient-values-file)
  "Values of transient commands.
The value of this variable persists between Emacs sessions
and you usually should not change it manually.")

(defun transient-save-values ()
  (transient--pp-to-file transient-values transient-values-file))

(defvar transient-levels
  (transient--read-file-contents transient-levels-file)
  "Levels of transient commands.
The value of this variable persists between Emacs sessions
and you usually should not change it manually.")

(defun transient-save-levels ()
  (transient--pp-to-file transient-levels transient-levels-file))

(defvar transient-history
  (transient--read-file-contents transient-history-file)
  "History of transient commands and infix arguments.
The value of this variable persists between Emacs sessions
\(unless `transient-save-history' is nil) and you usually
should not change it manually.")

(defun transient-save-history ()
  (setq transient-history
        (cl-sort (mapcar (pcase-lambda (`(,key . ,val))
                           (cons key (-take transient-history-limit
                                            (delete-dups val))))
                         transient-history)
                 #'string< :key #'car))
  (transient--pp-to-file transient-history transient-history-file))

(defun transient-maybe-save-history ()
  "Save the value of `transient-history'.
If `transient-save-history' is nil, then do nothing."
  (when transient-save-history
    (transient-save-history)))

(unless noninteractive
  (add-hook 'kill-emacs-hook 'transient-maybe-save-history))

;;; Classes
;;;; Prefix

(defclass transient-prefix ()
  ((prototype   :initarg :prototype)
   (command     :initarg :command)
   (level       :initarg :level)
   (variable    :initarg :variable    :initform nil)
   (value       :initarg :value)
   (scope       :initarg :scope       :initform nil)
   (history     :initarg :history     :initform nil)
   (history-pos :initarg :history-pos :initform 0)
   (history-key :initarg :history-key :initform nil)
   (man-page    :initarg :man-page    :initform nil)
   (info-manual :initarg :info-manual :initform nil)
   (transient-suffix     :initarg :transient-suffix     :initform nil)
   (transient-non-suffix :initarg :transient-non-suffix :initform nil)
   (incompatible         :initarg :incompatible         :initform nil))
  "Transient prefix command.

Each transient prefix command consists of a command, which is
stored in a symbols function slot and an object, which is stored
in the `transient--prefix' property of the same object.

When a transient prefix command is invoked, then a clone of that
object is stored in the global variable `transient--prefix' and
the prototype is stored in the clones `prototype' slot.")

;;;; Suffix

(defclass transient-child ()
  ((level
    :initarg :level
    :initform 1
    :documentation "Enable if level of prefix is equal or greater.")
   (if
    :initarg :if
    :initform nil
    :documentation "Enable if predicate returns non-nil.")
   (if-not
    :initarg :if-not
    :initform nil
    :documentation "Enable if predicate returns nil.")
   (if-non-nil
    :initarg :if-non-nil
    :initform nil
    :documentation "Enable if variable's value is non-nil.")
   (if-nil
    :initarg :if-nil
    :initform nil
    :documentation "Enable if variable's value is nil.")
   (if-mode
    :initarg :if-mode
    :initform nil
    :documentation "Enable if major-mode matches value.")
   (if-not-mode
    :initarg :if-not-mode
    :initform nil
    :documentation "Enable if major-mode does not match value.")
   (if-derived
    :initarg :if-derived
    :initform nil
    :documentation "Enable if major-mode derives from value.")
   (if-not-derived
    :initarg :if-not-derived
    :initform nil
    :documentation "Enable if major-mode does not derive from value."))
  "Abstract superclass for group and and suffix classes.

It is undefined what happens if more than one `if*' predicate
slot is non-nil."
  :abstract t)

(defclass transient-suffix (transient-child)
  ((key         :initarg :key)
   (command     :initarg :command)
   (transient   :initarg :transient)
   (format      :initarg :format      :initform " %k %d")
   (description :initarg :description :initform nil))
  "Superclass for suffix command.")

(defclass transient-infix (transient-suffix)
  ((transient                         :initform t)
   (argument    :initarg :argument)
   (shortarg    :initarg :shortarg)
   (value                             :initform nil)
   (multi-value :initarg :multi-value :initform nil)
   (allow-empty :initarg :allow-empty :initform nil)
   (history-key :initarg :history-key :initform nil)
   (reader      :initarg :reader      :initform nil)
   (prompt      :initarg :prompt      :initform nil)
   (choices     :initarg :choices     :initform nil)
   (format                            :initform " %k %d (%v)"))
  "Transient infix command."
  :abstract t)

(defclass transient-argument (transient-infix) ()
  "Abstract superclass for infix arguments."
  :abstract t)

(defclass transient-switch (transient-argument) ()
  "Class used for command-line argument that can be turned on and off.")

(defclass transient-option (transient-argument) ()
  "Class used for command-line argument that can take a value.")

(defclass transient-variable (transient-infix)
  ((variable    :initarg :variable)
   (format                            :initform " %k %d %v"))
  "Abstract superclass for infix commands that set a variable."
  :abstract t)

(defclass transient-switches (transient-argument)
  ((argument-format  :initarg :argument-format)
   (argument-regexp  :initarg :argument-regexp))
  "Class used for sets of mutually exclusive command-line switches.")

(defclass transient-files (transient-infix) ()
  "Class used for the \"--\" argument.
All remaining arguments are treated as files.
They become the value of this this argument.")

;;;; Group

(defclass transient-group (transient-child)
  ((suffixes    :initarg :suffixes    :initform nil)
   (hide        :initarg :hide        :initform nil)
   (description :initarg :description :initform nil))
  "Abstract superclass of all group classes."
  :abstract t)

(defclass transient-column (transient-group) ()
  "Group class that displays each element on a separate line.")

(defclass transient-row (transient-group) ()
  "Group class that displays all elements on a single line.")

(defclass transient-columns (transient-group) ()
  "Group class that displays elements organized in columns.
Direct elements have to be groups whose elements have to be
commands or string.  Each subgroup represents a column.  This
class takes care of inserting the subgroups' elements.")

(defclass transient-subgroups (transient-group) ()
  "Group class that wraps other groups.

Direct elements have to be groups whose elements have to be
commands or strings.  This group inserts an empty line between
subgroups.  The subgroups are responsible for displaying their
elements themselves.")

;;; Define

(defmacro define-transient-command (name arglist &rest args)
  "Define NAME as a transient prefix command.

ARGLIST are the arguments that command takes.
DOCSTRING is the documentation string and is optional.

These arguments can optionally be followed by key-value pairs.
Each key has to be a keyword symbol, either `:class' or a keyword
argument supported by the constructor of that class.  The
`transient-prefix' class is used if the class is not specified
explicitly.

GROUPs add key bindings for infix and suffix commands and specify
how these bindings are presented in the popup buffer.  At least
one GROUP has to be specified.  See info node `(transient)Binding
Suffix and Infix Commands'.

The BODY is optional.  If it is omitted, then ARGLIST is also
ignored and the function definition becomes:

  (lambda ()
    (interactive)
    (transient-setup \\='NAME))

If BODY is specified, then it must begin with an `interactive'
form that matches ARGLIST, and it must call `transient-setup'.
It may however call that function only when some condition is
satisfied; that is one of the reason why you might want to use
an explicit BODY.

All transients have a (possibly nil) value, which is exported
when suffix commands are called, so that they can consume that
value.  For some transients it might be necessary to have a sort
of secondary value, called a scope.  Such a scope would usually
be set in the commands `interactive' form and has to be passed
to the setup function:

  (transient-setup \\='NAME nil nil :scope SCOPE)

\(fn NAME ARGLIST [DOCSTRING] [KEYWORD VALUE]... GROUP... [BODY...])"
  (declare (debug (&define name lambda-list
                           [&optional lambda-doc]
                           [&rest keywordp sexp]
                           [&rest vectorp]
                           [&optional ("interactive" interactive) def-body])))
  (pcase-let ((`(,class ,slots ,suffixes ,docstr ,body)
               (transient--expand-define-args args)))
    `(progn
       (defalias ',name
         ,(if body
              `(lambda ,arglist ,@body)
            `(lambda ()
               (interactive)
               (transient-setup ',name))))
       (put ',name 'interactive-only t)
       (put ',name 'function-documentation ,docstr)
       (put ',name 'transient--prefix
            (,(or class 'transient-prefix) :command ',name ,@slots))
       (put ',name 'transient--layout
            ',(cl-mapcan (lambda (s) (transient--parse-child name s))
                         suffixes)))))

(defmacro define-suffix-command (name arglist &rest args)
  "Define NAME as a transient suffix command.

ARGLIST are the arguments that the command takes.
DOCSTRING is the documentation string and is optional.

These arguments can optionally be followed by key-value pairs.
Each key has to be a keyword symbol, either `:class' or a
keyword argument supported by the constructor of that class.
The `transient-suffix' class is used if the class is not
specified explicitly.

The BODY must begin with an `interactive' form that matches
ARGLIST.  Use the function `transient-args' or the low-level
variable `current-transient-suffixes' if the former does not
give you all the required details.  This should, but does not
necessarily have to be, done inside the `interactive' form;
just like for `prefix-arg' and `current-prefix-arg'.

\(fn NAME ARGLIST [DOCSTRING] [KEYWORD VALUE]... BODY...)"
  (declare (debug (&define name lambda-list
                           [&optional lambda-doc]
                           [&rest keywordp sexp]
                           ("interactive" interactive)
                           def-body)))
  (pcase-let ((`(,class ,slots ,_ ,docstr ,body)
               (transient--expand-define-args args)))
    `(progn
       (defalias ',name (lambda ,arglist ,@body))
       (put ',name 'interactive-only t)
       (put ',name 'function-documentation ,docstr)
       (put ',name 'transient--suffix
            (,(or class 'transient-suffix) :command ',name ,@slots)))))

(defmacro define-infix-command (name _arglist &rest args)
  "Define NAME as a transient infix command.

ARGLIST is always ignored and reserved for future use.
DOCSTRING is the documentation string and is optional.

The key-value pairs are mandatory.  All transient infix commands
are equal to each other (but not eq), so it is meaningless to
define an infix command without also setting at least `:class'
and one other keyword (which it is depends on the used class,
usually `:argument' or `:variable').

Each key has to be a keyword symbol, either `:class' or a keyword
argument supported by the constructor of that class.  The
`transient-switch' class is used if the class is not specified
explicitly.

The function definitions is always:

   (lambda ()
     (interactive)
     (let ((obj (transient-suffix-object)))
       (transient-infix-set obj (transient-infix-read obj)))
     (transient--show))

`transient-infix-read' and `transient-infix-set' are generic
functions.  Different infix commands behave differently because
the concrete methods are different for different infix command
classes.  In rare case the above command function might not be
suitable, even if you define your own infix command class.  In
that case you have to use `transient-suffix-command' to define
the infix command and use t as the value of the `:transient'
keyword.

\(fn NAME ARGLIST [DOCSTRING] [KEYWORD VALUE]...)"
  (declare (debug (&define name lambda-list
                           [&optional lambda-doc]
                           [&rest keywordp sexp])))
  (pcase-let ((`(,class ,slots ,_ ,docstr ,_)
               (transient--expand-define-args args)))
    `(progn
       (defalias ',name ,(transient--default-infix-command))
       (put ',name 'interactive-only t)
       (put ',name 'function-documentation ,docstr)
       (put ',name 'transient--suffix
            (,(or class 'transient-switch) :command ',name ,@slots)))))

(defalias 'define-infix-argument 'define-infix-command
  "Define NAME as a transient infix command.

Only use this alias to define an infix command that actually
sets an infix argument.  To define a infix command that, for
example, sets a variable use `define-infix-command' instead.

\(fn NAME ARGLIST [DOCSTRING] [KEYWORD VALUE]...)")

(defun transient--expand-define-args (args)
  (let (class keys suffixes docstr)
    (when (stringp (car args))
      (setq docstr (pop args)))
    (while (keywordp (car args))
      (let ((k (pop args))
            (v (pop args)))
        (if (eq k :class)
            (setq class v)
          (push k keys)
          (push v keys))))
    (while (vectorp (car args))
      (push (pop args) suffixes))
    (list (if (eq (car-safe class) 'quote)
              (cadr class)
            class)
          (nreverse keys)
          (nreverse suffixes)
          docstr
          args)))

(defun transient--parse-child (prefix spec)
  (cl-etypecase spec
    (vector  (when-let ((c (transient--parse-group  prefix spec))) (list c)))
    (list    (when-let ((c (transient--parse-suffix prefix spec))) (list c)))
    (string  (list spec))))

(defun transient--parse-group (prefix spec)
  (setq spec (append spec nil))
  (cl-symbol-macrolet
      ((car (car spec))
       (pop (pop spec)))
    (let (level class args)
      (when (integerp car)
        (setq level pop))
      (when (stringp car)
        (setq args (plist-put args :description pop)))
      (while (keywordp car)
        (let ((k pop))
          (if (eq k :class)
              (setq class pop)
            (setq args (plist-put args k pop)))))
      (vector (or level (oref-default 'transient-child level))
              (or class
                  (if (vectorp car)
                      'transient-columns
                    'transient-column))
              args
              (cl-mapcan (lambda (s) (transient--parse-child prefix s)) spec)))))

(defun transient--parse-suffix (prefix spec)
  (let (level class args)
    (cl-symbol-macrolet
        ((car (car spec))
         (pop (pop spec)))
      (when (integerp car)
        (setq level pop))
      (when (or (stringp car)
                (vectorp car))
        (setq args (plist-put args :key pop)))
      (when (or (stringp car)
                (eq (car-safe car) 'lambda)
                (and (symbolp car)
                     (not (commandp car))
                     (commandp (cadr spec))))
        (setq args (plist-put args :description pop)))
      (cond
        ((keywordp car)
         (error "Need command, got %S" car))
        ((symbolp car)
         (setq args (plist-put args :command pop)))
        ((or (stringp car)
             (and car (listp car)))
         (let ((arg pop))
           (cl-typecase arg
             (list
              (setq args (plist-put args :shortarg (car  arg)))
              (setq args (plist-put args :argument (cadr arg)))
              (setq arg  (cadr arg)))
             (string
              (when-let ((shortarg (transient--derive-shortarg arg)))
                (setq args (plist-put args :shortarg shortarg)))
              (setq args (plist-put args :argument arg))))
           (setq args (plist-put args :command
                                 (intern (format "transient:%s:%s"
                                                 prefix arg))))
           (cond ((and car (not (keywordp car)))
                  (setq class 'transient-option)
                  (setq args (plist-put args :reader pop)))
                 ((not (string-suffix-p "=" arg))
                  (setq class 'transient-switch))
                 (t
                  (setq class 'transient-option)
                  (setq args (plist-put args :reader 'read-string))))))
        (t
         (error "Needed command or argument, got %S" car)))
      (while (keywordp car)
        (let ((k pop))
          (cl-case k
            (:class (setq class pop))
            (:level (setq level pop))
            (t (setq args (plist-put args k pop)))))))
    (unless (plist-get args :key)
      (when-let ((shortarg (plist-get args :shortarg)))
        (setq args (plist-put args :key shortarg))))
    (list (or level (oref-default 'transient-child level))
          (or class 'transient-suffix)
          args)))

(defun transient--default-infix-command ()
  (cons 'lambda '(()
             (interactive)
             (let ((obj (transient-suffix-object)))
               (transient-infix-set obj (transient-infix-read obj)))
             (transient--show))))

(defun transient--ensure-infix-command (obj)
  (let ((cmd (oref obj command)))
    (unless (or (commandp cmd)
                (get cmd 'transient--infix-command))
      (if (or (cl-typep obj 'transient-switch)
              (cl-typep obj 'transient-option))
          (put cmd 'transient--infix-command
               (transient--default-infix-command))
        ;; This is not an anonymous infix argument.
        (error "Suffix %s is not defined or autoloaded as a command" cmd)))))

(defun transient--derive-shortarg (arg)
  (save-match-data
    (and (string-match "\\`\\(-[a-zA-Z]\\)\\(\\'\\|=\\)" arg)
         (match-string 1 arg))))

;;; Edit

(defun transient--insert-suffix (prefix loc suffix action)
  (let* ((suf (cl-etypecase suffix
                (vector (transient--parse-group  prefix suffix))
                (list   (transient--parse-suffix prefix suffix))
                (string suffix)))
         (mem (transient--layout-member loc prefix))
         (elt (car mem)))
    (cond
     ((not mem)
      (message "Cannot insert %S into %s; %s not found"
               suffix prefix loc))
     ((or (and (vectorp suffix) (not (vectorp elt)))
          (and (listp   suffix) (vectorp elt))
          (and (stringp suffix) (vectorp elt)))
      (message "Cannot place %S into %s at %s; %s"
               suffix prefix loc
               "suffixes and groups cannot be siblings"))
     (t
      (when (and (listp suffix)
                 (listp elt))
        (let ((key (plist-get (nth 2 suf) :key)))
          (if (equal (transient--kbd key)
                     (transient--kbd (plist-get (nth 2 elt) :key)))
              (setq action 'replace)
            (transient-remove-suffix prefix key))))
      (cl-ecase action
        (insert  (setcdr mem (cons elt (cdr mem)))
                 (setcar mem suf))
        (append  (setcdr mem (cons suf (cdr mem))))
        (replace (setcar mem suf)))))))

(defun transient-insert-suffix (prefix loc suffix)
  "Insert a SUFFIX into PREFIX before LOC.
PREFIX is a prefix command, a symbol.
SUFFIX is a suffix command or a group specification (of
  the same forms as expected by `define-transient-command').
LOC is a command, a key vector, a key description (a string
  as returned by `key-description'), or a coordination list
  (whose last element may also be a command or key).
See info node `(transient)Modifying Existing Transients'."
  (declare (indent defun))
  (transient--insert-suffix prefix loc suffix 'insert))

(defun transient-append-suffix (prefix loc suffix)
  "Insert a SUFFIX into PREFIX after LOC.
PREFIX is a prefix command, a symbol.
SUFFIX is a suffix command or a group specification (of
  the same forms as expected by `define-transient-command').
LOC is a command, a key vector, a key description (a string
  as returned by `key-description'), or a coordination list
  (whose last element may also be a command or key).
See info node `(transient)Modifying Existing Transients'."
  (declare (indent defun))
  (transient--insert-suffix prefix loc suffix 'append))

(defun transient-replace-suffix (prefix loc suffix)
  "Replace the suffix at LOC in PREFIX with SUFFIX.
PREFIX is a prefix command, a symbol.
SUFFIX is a suffix command or a group specification (of
  the same forms as expected by `define-transient-command').
LOC is a command, a key vector, a key description (a string
  as returned by `key-description'), or a coordination list
  (whose last element may also be a command or key).
See info node `(transient)Modifying Existing Transients'."
  (declare (indent defun))
  (transient--insert-suffix prefix loc suffix 'replace))

(defun transient-remove-suffix (prefix loc)
  "Remove the suffix or group at LOC in PREFIX.
PREFIX is a prefix command, a symbol.
LOC is a command, a key vector, a key description (a string
  as returned by `key-description'), or a coordination list
  (whose last element may also be a command or key).
See info node `(transient)Modifying Existing Transients'."
  (declare (indent defun))
  (transient--layout-member loc prefix 'remove))

(defun transient-get-suffix (prefix loc)
  "Return the suffix or group at LOC in PREFIX.
PREFIX is a prefix command, a symbol.
LOC is a command, a key vector, a key description (a string
  as returned by `key-description'), or a coordination list
  (whose last element may also be a command or key).
See info node `(transient)Modifying Existing Transients'."
  (if-let ((mem (transient--layout-member loc prefix)))
      (car mem)
    (error "%s not found in %s" loc prefix)))

(defun transient-suffix-put (prefix loc prop value)
  "Edit the suffix at LOC in PREFIX, setting PROP to VALUE.
PREFIX is a prefix command, a symbol.
SUFFIX is a suffix command or a group specification (of
  the same forms as expected by `define-transient-command').
LOC is a command, a key vector, a key description (a string
  as returned by `key-description'), or a coordination list
  (whose last element may also be a command or key).
See info node `(transient)Modifying Existing Transients'."
  (let ((suf (transient-get-suffix prefix loc)))
    (setf (elt suf 2)
          (plist-put (elt suf 2) prop value))))

(defun transient--layout-member (loc prefix &optional remove)
  (let ((val (or (get prefix 'transient--layout)
                 (error "%s is not a transient command" prefix))))
    (when (listp loc)
      (while (integerp (car loc))
        (let* ((children (if (vectorp val) (aref val 3) val))
               (mem (transient--nthcdr (pop loc) children)))
          (if (and remove (not loc))
              (let ((rest (delq (car mem) children)))
                (if (vectorp val)
                    (aset val 3 rest)
                  (put prefix 'transient--layout rest))
                (setq val nil))
            (setq val (if loc (car mem) mem)))))
      (setq loc (car loc)))
    (if loc
        (transient--layout-member-1 (transient--kbd loc) val remove)
      val)))

(defun transient--layout-member-1 (loc layout remove)
  (cond ((listp layout)
         (--any (transient--layout-member-1 loc it remove) layout))
        ((vectorp (car (aref layout 3)))
         (--any (transient--layout-member-1 loc it remove) (aref layout 3)))
        (remove
         (aset layout 3
               (delq (car (transient--group-member loc layout))
                     (aref layout 3)))
         nil)
        (t (transient--group-member loc layout))))

(defun transient--group-member (loc group)
  (cl-member-if (lambda (suffix)
                  (and (listp suffix)
                       (let* ((def (nth 2 suffix))
                              (cmd (plist-get def :command)))
                         (if (symbolp loc)
                             (eq cmd loc)
                           (equal (transient--kbd
                                   (or (plist-get def :key)
                                       (transient--command-key cmd)))
                                  loc)))))
                (aref group 3)))

(defun transient--kbd (keys)
  (when (vectorp keys)
    (setq keys (key-description keys)))
  (when (stringp keys)
    (setq keys (kbd keys)))
  keys)

(defun transient--command-key (cmd)
  (when-let ((obj (get cmd 'transient--suffix)))
    (cond ((slot-boundp obj 'key)
           (oref obj key))
          ((slot-exists-p obj 'shortarg)
           (if (slot-boundp obj 'shortarg)
               (oref obj shortarg)
             (transient--derive-shortarg (oref obj argument)))))))

(defun transient--nthcdr (n list)
  (nthcdr (if (< n 0) (- (length list) (abs n)) n) list))

;;; Variables

(defvar current-transient-prefix nil
  "The transient from which this suffix command was invoked.
This is an object representing that transient, use
`current-transient-command' to get the respective command.")

(defvar current-transient-command nil
  "The transient from which this suffix command was invoked.
This is a symbol representing that transient, use
`current-transient-object' to get the respective object.")

(defvar current-transient-suffixes nil
  "The suffixes of the transient from which this suffix command was invoked.
This is a list of objects.  Usually it is sufficient to instead
use the function `transient-args', which returns a list of
values.  In complex cases it might be necessary to use this
variable instead.")

(defvar post-transient-hook nil
  "Hook run after exiting a transient.")

(defvar transient--prefix nil)
(defvar transient--layout nil)
(defvar transient--suffixes nil)

(defconst transient--stay t   "Do not exist the transient.")
(defconst transient--exit nil "Do exit the transient.")

(defvar transient--exitp nil "Whether to exit the transient.")
(defvar transient--showp nil "Whether the transient is show in a popup buffer.")
(defvar transient--helpp nil "Whether help-mode is active.")
(defvar transient--editp nil "Whether edit-mode is active.")

(defvar transient--active-infix nil "The active infix awaiting user input.")

(defvar transient--timer nil)

(defvar transient--stack nil)

(defvar transient--buffer-name " *transient*"
  "Name of the transient buffer.")

(defvar transient--window nil
  "The window used to display the transient popup.")

(defvar transient--original-window nil
  "The window that was selected before the transient was invoked.
Usually it remains selected while the transient is active.")

(define-obsolete-variable-alias 'transient--source-buffer
  'transient--original-buffer "Transient 0.2.0")

(defvar transient--original-buffer nil
  "The buffer that was current before the transient was invoked.
Usually it remains current while the transient is active.")

(defvar transient--debug nil "Whether put debug information into *Messages*.")

(defvar transient--history nil)

;;; Identities

(defun transient-suffix-object (&optional command)
  "Return the object associated with the current suffix command.

Each suffix commands is associated with an object, which holds
additional information about the suffix, such as its value (in
the case of an infix command, which is a kind of suffix command).

This function is intended to be called by infix commands, whose
command definition usually (at least when defined using
`define-infix-command') is this:

   (lambda ()
     (interactive)
     (let ((obj (transient-suffix-object)))
       (transient-infix-set obj (transient-infix-read obj)))
     (transient--show))

\(User input is read outside of `interactive' to prevent the
command from being added to `command-history'.  See #23.)

Such commands need to be able to access their associated object
to guide how `transient-infix-read' reads the new value and to
store the read value.  Other suffix commands (including non-infix
commands) may also need the object to guide their behavior.

This function attempts to return the object associated with the
current suffix command even if the suffix command was not invoked
from a transient.  (For some suffix command that is a valid thing
to do, for others it is not.)  In that case nil may be returned
if the command was not defined using one of the macros intended
to define such commands.

The optional argument COMMAND is intended for internal use.  If
you are contemplating using it in your own code, then you should
probably use this instead:

  (get COMMAND 'transient--suffix)"
  (if transient--prefix
      (cl-find-if (lambda (obj)
                    (eq (transient--suffix-command obj)
                        (or command this-original-command)))
                  transient--suffixes)
    (when-let ((obj (get (or command this-command) 'transient--suffix))
               (obj (clone obj)))
      (transient-init-scope obj)
      (transient-init-value obj)
      obj)))

(defun transient--suffix-command (arg)
  "Return the command specified by ARG.

Given a suffix specified by ARG, this function returns the
respective command or a symbol that represents it.  It could
therefore be considered the inverse of `transient-suffix-object'.

Unlike that function it is only intended for internal use though,
and it is more complicated to describe because of some internal
tricks it has to account for.  You do not actually have to know
any of this.

ARG can be a `transient-suffix' object, a symbol representing a
command, or a command (which can be either a fbound symbol or a
lambda expression).

If it is an object, then the value of its `command' slot is used
as follows.  If ARG satisfies `commandp', then that is returned.
Otherwise it is assumed to be a symbol that merely represents the
command.  In that case the lambda expression that is stored in
the symbols `transient--infix-command' property is returned.

Therefore, if ARG is an object, then this function always returns
something that is callable as a command.

ARG can also be something that is callable as a function.  If it
is a symbol, then that is returned.  Otherwise it is a lambda
expression and a symbol that merely representing that command is
returned.

Therefore, if ARG is something that is callable as a command,
then this function always returns a symbol that is, or merely
represents that command.

The reason that there are \"symbols that merely represent a
command\" is that by avoiding binding a symbol as a command we
can prevent it from being offered as a completion candidate for
`execute-extended-command'.  That is useful for infix arguments,
which usually do not work correctly unless called from a
transient.  Unfortunately this only works for infix arguments
that are defined inline in the definition of a transient prefix
command; explicitly defined infix arguments continue to pollute
the command namespace.  It would be better if all this were made
unnecessary by a `execute-extended-command-ignore' symbol property
but unfortunately that does not exist (yet?)."
  (if (transient-suffix--eieio-childp arg)
      (let ((sym (oref arg command)))
        (if (commandp sym)
            sym
          (get sym 'transient--infix-command)))
    (if (symbolp arg)
        arg
      ;; ARG is an interactive lambda.  The symbol returned by this
      ;; is not actually a command, just a symbol representing it
      ;; for purposes other than invoking it as a command.
      (oref (transient-suffix-object) command))))

;;; Keymaps

(defvar transient-base-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "ESC ESC ESC") 'transient-quit-all)
    (define-key map (kbd "C-g") 'transient-quit-one)
    (define-key map (kbd "C-q") 'transient-quit-all)
    (define-key map (kbd "C-z") 'transient-suspend)
    (define-key map (kbd "C-v") 'transient-scroll-up)
    (define-key map (kbd "M-v") 'transient-scroll-down)
    (define-key map [next]      'transient-scroll-up)
    (define-key map [prior]     'transient-scroll-down)
    map)
  "Parent of other keymaps used by Transient.

This is the parent keymap of all the keymaps that are used in
all transients: `transient-map' (which in turn is the parent
of the transient-specific keymaps), `transient-edit-map' and
`transient-sticky-map'.

If you change a binding here, then you might also have to edit
`transient-sticky-map' and `transient-common-commands'.  While
the latter isn't a proper transient prefix command, it can be
edited using the same functions as used for transients.")

(defvar transient-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map transient-base-map)
    (define-key map (kbd "C-p") 'universal-argument)
    (define-key map (kbd "C--") 'negative-argument)
    (define-key map (kbd "C-t") 'transient-show)
    (define-key map (kbd "?")   'transient-help)
    (define-key map (kbd "C-h") 'transient-help)
    (define-key map (kbd "M-p") 'transient-history-prev)
    (define-key map (kbd "M-n") 'transient-history-next)
    map)
  "Top-level keymap used by all transients.")

(defvar transient-edit-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map transient-base-map)
    (define-key map (kbd "?")     'transient-help)
    (define-key map (kbd "C-h")   'transient-help)
    (define-key map (kbd "C-x l") 'transient-set-level)
    map)
  "Keymap that is active while a transient in is in \"edit mode\".")

(defvar transient-sticky-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map transient-base-map)
    (define-key map (kbd "C-g") 'transient-quit-seq)
    map)
  "Keymap that is active while an incomplete key sequence is active.")

(defvar transient--common-command-prefixes '(?\C-x))

(put 'transient-common-commands
     'transient--layout
     (cl-mapcan
      (lambda (s) (transient--parse-child 'transient-common-commands s))
      '([:hide (lambda ()
                 (and (not (memq (car transient--redisplay-key)
                                 transient--common-command-prefixes))
                      (not transient-show-common-commands)))
         ["Value commands"
          ("C-x s  " "Set"            transient-set)
          ("C-x C-s" "Save"           transient-save)
          ("M-p    " "Previous value" transient-history-prev)
          ("M-n    " "Next value"     transient-history-next)]
         ["Sticky commands"
          ;; Like `transient-sticky-map' except that
          ;; "C-g" has to be bound to a different command.
          ("C-g" "Quit prefix or transient" transient-quit-one)
          ("C-q" "Quit transient stack"     transient-quit-all)
          ("C-z" "Suspend transient stack"  transient-suspend)]
         ["Customize"
          ("C-x t" transient-toggle-common
           :description (lambda ()
                          (if transient-show-common-commands
                              "Hide common commands"
                            "Show common permanently")))
          ("C-x l" "Show/hide suffixes" transient-set-level)]])))

(defvar transient-predicate-map
  (let ((map (make-sparse-keymap)))
    (define-key map [handle-switch-frame]     'transient--do-suspend)
    (define-key map [transient-suspend]       'transient--do-suspend)
    (define-key map [transient-help]          'transient--do-stay)
    (define-key map [transient-set-level]     'transient--do-stay)
    (define-key map [transient-history-prev]  'transient--do-stay)
    (define-key map [transient-history-next]  'transient--do-stay)
    (define-key map [universal-argument]      'transient--do-stay)
    (define-key map [negative-argument]       'transient--do-stay)
    (define-key map [digit-argument]          'transient--do-stay)
    (define-key map [transient-quit-all]      'transient--do-quit-all)
    (define-key map [transient-quit-one]      'transient--do-quit-one)
    (define-key map [transient-quit-seq]      'transient--do-stay)
    (define-key map [transient-show]          'transient--do-stay)
    (define-key map [transient-update]        'transient--do-stay)
    (define-key map [transient-toggle-common] 'transient--do-stay)
    (define-key map [transient-set]           'transient--do-call)
    (define-key map [transient-save]          'transient--do-call)
    (define-key map [describe-key-briefly]    'transient--do-stay)
    (define-key map [describe-key]            'transient--do-stay)
    (define-key map [transient-scroll-up]     'transient--do-stay)
    (define-key map [transient-scroll-down]   'transient--do-stay)
    (define-key map [mwheel-scroll]           'transient--do-stay)
    (define-key map [transient-noop]              'transient--do-noop)
    (define-key map [transient-mouse-push-button] 'transient--do-move)
    (define-key map [transient-push-button]       'transient--do-move)
    (define-key map [transient-backward-button]   'transient--do-move)
    (define-key map [transient-forward-button]    'transient--do-move)
    (define-key map [transient-isearch-backward]  'transient--do-move)
    (define-key map [transient-isearch-forward]   'transient--do-move)
    map)
  "Base keymap used to map common commands to their transient behavior.

The \"transient behavior\" of a command controls, among other
things, whether invoking the command causes the transient to be
exited or not and whether infix arguments are exported before
doing so.

Each \"key\" is a command that is common to all transients and
that is bound in `transient-map', `transient-edit-map',
`transient-sticky-map' and/or `transient-common-command'.

Each binding is a \"pre-command\", a function that controls the
transient behavior of the respective command.

For transient commands that are bound in individual transients,
the transient behavior is specified using the `:transient' slot
of the corresponding object.")

(defvar transient-popup-navigation-map)

(defvar transient--transient-map nil)
(defvar transient--predicate-map nil)
(defvar transient--redisplay-map nil)
(defvar transient--redisplay-key nil)

(defun transient--push-keymap (map)
  (transient--debug "   push %s%s" map (if (symbol-value map) "" " VOID"))
  (with-demoted-errors "transient--push-keymap: %S"
    (internal-push-keymap (symbol-value map) 'overriding-terminal-local-map)))

(defun transient--pop-keymap (map)
  (transient--debug "   pop  %s%s" map (if (symbol-value map) "" " VOID"))
  (with-demoted-errors "transient--pop-keymap: %S"
    (internal-pop-keymap (symbol-value map) 'overriding-terminal-local-map)))

(defun transient--make-transient-map ()
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map (if transient--editp
                               transient-edit-map
                             transient-map))
    (dolist (obj transient--suffixes)
      (let ((key (oref obj key)))
        (when (vectorp key)
          (setq key (key-description key))
          (oset obj key key))
        (when transient-substitute-key-function
          (setq key (save-match-data
                      (funcall transient-substitute-key-function obj)))
          (oset obj key key))
        (let ((kbd (kbd key))
              (cmd (transient--suffix-command obj)))
          (when-let ((conflict (and transient-detect-key-conflicts
                                    (transient--lookup-key map kbd))))
            (unless (eq cmd conflict)
              (error "Cannot bind %S to %s and also %s"
                     (string-trim key)
                     cmd conflict)))
          (define-key map kbd cmd))))
    (when transient-enable-popup-navigation
      (setq map
            (make-composed-keymap (list map transient-popup-navigation-map))))
    map))

(defun transient--make-predicate-map ()
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map transient-predicate-map)
    (dolist (obj transient--suffixes)
      (let* ((cmd (transient--suffix-command obj))
             (sub-prefix (and (symbolp cmd) (get cmd 'transient--prefix))))
        (if (slot-boundp obj 'transient)
            (define-key map (vector cmd)
              (let ((do (oref obj transient)))
                (pcase do
                  (`t (if sub-prefix
                          'transient--do-replace
                        'transient--do-stay))
                  (`nil 'transient--do-exit)
                  (_ do))))
          (unless (lookup-key transient-predicate-map (vector cmd))
            (define-key map (vector cmd)
              (if sub-prefix
                  'transient--do-replace
                (or (oref transient--prefix transient-suffix)
                    'transient--do-exit)))))))
    map))

(defun transient--make-redisplay-map ()
  (setq transient--redisplay-key
        (cl-case this-command
          (transient-update
           (setq transient--showp t)
           (setq unread-command-events
                 (listify-key-sequence (this-single-command-raw-keys))))
          (transient-quit-seq
           (setq unread-command-events
                 (butlast (listify-key-sequence
                           (this-single-command-raw-keys))
                          2))
           (butlast transient--redisplay-key))
          (t nil)))
  (let ((topmap (make-sparse-keymap))
        (submap (make-sparse-keymap)))
    (when transient--redisplay-key
      (define-key topmap (vconcat transient--redisplay-key) submap)
      (set-keymap-parent submap transient-sticky-map))
    (map-keymap-internal
     (lambda (key def)
       (when (and (not (eq key ?\e))
                  (listp def)
                  (keymapp def))
         (define-key topmap (vconcat transient--redisplay-key (list key))
           'transient-update)))
     (if transient--redisplay-key
         (lookup-key transient--transient-map (vconcat transient--redisplay-key))
       transient--transient-map))
    topmap))

;;; Setup

(defun transient-setup (&optional name layout edit &rest params)
  "Setup the transient specified by NAME.

This function is called by transient prefix commands to setup the
transient.  In that case NAME is mandatory, LAYOUT and EDIT must
be nil and PARAMS may be (but usually is not) used to set e.g. the
\"scope\" of the transient (see `transient-define-prefix').

This function is also called internally in which case LAYOUT and
EDIT may be non-nil."
  (transient--debug 'setup)
  (cond
   ((not name)
    ;; Switching between regular and edit mode.
    (transient--pop-keymap 'transient--transient-map)
    (transient--pop-keymap 'transient--redisplay-map)
    (setq name (oref transient--prefix command))
    (setq params (list :scope (oref transient--prefix scope))))
   ((not (or layout                      ; resuming parent/suspended prefix
             current-transient-command)) ; entering child prefix
    (transient--stack-zap))              ; replace suspended prefix, if any
   (edit
    ;; Returning from help to edit.
    (setq transient--editp t)))
  (transient--init-objects name layout params)
  (transient--history-init transient--prefix)
  (setq transient--predicate-map (transient--make-predicate-map))
  (setq transient--transient-map (transient--make-transient-map))
  (setq transient--redisplay-map (transient--make-redisplay-map))
  (setq transient--original-window (selected-window))
  (setq transient--original-buffer (current-buffer))
  (transient--redisplay)
  (transient--init-transient)
  (transient--suspend-which-key-mode))

(defun transient--init-objects (name layout params)
  (setq transient--prefix
        (let ((proto (get name 'transient--prefix)))
          (apply #'clone proto
                 :prototype proto
                 :level (or (alist-get
                             t (alist-get name transient-levels))
                            transient-default-level)
                 params)))
  (transient-init-value transient--prefix)
  (setq transient--layout
        (or layout
            (let ((levels (alist-get name transient-levels)))
              (cl-mapcan (lambda (c) (transient--init-child levels c))
                         (append (get name 'transient--layout)
                                 (and (not transient--editp)
                                      (get 'transient-common-commands
                                           'transient--layout)))))))
  (setq transient--suffixes
        (cl-labels ((s (def)
                       (cond
                        ((stringp def) nil)
                        ((listp def) (cl-mapcan #'s def))
                        ((transient-group--eieio-childp def)
                         (cl-mapcan #'s (oref def suffixes)))
                        ((transient-suffix--eieio-childp def)
                         (list def)))))
          (cl-mapcan #'s transient--layout))))

(defun transient--init-child (levels spec)
  (cl-etypecase spec
    (vector  (transient--init-group  levels spec))
    (list    (transient--init-suffix levels spec))
    (string  (list spec))))

(defun transient--init-group (levels spec)
  (pcase-let ((`(,level ,class ,args ,children) (append spec nil)))
    (when (transient--use-level-p level)
      (let ((obj (apply class :level level args)))
        (when (transient--use-suffix-p obj)
          (when-let ((suffixes
                      (cl-mapcan (lambda (c) (transient--init-child levels c))
                                 children)))
            (oset obj suffixes suffixes)
            (list obj)))))))

(defun transient--init-suffix (levels spec)
  (pcase-let* ((`(,level ,class ,args) spec)
               (cmd (plist-get args :command))
               (level (or (alist-get (transient--suffix-command cmd) levels)
                          level)))
    (let ((fn (and (symbolp cmd)
                   (symbol-function cmd))))
      (when (autoloadp fn)
        (transient--debug "   autoload %s" cmd)
        (autoload-do-load fn)))
    (when (transient--use-level-p level)
      (let ((obj (if-let ((proto (and cmd
                                      (symbolp cmd)
                                      (get cmd 'transient--suffix))))
                     (apply #'clone proto :level level args)
                   (apply class :level level args))))
        (transient--init-suffix-key obj)
        (transient--ensure-infix-command obj)
        (when (transient--use-suffix-p obj)
          (transient-init-scope obj)
          (transient-init-value obj)
          (list obj))))))

(cl-defmethod transient--init-suffix-key ((obj transient-suffix))
  (unless (slot-boundp obj 'key)
    (error "No key for %s" (oref obj command))))

(cl-defmethod transient--init-suffix-key ((obj transient-argument))
  (if (transient-switches--eieio-childp obj)
      (cl-call-next-method obj)
    (unless (slot-boundp obj 'shortarg)
      (when-let ((shortarg (transient--derive-shortarg (oref obj argument))))
        (oset obj shortarg shortarg)))
    (unless (slot-boundp obj 'key)
      (if (slot-boundp obj 'shortarg)
          (oset obj key (oref obj shortarg))
        (error "No key for %s" (oref obj command))))))

(defun transient--use-level-p (level &optional edit)
  (or (and transient--editp (not edit))
      (and (>= level 1)
           (<= level (oref transient--prefix level)))))

(defun transient--use-suffix-p (obj)
  (with-slots
      (if if-not if-nil if-non-nil if-mode if-not-mode if-derived if-not-derived)
      obj
    (cond
     (if                  (funcall if))
     (if-not         (not (funcall if-not)))
     (if-non-nil          (symbol-value if-non-nil))
     (if-nil         (not (symbol-value if-nil)))
     (if-mode             (if (atom if-mode)
                              (eq major-mode if-mode)
                            (memq major-mode if-mode)))
     (if-not-mode    (not (if (atom if-not-mode)
                              (eq major-mode if-not-mode)
                            (memq major-mode if-not-mode))))
     (if-derived          (if (atom if-derived)
                              (derived-mode-p if-derived)
                            (apply #'derived-mode-p if-derived)))
     (if-not-derived (not (if (atom if-not-derived)
                              (derived-mode-p if-not-derived)
                            (apply #'derived-mode-p if-not-derived))))
     (t))))

;;; Flow-Control

(defun transient--init-transient ()
  (transient--debug 'init-transient)
  (transient--push-keymap 'transient--transient-map)
  (transient--push-keymap 'transient--redisplay-map)
  (add-hook 'pre-command-hook      #'transient--pre-command)
  (add-hook 'minibuffer-setup-hook #'transient--minibuffer-setup)
  (add-hook 'minibuffer-exit-hook  #'transient--minibuffer-exit)
  (add-hook 'post-command-hook     #'transient--post-command)
  (advice-add 'abort-recursive-edit :after #'transient--minibuffer-exit)
  (when transient--exitp
    ;; This prefix command was invoked as the suffix of another.
    ;; Prevent `transient--post-command' from removing the hooks
    ;; that we just added.
    (setq transient--exitp 'replace)))

(defun transient--pre-command ()
  (transient--debug 'pre-command)
  (cond
   ((memq this-command '(transient-update transient-quit-seq))
    (transient--pop-keymap 'transient--redisplay-map))
   ((and transient--helpp
         (not (memq this-command '(transient-quit-one
                                   transient-quit-all))))
    (cond
     ((transient-help)
      (transient--do-suspend)
      (setq this-command 'transient-suspend)
      (transient--pre-exit))
     (t
      (setq this-command 'transient-undefined))))
   ((and transient--editp
         (transient-suffix-object)
         (not (memq this-command '(transient-quit-one
                                   transient-quit-all
                                   transient-help))))
    (setq this-command 'transient-set-level))
   (t
    (setq transient--exitp nil)
    (when (eq (if-let ((fn (or (lookup-key transient--predicate-map
                                           (vector this-original-command))
                               (oref transient--prefix transient-non-suffix))))
                  (let ((action (funcall fn)))
                    (when (eq action transient--exit)
                      (setq transient--exitp (or transient--exitp t)))
                    action)
                (setq this-command
                      (let ((keys (this-command-keys-vector)))
                        (if (eq (aref keys (1- (length keys))) ?\C-g)
                            'transient-noop
                          'transient-undefined)))
                transient--stay)
              transient--exit)
      (transient--pre-exit)))))

(defun transient--pre-exit ()
  (transient--debug 'pre-exit)
  (transient--delete-window)
  (transient--timer-cancel)
  (transient--pop-keymap 'transient--transient-map)
  (transient--pop-keymap 'transient--redisplay-map)
  (remove-hook 'pre-command-hook #'transient--pre-command)
  (unless transient--showp
    (message ""))
  (setq transient--transient-map nil)
  (setq transient--predicate-map nil)
  (setq transient--redisplay-map nil)
  (setq transient--redisplay-key nil)
  (setq transient--showp nil)
  (setq transient--helpp nil)
  (setq transient--editp nil)
  (setq transient--prefix nil)
  (setq transient--layout nil)
  (setq transient--suffixes nil)
  (setq transient--original-window nil)
  (setq transient--original-buffer nil)
  (setq transient--window nil))

(defun transient--delete-window ()
  (when (window-live-p transient--window)
    (let ((buf (window-buffer transient--window)))
      (with-demoted-errors "Error while exiting transient: %S"
        (delete-window transient--window))
      (kill-buffer buf))))

(defun transient--export ()
  (setq current-transient-prefix transient--prefix)
  (setq current-transient-command (oref transient--prefix command))
  (setq current-transient-suffixes transient--suffixes)
  (transient--history-push transient--prefix))

(defun transient--minibuffer-setup ()
  (transient--debug 'minibuffer-setup)
  (unless (> (minibuffer-depth) 1)
    (unless transient--exitp
      (transient--pop-keymap 'transient--transient-map)
      (transient--pop-keymap 'transient--redisplay-map)
      (remove-hook 'pre-command-hook #'transient--pre-command))
    (remove-hook 'post-command-hook #'transient--post-command)))

(defun transient--minibuffer-exit ()
  (transient--debug 'minibuffer-exit)
  (unless (> (minibuffer-depth) 1)
    (unless transient--exitp
      (transient--push-keymap 'transient--transient-map)
      (transient--push-keymap 'transient--redisplay-map)
      (add-hook 'pre-command-hook #'transient--pre-command))
    (add-hook 'post-command-hook #'transient--post-command)))

(defun transient--post-command ()
  (transient--debug 'post-command)
  (if transient--exitp
      (progn
        (unless (and (eq transient--exitp 'replace)
                     (or transient--prefix
                         ;; The current command could act as a prefix,
                         ;; but decided not to call `transient-setup'.
                         (prog1 nil (transient--stack-zap))))
          (remove-hook   'minibuffer-setup-hook #'transient--minibuffer-setup)
          (remove-hook   'minibuffer-exit-hook  #'transient--minibuffer-exit)
          (advice-remove 'abort-recursive-edit  #'transient--minibuffer-exit)
          (remove-hook   'post-command-hook     #'transient--post-command))
        (setq current-transient-prefix nil)
        (setq current-transient-command nil)
        (setq current-transient-suffixes nil)
        (let ((resume (and transient--stack
                           (not (memq transient--exitp '(replace suspend))))))
          (setq transient--exitp nil)
          (setq transient--helpp nil)
          (setq transient--editp nil)
          (run-hooks 'post-transient-hook)
          (when resume
            (transient--stack-pop))))
    (transient--pop-keymap 'transient--redisplay-map)
    (setq transient--redisplay-map (transient--make-redisplay-map))
    (transient--push-keymap 'transient--redisplay-map)
    (unless (eq this-command (oref transient--prefix command))
      (transient--redisplay))))

(defun transient--stack-push ()
  (transient--debug 'stack-push)
  (push (list (oref transient--prefix command)
              transient--layout
              transient--editp
              :scope (oref transient--prefix scope))
        transient--stack))

(defun transient--stack-pop ()
  (transient--debug 'stack-pop)
  (and transient--stack
       (prog1 t (apply #'transient-setup (pop transient--stack)))))

(defun transient--stack-zap ()
  (transient--debug 'stack-zap)
  (setq transient--stack nil))

(defun transient--redisplay ()
  (if (or (eq transient-show-popup t)
          transient--showp)
      (unless (memq this-command '(transient-scroll-up
                                   transient-scroll-down
                                   mwheel-scroll))
        (transient--show))
    (when (and (numberp transient-show-popup)
               (not (zerop transient-show-popup))
               (not transient--timer))
      (transient--timer-start))
    (transient--show-brief)))

(defun transient--timer-start ()
  (setq transient--timer
        (run-at-time (abs transient-show-popup) nil
                     (lambda ()
                       (transient--timer-cancel)
                       (transient--show)
                       (let ((message-log-max nil))
                         (message ""))))))

(defun transient--timer-cancel ()
  (when transient--timer
    (cancel-timer transient--timer)
    (setq transient--timer nil)))

(defun transient--debug (arg &rest args)
  (when transient--debug
    (if (symbolp arg)
        (message "-- %-16s (cmd: %s, exit: %s)"
                 arg this-command transient--exitp)
    (apply #'message arg args))))

(defun transient--emergency-exit ()
  "Exit the current transient command after an error occured.
Beside being used with `condition-case', this function also has
to be a member of `debugger-mode-hook', else the debugger would
be unusable and exiting it by pressing \"q\" would fail because
the transient command would still be active and that key would
either be unbound or do something else."
  (when transient--prefix
    (setq transient--stack nil)
    (setq transient--exitp t)
    (transient--pre-exit)
    (transient--post-command)))

(add-hook 'debugger-mode-hook 'transient--emergency-exit)

(defmacro transient--with-emergency-exit (&rest body)
  (declare (indent defun))
  `(condition-case nil
       ,(macroexp-progn body)
     (error (transient--emergency-exit))))

;;; Pre-Commands

(defun transient--do-stay ()
  "Call the command without exporting variables and stay transient."
  transient--stay)

(defun transient--do-noop ()
  "Call `transient-noop' and stay transient."
  (setq this-command 'transient-noop)
  transient--stay)

(defun transient--do-warn ()
  "Call `transient-undefined' and stay transient."
  (setq this-command 'transient-undefined)
  transient--stay)

(defun transient--do-call ()
  "Call the command after exporting variables and stay transient."
  (transient--export)
  transient--stay)

(defun transient--do-exit ()
  "Call the command after exporting variables and exit the transient."
  (transient--export)
  (transient--stack-zap)
  transient--exit)

(defun transient--do-replace ()
  "Call the transient prefix command, replacing the active transient."
  (transient--export)
  (transient--stack-push)
  (setq transient--exitp 'replace)
  transient--exit)

(defun transient--do-suspend ()
  "Suspend the active transient, saving the transient stack."
  (transient--stack-push)
  (setq transient--exitp 'suspend)
  transient--exit)

(defun transient--do-quit-one ()
  "If active, quit help or edit mode, else exit the active transient."
  (cond (transient--helpp
         (setq transient--helpp nil)
         transient--stay)
        (transient--editp
         (setq transient--editp nil)
         (transient-setup)
         transient--stay)
        (t transient--exit)))

(defun transient--do-quit-all ()
  "Exit all transients without saving the transient stack."
  (transient--stack-zap)
  transient--exit)

(defun transient--do-move ()
  "Call the command if `transient-enable-popup-navigation' is non-nil.
In that case behave like `transient--do-stay', otherwise similar
to `transient--do-warn'."
  (unless transient-enable-popup-navigation
    (setq this-command 'transient-popup-navigation-help))
  transient--stay)

;;; Commands

(defun transient-noop ()
  "Do nothing at all."
  (interactive))

(defun transient-undefined ()
  "Warn the user that the pressed key is not bound to any suffix."
  (interactive)
  (message "Unbound suffix: `%s' (Use `%s' to abort, `%s' for help)"
           (propertize (key-description (this-single-command-keys))
                       'face 'font-lock-warning-face)
           (propertize "C-g" 'face 'transient-key)
           (propertize "?"   'face 'transient-key)))

(defun transient-toggle-common ()
  "Toggle whether common commands are always shown."
  (interactive)
  (setq transient-show-common-commands (not transient-show-common-commands)))

(defun transient-suspend ()
  "Suspend the current transient.
It can later be resumed using `transient-resume' while no other
transient is active."
  (interactive))

(defun transient-quit-all ()
  "Exit all transients without saving the transient stack."
  (interactive))

(defun transient-quit-one ()
  "Exit the current transients, possibly returning to the previous."
  (interactive))

(defun transient-quit-seq ()
  "Abort the current incomplete key sequence."
  (interactive))

(defun transient-update ()
  "Redraw the transient's state in the popup buffer."
  (interactive))

(defun transient-show ()
  "Show the transient's state in the popup buffer."
  (interactive)
  (setq transient--showp t))

(defvar-local transient--restore-winconf nil)

(defvar transient-resume-mode)

(defun transient-help ()
  "Show help for the active transient or one of its suffixes."
  (interactive)
  (if (called-interactively-p 'any)
      (setq transient--helpp t)
    (with-demoted-errors "transient-help: %S"
      (when (lookup-key transient--transient-map
                        (this-single-command-raw-keys))
        (setq transient--helpp nil)
        (let ((winconf (current-window-configuration)))
          (transient-show-help
           (if (eq this-original-command 'transient-help)
               transient--prefix
             (or (transient-suffix-object)
                 this-original-command)))
          (setq transient--restore-winconf winconf))
        (fit-window-to-buffer nil (frame-height) (window-height))
        (transient-resume-mode)
        (message "Type \"q\" to resume transient command.")
        t))))

(defun transient-set-level (&optional command level)
  "Set the level of the transient or one of its suffix commands."
  (interactive
   (let ((command this-original-command)
         (prefix (oref transient--prefix command)))
     (and (or (not (eq command 'transient-set-level))
              (and transient--editp
                   (setq command prefix)))
          (list command
                (let ((keys (this-single-command-raw-keys)))
                  (and (lookup-key transient--transient-map keys)
                       (string-to-number
                        (transient--read-number-N
                         (format "Set level for `%s': "
                                 (transient--suffix-command command))
                         nil nil (not (eq command prefix))))))))))
  (cond
   ((not command)
    (setq transient--editp t)
    (transient-setup))
   (level
    (let* ((prefix (oref transient--prefix command))
           (alist (alist-get prefix transient-levels))
           (key (transient--suffix-command command)))
      (if (eq command prefix)
          (progn (oset transient--prefix level level)
                 (setq key t))
        (oset (transient-suffix-object command) level level))
      (setf (alist-get key alist) level)
      (setf (alist-get prefix transient-levels) alist))
    (transient-save-levels))
   (t
    (transient-undefined))))

(defun transient-set ()
  "Save the value of the active transient for this Emacs session."
  (interactive)
  (transient-set-value (or transient--prefix current-transient-prefix)))

(defun transient-save ()
  "Save the value of the active transient persistenly across Emacs sessions."
  (interactive)
  (transient-save-value (or transient--prefix current-transient-prefix)))

(defun transient-history-next ()
  "Switch to the next value used for the active transient."
  (interactive)
  (let* ((obj transient--prefix)
         (pos (1- (oref obj history-pos)))
         (hst (oref obj history)))
    (if (< pos 0)
        (user-error "End of history")
      (oset obj history-pos pos)
      (oset obj value (nth pos hst))
      (mapc #'transient-init-value transient--suffixes))))

(defun transient-history-prev ()
  "Switch to the previous value used for the active transient."
  (interactive)
  (let* ((obj transient--prefix)
         (pos (1+ (oref obj history-pos)))
         (hst (oref obj history))
         (len (length hst)))
    (if (> pos (1- len))
        (user-error "End of history")
      (oset obj history-pos pos)
      (oset obj value (nth pos hst))
      (mapc #'transient-init-value transient--suffixes))))

(defun transient-scroll-up (&optional arg)
  "Scroll text of transient popup window upward ARG lines.
If ARG is nil scroll near full screen.  This is a wrapper
around `scroll-up-command' (which see)."
  (interactive "^P")
  (with-selected-window transient--window
    (scroll-up-command arg)))

(defun transient-scroll-down (&optional arg)
  "Scroll text of transient popup window down ARG lines.
If ARG is nil scroll near full screen.  This is a wrapper
around `scroll-down-command' (which see)."
  (interactive "^P")
  (with-selected-window transient--window
    (scroll-down-command arg)))

(defun transient-resume ()
  "Resume a previously suspended stack of transients."
  (interactive)
  (cond (transient--stack
         (let ((winconf transient--restore-winconf))
           (kill-local-variable 'transient--restore-winconf)
           (when transient-resume-mode
             (transient-resume-mode -1)
             (quit-window))
           (when winconf
             (set-window-configuration winconf)))
         (transient--stack-pop))
        (transient-resume-mode
         (kill-local-variable 'transient--restore-winconf)
         (transient-resume-mode -1)
         (quit-window))
        (t
         (message "No suspended transient command"))))

;;; Value
;;;; Init

(cl-defgeneric transient-init-scope (obj)
  "Set the scope of the suffix object OBJ.

The scope is actually a property of the transient prefix, not of
individual suffixes.  However it is possible to invoke a suffix
command directly instead of from a transient.  In that case, if
the suffix expects a scope, then it has to determine that itself
and store it in its `scope' slot.

This function is called for all suffix commands, but unless a
concrete method is implemented this falls through to the default
implementation, which is a noop.")

(cl-defmethod transient-init-scope ((_   transient-suffix))
  "Noop." nil)

(cl-defgeneric transient-init-value (_)
  "Set the initial value of the object OBJ.

This function is called for all prefix and suffix commands.

For suffix commands (including infix argument commands) the
default implementation is a noop.  Classes derived from the
abstract `transient-infix' class must implement this function.
Non-infix suffix commands usually don't have a value."
  nil)

(cl-defmethod transient-init-value ((obj transient-prefix))
  (if (slot-boundp obj 'value)
      (let ((value (oref obj value)))
        (when (functionp value)
          (oset obj value (funcall value))))
    (oset obj value
          (if-let ((saved (assq (oref obj command) transient-values)))
              (cdr saved)
            nil))))

(cl-defmethod transient-init-value ((obj transient-switch))
  (oset obj value
        (car (member (oref obj argument)
                     (oref transient--prefix value)))))

(cl-defmethod transient-init-value ((obj transient-option))
  (oset obj value
        (transient--value-match (format "\\`%s\\(.*\\)" (oref obj argument)))))

(cl-defmethod transient-init-value ((obj transient-switches))
  (oset obj value
        (transient--value-match (oref obj argument-regexp))))

(defun transient--value-match (re)
  (when-let ((match (cl-find-if (lambda (v)
                                  (and (stringp v)
                                       (string-match re v)))
                                (oref transient--prefix value))))
    (match-string 1 match)))

(cl-defmethod transient-init-value ((obj transient-files))
  (oset obj value
        (cdr (assoc "--" (oref transient--prefix value)))))

;;;; Read

(cl-defgeneric transient-infix-read (obj)
  "Determine the new value of the infix object OBJ.

This function merely determines the value; `transient-infix-set'
is used to actually store the new value in the object.

For most infix classes this is done by reading a value from the
user using the reader specified by the `reader' slot (using the
`transient-infix' method described below).

For some infix classes the value is changed without reading
anything in the minibuffer, i.e. the mere act of invoking the
infix command determines what the new value should be, based
on the previous value.")

(cl-defmethod transient-infix-read :around ((obj transient-infix))
  "Highlight the infix in the popup buffer.

Also arrange for the transient to be exited in case of an error
because otherwise Emacs would get stuck in an inconsistent state,
which might make it necessary to kill it from the outside."
  (let ((transient--active-infix obj))
    (transient--show))
  (transient--with-emergency-exit
    (cl-call-next-method obj)))

(cl-defmethod transient-infix-read ((obj transient-infix))
  "Read a value while taking care of history.

This method is suitable for a wide variety of infix commands,
including but not limitted to inline arguments and variables.

If you do not use this method for your own infix class, then
you should likely replicate a lot of the behavior of this
method.  If you fail to do so, then users might not appreciate
the lack of history, for example.

Only for very simple classes that toggle or cycle through a very
limitted number of possible values should you replace this with a
simple method that does not handle history.  (E.g. for a command
line switch the only possible values are \"use it\" and \"don't use
it\", in which case it is pointless to preserve history.)"
  (with-slots (value multi-value allow-empty choices) obj
    (if (and value
             (not multi-value)
             (not allow-empty)
             transient--prefix)
        (oset obj value nil)
      (let* ((overriding-terminal-local-map nil)
             (reader (oref obj reader))
             (prompt (transient-prompt obj))
             (value (if multi-value (mapconcat #'identity value ",") value))
             (history-key (or (oref obj history-key)
                              (oref obj command)))
             (transient--history (alist-get history-key transient-history))
             (transient--history (if (or (null value)
                                         (eq value (car transient--history)))
                                     transient--history
                                   (cons value transient--history)))
             (initial-input (and transient-read-with-initial-input
                                 (car transient--history)))
             (history (cons 'transient--history (if initial-input 1 0)))
             (value
              (cond
               (reader (funcall reader prompt initial-input history))
               (multi-value
                (completing-read-multiple prompt choices nil nil
                                          initial-input history))
               (choices
                (completing-read prompt choices nil t initial-input history))
               (t (read-string prompt initial-input history)))))
        (cond ((and (equal value "") (not allow-empty))
               (setq value nil))
              ((and (equal value "\"\"") allow-empty)
               (setq value "")))
        (when value
          (setf (alist-get history-key transient-history)
                (delete-dups transient--history)))
        value))))

(cl-defmethod transient-infix-read ((obj transient-switch))
  "Toggle the switch on or off."
  (if (oref obj value) nil (oref obj argument)))

(cl-defmethod transient-infix-read ((obj transient-switches))
  "Cycle through the mutually exclusive switches.
The last value is \"don't use any of these switches\"."
  (let ((choices (mapcar (apply-partially #'format (oref obj argument-format))
                         (oref obj choices))))
    (if-let ((value (oref obj value)))
        (cadr (member value choices))
      (car choices))))

;;;; Readers

(defun transient-read-directory (prompt _initial-input _history)
  "Read a directory."
  (expand-file-name (read-directory-name prompt)))

(defun transient-read-existing-directory (prompt _initial-input _history)
  "Read an existing directory."
  (expand-file-name (read-directory-name prompt nil nil t)))

(defun transient-read-number-N0 (prompt initial-input history)
  "Read a natural number (including zero) and return it as a string."
  (transient--read-number-N prompt initial-input history t))

(defun transient-read-number-N+ (prompt initial-input history)
  "Read a natural number (excluding zero) and return it as a string."
  (transient--read-number-N prompt initial-input history nil))

(defun transient--read-number-N (prompt initial-input history include-zero)
  (save-match-data
    (cl-block nil
      (while t
        (let ((str (read-from-minibuffer prompt initial-input nil nil history)))
          (cond ((string-equal str "")
                 (cl-return nil))
                ((string-match-p (if include-zero
                                     "\\`\\(0\\|[1-9][0-9]*\\)\\'"
                                   "\\`[1-9][0-9]*\\'")
                                 str)
                 (cl-return str))))
        (message "Please enter a natural number (%s zero)."
                 (if include-zero "including" "excluding"))
        (sit-for 1)))))

(defun transient-read-date (prompt default-time _history)
  "Read a date using `org-read-date' (which see)."
  (require 'org)
  (when (fboundp 'org-read-date)
    (org-read-date 'with-time nil nil prompt default-time)))

;;;; Prompt

(cl-defgeneric transient-prompt (obj)
  "Return the prompt to be used to read infix object OBJ's value.")

(cl-defmethod transient-prompt ((obj transient-infix))
  "Return the prompt to be used to read infix object OBJ's value.

This implementation should be suitable for almost all infix
commands.

If the value of OBJ's `prompt' slot is non-nil, then it must be
a string or a function.  If it is a string, then use that.  If
it is a function, then call that with OBJ as the only argument.
That function must return a string, which is then used as the
prompt.

Otherwise, if the value of either the `argument' or `variable'
slot of OBJ is a string, then base the prompt on that (prefering
the former), appending either \"=\" (if it appears to be a
command-line option) or \": \".

Finally fall through to using \"(BUG: no prompt): \" as the
prompt."
  (if-let ((prompt (oref obj prompt)))
      (let ((prompt (if (functionp prompt)
                        (funcall prompt obj)
                      prompt)))
        (if (stringp prompt)
            prompt
          "(BUG: no prompt): "))
    (or (when-let ((arg (and (slot-boundp obj 'argument) (oref obj argument))))
          (if (and (stringp arg) (string-suffix-p "=" arg))
              arg
            (concat arg ": ")))
        (when-let ((var (and (slot-boundp obj 'variable) (oref obj variable))))
          (and (stringp var)
               (concat var ": ")))
        "(BUG: no prompt): ")))

;;;; Set

(defvar transient--unset-incompatible t)

(cl-defgeneric transient-infix-set (obj value)
  "Set the value of infix object OBJ to value.")

(cl-defmethod transient-infix-set ((obj transient-infix) value)
  "Set the value of infix object OBJ to value.

This implementation should be suitable for almost all infix
commands."
  (oset obj value value))

(cl-defmethod transient-infix-set :around ((obj transient-argument) value)
  "Unset incompatible infix arguments."
  (let ((arg (if (slot-boundp obj 'argument)
                 (oref obj argument)
               (oref obj argument-regexp))))
    (if-let ((sic (and value arg transient--unset-incompatible))
             (spec (oref transient--prefix incompatible))
             (incomp (remove arg (cl-find-if (lambda (elt) (member arg elt)) spec))))
        (progn
          (cl-call-next-method obj value)
          (dolist (arg incomp)
            (when-let ((obj (cl-find-if (lambda (obj)
                                          (and (slot-boundp obj 'argument)
                                               (equal (oref obj argument) arg)))
                                        transient--suffixes)))
              (let ((transient--unset-incompatible nil))
                (transient-infix-set obj nil)))))
      (cl-call-next-method obj value))))

(cl-defmethod transient-set-value ((obj transient-prefix))
  (oset (oref obj prototype) value (transient-get-value))
  (transient--history-push obj))

;;;; Save

(cl-defmethod transient-save-value ((obj transient-prefix))
  (let ((value (transient-get-value)))
    (oset (oref obj prototype) value value)
    (setf (alist-get (oref obj command) transient-values) value)
    (transient-save-values))
  (transient--history-push obj))

;;;; Get

(defun transient-args (prefix)
  "Return the value of the transient prefix command PREFIX.
If the current command was invoked from the transient prefix
command PREFIX, then return the active infix arguments.  If
the current command was not invoked from PREFIX, then return
the set, saved or default value for PREFIX."
  (if (eq current-transient-command prefix)
      (delq nil (mapcar 'transient-infix-value current-transient-suffixes))
    (let ((transient--prefix nil)
          (transient--layout nil)
          (transient--suffixes nil))
      (transient--init-objects prefix nil nil)
      (delq nil (mapcar 'transient-infix-value transient--suffixes)))))

(defun transient-get-value ()
  (delq nil (mapcar 'transient-infix-value current-transient-suffixes)))

(cl-defgeneric transient-infix-value (obj)
  "Return the value of the suffix object OBJ.

This function is called by `transient-args' (which see), meaning
this function is how the value of a transient is determined so
that the invoked suffix command can use it.

Currently most values are strings, but that is not set in stone.
Nil is not a value, it means \"no value\".

Usually only infixes have a value, but see the method for
`transient-suffix'.")

(cl-defmethod transient-infix-value ((_   transient-suffix))
  "Return nil, which means \"no value\".

Infix arguments contribute the the transient's value while suffix
commands consume it.  This function is called for suffixes anyway
because a command that both contributes to the transient's value
and also consumes it is not completely unconceivable.

If you define such a command, then you must define a derived
class and implement this function because this default method
does nothing." nil)

(cl-defmethod transient-infix-value ((obj transient-infix))
  "Return the value of OBJ's `value' slot."
  (oref obj value))

(cl-defmethod transient-infix-value ((obj transient-option))
  "Return (concat ARGUMENT VALUE) or nil.

ARGUMENT and VALUE are the values of the respective slots of OBJ.
If VALUE is nil, then return nil.  VALUE may be the empty string,
which is not the same as nil."
  (when-let ((value (oref obj value)))
    (concat (oref obj argument) value)))

(cl-defmethod transient-infix-value ((_   transient-variable))
  "Return nil, which means \"no value\".

Setting the value of a variable is done by, well, setting the
value of the variable.  I.e. this is a side-effect and does not
contribute to the value of the transient."
  nil)

(cl-defmethod transient-infix-value ((obj transient-files))
  "Return (concat ARGUMENT VALUE) or nil.

ARGUMENT and VALUE are the values of the respective slots of OBJ.
If VALUE is nil, then return nil.  VALUE may be the empty string,
which is not the same as nil."
  (when-let ((value (oref obj value)))
    (cons (oref obj argument) value)))

;;; History

(cl-defgeneric transient--history-key (obj)
  "Return OBJ's history key.
If the value of the `history-key' slot is non-nil, then return
that.  Otherwise return the value of the `command' slot."
  (or (oref obj history-key)
      (oref obj command)))

(cl-defgeneric transient--history-push (obj)
  "Push the current value of OBJ to its entry in `transient-history'."
  (let ((key (transient--history-key obj)))
    (setf (alist-get key transient-history)
          (let ((args (transient-get-value)))
            (cons args (delete args (alist-get key transient-history)))))))

(cl-defgeneric transient--history-init (obj)
  "Initialize OBJ's `history' slot.
This is the transient-wide history; many individual infixes also
have a history of their own.")

(cl-defmethod transient--history-init ((obj transient-prefix))
  "Initialize OBJ's `history' slot from the variable `transient-history'."
  (let ((val (oref obj value)))
    (oset obj history
          (cons val (delete val (alist-get (transient--history-key obj)
                                           transient-history))))))

;;; Draw

(defun transient--show-brief ()
  (let ((message-log-max nil))
    (if (and transient-show-popup (<= transient-show-popup 0))
        (message "%s-" (key-description (this-command-keys)))
      (message
       "%s- [%s] %s"
       (key-description (this-command-keys))
       (oref transient--prefix command)
       (mapconcat
        #'identity
        (sort
         (cl-mapcan
          (lambda (suffix)
            (let ((key (kbd (oref suffix key))))
              ;; Don't list any common commands.
              (and (not (memq (oref suffix command)
                              `(,(lookup-key transient-map key)
                                ,(lookup-key transient-sticky-map key)
                                ;; From transient-common-commands:
                                transient-set
                                transient-save
                                transient-history-prev
                                transient-history-next
                                transient-quit-one
                                transient-toggle-common
                                transient-set-level)))
                   (list (propertize (oref suffix key) 'face 'transient-key)))))
          transient--suffixes)
         #'string<)
        (propertize "|" 'face 'transient-unreachable-key))))))

(defun transient--show ()
  (transient--timer-cancel)
  (setq transient--showp t)
  (let ((buf (get-buffer-create transient--buffer-name))
        (focus nil))
    (unless (window-live-p transient--window)
      (setq transient--window
            (display-buffer buf transient-display-buffer-action)))
    (with-selected-window transient--window
      (when transient-enable-popup-navigation
        (setq focus (button-get (point) 'command)))
      (erase-buffer)
      (set-window-hscroll transient--window 0)
      (set-window-dedicated-p transient--window t)
      (set-window-parameter transient--window 'no-other-window t)
      (setq window-size-fixed t)
      (setq mode-line-format (if (eq transient-mode-line-format 'line)
                                 nil
                               transient-mode-line-format))
      (setq mode-line-buffer-identification
            (symbol-name (oref transient--prefix command)))
      (if transient-enable-popup-navigation
          (setq-local cursor-in-non-selected-windows 'box)
        (setq cursor-type nil))
      (setq display-line-numbers nil)
      (setq show-trailing-whitespace nil)
      (transient--insert-groups)
      (when (or transient--helpp transient--editp)
        (transient--insert-help))
      (when (eq transient-mode-line-format 'line)
        (insert (propertize "__" 'face 'transient-separator
                            'display '(space :height (1))))
        (insert (propertize "\n" 'face 'transient-separator 'line-height t)))
      (let ((window-resize-pixelwise t)
            (window-size-fixed nil))
        (fit-window-to-buffer nil nil 1))
      (goto-char (point-min))
      (when transient-enable-popup-navigation
        (transient--goto-button focus)))))

(defun transient--insert-groups ()
  (let ((groups (cl-mapcan (lambda (group)
                             (let ((hide (oref group hide)))
                               (and (not (and (functionp hide)
                                              (funcall   hide)))
                                    (list group))))
                           transient--layout))
        group)
    (while (setq group (pop groups))
      (transient--insert-group group)
      (when groups
        (insert ?\n)))))

(cl-defgeneric transient--insert-group (group)
  "Format GROUP and its elements and insert the result.")

(cl-defmethod transient--insert-group :before ((group transient-group))
  "Insert GROUP's description, if any."
  (when-let ((desc (transient-format-description group)))
    (insert desc ?\n)))

(cl-defmethod transient--insert-group ((group transient-row))
  (dolist (suffix (oref group suffixes))
    (insert (transient-format suffix))
    (insert "   "))
  (insert ?\n))

(cl-defmethod transient--insert-group ((group transient-column))
  (dolist (suffix (oref group suffixes))
    (let ((str (transient-format suffix)))
      (insert str)
      (unless (string-match-p ".\n\\'" str)
        (insert ?\n)))))

(cl-defmethod transient--insert-group ((group transient-columns))
  (let* ((columns
          (mapcar
           (lambda (column)
             (let ((rows (mapcar 'transient-format (oref column suffixes))))
               (when-let ((desc (transient-format-description column)))
                 (push desc rows))
               rows))
           (oref group suffixes)))
         (rs (apply #'max (mapcar #'length columns)))
         (cs (length columns))
         (cw (--map (apply #'max (mapcar #'length it)) columns))
         (cc (-reductions-from (apply-partially #'+ 3) 0 cw)))
    (dotimes (r rs)
      (dotimes (c cs)
        (insert (make-string (- (nth c cc) (current-column)) ?\s))
        (when-let ((cell (nth r (nth c columns))))
          (insert cell))
        (when (= c (1- cs))
          (insert ?\n))))))

(cl-defmethod transient--insert-group ((group transient-subgroups))
  (let* ((subgroups (oref group suffixes))
         (n (length subgroups)))
    (dotimes (s n)
      (transient--insert-group (nth s subgroups))
      (when (< s (1- n))
        (insert ?\n)))))

(cl-defgeneric transient-format (obj)
  "Format and return OBJ for display.

When this function is called, then the current buffer is some
temporary buffer.  If you need the buffer from which the prefix
command was invoked to be current, then do so by temporarily
making `transient--original-buffer' current.")

(cl-defmethod transient-format ((arg string))
  "Return the string ARG after applying the `transient-heading' face."
  (propertize arg 'face 'transient-heading))

(cl-defmethod transient-format ((_   null))
  "Return a string containing just the newline character."
  "\n")

(cl-defmethod transient-format ((arg integer))
  "Return a string containing just the ARG character."
  (char-to-string arg))

(cl-defmethod transient-format :around ((obj transient-infix))
  "When reading user input for this infix, then highlight it."
  (let ((str (cl-call-next-method obj)))
    (when (eq obj transient--active-infix)
      (setq str (concat str "\n"))
      (add-face-text-property 0 (length str)
                              'transient-active-infix nil str))
    str))

(cl-defmethod transient-format :around ((obj transient-suffix))
  "When edit-mode is enabled, then prepend the level information.
Optional support for popup buttons is also implemented here."
  (let ((str (concat
              (and transient--editp
                   (let ((level (oref obj level)))
                     (propertize (format " %s " level)
                                 'face (if (transient--use-level-p level t)
                                           'transient-enabled-suffix
                                         'transient-disabled-suffix))))
              (cl-call-next-method obj))))
    (if transient-enable-popup-navigation
        (make-text-button str nil
                          'type 'transient-button
                          'command (transient--suffix-command obj))
      str)))

(cl-defmethod transient-format ((obj transient-infix))
  "Return a string generated using OBJ's `format'.
%k is formatted using `transient-format-key'.
%d is formatted using `transient-format-description'.
%f is formatted using `transient-format-value'."
  (format-spec (oref obj format)
               `((?k . ,(transient-format-key obj))
                 (?d . ,(transient-format-description obj))
                 (?v . ,(transient-format-value obj)))))

(cl-defmethod transient-format ((obj transient-suffix))
  "Return a string generated using OBJ's `format'.
%k is formatted using `transient-format-key'.
%d is formatted using `transient-format-description'."
  (format-spec (oref obj format)
               `((?k . ,(transient-format-key obj))
                 (?d . ,(transient-format-description obj)))))

(cl-defgeneric transient-format-key (obj)
  "Format OBJ's `key' for display and return the result.")

(cl-defmethod transient-format-key ((obj transient-suffix))
  "Format OBJ's `key' for display and return the result."
  (let ((key (oref obj key)))
    (if transient--redisplay-key
        (let ((len (length transient--redisplay-key))
              (seq (cl-coerce (edmacro-parse-keys key t) 'list)))
          (cond
           ((equal (-take len seq) transient--redisplay-key)
            (let ((pre (key-description (vconcat (-take len seq))))
                  (suf (key-description (vconcat (-drop len seq)))))
              (setq pre (replace-regexp-in-string "RET" "C-m" pre t))
              (setq pre (replace-regexp-in-string "TAB" "C-i" pre t))
              (setq suf (replace-regexp-in-string "RET" "C-m" suf t))
              (setq suf (replace-regexp-in-string "TAB" "C-i" suf t))
              ;; We use e.g. "-k" instead of the more correct "- k",
              ;; because the former is prettier.  If we did that in
              ;; the definition, then we want to drop the space that
              ;; is reinserted above.  False-positives are possible
              ;; for silly bindings like "-C-c C-c".
              (unless (string-match-p " " key)
                (setq pre (replace-regexp-in-string " " "" pre))
                (setq suf (replace-regexp-in-string " " "" suf)))
              (concat (propertize pre 'face 'default)
                      (and (string-prefix-p (concat pre " ") key) " ")
                      (propertize suf 'face 'transient-key)
                      (save-excursion
                        (when (string-match " +\\'" key)
                          (match-string 0 key))))))
           ((transient--lookup-key transient-sticky-map (kbd key))
            (propertize key 'face 'transient-key))
           (t
            (propertize key 'face 'transient-unreachable-key))))
      (propertize key 'face 'transient-key))))

(cl-defmethod transient-format-key :around ((obj transient-argument))
  (let ((key (cl-call-next-method obj)))
    (cond ((not transient-highlight-mismatched-keys))
          ((not (slot-boundp obj 'shortarg))
           (add-face-text-property
            0 (length key) 'transient-nonstandard-key nil key))
          ((not (string-equal key (oref obj shortarg)))
           (add-face-text-property
            0 (length key) 'transient-mismatched-key nil key)))
    key))

(cl-defgeneric transient-format-description (obj)
  "Format OBJ's `description' for display and return the result.")

(cl-defmethod transient-format-description ((obj transient-child))
  "The `description' slot may be a function, in which case that is
called inside the correct buffer (see `transient-insert-group')
and its value is returned to the caller."
  (when-let ((desc (oref obj description)))
    (if (functionp desc)
        (with-current-buffer transient--original-buffer
          (funcall desc))
      desc)))

(cl-defmethod transient-format-description ((obj transient-group))
  "Format the description by calling the next method.  If the result
doesn't use the `face' property at all, then apply the face
`transient-heading' to the complete string."
  (when-let ((desc (cl-call-next-method obj)))
    (if (text-property-not-all 0 (length desc) 'face nil desc)
        desc
      (propertize desc 'face 'transient-heading))))

(cl-defmethod transient-format-description :around ((obj transient-suffix))
  "Format the description by calling the next method.  If the result
is nil, then use \"(BUG: no description)\" as the description.
If the OBJ's `key' is currently unreachable, then apply the face
`transient-unreachable' to the complete string."
  (let ((desc (or (cl-call-next-method obj)
                  (propertize "(BUG: no description)" 'face 'error))))
    (if (transient--key-unreachable-p obj)
        (propertize desc 'face 'transient-unreachable)
      desc)))

(cl-defgeneric transient-format-value (obj)
  "Format OBJ's value for display and return the result.")

(cl-defmethod transient-format-value ((obj transient-suffix))
  (propertize (oref obj argument)
              'face (if (oref obj value)
                        'transient-argument
                      'transient-inactive-argument)))

(cl-defmethod transient-format-value ((obj transient-option))
  (let ((value (oref obj value)))
    (propertize (concat (oref obj argument) value)
                'face (if value
                          'transient-value
                        'transient-inactive-value))))

(cl-defmethod transient-format-value ((obj transient-switches))
  (with-slots (value argument-format choices) obj
    (format (propertize argument-format
                        'face (if value
                                  'transient-value
                                'transient-inactive-value))
            (concat
             (propertize "[" 'face 'transient-inactive-value)
             (mapconcat
              (lambda (choice)
                (propertize choice 'face
                            (if (equal (format argument-format choice) value)
                                'transient-value
                              'transient-inactive-value)))
              choices
              (propertize "|" 'face 'transient-inactive-value))
             (propertize "]" 'face 'transient-inactive-value)))))

(cl-defmethod transient-format-value ((obj transient-files))
  (let ((argument (oref obj argument)))
    (if-let ((value (oref obj value)))
        (propertize (concat argument " "
                            (mapconcat (lambda (f) (format "%S" f))
                                       (oref obj value) " "))
                    'face 'transient-argument)
    (propertize argument 'face 'transient-inactive-argument))))

(defun transient--key-unreachable-p (obj)
  (and transient--redisplay-key
       (let ((key (oref obj key)))
         (not (or (equal (-take (length transient--redisplay-key)
                                (cl-coerce (edmacro-parse-keys key t) 'list))
                         transient--redisplay-key)
                  (transient--lookup-key transient-sticky-map (kbd key)))))))

(defun transient--lookup-key (keymap key)
  (let ((val (lookup-key keymap key)))
    (and val (not (integerp val)) val)))

;;; Help

(cl-defgeneric transient-show-help (obj)
  "Show help for OBJ's command.")

(cl-defmethod transient-show-help ((obj transient-prefix))
  "Show the info manual, manpage or command doc-string.
Show the first one that is specified."
  (if-let ((manual (oref obj info-manual)))
      (info manual)
    (if-let ((manpage (oref obj man-page)))
        (transient--show-manpage manpage)
      (transient--describe-function (oref obj command)))))

(cl-defmethod transient-show-help ((_   transient-suffix))
  "Show the command doc-string."
  (if (eq this-original-command 'transient-help)
      (if-let ((manpage (oref transient--prefix man-page)))
          (transient--show-manpage manpage)
        (transient--describe-function (oref transient--prefix command)))
    (transient--describe-function this-original-command)))

(cl-defmethod transient-show-help ((obj transient-infix))
  "Show the manpage if defined or the command doc-string.
If the manpage is specified, then try to jump to the correct
location."
  (if-let ((manpage (oref transient--prefix man-page)))
      (transient--show-manpage manpage (oref obj argument))
    (transient--describe-function this-original-command)))

;; `cl-generic-generalizers' doesn't support `command' et al.
(cl-defmethod transient-show-help (cmd)
  "Show the command doc-string."
  (transient--describe-function cmd))

(defun transient--show-manpage (manpage &optional argument)
  (require 'man)
  (let* ((Man-notify-method 'meek)
         (buf (Man-getpage-in-background manpage))
         (proc (get-buffer-process buf)))
    (while (and proc (eq (process-status proc) 'run))
      (accept-process-output proc))
    (switch-to-buffer buf)
    (when argument
      (transient--goto-argument-description argument))))

(defun transient--describe-function (fn)
  (describe-function fn)
  (select-window (get-buffer-window (help-buffer))))

(defun transient--goto-argument-description (arg)
  (goto-char (point-min))
  (let ((case-fold-search nil)
        ;; This matches preceding/proceeding options.  Options
        ;; such as "-a", "-S[<keyid>]", and "--grep=<pattern>"
        ;; are matched by this regex without the shy group.
        ;; The ". " in the shy group is for options such as
        ;; "-m parent-number", and the "-[^[:space:]]+ " is
        ;; for options such as "--mainline parent-number"
        (others "-\\(?:. \\|-[^[:space:]]+ \\)?[^[:space:]]+"))
    (when (re-search-forward
           ;; Should start with whitespace and may have
           ;; any number of options before and/or after.
           (format
            "^[\t\s]+\\(?:%s, \\)*?\\(?1:%s\\)%s\\(?:, %s\\)*$"
            others
            ;; Options don't necessarily end in an "="
            ;; (e.g., "--gpg-sign[=<keyid>]")
            (string-remove-suffix "=" arg)
            ;; Simple options don't end in an "=".  Splitting this
            ;; into 2 cases should make getting false positives
            ;; less likely.
            (if (string-suffix-p "=" arg)
                ;; "[^[:space:]]*[^.[:space:]]" matches the option
                ;; value, which is usually after the option name
                ;; and either '=' or '[='.  The value can't end in
                ;; a period, as that means it's being used at the
                ;; end of a sentence.  The space is for options
                ;; such as '--mainline parent-number'.
                "\\(?: \\|\\[?=\\)[^[:space:]]*[^.[:space:]]"
              ;; Either this doesn't match anything (e.g., "-a"),
              ;; or the option is followed by a value delimited
              ;; by a "[", "<", or ":".  A space might appear
              ;; before this value, as in "-f <file>".  The
              ;; space alternative is for options such as
              ;; "-m parent-number".
              "\\(?:\\(?: \\| ?[\\[<:]\\)[^[:space:]]*[^.[:space:]]\\)?")
            others)
           nil t)
      (goto-char (match-beginning 1)))))

(defun transient--insert-help ()
  (unless (looking-back "\n\n" 2)
    (insert "\n"))
  (when transient--helpp
    (insert
     (format (propertize "\
Type a %s to show help for that suffix command, or %s to show manual.
Type %s to exit help.\n"
                         'face 'transient-heading)
             (propertize "<KEY>" 'face 'transient-key)
             (propertize "?"     'face 'transient-key)
             (propertize "C-g"   'face 'transient-key))))
  (when transient--editp
    (unless transient--helpp
      (insert
       (format (propertize "\
Type a %s to set level for that suffix command.
Type %s to set what levels are available for this prefix command.\n"
                           'face 'transient-heading)
               (propertize "<KEY>"   'face 'transient-key)
               (propertize "C-x l" 'face 'transient-key))))
    (with-slots (level) transient--prefix
      (insert
       (format (propertize "
Suffixes on levels %s are available.
Suffixes on levels %s and %s are unavailable.\n"
                           'face 'transient-heading)
               (propertize (format "1-%s" level)
                           'face 'transient-enabled-suffix)
               (propertize " 0 "
                           'face 'transient-disabled-suffix)
               (propertize (format ">=%s" (1+ level))
                           'face 'transient-disabled-suffix))))))

(defvar transient-resume-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [remap Man-quit]    'transient-resume)
    (define-key map [remap Info-exit]   'transient-resume)
    (define-key map [remap quit-window] 'transient-resume)
    map)
  "Keymap for `transient-resume-mode'.

This keymap remaps every command that would usually just quit the
documentation buffer to `transient-resume', which additionally
resumes the suspended transient.")

(define-minor-mode transient-resume-mode
  "Auxiliary minor-mode used to resume a transient after viewing help.")

;;; Compatibility
;;;; Popup Navigation

(defun transient-popup-navigation-help ()
  "Inform the user how to enable popup navigation commands."
  (interactive)
  (message "This command is only available if `%s' is non-nil"
           'transient-enable-popup-navigation))

(define-button-type 'transient-button
  'face nil
  'action (lambda (button)
            (let ((command (button-get button 'command)))
              ;; Yes, I know that this is wrong(tm).
              ;; Unfortunately it is also necessary.
              (setq this-original-command command)
              (call-interactively command))))

(defvar transient-popup-navigation-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "<down-mouse-1>") 'transient-noop)
    (define-key map (kbd "<mouse-1>") 'transient-mouse-push-button)
    (define-key map (kbd "RET")       'transient-push-button)
    (define-key map (kbd "<up>")      'transient-backward-button)
    (define-key map (kbd "C-p")       'transient-backward-button)
    (define-key map (kbd "<down>")    'transient-forward-button)
    (define-key map (kbd "C-n")       'transient-forward-button)
    (define-key map (kbd "C-r")       'transient-isearch-backward)
    (define-key map (kbd "C-s")       'transient-isearch-forward)
    map))

(defun transient-mouse-push-button (&optional pos)
  "Invoke the suffix the user clicks on."
  (interactive (list last-command-event))
  (push-button pos))

(defun transient-push-button ()
  "Invoke the selected suffix command."
  (interactive)
  (with-selected-window transient--window
    (push-button)))

(defun transient-backward-button (n)
  "Move to the previous button in the transient popup buffer.
See `backward-button' for information about N."
  (interactive "p")
  (with-selected-window transient--window
    (backward-button n t)))

(defun transient-forward-button (n)
  "Move to the next button in the transient popup buffer.
See `forward-button' for information about N."
  (interactive "p")
  (with-selected-window transient--window
    (forward-button n t)))

(defun transient--goto-button (command)
  (if (not command)
      (forward-button 1)
    (while (and (ignore-errors (forward-button 1))
                (not (eq (button-get (button-at (point)) 'command) command))))
    (unless (eq (button-get (button-at (point)) 'command) command)
      (goto-char (point-min))
      (forward-button 1))))

;;;; Popup Isearch

(defvar transient--isearch-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map isearch-mode-map)
    (define-key map [remap isearch-exit]   'transient-isearch-exit)
    (define-key map [remap isearch-cancel] 'transient-isearch-cancel)
    (define-key map [remap isearch-abort]  'transient-isearch-abort)
    map))

(defun transient-isearch-backward (&optional regexp-p)
  "Do incremental search backward.
With a prefix argument, do an incremental regular expression
search instead."
  (interactive "P")
  (transient--isearch-setup)
  (let ((isearch-mode-map transient--isearch-mode-map))
    (isearch-mode nil regexp-p)))

(defun transient-isearch-forward (&optional regexp-p)
  "Do incremental search forward.
With a prefix argument, do an incremental regular expression
search instead."
  (interactive "P")
  (transient--isearch-setup)
  (let ((isearch-mode-map transient--isearch-mode-map))
    (isearch-mode t regexp-p)))

(defun transient-isearch-exit ()
  "Like `isearch-exit' but adapted for `transient'."
  (interactive)
  (isearch-exit)
  (transient--isearch-exit))

(defun transient-isearch-cancel ()
  "Like `isearch-cancel' but adapted for `transient'."
  (interactive)
  (condition-case nil (isearch-cancel) (quit))
  (transient--isearch-exit))

(defun transient-isearch-abort ()
  "Like `isearch-abort' but adapted for `transient'."
  (interactive)
  (condition-case nil (isearch-abort) (quit))
  (transient--isearch-exit))

(defun transient--isearch-setup ()
  (select-window transient--window)
  (transient--pop-keymap 'transient--transient-map)
  (transient--pop-keymap 'transient--redisplay-map)
  (remove-hook 'pre-command-hook #'transient--pre-command)
  (remove-hook 'post-command-hook #'transient--post-command))

(defun transient--isearch-exit ()
  (select-window transient--original-window)
  (transient--push-keymap 'transient--transient-map)
  (transient--push-keymap 'transient--redisplay-map)
  (add-hook 'pre-command-hook #'transient--pre-command)
  (add-hook 'post-command-hook #'transient--post-command))

;;;; Other Packages

(declare-function which-key-mode "which-key" (&optional arg))

(defun transient--suspend-which-key-mode ()
  (when (bound-and-true-p which-key-mode)
    (which-key-mode -1)
    (add-hook 'post-transient-hook 'transient--resume-which-key-mode)))

(defun transient--resume-which-key-mode ()
  (unless transient--prefix
    (which-key-mode 1)
    (remove-hook 'post-transient-hook 'transient--resume-which-key-mode)))

(defun transient-bind-q-to-quit ()
  "Modify some keymaps to bind \"q\" to the appropriate quit command.

\"C-g\" is the default binding for such commands now, but Transient's
predecessor Magit-Popup used \"q\" instead.  If you would like to get
that binding back, then call this function in your init file like so:

  (with-eval-after-load \\='transient
    (transient-bind-q-to-quit))

Individual transients may already bind \"q\" to something else
and such a binding would shadow the quit binding.  If that is the
case then \"Q\" is bound to whatever \"q\" would have been bound
to by setting `transient-substitute-key-function' to a function
that does that.  Of course \"Q\" may already be bound to something
else, so that function binds \"M-q\" to that command instead.
Of course \"M-q\" may already be bound to something else, but
we stop there."
  (define-key transient-base-map   "q" 'transient-quit-one)
  (define-key transient-sticky-map "q" 'transient-quit-seq)
  (setq transient-substitute-key-function
        'transient-rebind-quit-commands))

(defun transient-rebind-quit-commands (obj)
  "See `transient-bind-q-to-quit'."
  (let ((key (oref obj key)))
    (cond ((string-equal key "q") "Q")
          ((string-equal key "Q") "M-q")
          (t key))))

;;; Font-Lock

(defconst transient-font-lock-keywords
  (eval-when-compile
    `((,(concat "("
                (regexp-opt (list "define-transient-command"
                                  "define-infix-command"
                                  "define-infix-argument"
                                  "define-suffix-command")
                            t)
                "\\_>[ \t'\(]*"
                "\\(\\(?:\\sw\\|\\s_\\)+\\)?")
       (1 'font-lock-keyword-face)
       (2 'font-lock-function-name-face nil t)))))

(font-lock-add-keywords 'emacs-lisp-mode transient-font-lock-keywords)

;;; _
(provide 'transient)
;; Local Variables:
;; indent-tabs-mode: nil
;; End:
;;; transient.el ends here
