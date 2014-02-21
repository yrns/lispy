(require 'lispy)

;; ——— Infrastructure ——————————————————————————————————————————————————————————
(defmacro lispy-with (in &rest body)
  `(with-temp-buffer
     (emacs-lisp-mode)
     (lispy-mode)
     (insert ,in)
     (when (search-backward "~" nil t)
       (delete-char 1)
       (set-mark (point))
       (goto-char (point-max)))
     (search-backward "|")
     (delete-char 1)
     ,@(mapcar (lambda(x) (if (stringp x) `(lispy-unalias ,x) x)) body)
     (insert "|")
     (when (region-active-p)
       (exchange-point-and-mark)
       (insert "~"))
     (buffer-substring-no-properties
      (point-min)
      (point-max))))

(defmacro lispy-with-value (in &rest body)
  `(with-temp-buffer
     (emacs-lisp-mode)
     (lispy-mode)
     (insert ,in)
     (when (search-backward "~" nil t)
       (delete-char 1)
       (set-mark (point))
       (goto-char (point-max)))
     (search-backward "|")
     (delete-char 1)
     ,@(mapcar (lambda(x) (if (stringp x) `(lispy-unalias ,x) x)) body)))

(defun lispy-decode-keysequence (str)
  "Decode STR from e.g. \"23ab5c\" to '(23 \"a\" \"b\" 5 \"c\")"
  (let ((table (copy-seq (syntax-table))))
    (loop for i from ?0 to ?9 do
         (modify-syntax-entry i "." table))
    (loop for i from ? to ? do
         (modify-syntax-entry i "w" table))
    (loop for i in '(? ?\( ?\) ?\[ ?\] ?{ ?} ?\" ?\')
         do (modify-syntax-entry i "w" table))
    (cl-mapcan (lambda(x)
                 (let ((y (ignore-errors (read x))))
                   (if (numberp y)
                       (list y)
                     (mapcar #'string x))))
               (with-syntax-table table
                 (split-string str "\\b" t)))))

(ert-deftest lispy-decode-keysequence ()
  (should (equal (lispy-decode-keysequence "23ab50c")
                 '(23 "a" "b" 50 "c")))
  (should (equal (lispy-decode-keysequence "3\C-d")
                 '(3 "")))
  (should (equal (lispy-decode-keysequence "3\C-?")
                 '(3 ""))))

(defun lispy-unalias (seq)
  "Emulate pressing keys decoded from SEQ."
  (let ((keys (lispy-decode-keysequence seq))
        key)
    (while (setq key (pop keys))
      (if (numberp key)
          (let ((current-prefix-arg (list key)))
            (when keys
              (lispy--unalias-key (pop keys))))
        (lispy--unalias-key key)))))

(defun lispy--unalias-key (key)
  "Call command that corresponds to KEY.
Insert KEY if there's no command."
  (let ((cmd (cdr (assoc 'lispy-mode (minor-mode-key-binding key)))))
    (if (or (and cmd (or (looking-at lispy-left)
                         (looking-back lispy-right)))
            (progn
              (setq cmd (key-binding key))
              (not (cond ((eq cmd 'self-insert-command))
                         ((string-match "^special" (symbol-name cmd)))))))
        (call-interactively cmd)
      (insert key))))

;; ——— Tests ———————————————————————————————————————————————————————————————————
(ert-deftest lispy-forward ()
  (should (string= (lispy-with "(|(a) (b) (c))" "]")
                   "((a)| (b) (c))"))
  (should (string= (lispy-with "((|a) (b) (c))" "]")
                   "((a)| (b) (c))"))
  (should (string= (lispy-with "((a) |(b) (c))" "]")
                   "((a) (b)| (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "]]")
                   "((a) (b)| (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "3]")
                   "((a) (b) (c)|)"))
  (should (string= (lispy-with "(|(a) (b) (c))" "]]]]")
                   "((a) (b) (c))|"))
  (should (string= (lispy-with "(|(a) (b) (c))" "4]")
                   "((a) (b) (c)|)"))
  (should (string= (lispy-with "(|(a) (b) (c))" "40]")
                   "((a) (b) (c)|)"))
  (should (string= (lispy-with "(|(a) (b) (c))"
                               (set-mark (point))
                               "]"
                               (call-interactively 'kill-region))
                   "(~| (b) (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))"
                               (set-mark (point))
                               "2]"
                               (call-interactively 'kill-region))
                   "(~| (c))"))
  (should (lispy-with-value "(|(a) (b) (c))" (set-mark (point)) "]]]" (region-active-p)))
  (should (not (lispy-with-value "(a) (b) (c)| " (lispy-forward 1))))
  (should (not (lispy-with-value "(a) (b) (c)|" (lispy-forward 1))))
  ;; break active region when exiting list
  (should (not (lispy-with-value "(|(a) (b) (c))" (set-mark (point)) "]]]]" (region-active-p))))
  (should (lispy-with-value "(a)| (b)\n" (lispy-forward 2))))

(ert-deftest lispy-backward ()
  (should (string= (lispy-with "(|(a) (b) (c))" "[")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "((a)|)" "[")
                   "(|(a))"))
  (should (string= (lispy-with "((|a) (b) (c))" "[")
                   "(|(a) (b) (c))"))
  (should (string= (lispy-with "((a) |(b) (c))" "[")
                   "(|(a) (b) (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "[[")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "3[")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "[")
                   "((a) (b) |(c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "4[")
                   "(|(a) (b) (c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "40[")
                   "(|(a) (b) (c))"))
  (should (string= (lispy-with "((b)|\"foo\")" "[")
                   "(|(b)\"foo\")"))
  (should (string= (lispy-with "(bar)\n;; (foo baar)|" "[")
                   "|(bar)\n;; (foo baar)"))
  (should (string= (lispy-with "(foo)\n;; (foo bar\n;;      tanf)|" "[")
                   "|(foo)\n;; (foo bar\n;;      tanf)")))

(ert-deftest lispy-out-forward ()
  (should (string= (lispy-with "(|(a) (b) (c))" "l")
                   "((a) (b) (c))|"))
  (should (string= (lispy-with "(|(a) (b) (c))" "ll")
                   "((a) (b) (c))|"))
  (should (string= (lispy-with "(|(a) (b) (c))" (lispy-out-forward 1))
                   "((a) (b) (c))|"))
  (should (string= (lispy-with "(|(a) (b) (c))"
                               (lispy-out-forward 1)
                               (lispy-out-forward 1))
                   "((a) (b) (c))|"))
  (should (string= (lispy-with "((|a) (b) (c))" (lispy-out-forward 1))
                   "((a)| (b) (c))"))
  (should (string= (lispy-with "((|a) (b) (c))"
                               (lispy-out-forward 1)
                               (lispy-out-forward 1))
                   "((a) (b) (c))|"))
  (should (string= (lispy-with "((|a) (b) (c))" (lispy-out-forward 2))
                   "((a) (b) (c))|"))
  (should (string= (lispy-with "((a) \"(|foo)\" (c))" (lispy-out-forward 2))
                   "((a) \"(foo)\" (c))|"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "l")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))|))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "ll")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)))|)"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "3l")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))))|"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "9l")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))))|"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "l")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))|))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "ll")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)))|)"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "3l")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))))|"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "9l")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))))|")))

(ert-deftest lispy-out-backward ()
  (should (string= (lispy-with "(|(a) (b) (c))" "a")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "aa")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "((a)| (b) (c))" "a")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "((a) (b)| (c))" "a")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "((a) |(b) (c))" "a")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "a")
                   "(defun foo ()\n  (let ((a 1))\n    |(let ((b 2))\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "aa")
                   "(defun foo ()\n  |(let ((a 1))\n    (let ((b 2))\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "3a")
                   "|(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "9a")
                   "|(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "a")
                   "(defun foo ()\n  (let ((a 1))\n    |(let ((b 2))\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "aa")
                   "(defun foo ()\n  |(let ((a 1))\n    (let ((b 2))\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "3a")
                   "|(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "9a")
                   "|(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something))))"))
  (should (equal (lispy-with-value "|(foo)" (lispy-backward 1)) nil))
  (should (equal (lispy-with "((foo \"(\"))\n((foo \")\"))\n\"un|expected\"" (lispy-backward 1))
                 "((foo \"(\"))\n|((foo \")\"))\n\"unexpected\"")))

