#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

(in-package #:cl-py)

(defstruct %uri
  scheme
  host
  port
  path
  query
  fragment)

(defun %uri-error (message &rest args)
  (error 'adapter-error :message (apply #'format nil message args)))

(defun %find-first-index (text characters &key (start 0))
  (loop for index from start below (length text)
        when (find (char text index) characters :test #'char=)
        do (return index)))

(defun %parse-port (text)
  (unless (plusp (length text))
    (%uri-error "Empty port in URI"))
  (unless (every #'digit-char-p text)
    (%uri-error "Invalid port in URI: ~A" text))
  (let ((port (parse-integer text)))
    (unless (<= 1 port 65535)
      (%uri-error "Port out of range in URI: ~D" port))
    port))

(defun %parse-uri (text)
  (when (zerop (length text))
    (%uri-error "URI must not be empty"))
  (when (%find-first-index text '(#\Space #\Tab #\Newline #\Return))
    (%uri-error "URI must not contain whitespace"))
  (let ((scheme-end (position #\: text)))
    (unless scheme-end
      (%uri-error "URI must include a scheme"))
    (let ((scheme (string-downcase (subseq text 0 scheme-end))))
      (unless (member scheme '("http") :test #'string=)
        (%uri-error "Unsupported URI scheme: ~A" scheme))
      (unless (and (>= (length text) (+ scheme-end 3))
                   (string= "//" text :start1 0 :end1 2 :start2 (1+ scheme-end) :end2 (+ scheme-end 3)))
        (%uri-error "URI must include // after scheme"))
      (let* ((authority-start (+ scheme-end 3))
             (path-start (or (%find-first-index text '(#\/ #\? #\#) :start authority-start)
                             (length text)))
             (authority (subseq text authority-start path-start))
             (port-marker (position #\: authority :from-end t))
             (host (if port-marker
                       (subseq authority 0 port-marker)
                       authority))
             (port (if port-marker
                       (%parse-port (subseq authority (1+ port-marker)))
                       80))
             (path-end (or (%find-first-index text '(#\? #\#) :start path-start)
                           (length text)))
             (path (if (< path-start path-end)
                       (subseq text path-start path-end)
                       "/"))
             (query-start (and (< path-end (length text))
                               (char= (char text path-end) #\?)
                               (1+ path-end)))
             (fragment-start (and query-start (%find-first-index text '(#\#) :start query-start)))
             (query (when query-start
                      (subseq text
                              query-start
                              (or fragment-start (length text)))))
             (fragment (when fragment-start
                         (subseq text (1+ fragment-start)))))
        (when (zerop (length authority))
          (%uri-error "URI authority must not be empty"))
        (when (zerop (length host))
          (%uri-error "URI host must not be empty"))
        (unless (char= (char path 0) #\/)
          (%uri-error "URI path must begin with /"))
        (make-%uri :scheme scheme
                   :host (string-downcase host)
                   :port port
                   :path path
                   :query query
                   :fragment fragment)))))

(defun normalize-uri (text)
  (let* ((uri (%parse-uri text))
         (default-port-p (= (%uri-port uri) 80)))
    (with-output-to-string (stream)
      (format stream "~A://~A" (%uri-scheme uri) (%uri-host uri))
      (unless default-port-p
        (format stream ":~D" (%uri-port uri)))
      (write-string (%uri-path uri) stream)
      (when (%uri-query uri)
        (format stream "?~A" (%uri-query uri)))
      (when (%uri-fragment uri)
        (format stream "#~A" (%uri-fragment uri))))))

(defun %http-request-target (uri)
  (if (%uri-query uri)
      (format nil "~A?~A" (%uri-path uri) (%uri-query uri))
      (%uri-path uri)))

(defun %split-http-response (response)
  (let ((separator (or (search (format nil "~C~C~C~C" #\Return #\Newline #\Return #\Newline)
                               response)
                       (search (format nil "~C~C" #\Newline #\Newline)
                               response))))
    (unless separator
      (%uri-error "Malformed HTTP response"))
    (if (search (format nil "~C~C~C~C" #\Return #\Newline #\Return #\Newline) response)
        (values (subseq response 0 separator)
                (subseq response (+ separator 4)))
        (values (subseq response 0 separator)
                (subseq response (+ separator 2))))))

(defun %parse-status-code (header-text)
  (let* ((line-end (or (position #\Newline header-text) (length header-text)))
         (status-line (string-trim '(#\Return #\Newline) (subseq header-text 0 line-end)))
         (first-space (position #\Space status-line))
         (second-space (and first-space (position #\Space status-line :start (1+ first-space)))))
    (unless (and first-space second-space)
      (%uri-error "Malformed HTTP status line: ~A" status-line))
    (%parse-port (subseq status-line (1+ first-space) second-space))))

(defun %read-all-characters (stream)
  (with-output-to-string (output)
    (loop for character = (read-char stream nil nil)
          while character
          do (write-char character output))))

(defun %header-value (headers header-name)
  (let ((prefix (string-downcase (format nil "~A:" header-name))))
    (loop for line in headers
          for trimmed = (string-right-trim '(#\Return) line)
          for lower = (string-downcase trimmed)
          when (and (>= (length lower) (length prefix))
                    (string= prefix lower :start1 0 :end1 (length prefix) :start2 0 :end2 (length prefix)))
          do (return (string-trim '(#\Space #\Tab) (subseq trimmed (length prefix)))))))

(defun %read-http-response (stream)
  (let ((status-line (read-line stream nil nil)))
    (unless status-line
      (%uri-error "Malformed HTTP response"))
    (let ((headers nil))
      (loop for line = (read-line stream nil nil)
            while line
            until (string= (string-right-trim '(#\Return) line) "")
            do (push line headers))
      (let* ((header-lines (nreverse headers))
             (content-length-text (%header-value header-lines "Content-Length"))
             (body (if content-length-text
                       (let* ((length (%parse-port content-length-text))
                              (buffer (make-string length)))
                         (read-sequence buffer stream)
                         buffer)
                       (%read-all-characters stream))))
        (values status-line header-lines body)))))

(defun %http-fetch-text-sbcl (uri)
  (require :sb-bsd-sockets)
  (let* ((socket (make-instance 'sb-bsd-sockets:inet-socket :type :stream :protocol :tcp))
         (host-entry (sb-bsd-sockets:get-host-by-name (%uri-host uri)))
         (address (first (sb-bsd-sockets:host-ent-addresses host-entry)))
         (stream nil))
    (unwind-protect
        (progn
          (sb-bsd-sockets:socket-connect socket address (%uri-port uri))
          (setf stream (sb-bsd-sockets:socket-make-stream socket
                                                          :input t
                                                          :output t
                                                          :element-type 'character
                                                          :external-format :utf-8
                                                          :auto-close t))
            (let ((host-header (if (= (%uri-port uri) 80)
                 (%uri-host uri)
                 (format nil "~A:~D" (%uri-host uri) (%uri-port uri))))
            (crlf (format nil "~C~C" #\Return #\Newline)))
                (write-string
                 (format nil
                   "GET ~A HTTP/1.1~AHost: ~A~AConnection: close~AAccept: application/json, text/plain, */*~AUser-Agent: cl-py/0.1~A~A"
                   (%http-request-target uri)
                   crlf
                   host-header
                   crlf
                   crlf
                   crlf
                   crlf
                   crlf)
                 stream)
            (finish-output stream))
          (multiple-value-bind (status-line headers body)
              (%read-http-response stream)
            (declare (ignore headers))
            (let ((status-code (%parse-status-code status-line)))
              (unless (= status-code 200)
                (%uri-error "HTTP request failed with status ~D" status-code))
              body)))
      (when stream
        (ignore-errors (close stream)))
      (ignore-errors (sb-bsd-sockets:socket-close socket)))))

(defun fetch-text (text)
  (let ((uri (%parse-uri (normalize-uri text))))
    #+sbcl (%http-fetch-text-sbcl uri)
    #-sbcl (%uri-error "fetch-text currently requires SBCL for native socket support")))

(defun fetch-json (text)
  (parse-json (fetch-text text)))

(defun %uri-cli-normalize (text)
  (format t "~A~%" (normalize-uri (%resolve-json-cli-input text))))

(defun %http-cli-fetch-text (text)
  (format t "~A~%" (fetch-text (%resolve-json-cli-input text))))

(defun %http-cli-fetch-json (text)
  (prin1 (fetch-json (%resolve-json-cli-input text)))
  (terpri))

(defun %print-uri-usage ()
  (format t "  uri normalize <uri|@path|->~%"))

(defun %print-uri-help ()
  (%print-uri-usage)
  (format t "~%Input Forms:~%")
  (format t "  Inline URI text~%")
  (format t "  @path to read from a file~%")
  (format t "  - to read from standard input~%")
  (format t "~%Examples:~%")
  (format t "  sbcl --script scripts/dev-cli.lisp uri normalize HTTP://Example.COM:80/path?q=1~%")
  (format t "  sbcl --script scripts/dev-cli.lisp uri normalize @tmp-uri.txt~%"))

(defun %print-http-usage ()
  (format t "  http fetch-text <uri|@path|->~%")
  (format t "  http fetch-json <uri|@path|->~%"))

(defun %print-http-help ()
  (%print-http-usage)
  (format t "~%Input Forms:~%")
  (format t "  Inline URI text~%")
  (format t "  @path to read from a file~%")
  (format t "  - to read from standard input~%")
  (format t "~%Examples:~%")
  (format t "  sbcl --script scripts/dev-cli.lisp http fetch-text http://127.0.0.1:8080/~%")
  (format t "  sbcl --script scripts/dev-cli.lisp http fetch-json http://127.0.0.1:8080/data~%")
  (format t "  sbcl --script scripts/dev-cli.lisp http fetch-text @tmp-uri.txt~%"))

(defun dispatch-uri-command (args)
  (cond
    ((null args)
     (cl-py.internal:signal-cli-usage-error "uri requires a subcommand" #'%print-uri-usage))
    ((cl-py.internal:help-flag-p (first args))
     (%print-uri-usage))
    ((string= (first args) "normalize")
     (if (< (length (rest args)) 1)
         (cl-py.internal:signal-cli-usage-error "uri normalize requires a URI value" #'%print-uri-usage)
         (%uri-cli-normalize (second args))))
    (t
     (cl-py.internal:signal-cli-usage-error
      (format nil "Unknown uri subcommand: ~A" (first args))
      #'%print-uri-usage))))

(defun dispatch-http-command (args)
  (cond
    ((null args)
     (cl-py.internal:signal-cli-usage-error "http requires a subcommand" #'%print-http-usage))
    ((cl-py.internal:help-flag-p (first args))
     (%print-http-usage))
    ((string= (first args) "fetch-text")
     (if (< (length (rest args)) 1)
         (cl-py.internal:signal-cli-usage-error "http fetch-text requires a URI value" #'%print-http-usage)
         (%http-cli-fetch-text (second args))))
    ((string= (first args) "fetch-json")
     (if (< (length (rest args)) 1)
         (cl-py.internal:signal-cli-usage-error "http fetch-json requires a URI value" #'%print-http-usage)
         (%http-cli-fetch-json (second args))))
    (t
     (cl-py.internal:signal-cli-usage-error
      (format nil "Unknown http subcommand: ~A" (first args))
      #'%print-http-usage))))

(cl-py.internal:register-top-level-cli-command
 "uri"
 #'dispatch-uri-command
 :usage "uri <subcommand>"
 :summary "Native URI normalization helpers"
 :detail-printer #'%print-uri-help)

(cl-py.internal:register-top-level-cli-command
 "http"
 #'dispatch-http-command
 :usage "http <subcommand>"
 :summary "Native HTTP text and JSON fetch helpers"
 :detail-printer #'%print-http-help)