;;; debug-hooks-test.el --- tests for esup -*- lexical-binding: t -*-

;;; Commentary:

;; Tests for debug-hooks-test.el

;;; Code:
(eval-when-compile
  (require 'cl))

(require 'debug-hooks)

(defvar dht--test-buffer "*debug-hooks-test-log*"
  "Output buffer for debug-hooks log messages.")

(defmacro with-temp-hooks (hooks-alist &rest forms)
  "Defines a new variable for each element in HOOKS-ALIST.
Errors if the variable is already in use.  For each hook created,
also defines the list of hooks functions."
  (declare (indent 1))
  (let ((hooks (eval hooks-alist)))
    `(progn 
       ,@(dht//make-init-all-hooks hooks)
       (unwind-protect
           (progn ,@forms)
         ,@(dht//make-uninit-all-advised-fns hooks)
         ,@(dht//make-uninit-all-hooks hooks)))))

(defun dht//make-init-all-hooks (hooks-alist)
  "Create initialization code for HOOKS-ALIST."
  (cl-loop for (hook-var . hook-def) in hooks-alist
           append (dht//make-init-single-hook hook-var hook-def)))

(defun dht//make-init-single-hook (hook-var hook-def)
  "Create initialization code HOOK-VAR and HOOK-DEF.
If HOOK-DEF is a list of symbols, creates a new function for each
symbol.  If HOOK-DEF is a single symbol, creates a single new
function."
  (append
   (list `(defvar ,hook-var nil))

   (cond
    ((symbolp hook-def)
     `((defun ,hook-def ())
       (setq ,hook-var ',hook-def)))

    ((listp hook-def)
     (cl-loop for fn-symbol in hook-def
              collect `(defun ,fn-symbol ()) into def-list
              collect fn-symbol into setq-list
              finally
              (return
               (append def-list (list `(setq ,hook-var ',setq-list)))))))))

(defun dht//make-uninit-all-hooks (hooks-alist)
  "Create cleanup code for all functions and variables in HOOKS-ALIST."
  (cl-loop for (hook-var . hook-def) in hooks-alist
           append (dht//make-uninit-single-hook hook-var hook-def)))

(defun dht//make-uninit-single-hook (hook-var hook-def)
  "Create cleanup code for HOOK-VAR and HOOK-DEF."
  (append
   (list `(makunbound ',hook-var))

   (cond
    ((symbolp hook-def) `((fmakunbound ',hook-def)))

    ((listp hook-def)
     (cl-loop for fn-symbol in hook-def collect `(fmakunbound ',fn-symbol))))))

(defun dht//make-uninit-all-advised-fns (hooks-alist)
  "Create cleanup code for all advised functions in HOOKS-ALIST."
  (cl-loop for (hook-var . hook-def) in hooks-alist
           append (dht//make-uninit-single-advised-fn hook-def)))

(defun dht//make-uninit-single-advised-fn (hook-def)
  "Create cleanup code for the functions specified by HOOK-DEF."
  (cond
   ((symbolp hook-def) `((dht//unadvise ',hook-def)))

   ((listp hook-def)
    (cl-loop for fn-symbol in hook-def collect `(dht//unadvise ',fn-symbol)))))

(defun dht//unadvise (advised-fn)
  "Remove advice from ADVISED-FN."
  (advice-mapc (lambda (added-func props) (fmakunbound added-func))
               advised-fn))

(defun dht//collect-advice (advised-fn)
  "Return a list of all advisors for ADVISED-FN."
  (let ((advisors nil))
    (advice-mapc (lambda (added-func props) (add-to-list 'advisors added-func))
                 advised-fn)
    advisors))

(defmacro with-debug-hooks-test-buffer (&rest forms)
  "Run FORMS after setting `debug-hooks-buffer' to a test buffer."
  (declare (indent 0))
  (let ((orig-buffer-symbol (make-symbol "orig-buffer")))
    `(let ((,orig-buffer-symbol debug-hooks-buffer))
       (unwind-protect
           (with-current-buffer (get-buffer-create dht--test-buffer)
             ;; (erase-buffer)
             (setq debug-hooks-buffer dht--test-buffer)
             ,@forms))
       (setq debug-hooks-buffer ,orig-buffer-symbol))))

(ert-deftest debug-hooks-advise-single-function__has-one-advice__no-list ()
  (with-temp-hooks '((fake-hook . fake-hook-impl))
    (debug-hooks-advise-single-function 'fake-hook-impl 'fake-hook)
    (should (equal (length (dht//collect-advice 'fake-hook-impl)) 1))))

(ert-deftest debug-hooks-advise-single-function__writes-to-log ()
  (with-temp-hooks '((fake-hook . fake-hook-impl))
    (with-debug-hooks-test-buffer
      (debug-hooks-advise-single-function 'fake-hook-impl 'fake-hook)
      (run-hooks 'fake-hook)
      (should (string-match-p "fake-hook - fake-hook-impl" (buffer-string))))))

(ert-deftest debug-hooks-advise-hooks__has-one-advice__one-function ()
  (with-temp-hooks '((foo-hook . foo-hook-impl))
    (debug-hooks-advise-hooks '(foo-hook))
    (should (equal (length (dht//collect-advice 'foo-hook-impl)) 1))))

(ert-deftest debug-hooks-advise-hooks__has-one-advice__one-hook__many-fns ()
  (with-temp-hooks '((bar-hook . (bar-hook-impl-1 bar-hook-impl-2)))
    (debug-hooks-advise-hooks '(bar-hook))
    (should (equal (length (dht//collect-advice 'bar-hook-impl-1)) 1))
    (should (equal (length (dht//collect-advice 'bar-hook-impl-2)) 1))))

(ert-deftest debug-hooks-advise-hooks__has-one-advice__many-hooks__many-fns ()
  (with-temp-hooks '((qux-hook . (qux-hook-impl-1 qux-hook-impl-2))
                     (bar-hook . (bar-hook-impl-1 bar-hook-impl-2)))
    (debug-hooks-advise-hooks '(qux-hook bar-hook))
    (should (equal (length (dht//collect-advice 'qux-hook-impl-1)) 1))
    (should (equal (length (dht//collect-advice 'qux-hook-impl-2)) 1))
    (should (equal (length (dht//collect-advice 'bar-hook-impl-1)) 1))
    (should (equal (length (dht//collect-advice 'bar-hook-impl-2)) 1))))

(ert-deftest debug-hooks-advise-hooks__has-one-advice__mix ()
  (with-temp-hooks '((bar-hook . (bar-hook-impl-1 bar-hook-impl-2))
                     (foo-hook . foo-hook-impl))
    (debug-hooks-advise-hooks '(bar-hook foo-hook))
    (should (equal (length (dht//collect-advice 'bar-hook-impl-1)) 1))
    (should (equal (length (dht//collect-advice 'bar-hook-impl-2)) 1))
    (should (equal (length (dht//collect-advice 'foo-hook-impl)) 1))))

(ert-deftest debug-hooks-advise-hooks__writes-log__one-function ()
  (with-temp-hooks '((baz-hook . baz-hook-impl))
    (with-debug-hooks-test-buffer
      (debug-hooks-advise-hooks '(baz-hook))
      (run-hooks 'baz-hook)
      (should (string-match-p "baz-hook - baz-hook-impl" (buffer-string))))))

(ert-deftest debug-hooks-advise-hooks__writes-log__many-functions ()
  (with-temp-hooks '((baz-hook . baz-hook-impl)
                     (zee-hook . zee-hook-impl))
    (with-debug-hooks-test-buffer
      (debug-hooks-advise-hooks '(baz-hook zee-hook))
      (run-hooks 'baz-hook)
      (run-hooks 'zee-hook)
      (should (string-match-p "baz-hook - baz-hook-impl" (buffer-string)))
      (should (string-match-p "zee-hook - zee-hook-impl" (buffer-string))))))


(ert-deftest debug-hooks-advise-hooks__writes-log__mix ()
  (with-temp-hooks '((alpha-hook . (alpha-hook-impl-1))
                     (bravo-hook . bravo-hook-impl))
    (with-debug-hooks-test-buffer
      (debug-hooks-advise-hooks '(alpha-hook bravo-hook))
      (run-hooks 'alpha-hook)
      (run-hooks 'bravo-hook)
      (should (string-match-p "alpha-hook - alpha-hook-impl" (buffer-string)))
      (should (string-match-p "bravo-hook - bravo-hook-impl"
                              (buffer-string))))))

(provide 'debug-hooks-test)
;;; debug-hooks-test.el end here