(ert-deftest lispy-flow ()
  (should (string= (lispy-with "(|(a) (b) (c))" "f")
                   "((a) |(b) (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "ff")
                   "((a) (b) |(c))"))
  (should (string= (lispy-with "((a)| (b) (c))" "f")
                   "((a)| (b) (c))"))
  (should (string= (lispy-with "((a) (b)| (c))" "f")
                   "((a)| (b) (c))"))
  (should (string= (lispy-with "((a) |(b) (c))" "f")
                   "((a) (b) |(c))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "f")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))|\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "ff")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2)|)\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "3f")
                   "(defun foo ()\n  (let ((a 1))|\n    (let ((b 2))\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      (something)|)))" "9f")
                   "(defun foo ()|\n  (let ((a 1))\n    (let ((b 2))\n      (something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "f")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "ff")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))" "3f")
                   "(defun foo ()\n  (let ((a 1))\n    (let ((b 2))\n      |(something))))")))

(ert-deftest lispy-counterclockwise ()
  (should (string= (lispy-with "(|(a) (b) (c))" "o")
                   "((a) |(b) (c))"))
  (should (string= (lispy-with "(|(a))" "o")
                   "((a)|)"))
  (should (string= (lispy-with "(|(a) (b) (c))" "oo")
                   "((a) (b) |(c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "ooo")
                   "((a) (b) (c)|)"))
  (should (string= (lispy-with "(|(a) (b) (c))" "oooo")
                   "((a) (b)| (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "ooooo")
                   "((a)| (b) (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "oooooo")
                   "(|(a) (b) (c))"))
  (should (string= (lispy-with "|((a) (b) (c))" "o")
                   "((a) (b) (c))|"))
  (should (string= (lispy-with "|((a) (b) (c))" "oo")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "(|(b)\"foo\")" "o")
                   "((b)|\"foo\")")))

