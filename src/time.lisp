(in-package #:cl-py)

(defun %time-error (message &rest args)
  (error 'adapter-error :message (apply #'format nil message args)))

(defun %parse-fixed-integer (text start end label)
  (let ((token (subseq text start end)))
    (unless (every #'digit-char-p token)
      (%time-error "Invalid ~A component in timestamp: ~A" label token))
    (parse-integer token)))

(defun %leap-year-p (year)
  (or (and (zerop (mod year 400)))
      (and (zerop (mod year 4))
           (not (zerop (mod year 100))))))

(defun %days-in-month (year month)
  (case month
    ((1 3 5 7 8 10 12) 31)
    ((4 6 9 11) 30)
    (2 (if (%leap-year-p year) 29 28))
    (otherwise 0)))

(defun %validate-timestamp-components (year month day hour minute second offset-minutes)
  (unless (<= 1 month 12)
    (%time-error "Month out of range in timestamp: ~D" month))
  (unless (<= 1 day (%days-in-month year month))
    (%time-error "Day out of range in timestamp: ~D" day))
  (unless (<= 0 hour 23)
    (%time-error "Hour out of range in timestamp: ~D" hour))
  (unless (<= 0 minute 59)
    (%time-error "Minute out of range in timestamp: ~D" minute))
  (unless (<= 0 second 59)
    (%time-error "Second out of range in timestamp: ~D" second))
  (unless (<= -1439 offset-minutes 1439)
    (%time-error "Offset out of range in timestamp: ~D" offset-minutes))
  (handler-case
      (encode-universal-time second minute hour day month year (- (/ offset-minutes 60)))
    (error ()
      (%time-error "Invalid timestamp components"))))

(defun %parse-iso-offset (text)
  (cond
    ((string= text "Z")
     0)
    ((= (length text) 6)
     (let* ((sign-char (char text 0))
            (sign (case sign-char
                    (#\+ 1)
                    (#\- -1)
                    (otherwise (%time-error "Invalid timestamp offset sign: ~A" sign-char))))
            (hours (%parse-fixed-integer text 1 3 "offset hour"))
            (minutes (%parse-fixed-integer text 4 6 "offset minute")))
       (unless (char= (char text 3) #\:)
         (%time-error "Expected ':' in timestamp offset"))
       (unless (<= hours 23)
         (%time-error "Offset hour out of range: ~D" hours))
       (unless (<= minutes 59)
         (%time-error "Offset minute out of range: ~D" minutes))
       (* sign (+ (* hours 60) minutes))))
    (t
     (%time-error "Unsupported timestamp offset: ~A" text))))

(defun parse-iso-timestamp (text)
  (unless (or (= (length text) 20)
              (= (length text) 25))
    (%time-error "Unsupported ISO-8601 timestamp length: ~D" (length text)))
  (unless (and (char= (char text 4) #\-)
               (char= (char text 7) #\-)
               (char= (char text 10) #\T)
               (char= (char text 13) #\:)
               (char= (char text 16) #\:))
    (%time-error "Timestamp must match YYYY-MM-DDTHH:MM:SSZ or YYYY-MM-DDTHH:MM:SS+HH:MM"))
  (let* ((year (%parse-fixed-integer text 0 4 "year"))
         (month (%parse-fixed-integer text 5 7 "month"))
         (day (%parse-fixed-integer text 8 10 "day"))
         (hour (%parse-fixed-integer text 11 13 "hour"))
         (minute (%parse-fixed-integer text 14 16 "minute"))
         (second (%parse-fixed-integer text 17 19 "second"))
         (offset-minutes (%parse-iso-offset (subseq text 19))))
    (%validate-timestamp-components year month day hour minute second offset-minutes)
    (list :timestamp
          :year year
          :month month
          :day day
          :hour hour
          :minute minute
          :second second
          :offset-minutes offset-minutes)))

(defun %timestamp-field (timestamp field)
  (unless (and (listp timestamp)
               (eq (first timestamp) :timestamp))
    (%time-error "Expected timestamp value produced by parse-iso-timestamp"))
  (or (getf (rest timestamp) field)
      (if (member field '(:year :month :day :hour :minute :second :offset-minutes))
          (%time-error "Timestamp is missing field ~A" field)
          nil)))

(defun %format-offset (offset-minutes)
  (let* ((sign (if (minusp offset-minutes) #\- #\+))
         (absolute-offset (abs offset-minutes))
         (hours (floor absolute-offset 60))
         (minutes (mod absolute-offset 60)))
    (format nil "~C~2,'0D:~2,'0D" sign hours minutes)))

(defun format-iso-timestamp (timestamp)
  (let ((year (%timestamp-field timestamp :year))
        (month (%timestamp-field timestamp :month))
        (day (%timestamp-field timestamp :day))
        (hour (%timestamp-field timestamp :hour))
        (minute (%timestamp-field timestamp :minute))
        (second (%timestamp-field timestamp :second))
        (offset-minutes (%timestamp-field timestamp :offset-minutes)))
    (%validate-timestamp-components year month day hour minute second offset-minutes)
    (format nil
            "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0D~A"
            year month day hour minute second (%format-offset offset-minutes))))

(defun %time-cli-parse-iso (text)
  (prin1 (parse-iso-timestamp (%resolve-json-cli-input text)))
  (terpri))

(defun %time-cli-format-iso (text)
  (let* ((*read-eval* nil)
         (resolved-text (%resolve-json-cli-input text)))
    (multiple-value-bind (timestamp position)
        (read-from-string resolved-text)
      (let ((remainder (string-trim '(#\Space #\Tab #\Newline #\Return)
                                    (subseq resolved-text position))))
        (unless (string= remainder "")
          (%time-error "Unexpected trailing Lisp input while reading timestamp form"))
        (format t "~A~%" (format-iso-timestamp timestamp))))))

(defun %print-time-usage ()
  (format t "  time parse-iso <timestamp|@path|->~%")
  (format t "  time format-iso <timestamp-form|@path|->~%"))

(defun %print-time-help ()
  (%print-time-usage)
  (format t "~%Input Forms:~%")
  (format t "  Inline ISO-8601 text or Lisp timestamp forms~%")
  (format t "  @path to read from a file~%")
  (format t "  - to read from standard input~%")
  (format t "~%Examples:~%")
  (format t "  sbcl --script scripts/dev-cli.lisp time parse-iso 2026-03-29T10:20:30Z~%")
  (format t "  sbcl --script scripts/dev-cli.lisp time format-iso '(:timestamp :year 2026 :month 3 :day 29 :hour 10 :minute 20 :second 30 :offset-minutes 0)'~%")
  (format t "  sbcl --script scripts/dev-cli.lisp time parse-iso @tmp-time.txt~%"))

(defun dispatch-time-command (args)
  (cond
    ((null args)
     (cl-py.internal:signal-cli-usage-error "time requires a subcommand" #'%print-time-usage))
    ((cl-py.internal:help-flag-p (first args))
     (%print-time-usage))
    ((string= (first args) "parse-iso")
     (if (< (length (rest args)) 1)
         (cl-py.internal:signal-cli-usage-error "time parse-iso requires a timestamp value" #'%print-time-usage)
         (%time-cli-parse-iso (second args))))
    ((string= (first args) "format-iso")
     (if (< (length (rest args)) 1)
         (cl-py.internal:signal-cli-usage-error "time format-iso requires a timestamp form" #'%print-time-usage)
         (%time-cli-format-iso (second args))))
    (t
     (cl-py.internal:signal-cli-usage-error
      (format nil "Unknown time subcommand: ~A" (first args))
      #'%print-time-usage))))

(cl-py.internal:register-top-level-cli-command
 "time"
 #'dispatch-time-command
 :usage "time <subcommand>"
 :summary "Native ISO-8601 timestamp parse and format helpers"
 :detail-printer #'%print-time-help)