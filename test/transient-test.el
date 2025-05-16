;;; llama-tests.el --- Tests for Llama  -*- lexical-binding:t -*-

;; Copyright (C) 2018-2025 Jonas Bernoulli

;; Authors: Jonas Bernoulli <emacs.transient@jonas.bernoulli.dev>
;; Homepage: https://github.com/magit/transient

;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation, either version 3 of the License,
;; or (at your option) any later version.
;;
;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this file.  If not, see <https://www.gnu.org/licenses/>.

;;; Code:

(require 'ert)

(setq ert-batch-backtrace-right-margin 95)
(setq ert-batch-print-length nil)
(setq ert-batch-print-level nil)

(require 'transient)

;; (setq transient-detect-key-conflicts t)
(setq transient-error-on-insert-failure t)

(transient-define-suffix test-command-a () :key "a" (interactive))
(transient-define-suffix test-command-b () :key "b" (interactive))
(transient-define-suffix test-command-c () :key "c" (interactive))
(transient-define-suffix test-command-d () :key "d" (interactive))
(transient-define-suffix test-command-e () :key "e" (interactive))
(transient-define-suffix test-command-f () :key "f" (interactive))
(transient-define-suffix test-command-g () :key "g" (interactive))
(transient-define-suffix test-command-h () :key "h" (interactive))
(transient-define-suffix test-command-i () :key "i" (interactive))
(transient-define-suffix test-command-j () :key "j" (interactive))

(transient-define-suffix test-command-m () (interactive))

(transient-define-suffix test-command-u () :key "u" (interactive))
(transient-define-suffix test-command-v () :key "v" (interactive))
(transient-define-suffix test-command-w () :key "w" (interactive))
(transient-define-suffix test-command-x () :key "x" (interactive))
(transient-define-suffix test-command-y () :key "y" (interactive))
(transient-define-suffix test-command-z () :key "z" (interactive))

(ert-deftest transient-test-101-define nil
  (transient-define-prefix test-101-menu ()
    [(test-command-a)
     (test-command-b :key "b")
     (test-command-c :key "C")
     (test-command-m :key "m")])
  (defvar test-101-menu--layout (transient--get-layout 'test-101-menu))
  (should (equal (transient--get-layout 'test-101-menu)
                 [2 nil
                  ([transient-column nil
                    ((transient-suffix :command test-command-a)
                     (transient-suffix :command test-command-b :key "b")
                     (transient-suffix :command test-command-c :key "C")
                     (transient-suffix :command test-command-m :key "m"))])]))
  (should (eq (transient--get-layout 'test-101-menu) test-101-menu--layout)))

(ert-deftest transient-test-102-include nil
  (transient-define-group test-102-top-group
    [:class transient-row
     (test-command-a)
     (test-command-b)])
  (should (equal (transient--get-layout 'test-102-top-group)
                 [2 nil
                  ([transient-row nil
                    ((transient-suffix :command test-command-a)
                     (transient-suffix :command test-command-b))])]))
  (transient-define-group test-102-top-groups
    [[(test-command-c)
      (test-command-d)]
     [(test-command-e)
      (test-command-f)]])
  (should (equal (transient--get-layout 'test-102-top-groups)
                 [2 nil
                  ([transient-columns nil
                    ([transient-column nil
                      ((transient-suffix :command test-command-c)
                       (transient-suffix :command test-command-d))]
                     [transient-column nil
                      ((transient-suffix :command test-command-e)
                       (transient-suffix :command test-command-f))])])]))
  (transient-define-group test-102-child-group
    [(test-command-i)
     (test-command-j)])
  (should (equal (transient--get-layout 'test-102-child-group)
                 [2 nil
                  ([transient-column nil
                    ((transient-suffix :command test-command-i)
                     (transient-suffix :command test-command-j))])]))
  (transient-define-group test-102-suffixes
    (test-command-z)
    (test-command-y))
  (should (equal (transient--get-layout 'test-102-suffixes)
                 [2 nil
                  ((transient-suffix :command test-command-z)
                   (transient-suffix :command test-command-y))]))
  (transient-define-prefix test-102-menu ()
    'test-102-top-group
    ;; KLUDGE Unquoted at top-level deprecated but still supported.
    test-102-top-groups
    [[(test-command-g)
      (test-command-h)
      test-102-suffixes]
     test-102-child-group])
  (should (equal (transient--get-layout 'test-102-menu)
                 [2 nil
                  (test-102-top-group
                   test-102-top-groups
                   [transient-columns nil
                    ([transient-column nil
                      ((transient-suffix :command test-command-g)
                       (transient-suffix :command test-command-h)
                       test-102-suffixes)]
                     test-102-child-group)])])))

(ert-deftest transient-test-201-locate nil
  (transient-define-prefix test-201-menu ()
    [(test-command-a)
     (test-command-b)
     (test-command-c)]
    [:if-nil nil
     (test-command-d :description "1")
     (test-command-e)
     (test-command-f)]
    [[:if-non-nil nil
      (test-command-d :description "2")]
     [(test-command-a :key "A")]])
  (should (equal (transient--locate-child 'test-201-menu "a")
                 '((transient-suffix :command test-command-a)
                   [transient-column nil
                    ((transient-suffix :command test-command-a)
                     (transient-suffix :command test-command-b)
                     (transient-suffix :command test-command-c))])))
  (should (equal (transient--locate-child 'test-201-menu 'test-command-b)
                 '((transient-suffix :command test-command-b)
                   [transient-column nil
                    ((transient-suffix :command test-command-a)
                     (transient-suffix :command test-command-b)
                     (transient-suffix :command test-command-c))])))
  (should (equal (transient-get-suffix 'test-201-menu [0 0])
                 '(transient-suffix :command test-command-a)))
  (should (equal (transient-get-suffix 'test-201-menu [0 2])
                 '(transient-suffix :command test-command-c)))
  (should (equal (transient-get-suffix 'test-201-menu [0 -3])
                 '(transient-suffix :command test-command-a)))
  (should (equal (transient-get-suffix 'test-201-menu [0 -1])
                 '(transient-suffix :command test-command-c)))
  (should (equal (transient-get-suffix 'test-201-menu [1 1])
                 '(transient-suffix :command test-command-e)))
  (should (equal (transient-get-suffix 'test-201-menu "d")
                 '(transient-suffix :command test-command-d :description "1")))
  (should (equal (transient-get-suffix 'test-201-menu [2 0 "d"])
                 '(transient-suffix :command test-command-d :description "2")))
  (should (equal (transient-get-suffix 'test-201-menu [2 "d"])
                 '(transient-suffix :command test-command-d :description "2")))
  (should (equal (transient-get-suffix 'test-201-menu [2 1 test-command-a])
                 '(transient-suffix :command test-command-a :key "A")))
  (should (equal (transient-get-suffix 'test-201-menu [2 test-command-a])
                 '(transient-suffix :command test-command-a :key "A")))
  (should (equal (transient-get-suffix 'test-201-menu [0])
                 [transient-column nil
                  ((transient-suffix :command test-command-a)
                   (transient-suffix :command test-command-b)
                   (transient-suffix :command test-command-c))]))
  (should (equal (transient-get-suffix 'test-201-menu [-1 -1])
                 [transient-column nil
                  ((transient-suffix :command test-command-a :key "A"))]))
  ;; KLUDGE Coordinates as list are deprecated but still supported.
  (should (equal (transient-get-suffix 'test-201-menu '(-1 -1 0))
                 '(transient-suffix :command test-command-a :key "A")))
  (should (equal (transient-get-suffix 'test-201-menu '(-1 "A"))
                 '(transient-suffix :command test-command-a :key "A"))))

(ert-deftest transient-test-202-locate-include nil
  (transient-define-group test-202-group
    [(test-command-c)
     (test-command-d)])
  (transient-define-group test-202-list
    [(test-command-f)
     (test-command-g)])
  (transient-define-prefix test-202-menu ()
    [[(test-command-a)
      (test-command-b)]
     test-202-group
     [(test-command-e)
      test-202-list
      (test-command-h)]])
  (should (equal (transient-get-suffix 'test-202-menu [0 1])
                 'test-202-group))
  (should (equal (transient-get-suffix 'test-202-menu [0 1 0])
                 '(transient-suffix :command test-command-c)))
  (should (equal (transient-get-suffix 'test-202-menu [0 1 "c"])
                 '(transient-suffix :command test-command-c)))
  (should (equal (transient-get-suffix 'test-202-menu [0 "c"])
                 '(transient-suffix :command test-command-c)))
  ;; MAYBE Consider expanding inlined suffix lists when doing
  ;; coordinate lookup, so that the next two would return
  ;;   (transient-suffix :command test-command-f) and
  ;;   (transient-suffix :command test-command-g).
  (should (equal (transient-get-suffix 'test-202-menu [0 2 1])
                 'test-202-list))
  (should (equal (transient-get-suffix 'test-202-menu [0 2 2])
                 '(transient-suffix :command test-command-h))))

(ert-deftest transient-test-301-change-key nil
  (transient-define-prefix test-301-menu ()
    [(test-command-a)
     (test-command-b)
     (test-command-c)
     (test-command-d)])
  (defvar test-301-menu--layout (transient--get-layout 'test-301-menu))
  (transient-suffix-put 'test-301-menu "a"             :key "A")
  (transient-suffix-put 'test-301-menu 'test-command-b :key "B")
  (transient-suffix-put 'test-301-menu [0 -2]          :key "C")
  (transient-suffix-put 'test-301-menu "d"             :key "D")
  (should (equal (transient--get-layout 'test-301-menu)
                 [2 nil
                  ([transient-column nil
                    ((transient-suffix :command test-command-a :key "A")
                     (transient-suffix :command test-command-b :key "B")
                     (transient-suffix :command test-command-c :key "C")
                     (transient-suffix :command test-command-d :key "D"))])]))
  (should (eq (transient--get-layout 'test-301-menu) test-301-menu--layout)))

(ert-deftest transient-test-302-insert nil
  (transient-define-prefix test-302-menu ()
    [(test-command-a)
     (test-command-b)
     (test-command-c)
     (test-command-d)])
  (defvar test-302-menu--layout (transient--get-layout 'test-302-menu))
  (transient-insert-suffix 'test-302-menu "a" '(test-command-z))
  (transient-append-suffix 'test-302-menu "a" '(test-command-y))
  (transient-insert-suffix 'test-302-menu "b" '(test-command-x))
  (transient-append-suffix 'test-302-menu "b" '(test-command-w))
  (transient-insert-suffix 'test-302-menu "d" '(test-command-v))
  (transient-append-suffix 'test-302-menu "d" '(test-command-u))
  (should (equal (transient--get-layout 'test-302-menu)
                 [2 nil
                  ([transient-column nil
                    ((transient-suffix :command test-command-z)
                     (transient-suffix :command test-command-a)
                     (transient-suffix :command test-command-y)
                     (transient-suffix :command test-command-x)
                     (transient-suffix :command test-command-b)
                     (transient-suffix :command test-command-w)
                     (transient-suffix :command test-command-c)
                     (transient-suffix :command test-command-v)
                     (transient-suffix :command test-command-d)
                     (transient-suffix :command test-command-u))])]))
  (should (eq (transient--get-layout 'test-302-menu) test-302-menu--layout)))

(ert-deftest transient-test-303-insert-group nil
  (transient-define-prefix test-303-menu ()
    [[(test-command-a)]
     [(test-command-b)]])
  (transient-define-group test-303-group-c [(test-command-c)])
  (transient-define-group test-303-group-d [(test-command-d)])
  (transient-define-group test-303-group-e [(test-command-e)])
  (transient-define-group test-303-group-f [(test-command-f)])
  (transient-insert-suffix 'test-303-menu [0] 'test-303-group-c)
  (transient-insert-suffix 'test-303-menu [1 1] 'test-303-group-d)
  (transient-insert-suffix 'test-303-menu [1 -1] 'test-303-group-e)
  (transient-append-suffix 'test-303-menu [-1] 'test-303-group-f)
  (should (equal (transient--get-layout 'test-303-menu)
                 [2 nil
                  (test-303-group-c
                   [transient-columns nil
                    ([transient-column nil
                      ((transient-suffix :command test-command-a))]
                     test-303-group-d
                     test-303-group-e
                     [transient-column nil
                      ((transient-suffix :command test-command-b))])]
                   test-303-group-f)])))

(ert-deftest transient-test-304-remove nil
  (transient-define-prefix test-304-menu ()
    [(test-command-a)
     (test-command-b)
     (test-command-c)
     (test-command-d)
     (test-command-e)
     (test-command-f)
     (test-command-g)])
  (defvar test-304-menu--layout (transient--get-layout 'test-304-menu))
  (transient-remove-suffix 'test-304-menu "a")
  (transient-remove-suffix 'test-304-menu 'test-command-b)
  (transient-remove-suffix 'test-304-menu "c")
  (transient-remove-suffix 'test-304-menu [0 0])
  (transient-remove-suffix 'test-304-menu [0 -1])
  (should (equal (transient--get-layout 'test-304-menu)
                 [2 nil
                  ([transient-column nil
                    ((transient-suffix :command test-command-e)
                     (transient-suffix :command test-command-f))])]))
  (should (eq (transient--get-layout 'test-304-menu) test-304-menu--layout)))

(ert-deftest transient-test-305-edit-include nil
  (transient-define-group test-305-group
    [(test-command-a)
     (test-command-b)
     (test-command-c)
     (test-command-d)
     (test-command-e)
     (test-command-f)])
  (transient-define-prefix test-305-menu-1 () 'test-305-group)
  (transient-define-prefix test-305-menu-2 () 'test-305-group)
  (transient-suffix-put 'test-305-group  "a" :key "A")
  (transient-suffix-put 'test-305-menu-1 "b" :key "B")
  (transient-suffix-put 'test-305-menu-2 "c" :key "C")
  (should (equal (transient--get-layout 'test-305-group)
                 [2 nil
                  ([transient-column nil
                    ((transient-suffix :command test-command-a :key "A")
                     (transient-suffix :command test-command-b :key "B")
                     (transient-suffix :command test-command-c :key "C")
                     (transient-suffix :command test-command-d)
                     (transient-suffix :command test-command-e)
                     (transient-suffix :command test-command-f))])]))
  (transient-insert-suffix 'test-305-group  "A" '(test-command-z))
  (transient-append-suffix 'test-305-group  "f" '(test-command-y))
  (transient-insert-suffix 'test-305-menu-1 "z" '(test-command-x))
  (transient-append-suffix 'test-305-menu-2 "y" '(test-command-w))
  (should (equal (transient--get-layout 'test-305-group)
                 [2 nil
                  ([transient-column nil
                    ((transient-suffix :command test-command-x)
                     (transient-suffix :command test-command-z)
                     (transient-suffix :command test-command-a :key "A")
                     (transient-suffix :command test-command-b :key "B")
                     (transient-suffix :command test-command-c :key "C")
                     (transient-suffix :command test-command-d)
                     (transient-suffix :command test-command-e)
                     (transient-suffix :command test-command-f)
                     (transient-suffix :command test-command-y)
                     (transient-suffix :command test-command-w))])]))
  (transient-remove-suffix 'test-305-group "z")
  (transient-remove-suffix 'test-305-group "y")
  (transient-remove-suffix 'test-305-group "x")
  (transient-remove-suffix 'test-305-group "w")
  (should (equal (transient--get-layout 'test-305-group)
                 [2 nil
                  ([transient-column nil
                    ((transient-suffix :command test-command-a :key "A")
                     (transient-suffix :command test-command-b :key "B")
                     (transient-suffix :command test-command-c :key "C")
                     (transient-suffix :command test-command-d)
                     (transient-suffix :command test-command-e)
                     (transient-suffix :command test-command-f))])]))
  (should (equal (transient--get-layout 'test-305-menu-1)
                 (transient--get-layout 'test-305-menu-2))))

(ert-deftest transient-test-306-inline nil
  (transient-define-group test-306-group-a [(test-command-a)])
  (transient-define-group test-306-group-b [(test-command-b)])
  (transient-define-group test-306-group-d [(test-command-d)])
  (transient-define-group test-306-group-e [(test-command-e)])
  (transient-define-prefix test-306-menu ()
    'test-306-group-a
    [test-306-group-b
     [(test-command-c)]
     test-306-group-d]
    'test-306-group-e)
  (transient-inline-group 'test-306-menu 'test-306-group-a)
  (transient-inline-group 'test-306-menu 'test-306-group-b)
  (transient-inline-group 'test-306-menu 'test-306-group-d)
  (transient-inline-group 'test-306-menu 'test-306-group-e)
  (should (equal (transient--get-layout 'test-306-menu)
                 [2 nil
                  ([transient-column nil
                    ((transient-suffix :command test-command-a))]
                   [transient-columns nil
                    ([transient-column nil
                      ((transient-suffix :command test-command-b))]
                     [transient-column nil
                      ((transient-suffix :command test-command-c))]
                     [transient-column nil
                      ((transient-suffix :command test-command-d))])]
                   [transient-column nil
                    ((transient-suffix :command test-command-e))])])))

;; Local Variables:
;; indent-tabs-mode: nil
;; End:
;;; transient-tests.el ends here