(ert-deftest lispy-clockwise ()
  (should (string= (lispy-with "(|(a) (b) (c))" "p")
                   "((a)| (b) (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "pp")
                   "((a) (b)| (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "ppp")
                   "((a) (b) (c)|)"))
  (should (string= (lispy-with "(|(a) (b) (c))" "pppp")
                   "((a) (b) |(c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "ppppp")
                   "((a) |(b) (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "pppppp")
                   "(|(a) (b) (c))"))
  (should (string= (lispy-with "|((a) (b) (c))" "p")
                   "((a) (b) (c))|"))
  (should (string= (lispy-with "|((a) (b) (c))" "pp")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "(a) (b) (c)| " "p")
                   "(a) (b) |(c) "))
  (should (string= (lispy-with "(a) (b) (c)|" "p")
                   "(a) (b) |(c)"))
  (should (string= (lispy-with "((b)|\"foo\")" "p")
                   "(|(b)\"foo\")")))

(ert-deftest lispy-down ()
  (should (string= (lispy-with "(|(a) (b) (c))" "j")
                   "((a) |(b) (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "jj")
                   "((a) (b) |(c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "2j")
                   "((a) (b) |(c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "jjj")
                   "((a) (b) (c)|)"))
  (should (string= (lispy-with "(|(a) (b) (c))" "3j")
                   "((a) (b) (c)|)"))
  (should (string= (lispy-with "(|(a) (b) (c))" "jjjj")
                   "((a) (b) |(c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "4j")
                   "((a) (b) (c)|)"))
  (should (string= (lispy-with "(a)| (b)\n" "2j")
                   "(a) (b)|\n"))
  (should (string= (lispy-with "(foo\n |(one)\n two\n (three)\n (four))" "j")
                   "(foo\n (one)\n two\n |(three)\n (four))"))
  (should (string= (lispy-with "(foo\n |(one)\n two\n (three)\n (four))" "jj")
                   "(foo\n (one)\n two\n (three)\n |(four))"))
  (should (string= (lispy-with "(foo\n |(one)\n two\n (three)\n (four))" "jjj")
                   "(foo\n (one)\n two\n (three)\n (four)|)"))
  (should (string= (lispy-with "(foo\n (one)|\n two\n (three)\n (four))" "j")
                   "(foo\n (one)\n two\n (three)|\n (four))"))
  (should (string= (lispy-with "(foo\n (one)|\n two\n (three)\n (four))" "jj")
                   "(foo\n (one)\n two\n (three)\n (four)|)"))
  (should (string= (lispy-with "(foo\n (one)|\n two\n (three)\n (four))" "jjj")
                   "(foo\n (one)\n two\n (three)\n |(four))")))

(ert-deftest lispy-up ()
  (should (string= (lispy-with "((a) (b) (c)|)" "k")
                   "((a) (b)| (c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "kk")
                   "((a)| (b) (c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "2k")
                   "((a)| (b) (c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "kkk")
                   "(|(a) (b) (c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "3k")
                   "(|(a) (b) (c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "kkkk")
                   "((a)| (b) (c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "4k")
                   "(|(a) (b) (c))"))
  (should (string= (lispy-with ";; \n(foo)\n|(bar)" "2k")
                   ";; \n|(foo)\n(bar)"))
  (should (string= (lispy-with "(foo\n |(one)\n two\n (three)\n (four))" "k")
                   "(foo\n (one)|\n two\n (three)\n (four))"))
  (should (string= (lispy-with "(foo\n |(one)\n two\n (three)\n (four))" "kk")
                   "(foo\n |(one)\n two\n (three)\n (four))"))
  (should (string= (lispy-with "(foo\n (one)|\n two\n (three)\n (four))" "k")
                   "(foo\n |(one)\n two\n (three)\n (four))"))
  (should (string= (lispy-with "(foo\n (one)\n two\n (three)|\n (four))" "k")
                   "(foo\n (one)|\n two\n (three)\n (four))"))
  (should (string= (lispy-with "(foo\n (one)\n two\n (three)|\n (four))" "kk")
                   "(foo\n |(one)\n two\n (three)\n (four))"))
  (should (string= (lispy-with "(foo\n (one)\n two\n (three)\n (four)|)" "k")
                   "(foo\n (one)\n two\n (three)|\n (four))"))
  (should (string= (lispy-with "(foo\n (one)\n two\n (three)\n (four)|)" "kk")
                   "(foo\n (one)|\n two\n (three)\n (four))"))
  (should (string= (lispy-with "(foo\n (one)\n two\n (three)\n (four)|)" "kk")
                   "(foo\n (one)|\n two\n (three)\n (four))")))

