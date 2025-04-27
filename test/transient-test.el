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

(transient-define-suffix test-command-a () (interactive))
(transient-define-suffix test-command-b () (interactive))
(transient-define-suffix test-command-c () :key "c" (interactive))
(transient-define-suffix test-command-d () (interactive))
(transient-define-suffix test-command-e () (interactive))
(transient-define-suffix test-command-f () (interactive))
(transient-define-suffix test-command-g () (interactive))
(transient-define-suffix test-command-h () (interactive))
(transient-define-suffix test-command-i () (interactive))
(transient-define-suffix test-command-j () (interactive))

(transient-define-suffix test-command-q () (interactive))
(transient-define-suffix test-command-r () (interactive))
(transient-define-suffix test-command-s () (interactive))
(transient-define-suffix test-command-t () (interactive))
(transient-define-suffix test-command-u () (interactive))
(transient-define-suffix test-command-v () (interactive))
(transient-define-suffix test-command-w () :key "w" (interactive))
(transient-define-suffix test-command-x () :key "x" (interactive))
(transient-define-suffix test-command-y () :key "y" (interactive))
(transient-define-suffix test-command-z () :key "z" (interactive))

(ert-deftest transient-test-101-define nil
  (transient-define-prefix test-101-menu ()
    [(test-command-a :key "a")
     (test-command-b :key "b")
     (test-command-c)
     (test-command-d :key "d")])
  (defvar test-101-menu--layout (transient--get-layout 'test-101-menu))
  (should (equal (transient--get-layout 'test-101-menu)
                 [2 nil
                  ([transient-column nil
                    ((transient-suffix :command test-command-a :key "a")
                     (transient-suffix :command test-command-b :key "b")
                     (transient-suffix :command test-command-c)
                     (transient-suffix :command test-command-d :key "d"))])]))
  (should (eq (transient--get-layout 'test-101-menu) test-101-menu--layout)))

(ert-deftest transient-test-102-change-key nil
  (transient-define-prefix test-102-menu ()
    [(test-command-a :key "a")
     (test-command-b :key "b")
     (test-command-c)
     (test-command-d :key "d")])
  (defvar test-102-menu--layout (transient--get-layout 'test-102-menu))
  (transient-suffix-put 'test-102-menu "a"             :key "A")
  (transient-suffix-put 'test-102-menu 'test-command-b :key "B")
  (transient-suffix-put 'test-102-menu [0 -2]          :key "C")
  (transient-suffix-put 'test-102-menu "d"             :key "D")
  (should (equal (transient--get-layout 'test-102-menu)
                 [2 nil
                  ([transient-column nil
                    ((transient-suffix :command test-command-a :key "A")
                     (transient-suffix :command test-command-b :key "B")
                     (transient-suffix :command test-command-c :key "C")
                     (transient-suffix :command test-command-d :key "D"))])]))
  (should (eq (transient--get-layout 'test-102-menu) test-102-menu--layout)))

(ert-deftest transient-test-103-insert nil
  (transient-define-prefix test-103-menu ()
    [(test-command-a :key "a")
     (test-command-b :key "b")
     (test-command-c)
     (test-command-d :key "d")])
  (defvar test-103-menu--layout (transient--get-layout 'test-103-menu))
  (transient-insert-suffix 'test-103-menu "a" '(test-command-z))
  (transient-append-suffix 'test-103-menu "a" '(test-command-y))
  (transient-insert-suffix 'test-103-menu "b" '(test-command-x))
  (transient-append-suffix 'test-103-menu "b" '(test-command-w))
  (transient-insert-suffix 'test-103-menu "d" '(test-command-v :key "v"))
  (transient-append-suffix 'test-103-menu "d" '(test-command-u :key "u"))
  (should (equal (transient--get-layout 'test-103-menu)
                 [2 nil
                  ([transient-column nil
                    ((transient-suffix :command test-command-z)
                     (transient-suffix :command test-command-a :key "a")
                     (transient-suffix :command test-command-y)
                     (transient-suffix :command test-command-x)
                     (transient-suffix :command test-command-b :key "b")
                     (transient-suffix :command test-command-w)
                     (transient-suffix :command test-command-c)
                     (transient-suffix :command test-command-v :key "v")
                     (transient-suffix :command test-command-d :key "d")
                     (transient-suffix :command test-command-u :key "u"))])]))
  (should (eq (transient--get-layout 'test-103-menu) test-103-menu--layout)))

(ert-deftest transient-test-104-remove nil
  (transient-define-prefix test-104-menu ()
    [(test-command-a :key "a")
     (test-command-b :key "b")
     (test-command-c)
     (test-command-d :key "d")
     (test-command-e :key "e")
     (test-command-f :key "f")
     (test-command-g :key "g")])
  (defvar test-104-menu--layout (transient--get-layout 'test-104-menu))
  (transient-remove-suffix 'test-104-menu "a")
  (transient-remove-suffix 'test-104-menu 'test-command-b)
  (transient-remove-suffix 'test-104-menu "c")
  (transient-remove-suffix 'test-104-menu [0 0])
  (transient-remove-suffix 'test-104-menu [0 -1])
  (should (equal (transient--get-layout 'test-104-menu)
                 [2 nil
                  ([transient-column nil
                    ((transient-suffix :command test-command-e :key "e")
                     (transient-suffix :command test-command-f :key "f"))])]))
  (should (eq (transient--get-layout 'test-104-menu) test-104-menu--layout)))

(ert-deftest transient-test-105-include nil
  (transient-define-group test-105-top-group
    [:class transient-row
     (test-command-a :key "a")
     (test-command-b :key "b")])
  (should (equal (transient--get-layout 'test-105-top-group)
                 [2 nil
                  ([transient-row nil
                    ((transient-suffix :command test-command-a :key "a")
                     (transient-suffix :command test-command-b :key "b"))])]))
  (transient-define-group test-105-top-groups
    [[(test-command-c :key "c")
      (test-command-d :key "d")]
     [(test-command-e :key "e")
      (test-command-f :key "f")]])
  (should (equal (transient--get-layout 'test-105-top-groups)
                 [2 nil
                  ([transient-columns nil
                    ([transient-column nil
                      ((transient-suffix :command test-command-c :key "c")
                       (transient-suffix :command test-command-d :key "d"))]
                     [transient-column nil
                      ((transient-suffix :command test-command-e :key "e")
                       (transient-suffix :command test-command-f :key "f"))])])]))
  (transient-define-group test-105-child-group
    [(test-command-g :key "g")
     (test-command-h :key "h")])
  (should (equal (transient--get-layout 'test-105-child-group)
                 [2 nil
                  ([transient-column nil
                    ((transient-suffix :command test-command-g :key "g")
                     (transient-suffix :command test-command-h :key "h"))])]))
  (transient-define-group test-105-suffix-list
    (test-command-z :key "z")
    (test-command-y :key "y"))
  (should (equal (transient--get-layout 'test-105-suffix-list)
                 [2 nil
                  ((transient-suffix :command test-command-z :key "z")
                   (transient-suffix :command test-command-y :key "y"))]))
  (transient-define-prefix test-105-menu ()
    'test-105-top-group
    'test-105-top-groups
    [[(test-command-i :key "i")
      (test-command-j :key "j")
      test-105-suffix-list]
     test-105-child-group])
  (should (equal (transient--get-layout 'test-105-menu)
                 [2 nil
                  (test-105-top-group
                   test-105-top-groups
                   [transient-columns nil
                    ([transient-column nil
                      ((transient-suffix :command test-command-i :key "i")
                       (transient-suffix :command test-command-j :key "j")
                       test-105-suffix-list)]
                     test-105-child-group)])]))
  )

(ert-deftest transient-test-106-edit-include nil
  (transient-define-group test-106-group
    [(test-command-a :key "a")
     (test-command-b :key "b")
     (test-command-c :key "c")
     (test-command-d :key "d")
     (test-command-e :key "e")
     (test-command-f :key "f")])
  (transient-define-prefix test-106-menu-1 ()
    'test-106-group)
  (transient-define-prefix test-106-menu-2 ()
    'test-106-group)
  (transient-suffix-put 'test-106-group  "a" :key "A")
  (transient-suffix-put 'test-106-menu-1 "b" :key "B")
  (transient-suffix-put 'test-106-menu-2 "c" :key "C")
  (should (equal (transient--get-layout 'test-106-group)
                 [2 nil
                  ([transient-column nil
                    ((transient-suffix :command test-command-a :key "A")
                     (transient-suffix :command test-command-b :key "B")
                     (transient-suffix :command test-command-c :key "C")
                     (transient-suffix :command test-command-d :key "d")
                     (transient-suffix :command test-command-e :key "e")
                     (transient-suffix :command test-command-f :key "f"))])]))
  (transient-insert-suffix 'test-106-group  "A" '(test-command-z :key "z"))
  (transient-append-suffix 'test-106-group  "f" '(test-command-y :key "y"))
  (transient-insert-suffix 'test-106-menu-1 "z" '(test-command-x :key "x"))
  (transient-append-suffix 'test-106-menu-2 "y" '(test-command-w :key "w"))
  (should (equal (transient--get-layout 'test-106-group)
                 [2 nil
                  ([transient-column nil
                    ((transient-suffix :command test-command-x :key "x")
                     (transient-suffix :command test-command-z :key "z")
                     (transient-suffix :command test-command-a :key "A")
                     (transient-suffix :command test-command-b :key "B")
                     (transient-suffix :command test-command-c :key "C")
                     (transient-suffix :command test-command-d :key "d")
                     (transient-suffix :command test-command-e :key "e")
                     (transient-suffix :command test-command-f :key "f")
                     (transient-suffix :command test-command-y :key "y")
                     (transient-suffix :command test-command-w :key "w"))])]))
  (transient-remove-suffix 'test-106-group "z")
  (transient-remove-suffix 'test-106-group "y")
  (transient-remove-suffix 'test-106-group "x")
  (transient-remove-suffix 'test-106-group "w")
  (should (equal (transient--get-layout 'test-106-group)
                 [2 nil
                  ([transient-column nil
                    ((transient-suffix :command test-command-a :key "A")
                     (transient-suffix :command test-command-b :key "B")
                     (transient-suffix :command test-command-c :key "C")
                     (transient-suffix :command test-command-d :key "d")
                     (transient-suffix :command test-command-e :key "e")
                     (transient-suffix :command test-command-f :key "f"))])]))
  )

(ert-deftest transient-test-107-edit-include-list nil
  (transient-define-group test-107-suffix-list
    (test-command-c :key "c")
    (test-command-d :key "d"))
  (transient-define-prefix test-107-menu ()
    [(test-command-a :key "a")
     (test-command-b :key "b")
     test-107-suffix-list
     (test-command-e :key "e")
     (test-command-f :key "f")])
  (transient-append-suffix 'test-107-menu "c" '(test-command-z :key "z"))
  ) ;TODO

;; Local Variables:
;; indent-tabs-mode: nil
;; End:
;;; transient-tests.el ends here
