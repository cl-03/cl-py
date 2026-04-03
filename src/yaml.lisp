(in-package #:cl-py)

(defun %yaml-error (message &rest args)
  (error 'adapter-error :message (apply #'format nil message args)))

(defun %yaml-blank-or-comment-p (line)
  "Return true if line is blank or a comment."
  (let ((trimmed (string-left-trim '(#\Space #\Tab) line)))
    (or (string= trimmed "")
        (char= (char trimmed 0) #\#))))

(defun %get-indentation (line)
  "Return the number of leading spaces in a line."
  (loop for i below (length line)
        for char = (char line i)
        while (char= char #\Space)
        count t))

(defun %strip-comment (line)
  "Strip inline comment from a YAML line."
  (let ((in-quote nil)
        (result (make-string-output-stream)))
    (loop for i below (length line)
          for char = (char line i)
          do (cond
               ((and (char= char #\') (not in-quote))
                (setf in-quote (not in-quote))
                (write-char char result))
               ((and (char= char #\") (not in-quote))
                (setf in-quote (not in-quote))
                (write-char char result))
               ((and (char= char #\#) (not in-quote))
                (return-from %strip-comment (get-output-stream-string result)))
               (t
                (write-char char result)))
          finally (return (get-output-stream-string result)))))

(defun %parse-yaml-scalar (value)
  "Parse a YAML scalar value into a Lisp value."
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) value)))
    (cond
      ((string= trimmed "") nil)
      ((string= trimmed "~") nil)
      ((string= trimmed "null") nil)
      ((string= trimmed "Null") nil)
      ((string= trimmed "NULL") nil)
      ((string= trimmed "true") :true)
      ((string= trimmed "True") :true)
      ((string= trimmed "TRUE") :true)
      ((string= trimmed "false") :false)
      ((string= trimmed "False") :false)
      ((string= trimmed "FALSE") :false)
      ((and (>= (length trimmed) 2)
            (char= (char trimmed 0) #\")
            (char= (char trimmed (1- (length trimmed))) #\"))
       (subseq trimmed 1 (1- (length trimmed))))
      ((and (>= (length trimmed) 2)
            (char= (char trimmed 0) #\')
            (char= (char trimmed (1- (length trimmed))) #\'))
       (subseq trimmed 1 (1- (length trimmed))))
      (t (let ((parsed (parse-integer trimmed :junk-allowed t)))
           (if parsed
               parsed
               trimmed))))))

(defun %split-lines (text)
  "Split text into lines by newline characters."
  (loop with start = 0
        for i below (length text)
        when (char= (char text i) #\Newline)
        collect (subseq text start i) into lines
        and do (setf start (1+ i))
        finally (return (if (< start (length text))
                            (nconc lines (list (subseq text start)))
                            lines))))

(defun %yaml-lines-at-indent (lines start base-indent)
  "Collect consecutive lines at or deeper than base-indent.
Returns (values line-indices next-index)."
  (let ((indices nil))
    (loop for i from start below (length lines)
          for line = (elt lines i)
          until (%yaml-blank-or-comment-p line)
          for indent = (%get-indentation line)
          while (>= indent base-indent)
          do (push i indices)
          finally (return (values (nreverse indices) i)))))

(defun parse-yaml-structure (lines start base-indent)
  "Parse YAML structure starting at given line.
Returns (values result next-line-index)."
  ;; Skip blank/comment lines
  (loop while (and (< start (length lines))
                   (%yaml-blank-or-comment-p (elt lines start)))
        do (incf start))

  (when (>= start (length lines))
    (return-from parse-yaml-structure (values nil start)))

  (let* ((line (elt lines start))
         (indent (%get-indentation line))
         (content (string-trim '(#\Space #\Tab) (%strip-comment line))))

    (when (< indent base-indent)
      (return-from parse-yaml-structure (values nil start)))

    (when (zerop (length content))
      (return-from parse-yaml-structure (values nil (1+ start))))

    (let ((first-char (char content 0)))
      (cond
        ;; Sequence (list)
        ((char= first-char #\-)
         (parse-yaml-sequence lines start indent))

        ;; Mapping (object)
        ((and (find #\: content)
              (not (or (char= first-char #\") (char= first-char #\'))))
         (parse-yaml-mapping lines start indent))

        ;; Scalar value
        (t
         (values (%parse-yaml-scalar content) (1+ start)))))))

(defun parse-yaml-sequence (lines start base-indent)
  "Parse a YAML sequence starting at given line."
  (let ((items nil))
    (loop while (< start (length lines))
          for current-line = (elt lines start)
          for current-indent = (%get-indentation current-line)
          for current-content = (string-trim '(#\Space #\Tab) (%strip-comment current-line))
          do (cond
               ((%yaml-blank-or-comment-p current-line)
                (incf start))
               ((< current-indent base-indent)
                (return))
               ((and (= current-indent base-indent)
                     (char= (char current-content 0) #\-))
                (let ((rest-content (subseq current-content 1)))
                  (if (and (plusp (length rest-content))
                           (not (%yaml-blank-or-comment-p rest-content)))
                      (progn
                        (push (%parse-yaml-scalar rest-content) items)
                        (incf start))
                      (multiple-value-bind (val next-idx)
                          (parse-yaml-structure lines (1+ start) (+ current-indent 2))
                        (push val items)
                        (setf start next-idx)))))
               (t
                (return)))
          finally (return))
    (values (coerce (nreverse items) 'vector) start)))

(defun parse-yaml-mapping (lines start base-indent)
  "Parse a YAML mapping starting at given line."
  (let ((pairs nil))
    (loop while (< start (length lines))
          for current-line = (elt lines start)
          for current-indent = (%get-indentation current-line)
          for current-content = (string-trim '(#\Space #\Tab) (%strip-comment current-line))
          do (cond
               ((%yaml-blank-or-comment-p current-line)
                (incf start))
               ((< current-indent base-indent)
                (return))
               ((= current-indent base-indent)
                (let ((colon-pos (position #\: current-content)))
                  (if (null colon-pos)
                      (progn (incf start) (return))
                      (let* ((key (string-trim '(#\Space #\Tab)
                                               (subseq current-content 0 colon-pos)))
                             (val-part (subseq current-content (1+ colon-pos)))
                             (trimmed-val (string-trim '(#\Space #\Tab) val-part)))
                        (push (cons key nil) pairs)
                        (if (zerop (length trimmed-val))
                            (multiple-value-bind (val next-idx)
                                (parse-yaml-structure lines (1+ start) (+ current-indent 2))
                              (setf (cdr (car pairs)) val)
                              (setf start next-idx))
                            (progn
                              (let ((parsed (%parse-yaml-scalar trimmed-val)))
                                (setf (cdr (car pairs)) parsed)
                                (incf start))))))))
               (t
                (return)))
          finally (return))
    (values (cons :object (nreverse pairs)) start)))

(defun parse-yaml (text)
  "Parse YAML text into a Common Lisp data structure.
Maps are represented as (:object (key1 . value1) (key2 . value2) ...)
Arrays are represented as vectors."
  (let* ((lines (%split-lines (substitute #\Newline #\Return text)))
         (filtered (remove-if #'%yaml-blank-or-comment-p lines)))
    (if (null filtered)
        nil
        (multiple-value-bind (val _) (parse-yaml-structure filtered 0 0)
          (declare (ignore _))
          val))))

(defun %yaml-escape-string (text)
  "Escape a string for YAML output if needed."
  (cond
    ((or (find #\Newline text) (find #\Return text)
         (find #\: text) (find #\# text) (find #\' text) (find #\" text)
         (find #\\ text) (find #\| text) (find #\> text)
         (find #\& text) (find #\* text) (find #\! text)
         (find #\@ text) (find #\` text) (find #\, text)
         (find #\? text)
         (and (plusp (length text))
              (or (char= (char text 0) #\Space) (char= (char text 0) #\Tab)
                  (char= (char text 0) #\-)))
         (string= text "")
         (string= text "true") (string= text "false")
         (string= text "null") (string= text "~"))
     (if (find #\" text)
         (format nil "\"~A\"" (substitute #\' #\" text))
         (format nil "'~A'" text)))
    (t text)))

(defun %emit-yaml-value (value indent)
  "Emit a YAML representation of a Lisp value."
  (let ((indent-str (make-string indent :initial-element #\Space)))
    (cond
      ((member value '(t :true) :test #'eq) "true")
      ((member value '(:false) :test #'eq) "false")
      ((member value '(nil :null) :test #'eq) "null")
      ((stringp value) (%yaml-escape-string value))
      ((numberp value) (princ-to-string value))
      ((vectorp value)
       (if (= (length value) 0)
           "[]"
           (format nil "~%~{~A~^~%~}"
                   (mapcar (lambda (item)
                             (format nil "~A- ~A" indent-str (%emit-yaml-value item (+ indent 2))))
                           (coerce value 'list)))))
      ((and (consp value) (eq (car value) :object))
       (if (null (cdr value))
           "{}"
           (format nil "~%~{~A~^~%~}"
                   (mapcar (lambda (entry)
                             (let ((key (car entry))
                                   (val (%emit-yaml-value (cdr entry) (+ indent 2))))
                               (if (or (find #\Newline val) (string= val "{}") (and (plusp (length val)) (char= (char val 0) #\Newline)))
                                   (format nil "~A~A:~A" indent-str key val)
                                   (format nil "~A~A: ~A" indent-str key val))))
                           (cdr value)))))
      ((listp value)
       (if (null value)
           "[]"
           (format nil "~%~{~A~^~%~}"
                   (mapcar (lambda (item)
                             (format nil "~A- ~A" indent-str (%emit-yaml-value item (+ indent 2))))
                           value))))
      ((consp value)
       ;; Handle improper cons cells (e.g., ("key" . "value") as a single entry)
       (let ((key (car value))
             (val (%emit-yaml-value (cdr value) (+ indent 2))))
         (if (or (find #\Newline val) (string= val "{}") (and (plusp (length val)) (char= (char val 0) #\Newline)))
             (format nil "~%~A~A:~A" indent-str key val)
             (format nil "~%~A~A: ~A" indent-str key val))))
      (t (%yaml-escape-string (princ-to-string value))))))

(defun emit-yaml (value)
  "Emit YAML text from a Common Lisp data structure."
  (let ((result (%emit-yaml-value value 0)))
    (if (or (stringp value) (numberp value)
            (member value '(t :true :false nil :null) :test #'eq))
        result
        (string-trim '(#\Newline #\Return) result))))

(defun normalize-yaml (text)
  "Normalize YAML text by parsing and re-emitting it."
  (emit-yaml (parse-yaml text)))

(defun %yaml-cli-parse (text)
  (let ((input (%resolve-json-cli-input text)))
    (prin1 (parse-yaml input))
    (terpri)))

(defun %yaml-cli-emit (text)
  (let* ((*read-eval* nil)
         (resolved-text (%resolve-json-cli-input text)))
    (multiple-value-bind (value position) (read-from-string resolved-text)
      (let ((remainder (string-trim '(#\Space #\Tab #\Newline #\Return)
                                    (subseq resolved-text position))))
        (unless (string= remainder "")
          (%yaml-error "Unexpected trailing Lisp input while reading form"))
        (format t "~A~%" (emit-yaml value))))))

(defun %yaml-cli-normalize (text)
  (format t "~A~%" (normalize-yaml (%resolve-json-cli-input text))))

(defun %print-yaml-usage ()
  (format t "  yaml parse <yaml|@path|->~%")
  (format t "  yaml emit <lisp-value|@path|->~%")
  (format t "  yaml normalize <yaml|@path|->~%"))

(defun %print-yaml-help ()
  (%print-yaml-usage)
  (format t "~%Input Forms:~%")
  (format t "  Inline YAML or Lisp data~%")
  (format t "  @path to read from a file~%")
  (format t "  - to read from standard input~%")
  (format t "~%Examples:~%")
  (format t "  sbcl --script scripts/dev-cli.lisp yaml parse 'name: cl-py'~%")
  (format t "  sbcl --script scripts/dev-cli.lisp yaml emit '((\"name\" . \"cl-py\"))'~%")
  (format t "  sbcl --script scripts/dev-cli.lisp yaml normalize @config.yaml~%"))

(defun dispatch-yaml-command (args)
  (cond
    ((null args)
     (cl-py.internal:signal-cli-usage-error "yaml requires a subcommand" #'%print-yaml-usage))
    ((cl-py.internal:help-flag-p (first args))
     (%print-yaml-usage))
    ((string= (first args) "parse")
     (if (< (length (rest args)) 1)
         (cl-py.internal:signal-cli-usage-error "yaml parse requires an input value" #'%print-yaml-usage)
         (%yaml-cli-parse (second args))))
    ((string= (first args) "emit")
     (if (< (length (rest args)) 1)
         (cl-py.internal:signal-cli-usage-error "yaml emit requires an input value" #'%print-yaml-usage)
         (%yaml-cli-emit (second args))))
    ((string= (first args) "normalize")
     (if (< (length (rest args)) 1)
         (cl-py.internal:signal-cli-usage-error "yaml normalize requires an input value" #'%print-yaml-usage)
         (%yaml-cli-normalize (second args))))
    (t
     (cl-py.internal:signal-cli-usage-error
      (format nil "Unknown yaml subcommand: ~A" (first args))
      #'%print-yaml-usage))))

(cl-py.internal:register-top-level-cli-command
 "yaml"
 #'dispatch-yaml-command
 :usage "yaml <subcommand>"
 :summary "Native YAML parse, emit, and normalize helpers"
 :detail-printer #'%print-yaml-help)