(ert-deftest lispy-different ()
  (should (string= (lispy-with "((a) (b) (c)|)" "d")
                   "((a) (b) |(c))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "dd")
                   "((a) (b) (c)|)"))
  (should (string= (lispy-with "((a) (b) (c))|" "d")
                   "|((a) (b) (c))")))

(ert-deftest lispy-kill ()
  (should (string= (lispy-with "\n\n|(defun foo ()\n    )" (lispy-kill))
                   "|\n\n "))
  ;; while ahead of defun, and there's a comment before, move there
  (should (string= (lispy-with "\n;comment\n|(defun foo ()\n    )" (lispy-kill))
                   "|\n;comment\n "))
  (should (string= (lispy-with "(|(a) (b) (c))" "\C-k")
                   "(|)"))
  (should (string= (lispy-with "((a) |(b) (c))" "\C-k")
                   "((a) |)"))
  (should (string= (lispy-with "((a) (b) |(c))" "\C-k")
                   "((a) (b) |)"))
  (should (string= (lispy-with "((a)|\n (b) (c))" "\C-k")
                   "((a)| (b) (c))"))
  (should (string= (lispy-with "((a)|\n (b) (c))" "\C-k\C-k")
                   "((a)|)"))
  (should (string= (lispy-with "(a b c)\n(|)" "\C-k")
                   "(a b c)\n|")))

(ert-deftest lispy-yank ()
  (should (string= (lispy-with "\"|\"" (kill-new "foo") (lispy-yank))
                   "\"foo|\""))
  (should (string= (lispy-with "\"|\"" (kill-new "\"foo\"") (lispy-yank))
                   "\"\\\"foo\\\"|\"")))

(ert-deftest lispy-delete ()
  (should (string= (lispy-with "(|(a) (b) (c))" "\C-d")
                   "(|(b) (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "2\C-d")
                   "(|(c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "3\C-d")
                   "|()"))
  (should (string= (lispy-with "(|(a) \"foo\")" "\C-d")
                   "|(\"foo\")"))
  (should (string= (lispy-with "(|(a)\"foo\")" "\C-d")
                   "|(\"foo\")"))
  (should (string= (lispy-with "(|(a) b (c))" "\C-d")
                   "(b |(c))"))
  (should (string= (lispy-with "((a) |\"foo\" (c))" "\C-d")
                   "((a) |(c))"))
  (should (string= (lispy-with "((a) (|) (c))" "\C-d")
                   "((a)| (c))"))
  (should (string= (lispy-with "(a (|) c)" "\C-d")
                   "(a c)|"))
  (should (string= (lispy-with "(foo \"bar|\")" "\C-d")
                   "(foo |\"bar\")"))
  (should (string= (lispy-with "\"foo|\\\"\\\"\"" "\C-d")
                   "\"foo|\\\"\""))
  (should (string= (lispy-with "\"|\\\\(foo\\\\)\"" "\C-d")
                   "\"|foo\""))
  (should (string= (lispy-with "\"\\\\(foo|\\\\)\"" "\C-d")
                   "\"foo|\"")))

(ert-deftest lispy-delete-backward ()
  (should (string= (lispy-with "((a) (b) (c)|)" "\C-?")
                   "((a) (b)|)"))
  (should (string= (lispy-with "((a) (b) (c)|)" "2\C-?")
                   "((a)|)"))
  (should (string= (lispy-with "((a) (b) (c)|)" "3\C-?")
                   "()|"))
  (should (string= (lispy-with "(a (b)| c)" "\C-?")
                   "(a c)|"))
  (should (string= (lispy-with "(a (|) c)" "\C-?")
                   "(a c)|"))
  (should (string= (lispy-with "(foo \"|bar\")" "\C-?")
                   "(foo \"bar\"|)"))
  (should (string= (lispy-with "(a \"\"| c)" "\C-?")
                   "(a c)|"))
  (should (string= (lispy-with ";|" "\C-?")
                   "|"))
  (should (string= (lispy-with "\"\\\\(|foo\\\\)\"" "\C-?")
                   "\"|foo\""))
  (should (string= (lispy-with "\"\\\\(foo\\\\)|\"" "\C-?")
                   "\"foo|\""))
  (should (string= (lispy-with "\"\\\\(|foo\"" "\C-?")
                   "\"\\\\|foo\""))
  (should (string= (lispy-with "(foo)\n;; ()|" "\C-?")
                   "(foo)\n;; (|"))
  (should (string= (lispy-with "(~\"foo\"|)" "\C-?")
                   "(~|)"))
  (should (string= (lispy-with "(|\"foo\"~)" "\C-?")
                   "(~|)"))
  (should (string= (lispy-with "(foo bar)\n;; comment\n(foo bar)|" "\C-?")
                   "(foo bar)|\n;; comment\n")))

