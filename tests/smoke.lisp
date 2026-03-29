#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
        (require :sb-bsd-sockets))

(defpackage #:cl-py-tests
  (:use #:cl)
  (:import-from #:cl-py
                #:adapter-id
                #:adapter-metadata
                #:emit-json
                #:fetch-json
                #:fetch-text
                #:find-adapter
                #:format-iso-timestamp
                #:diff-registry-snapshots
                #:load-registry-snapshot
                #:latest-registry-snapshot-id
                #:list-adapters
                #:list-registry-snapshots
                #:normalize-uri
                #:normalize-json
                #:normalize-packaging-version
                #:parse-json
                #:parse-iso-timestamp
                #:parse-dateutil-isodatetime
                #:registry-adapter-history
                #:run-bounded-task-batch
                #:save-registry-snapshot
                #:slugify-text
                #:summarize-registry-snapshot
                #:validate-jsonschema-instance)
  (:export #:run-tests))

(in-package #:cl-py-tests)

(defvar *failures* 0)

(defun %capture-output (thunk)
        (with-output-to-string (stream)
                (let ((*standard-output* stream))
                        (funcall thunk))))

(defun %check (condition description)
  (format t "~:[FAIL~;PASS~] ~A~%" condition description)
  (unless condition
    (incf *failures*)))

(defun %adapter-registry-test ()
  (%check (plusp (length (cl-py:list-adapters)))
          "registry contains at least one adapter")
  (%check (not (null (cl-py:find-adapter "packaging")))
          "packaging adapter is registered")
  (%check (not (null (cl-py:find-adapter "dateutil")))
          "dateutil adapter is registered")
  (%check (not (null (cl-py:find-adapter "slugify")))
          "slugify adapter is registered")
  (%check (not (null (cl-py:find-adapter "jsonschema")))
          "jsonschema adapter is registered"))

(defun %adapter-ids-test ()
  (%check (member "packaging"
                  (mapcar #'cl-py:adapter-id (cl-py:list-adapters))
                  :test #'string=)
          "registry exposes packaging adapter id")
  (%check (member "dateutil"
                  (mapcar #'cl-py:adapter-id (cl-py:list-adapters))
                  :test #'string=)
          "registry exposes dateutil adapter id")
  (%check (member "slugify"
                  (mapcar #'cl-py:adapter-id (cl-py:list-adapters))
                  :test #'string=)
          "registry exposes slugify adapter id")
  (%check (member "jsonschema"
                  (mapcar #'cl-py:adapter-id (cl-py:list-adapters))
                  :test #'string=)
          "registry exposes jsonschema adapter id"))

(defun %packaging-metadata-test ()
  (let ((metadata (cl-py:adapter-metadata "packaging")))
    (%check (string= "packaging" (getf metadata :id))
            "metadata exposes packaging adapter id")
    (%check (string= "1.0" (getf metadata :manifest-version))
            "metadata exposes packaging manifest version")
    (%check (search "github.com/pypa/packaging" (getf metadata :upstream-url))
            "metadata exposes packaging upstream URL")
    (%check (string= "packaging" (getf metadata :python-distribution))
            "metadata exposes packaging distribution name")
    (%check (string= "packaging>=24.0,<26.0" (getf metadata :python-requirement))
            "metadata exposes packaging requirement range")
    (%check (member "normalize-version" (getf metadata :capabilities) :test #'string=)
            "metadata exposes normalize-version capability")))

(defun %dateutil-metadata-test ()
  (let ((metadata (cl-py:adapter-metadata "dateutil")))
    (%check (string= "dateutil" (getf metadata :id))
            "metadata exposes dateutil adapter id")
    (%check (string= "1.0" (getf metadata :manifest-version))
            "metadata exposes dateutil manifest version")
    (%check (search "github.com/dateutil/dateutil" (getf metadata :upstream-url))
            "metadata exposes dateutil upstream URL")
    (%check (string= "python-dateutil" (getf metadata :python-distribution))
            "metadata exposes dateutil distribution name")
    (%check (string= "python-dateutil>=2.9,<3.0" (getf metadata :python-requirement))
            "metadata exposes dateutil requirement range")
    (%check (member "parse-isodatetime" (getf metadata :capabilities) :test #'string=)
            "metadata exposes parse-isodatetime capability")))

(defun %slugify-metadata-test ()
  (let ((metadata (cl-py:adapter-metadata "slugify")))
    (%check (string= "slugify" (getf metadata :id))
            "metadata exposes slugify adapter id")
    (%check (string= "1.0" (getf metadata :manifest-version))
            "metadata exposes slugify manifest version")
    (%check (search "github.com/un33k/python-slugify" (getf metadata :upstream-url))
            "metadata exposes slugify upstream URL")
    (%check (string= "python-slugify" (getf metadata :python-distribution))
            "metadata exposes slugify distribution name")
    (%check (string= "python-slugify>=8.0,<9.0" (getf metadata :python-requirement))
            "metadata exposes slugify requirement range")
    (%check (member "slugify-text" (getf metadata :capabilities) :test #'string=)
            "metadata exposes slugify-text capability")))

(defun %jsonschema-metadata-test ()
  (let ((metadata (cl-py:adapter-metadata "jsonschema")))
    (%check (string= "jsonschema" (getf metadata :id))
            "metadata exposes jsonschema adapter id")
    (%check (string= "1.0" (getf metadata :manifest-version))
            "metadata exposes jsonschema manifest version")
    (%check (search "github.com/python-jsonschema/jsonschema" (getf metadata :upstream-url))
            "metadata exposes jsonschema upstream URL")
    (%check (string= "jsonschema" (getf metadata :python-distribution))
            "metadata exposes jsonschema distribution name")
    (%check (string= "jsonschema>=4.0,<5.0" (getf metadata :python-requirement))
            "metadata exposes jsonschema requirement range")
    (%check (member "validate-instance" (getf metadata :capabilities) :test #'string=)
            "metadata exposes validate-instance capability")))

(defun %native-json-parse-test ()
  (let* ((value (parse-json "{\"name\":\"cl-py\",\"active\":true,\"items\":[1,2,null]}") )
         (entries (cdr value))
         (items (cdr (assoc "items" entries :test #'string=))))
    (%check (and (consp value) (eq :object (car value)))
            "native json parser preserves object identity")
    (%check (string= "cl-py" (cdr (assoc "name" entries :test #'string=)))
            "native json parser reads object string fields")
    (%check (eq :true (cdr (assoc "active" entries :test #'string=)))
            "native json parser preserves boolean values")
    (%check (and (vectorp items)
                 (= 3 (length items))
                 (eql 1 (aref items 0))
                 (eq :null (aref items 2)))
            "native json parser reads nested arrays and null values")))

(defun %native-json-emit-test ()
  (%check (string=
           "{\"active\":true,\"items\":[1,2,null],\"name\":\"cl-py\"}"
           (emit-json '(("name" . "cl-py")
                        ("active" . :true)
                        ("items" . #(1 2 :null)))))
          "native json emitter serializes deterministic canonical objects"))

(defun %native-json-normalize-test ()
  (%check (string=
           "{\"a\":1,\"b\":[true,false,null],\"name\":\"cl-py\"}"
           (normalize-json "{\"name\":\"cl-py\",\"b\":[true,false,null],\"a\":1}"))
          "native json normalization produces canonical key ordering"))

(defun %native-time-parse-test ()
        (let ((timestamp (parse-iso-timestamp "2026-03-29T10:20:30Z")))
                (%check (and (listp timestamp) (eq :timestamp (first timestamp)))
                                                "native time parser preserves timestamp identity")
                (%check (= 2026 (getf (rest timestamp) :year))
                                                "native time parser reads year correctly")
                (%check (= 0 (getf (rest timestamp) :offset-minutes))
                                                "native time parser normalizes UTC offset correctly")))

(defun %native-time-offset-test ()
        (let ((timestamp (parse-iso-timestamp "2026-03-29T10:20:30+05:30")))
                (%check (= 330 (getf (rest timestamp) :offset-minutes))
                                                "native time parser preserves positive offsets")
                (%check (string= "2026-03-29T10:20:30+05:30"
                                                                                 (format-iso-timestamp timestamp))
                                                "native time formatter round-trips offset timestamps")))

(defun %native-time-invalid-test ()
        (handler-case
                        (progn
                                (parse-iso-timestamp "2026-02-30T10:20:30Z")
                                (%check nil "native time parser rejects invalid dates"))
                (cl-py:adapter-error ()
                        (%check t "native time parser rejects invalid dates"))))

(defun %native-uri-normalize-test ()
        (%check (string=
                                         "http://example.com/path?q=1#frag"
                                         (normalize-uri "HTTP://Example.COM:80/path?q=1#frag"))
                                        "native uri normalization lowercases host and removes default port")
        (%check (string=
                                         "http://example.com:8080/"
                                         (normalize-uri "http://Example.com:8080"))
                                        "native uri normalization preserves non-default port and default path"))

#+sbcl
(defun %with-local-http-response (body thunk &key (content-type "text/plain"))
  (let ((listener (make-instance 'sb-bsd-sockets:inet-socket :type :stream :protocol :tcp))
        (server-thread nil))
    (unwind-protect
        (progn
          (sb-bsd-sockets:socket-bind listener #(127 0 0 1) 0)
          (sb-bsd-sockets:socket-listen listener 1)
          (multiple-value-bind (address port)
              (sb-bsd-sockets:socket-name listener)
            (declare (ignore address))
            (setf server-thread
                  (sb-thread:make-thread
                   (lambda ()
                     (let ((client-socket nil)
                           (stream nil))
                       (unwind-protect
                           (progn
                             (setf client-socket (sb-bsd-sockets:socket-accept listener))
                             (setf stream (sb-bsd-sockets:socket-make-stream client-socket
                                                                             :input t
                                                                             :output t
                                                                             :element-type 'character
                                                                             :external-format :utf-8
                                                                             :auto-close t))
                             (loop for line = (read-line stream nil nil)
                                   while line
                                             until (string= (string-right-trim '(#\Return) line) ""))
                             (write-string
                              (let ((crlf (format nil "~C~C" #\Return #\Newline)))
                                (format nil
                                        "HTTP/1.1 200 OK~AContent-Type: ~A~AContent-Length: ~D~AConnection: close~A~A~A"
                                        crlf
                                        content-type
                                        crlf
                                        (length body)
                                        crlf
                                        crlf
                                        crlf
                                        body))
                              stream)
                             (finish-output stream))
                         (when stream
                           (ignore-errors (close stream)))
                         (when client-socket
                           (ignore-errors (sb-bsd-sockets:socket-close client-socket))))))))
            (prog1
                (funcall thunk (format nil "http://127.0.0.1:~D/test" port))
              (when server-thread
                (sb-thread:join-thread server-thread)))))
      (ignore-errors (sb-bsd-sockets:socket-close listener)))))

#-sbcl
(defun %with-local-http-response (body thunk &key (content-type "text/plain"))
        (declare (ignore body thunk content-type))
        (format t "SKIP native HTTP tests require SBCL sockets~%"))

(defun %native-http-fetch-text-test ()
        (%with-local-http-response
         "hello from cl-py"
         (lambda (uri)
                 (%check (string= "hello from cl-py" (fetch-text uri))
                                                 "native http fetch-text reads loopback response body"))))

(defun %native-http-fetch-json-test ()
        (%with-local-http-response
         "{\"service\":\"cl-py\",\"active\":true}"
         (lambda (uri)
                 (let ((value (fetch-json uri)))
                         (%check (and (consp value) (eq :object (first value)))
                                                         "native http fetch-json parses json response bodies")
                         (%check (string= "cl-py" (cdr (assoc "service" (cdr value) :test #'string=)))
                                                         "native http fetch-json preserves object fields")))
         :content-type "application/json"))

(defun %with-temporary-store-directory (thunk)
  (let ((root (merge-pathnames (format nil "cl-py-store-test-~D/" (get-universal-time))
                               (uiop:temporary-directory))))
    (ensure-directories-exist (merge-pathnames "probe.txt" root))
    (unwind-protect
        (funcall thunk root)
      (ignore-errors (uiop:delete-directory-tree root :validate t)))))

(defun %native-store-snapshot-test ()
  (%with-temporary-store-directory
   (lambda (directory)
     (let* ((path (save-registry-snapshot :directory directory :snapshot-id "smoke-registry"))
            (snapshots (list-registry-snapshots :directory directory))
            (snapshot (load-registry-snapshot "smoke-registry" :directory directory))
            (entries (cdr snapshot))
            (adapters (cdr (assoc "adapters" entries :test #'string=))))
       (%check (probe-file path)
               "native store writes registry snapshots to disk")
       (%check (equal '("smoke-registry") snapshots)
               "native store lists registry snapshots deterministically")
       (%check (string= "smoke-registry" (cdr (assoc "snapshot-id" entries :test #'string=)))
               "native store preserves snapshot identifiers")
       (%check (and (vectorp adapters) (plusp (length adapters)))
               "native store loads adapter snapshot payloads")))))

(defun %native-store-query-test ()
  (%with-temporary-store-directory
   (lambda (directory)
     (let* ((baseline-path (save-registry-snapshot :directory directory :snapshot-id "baseline"))
            (nightly-path (save-registry-snapshot :directory directory :snapshot-id "nightly"))
            (baseline (load-registry-snapshot "baseline" :directory directory))
            (entries (cdr baseline)))
       (declare (ignore baseline-path nightly-path))
       (with-open-file (stream (%snapshot-path-for-test directory "nightly")
                               :direction :output
                               :if-exists :supersede
                               :if-does-not-exist :create)
         (write-string
          (emit-json
           (list :object
                 (cons "snapshot-id" "nightly")
                 (cons "created-at" (cdr (assoc "created-at" entries :test #'string=)))
                 (cons "adapter-count" 3)
                 (cons "adapters"
                       (coerce (subseq (coerce (cdr (assoc "adapters" entries :test #'string=)) 'list) 0 3)
                               'vector))))
          stream)
         (terpri stream))
       (let* ((latest (latest-registry-snapshot-id :directory directory))
              (summary (summarize-registry-snapshot "baseline" :directory directory))
              (diff (diff-registry-snapshots "baseline" "nightly" :directory directory))
              (history (registry-adapter-history "slugify" :directory directory))
              (summary-entries (cdr summary))
              (diff-entries (cdr diff)))
         (%check (string= "nightly" latest)
                 "native store queries return the latest snapshot id")
         (%check (vectorp (cdr (assoc "adapter-ids" summary-entries :test #'string=)))
                 "native store summary returns adapter id vectors")
         (%check (= 1 (length (cdr (assoc "removed-adapter-ids" diff-entries :test #'string=))))
                 "native store diff reports removed adapters between snapshots")
         (%check (= 2 (length history))
                 "native store adapter history returns one record per snapshot")
         (%check (eq :false (cdr (assoc "present" (cdr (aref history 1)) :test #'string=)))
                 "native store adapter history records adapter absence in later snapshots"))))))

(defun %snapshot-path-for-test (directory snapshot-id)
  (merge-pathnames (format nil "registry/~A.json" snapshot-id)
                   (uiop:ensure-directory-pathname directory)))

#+sbcl
(defun %native-concurrency-batch-test ()
  (let ((active-count 0)
        (max-active-count 0)
        (mutex (sb-thread:make-mutex :name "cl-py-concurrency-test")))
    (labels ((enter-task ()
               (sb-thread:with-mutex (mutex)
                 (incf active-count)
                 (setf max-active-count (max max-active-count active-count))))
             (leave-task ()
               (sb-thread:with-mutex (mutex)
                 (decf active-count)))
             (make-task (delay value &key fail)
               (lambda ()
                 (enter-task)
                 (unwind-protect
                      (progn
                        (sleep delay)
                        (if fail
                            (error "intentional concurrency failure")
                            value))
                   (leave-task)))))
      (let ((results (run-bounded-task-batch
                      (list (make-task 0.05 "alpha")
                            (make-task 0.02 "bravo")
                            (make-task 0.01 "charlie" :fail t)
                            (make-task 0.03 "delta"))
                      :max-concurrency 2)))
        (%check (= 4 (length results))
                "native concurrency returns one result per task")
        (%check (string= "alpha" (getf (first results) :value))
                "native concurrency preserves ordered success results")
        (%check (string= "error" (getf (third results) :status))
                "native concurrency preserves per-task failures")
        (%check (search "intentional concurrency failure" (getf (third results) :message))
                "native concurrency records failure messages")
        (%check (> max-active-count 1)
                "native concurrency runs more than one task in parallel on SBCL")
        (%check (<= max-active-count 2)
                "native concurrency respects the max-concurrency bound")))))

#-sbcl
(defun %native-concurrency-batch-test ()
  (format t "SKIP native concurrency tests require SBCL threads~%"))

(defun %cli-help-output-test ()
  (let ((output (%capture-output #'cl-py.internal:print-cli-usage)))
    (%check (search "help [command]" output)
            "cli usage includes the help command")
    (%check (search "Run `help <command>`" output)
            "cli usage explains how to get detailed command help")
    (%check (search "json <subcommand>" output)
            "cli usage includes registered native top-level commands")
    (%check (search "jobs <subcommand>" output)
            "cli usage includes the jobs command group")
    (%check (search "store <subcommand>" output)
            "cli usage includes the store command group")
    (%check (search "Adapter Command Groups:" output)
            "cli usage groups adapter commands by adapter")
    (%check (search "packaging" output)
            "cli usage includes adapter group headers")
    (%check (search "List registered adapters with manifest metadata" output)
            "cli usage includes command summaries")))

(defun %cli-usage-error-test ()
  (handler-case
      (progn
        (cl-py.internal:dispatch-top-level-command '("unknown-command"))
        (%check nil "cli dispatch rejects unknown top-level commands"))
    (cl-py:cli-usage-error ()
      (%check t "cli dispatch rejects unknown top-level commands"))))

(defun %cli-command-help-test ()
  (let ((output (%capture-output (lambda ()
                                   (cl-py.internal:print-command-help "json")))))
    (%check (search "Usage: json <subcommand>" output)
            "cli command help prints a usage header for native command groups")
    (%check (search "json parse" output)
            "cli command help prints subcommand usage for native command groups")
    (%check (search "Input Forms:" output)
            "cli command help includes input form guidance")
    (%check (search "Examples:" output)
            "cli command help includes runnable examples")
    (%check (search "Native JSON" output)
            "cli command help includes the registered summary")))

(defun %cli-http-help-test ()
  (let ((output (%capture-output (lambda ()
                                   (cl-py.internal:print-command-help "http")))))
    (%check (search "fetch-text" output)
            "http help prints subcommand usage")
    (%check (search "127.0.0.1:8080" output)
            "http help includes concrete examples")))

(defun %cli-store-help-test ()
  (let ((output (%capture-output (lambda ()
                                   (cl-py.internal:print-command-help "store")))))
    (%check (search "snapshot-registry" output)
            "store help prints store subcommands")
    (%check (search "diff-registry" output)
            "store help prints query subcommands")
    (%check (search "adapter-history" output)
            "store help prints adapter history queries")
    (%check (search "CL_PY_STORE_DIR" output)
            "store help describes store directory override")
    (%check (search "nightly" output)
            "store help includes snapshot examples")))

(defun %cli-jobs-help-test ()
  (let ((output (%capture-output (lambda ()
                                   (cl-py.internal:print-command-help "jobs")))))
    (%check (search "demo-batch" output)
            "jobs help prints jobs subcommands")
    (%check (search "ordered" output)
            "jobs help explains ordered results")
    (%check (search "demo-batch 2" output)
            "jobs help includes concurrency examples")))

(defun %cli-registry-help-test ()
  (let ((output (%capture-output (lambda ()
                                   (cl-py.internal:print-command-help "registry")))))
    (%check (search "Usage: registry" output)
            "registry help prints a usage header")
    (%check (search "Subcommands: none" output)
            "registry help describes that it has no subcommands")))

(defun %cli-adapter-help-test ()
  (let ((output (%capture-output (lambda ()
                                   (cl-py.internal:print-command-help "packaging")))))
    (%check (search "packaging" output)
            "adapter help prints the adapter group header")
    (%check (search "normalize-version <value>" output)
            "adapter help prints registered adapter subcommands")))

(defun %optional-packaging-integration-test ()
  (handler-case
      (%check (string= "1.0rc1" (normalize-packaging-version "1.0rc1"))
              "packaging integration normalizes version strings")
    (error (condition)
      (declare (ignore condition))
      (format t "SKIP packaging integration requires Python + packaging~%"))))

(defun %optional-dateutil-integration-test ()
  (handler-case
      (%check (string= "2026-03-29T10:20:30+00:00"
                       (parse-dateutil-isodatetime "2026-03-29T10:20:30+00:00"))
              "dateutil integration parses ISO datetimes")
    (error (condition)
      (declare (ignore condition))
      (format t "SKIP dateutil integration requires Python + python-dateutil~%"))))

(defun %optional-slugify-integration-test ()
  (handler-case
      (%check (string= "hello-common-lisp"
                       (slugify-text "Hello Common Lisp"))
              "slugify integration creates URL-friendly slugs")
    (error (condition)
      (declare (ignore condition))
      (format t "SKIP slugify integration requires Python + python-slugify~%"))))

(defun %optional-jsonschema-integration-test ()
        (handler-case
                        (%check (string= "valid"
                                                                                         (validate-jsonschema-instance
                                                                                                "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},\"required\":[\"name\"]}"
                                                                                                "{\"name\":\"cl-py\"}"))
                                                        "jsonschema integration validates a JSON instance")
                (error (condition)
                        (declare (ignore condition))
                        (format t "SKIP jsonschema integration requires Python + jsonschema~%"))))

(defun run-tests ()
  (setf *failures* 0)
  (%adapter-registry-test)
  (%adapter-ids-test)
  (%packaging-metadata-test)
  (%dateutil-metadata-test)
  (%slugify-metadata-test)
  (%jsonschema-metadata-test)
        (%native-json-parse-test)
        (%native-json-emit-test)
        (%native-json-normalize-test)
  (%native-time-parse-test)
  (%native-time-offset-test)
  (%native-time-invalid-test)
        (%native-uri-normalize-test)
        (%native-http-fetch-text-test)
        (%native-http-fetch-json-test)
        (%native-store-snapshot-test)
        (%native-store-query-test)
                                (%native-concurrency-batch-test)
        (%cli-help-output-test)
        (%cli-usage-error-test)
        (%cli-command-help-test)
        (%cli-http-help-test)
                                (%cli-jobs-help-test)
        (%cli-store-help-test)
          (%cli-registry-help-test)
          (%cli-adapter-help-test)
  (%optional-packaging-integration-test)
  (%optional-dateutil-integration-test)
  (%optional-slugify-integration-test)
  (%optional-jsonschema-integration-test)
  (when (plusp *failures*)
    (error "Smoke tests failed: ~D" *failures*))
  (format t "All smoke tests completed.~%"))