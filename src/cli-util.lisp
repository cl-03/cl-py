(in-package #:cl-py.internal)

;;; CLI Option Parser Utilities - 简单的参数解析工具

;;; 工具函数

(defun parse-non-negative-integer (value option-name)
  "Parse a string as a non-negative integer."
  (handler-case
      (let ((num (parse-integer value :junk-allowed t)))
        (if (>= num 0)
            num
            (signal-cli-usage-error
             (format nil "~A requires a non-negative integer, got: ~A" option-name value)
             #'print-cli-usage)))
    (error ()
      (signal-cli-usage-error
       (format nil "~A requires a non-negative integer, got: ~A" option-name value)
       #'print-cli-usage))))

(defun validate-sort-mode (value valid-modes option-name)
  "Validate a sort mode against a list of allowed values."
  (if (member value valid-modes :test #'string=)
      value
      (signal-cli-usage-error
       (format nil "~A must be one of: ~{~A~^, ~}. Got: ~A"
               option-name valid-modes value)
       #'print-cli-usage)))

(defun validate-inventory-sort-mode (value context)
  "Validate inventory sort mode."
  (validate-sort-mode value
                      '("created-at-desc" "created-at-asc"
                        "snapshot-id-asc" "snapshot-id-desc"
                        "adapter-count-asc" "adapter-count-desc")
                      (format nil "~A --sort" context)))

(defun parse-keep-count (value context)
  "Parse and validate a keep-count argument."
  (let ((num (parse-non-negative-integer value context)))
    (if (> num 0)
        num
        (signal-cli-usage-error
         (format nil "~A requires a positive integer, got: ~A" context value)
         #'print-cli-usage))))

;;; 简单的选项解析辅助函数

(defun %parse-flag (args flag-name &optional result)
  "Parse a boolean flag like --dry-run. Returns (values new-args result)."
  (if (member flag-name args :test #'string=)
      (values (remove flag-name args :test #'string=) t)
      (values args (or result nil))))

(defun %parse-option (args option-name &optional default)
  "Parse an option with a value like --prefix VALUE. Returns (values new-args value)."
  (let ((pos (position option-name args :test #'string=)))
    (if (and pos (< (1+ pos) (length args)))
        (values (append (subseq args 0 pos) (subseq args (+ pos 2)))
                (elt args (+ pos 1)))
        (values args default))))

(defun %parse-repeatable-option (args option-name)
  "Parse a repeatable option like --prefix A --prefix B. Returns (values new-args values-list)."
  (let ((values nil)
        (remaining args))
    (loop while (position option-name remaining :test #'string=)
          do (let ((pos (position option-name remaining :test #'string=)))
               (when (< (1+ pos) (length remaining))
                 (push (elt remaining (+ pos 1)) values)
                 (setf remaining (append (subseq remaining 0 pos)
                                         (subseq remaining (+ pos 2)))))))
    (values remaining (nreverse values))))

(defun %parse-required-option (args option-name context)
  "Parse a required option, signaling error if missing."
  (multiple-value-bind (new-args value)
      (%parse-option args option-name)
    (if value
        (values new-args value)
        (signal-cli-usage-error
         (format nil "~A requires --~A" context option-name)
         #'print-cli-usage))))