(ert-deftest lispy-pair ()
  (should (string= (lispy-with "\"\\\\|\"" "(")
                   "\"\\\\(|\\\\)\""))
  (should (string= (lispy-with "\"\\\\|\"" "{")
                   "\"\\\\{|\\\\}\""))
  (should (string= (lispy-with "\"\\\\|\"" "}")
                   "\"\\\\[|\\\\]\"")))

(ert-deftest lispy-slurp ()
  (should (string= (lispy-with "()|(a) (b) (c)" ">")
                   "((a))| (b) (c)"))
  (should (string= (lispy-with "()|(a) (b) (c)" ">>")
                   "((a) (b))| (c)"))
  (should (string= (lispy-with "()|(a) (b) (c)" ">>>")
                   "((a) (b) (c))|"))
  (should (string= (lispy-with "()|(a) (b) (c)" ">>>>")
                   "((a) (b) (c))|"))
  (should (string= (lispy-with "(a) (b) (c)|()" ">")
                   "(a) (b) |((c))"))
  (should (string= (lispy-with "(a) (b) (c)|()" ">>")
                   "(a) |((b) (c))"))
  (should (string= (lispy-with "(a) (b) (c)|()" ">>>")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "(a) (b) (c)|()" ">>>>")
                   "|((a) (b) (c))"))
  (should (string= (lispy-with "(insert)|\"foo\"" ">")
                   "(insert \"foo\")|")))

(ert-deftest lispy-barf ()
  (should (string= (lispy-with "((a) (b) (c))|" "<")
                   "((a) (b))| (c)"))
  (should (string= (lispy-with "((a) (b) (c))|" "<<")
                   "((a))| (b) (c)"))
  (should (string= (lispy-with "((a) (b) (c))|" "<<<")
                   "()|(a) (b) (c)"))
  (should (string= (lispy-with "((a) (b) (c))|" "<<<<")
                   "()|(a) (b) (c)"))
  (should (string= (lispy-with "|((a) (b) (c))" "<")
                   "(a) |((b) (c))"))
  (should (string= (lispy-with "|((a) (b) (c))" "<<")
                   "(a) (b) |((c))"))
  (should (string= (lispy-with "|((a) (b) (c))" "<<<")
                   "(a) (b) (c)|()"))
  (should (string= (lispy-with "|((a) (b) (c))" "<<<<")
                   "(a) (b) (c)|()")))

(ert-deftest lispy-splice ()
  (should (string= (lispy-with "(|(a) (b) (c))" "/")
                   "(a |(b) (c))"))
  (should (string= (lispy-with "((a) |(b) (c))" "/")
                   "((a) b |(c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "///")
                   "|(a b c)"))
  (should (string= (lispy-with "((a) (b) (c)|)" "/")
                   "((a) (b)| c)"))
  (should (string= (lispy-with "((a) (b) (c)|)" "//")
                   "((a)| b c)"))
  (should (string= (lispy-with "((a) (b) (c)|)" "///")
                   "(a b c)|"))
  (should (string= (lispy-with "|(a b c)" "/")
                   "|a b c"))
  (should (string= (lispy-with "(a b c)|" "/")
                   "a b c|")))

(ert-deftest lispy-raise ()
  (should (string= (lispy-with "(if (and |(pred1) (pred2))\n    (thing1)\n  (thing2))" "r")
                   "(if |(pred1)\n    (thing1)\n  (thing2))"))
  (should (string= (lispy-with "(if (and (pred1) |(pred2))\n    (thing1)\n  (thing2))" "r")
                   "(if |(pred2)\n    (thing1)\n  (thing2))"))
  (should (string= (lispy-with "(if (and (pred1)| (pred2))\n    (thing1)\n  (thing2))" "r")
                   "(if (pred1)|\n    (thing1)\n  (thing2))"))
  (should (string= (lispy-with "(if (and (pred1) (pred2)|)\n    (thing1)\n  (thing2))" "r")
                   "(if (pred2)|\n    (thing1)\n  (thing2))"))
  (should (string= (lispy-with "(if (and (pred1) (pred2))\n    |(thing1)\n  (thing2))" "r")
                   "|(thing1)"))
  (should (string= (lispy-with "(if (and (pred1) (pred2))\n    (thing1)|\n  (thing2))" "r")
                   "(thing1)|"))
  (should (string= (lispy-with "(if (and (pred1) (pred2))\n    (thing1)\n  |(thing2))" "r")
                   "|(thing2)"))
  (should (string= (lispy-with "(if (and (pred1) (pred2))\n    (thing1)\n  (thing2)|)" "r")
                   "(thing2)|"))
  (should (string= (lispy-with "(a (f~oob|ar) c)" (lispy-raise)) "(a oob c)|"))
  (should (string= (lispy-with "(a (f|oob~ar) c)" (lispy-raise)) "(a oob c)|"))
  (should (string= (lispy-with "(\n     |(foo))" "r") "|(foo)")))

(ert-deftest lispy-raise-some ()
  (should (string= (lispy-with "(if (and |(pred1) (pred2))\n    (thing1)\n  (thing2))" "R")
                   "(if |(pred1) (pred2)\n  (thing1)\n  (thing2))"))
  (should (string= (lispy-with "(if (and (pred1) |(pred2))\n    (thing1)\n  (thing2))" "R")
                   "(if |(pred2)\n    (thing1)\n  (thing2))"))
  (should (string= (lispy-with "(if (and (pred1) (pred2))\n    |(thing1)\n  (thing2))" "R")
                   "|(thing1)\n(thing2)"))
  (should (string= (lispy-with "(progn\n  |(foo)\n  nil)" "R")
                   "|(foo)\nnil"))
  (should (string= (lispy-with "(a\n b\n (foo)|\n c)" "R")
                   "a\nb\n(foo)|")))

(ert-deftest lispy-convolute ()
  (should (string= (lispy-with "(when (pred)\n  (let ((x 1))\n    |(foo)\n    (bar)))" "C")
                   "(let ((x 1))\n  (when (pred)\n    |(foo)\n    (bar)))"))
  (should (string= (lispy-with "(when (pred)\n  (let ((x 1))\n    |(foo)\n    (bar)))" "CC")
                   "(when (pred)\n  (let ((x 1))\n    |(foo)\n    (bar)))"))
  (should (string= (lispy-with "(+ 1 (* 2 ~3|))" (lispy-convolute))
                   "(* 2 (+ 1 ~3|))"))
  (should (string= (lispy-with "(+ 1 (* 2 |3~))" (lispy-convolute))
                   "(* 2 (+ 1 |3~))")))

(ert-deftest lispy-join ()
  (should (string= (lispy-with "(foo) |(bar)" "+")
                   "|(foo bar)"))
  (should (string= (lispy-with "(foo)| (bar)" "+")
                   "(foo bar)|")))

(ert-deftest lispy-split ()
  (should (string= (lispy-with "(foo |bar)" (lispy-split))
                   "(foo)\n|(bar)")))

(ert-deftest lispy-move-up ()
  (should (string= (lispy-with "((a) (b) |(c))" "w")
                   "((a) |(c) (b))"))
  (should (string= (lispy-with "((a) (b) |(c))" "ww")
                   "(|(c) (a) (b))"))
  (should (string= (lispy-with "((a) (b) |(c))" "www")
                   "(|(c) (a) (b))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "w")
                   "((a) (c)| (b))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "ww")
                   "((c)| (a) (b))"))
  (should (string= (lispy-with "((a) (b) (c)|)" "www")
                   "((c)| (a) (b))"))
  (should (string= (lispy-with "((a) |(b) (c))" "mjw")
                   "(~(b) (c)| (a))"))
  (should (string= (lispy-with "(foo b|ar)"
                               (lispy-mark-symbol)
                               (lispy-move-up))
                   "(~bar| foo)")))

(ert-deftest lispy-move-down ()
  (should (string= (lispy-with "(|(a) (b) (c))" "s")
                   "((b) |(a) (c))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "ss")
                   "((b) (c) |(a))"))
  (should (string= (lispy-with "(|(a) (b) (c))" "sss")
                   "((b) (c) |(a))"))
  (should (string= (lispy-with "((a)| (b) (c))" "s")
                   "((b) (a)| (c))"))
  (should (string= (lispy-with "((a)| (b) (c))" "ss")
                   "((b) (c) (a)|)"))
  (should (string= (lispy-with "((a)| (b) (c))" "sss")
                   "((b) (c) (a)|)"))
  (should (string= (lispy-with "(|(a) (b) (c))" "m]s")
                   "((c) ~(a) (b)|)"))
  (should (string= (lispy-with "(f|oo bar)"
                               (lispy-mark-symbol)
                               (lispy-move-down))
                   "(bar ~foo|)")))

(ert-deftest lispy-clone ()
  (should (string= (lispy-with "(foo)|" "c")
                   "(foo)\n(foo)|"))
  (should (string= (lispy-with "|(foo)" "c")
                   "|(foo)\n(foo)")))

(ert-deftest lispy-oneline ()
  (should (string= (lispy-with "|(defun abc (x)\n  \"def.\"\n  (+ x\n     x\n     x))" "O")
                   "|(defun abc (x) \"def.\" (+ x x x))"))
  (should (string= (lispy-with "(defun abc (x)\n  \"def.\"\n  (+ x\n     x\n     x))|" "O")
                   "(defun abc (x) \"def.\" (+ x x x))|"))
  (should (string= (lispy-with "|(defun foo ()\n  ;; comment\n  (bar)\n  (baz))" "O")
                   ";; comment\n|(defun foo () (bar) (baz))")))

(ert-deftest lispy-multiline ()
  (should (string= (lispy-with "|(defun abc (x) \"def.\" (+ x x x) (foo) (bar))" "M")
                   "|(defun abc (x)\n  \"def.\" (+ x x x)\n  (foo)\n  (bar))"))
  (should (string= (lispy-with "|(defun abc(x)\"def.\"(+ x x x)(foo)(bar))" "M")
                   "|(defun abc(x)\n  \"def.\"(+ x x x)\n  (foo)\n  (bar))")))

(ert-deftest lispy-comment ()
  (should (string= (lispy-with "(defun foo ()\n  (let (a b c)\n    (cond ((s1)\n           |(s2)\n           (s3)))))" ";")
                   "(defun foo ()\n  (let (a b c)\n    (cond ((s1)\n           ;; (s2)\n           |(s3)))))"))
  (should (string= (lispy-with "(defun foo ()\n  (let (a b c)\n    (cond ((s1)\n           |(s2)\n           (s3)))))" ";;")
                   "(defun foo ()\n  (let (a b c)\n    (cond |((s1)\n           ;; (s2)\n           ;; (s3)\n           ))))"))
  (should (string-match "(defun foo ()\n  (let (a b c)\n    |(cond ;; ((s1)\n          ;;  ;; (s2)\n          ;;  ;; (s3)\n          ;;  )\n     *)))"
                        (lispy-with "(defun foo ()\n  (let (a b c)\n    (cond ((s1)\n           |(s2)\n           (s3)))))" ";;;")))
  (should (string-match "(defun foo ()\n  |(let (a b c)\n    ;; (cond ;; ((s1)\n    ;;       ;;  ;; (s2)\n    ;;       ;;  ;; (s3)\n    ;;       ;;  )\n    ;;   *)\n   *))"
                        (lispy-with "(defun foo ()\n  (let (a b c)\n    (cond ((s1)\n           |(s2)\n           (s3)))))" ";;;;")))
  (should (string-match "|(defun foo ()\n  ;; (let (a b c)\n  ;;   ;; (cond ;; ((s1)\n  ;;   ;;       ;;  ;; (s2)\n  ;;   ;;       ;;  ;; (s3)\n  ;;   ;;       ;;  )\n  ;;   ;;  *)\n  ;;   )\n  )"
                        (lispy-with "(defun foo ()\n  (let (a b c)\n    (cond ((s1)\n           |(s2)\n           (s3)))))" ";;;;;")))
  (should (string-match "|;; (defun foo ()\n;;   ;; (let (a b c)\n;;   ;;   ;; (cond ;; ((s1)\n;;   ;;   ;;       ;;  ;; (s2)\n;;   ;;   ;;       ;;  ;; (s3)\n;;   ;;   ;;       ;;  )\n;;   ;;   ;;  *)\n;;   ;;   )\n;;   )"
                        (lispy-with "(defun foo ()\n  (let (a b c)\n    (cond ((s1)\n           |(s2)\n           (s3)))))" ";;;;;;")))
  (should (string= (lispy-with ";; line| 1\n;; line 2\n (a b c)\n ;; line 3" (lispy-comment 2))
                   "line| 1\nline 2\n (a b c)\n ;; line 3"))
  (should (string= (lispy-with ";; line 1\n;; line 2|\n (a b c)\n ;; line 3" (lispy-comment 2))
                   "line 1\nline 2|\n (a b c)\n ;; line 3"))
  (should (string= (lispy-with "(|\"foo\"\n (bar)\n baz)" ";")
                   "(;; \"foo\"\n |(bar)\n baz)")))

(ert-deftest lispy-move-end-of-line ()
  (should (string= (lispy-with "(foo (bar #\\x \"|baz \\\\ quux\") zot)" "\C-e")
                   "(foo (bar #\\x \"baz \\\\ quux\") zot)|"))
  (should (string= (lispy-with "(foo (bar #\\x \"|baz \\\\ quux\") zot)" "\C-e\C-e")
                   "(foo (bar #\\x \"baz \\\\ quux\"|) zot)"))
  (should (string= (lispy-with "\"fo|o\nbar\" baz" "\C-e\C-e")
                   "\"foo\nbar\"| baz"))
  (should (string= (lispy-with "\"foo|\nbar\" baz" "\C-e")
                   "\"foo\nbar\"| baz")))

(ert-deftest lispy-string-oneline ()
  (should (string= (lispy-with "\"foo\nb|ar\n\"" (lispy-string-oneline))
                   "\"foo\\nbar\\n\"|")))

(ert-deftest lispy-stringify ()
  (should (string= (lispy-with "(a\n b\n (foo)\n c)|" "S")
                   "|\"(a\n b\n (foo)\n c)\""))
  (should (string= (lispy-with "(progn |(1 2 3))" "S")
                   "|(progn \"(1 2 3)\")"))
  (should (string= (lispy-with "(progn |(1 2 3))" "SS")
                   "|\"(progn \\\"(1 2 3)\\\")\""))
  (should (string= (lispy-with "(foo |(bar #\\x \"baz \\\\ quux\") zot)" "S")
                   "|(foo \"(bar #\\\\x \\\"baz \\\\\\\\ quux\\\")\" zot)")))

(ert-deftest lispy-eval ()
  (should (string= (lispy-with-value "(+ 2 2)|" (lispy-eval)) "4")))

(ert-deftest lispy-eval-and-insert ()
  (should (string= (lispy-with "(+ 2 2)|" "E")
                   "(+ 2 2)4|")))

(ert-deftest lispy-quotes ()
  (should (string= (lispy-with "(frob grovel |full lexical)" "\"")
                   "(frob grovel \"|\" full lexical)"))
  (should (string= (lispy-with "(foo \"bar |baz\" quux)" "\"")
                   "(foo \"bar \\\"|\\\"baz\" quux)"))
  (should (string= (lispy-with "\"(fo|o)\"" (lispy-quotes 1))
                   "(foo)|")))

(ert-deftest lispy-normalize ()
  (should (string= (lispy-with "|(foo (bar)baz)" "N")
                   "|(foo (bar) baz)"))
  (should (string= (lispy-with "(foo (bar)baz)|" "N")
                   "(foo (bar) baz)|")))

(ert-deftest lispy--normalize ()
  (should (string= (lispy-with "|(bar\n  foo )" (lispy--normalize 0))
                   "|(bar\n  foo)"))
  (should (string= (lispy-with "|(foo \")\")" (lispy--normalize 0))
                   "|(foo \")\")")))

(ert-deftest lispy--remove-gaps ()
  (should (string= (lispy-with "((a) |(c))" (lispy--remove-gaps))
                   "((a) |(c))")))

(ert-deftest clojure-thread-macro ()
  ;; changes indentation
  (require 'cider)
  (should (string= (lispy-with "|(map sqr (filter odd? [1 2 3 4 5]))" "2(->>]<]<]wwlM")
                   "(->> [1 2 3 4 5]\n  (map sqr)\n  (filter odd?))|")))

(ert-deftest lispy-mark ()
  (should (string= (lispy-with "|;; abc\n;; def\n;; ghi" (lispy-mark))
                   "~;; abc\n;; def\n;; ghi|"))
  (should (string= (lispy-with ";; a|bc\n;; def\n;; ghi" (lispy-mark))
                   "~;; abc\n;; def\n;; ghi|"))
  (should (string= (lispy-with ";; abc\n|;; def\n;; ghi" (lispy-mark))
                   "~;; abc\n;; def\n;; ghi|"))
  (should (string= (lispy-with ";; abc\n;; def\n;; ghi|" (lispy-mark))
                   "~;; abc\n;; def\n;; ghi|")))

(ert-deftest lispy-to-lambda ()
  (should (string= (lispy-with "|(defun foo (x y)\n  (bar))" (lispy-to-lambda))
                   "|(lambda (x y)\n  (bar))"))
  (should (string= (lispy-with "(defun foo (x y)\n  |(bar))" (lispy-to-lambda))
                   "|(lambda (x y)\n  (bar))"))
  (should (string= (lispy-with "(defun foo (x y)\n  (bar))|" (lispy-to-lambda))
                   "|(lambda (x y)\n  (bar))")))

(provide 'lispy-test)

;;; Local Variables:
;;; outline-regexp: ";; ———"
;;; End:

;;; lispy.el ends here
