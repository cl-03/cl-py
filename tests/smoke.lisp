#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
        (require :sb-bsd-sockets)
        (require :sb-posix))

(defpackage #:cl-py-tests
  (:use #:cl)
  (:import-from #:cl-py
                #:adapter-id
                #:adapter-metadata
                #:delete-registry-snapshot
                #:delete-registry-snapshots
                #:prune-registry-snapshots
                #:emit-json
                #:fetch-json
                #:fetch-text
                #:find-adapter
                #:format-iso-timestamp
                #:diff-registry-snapshots
                #:diff-registry-snapshot-reports
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
                #:report-registry-snapshot
                #:run-bounded-task-batch
                #:save-registry-snapshot
                #:slugify-text
                #:summarize-registry-snapshot
                #:validate-jsonschema-instance)
  (:export #:run-tests))

(in-package #:cl-py-tests)

(defvar *failures* 0)

(defun %json-object-entry (value key)
        (cdr (assoc key (cdr value) :test #'string=)))

#+sbcl
(defun %call-with-environment-variable (name value thunk)
        (let ((previous (sb-posix:getenv name)))
                (unwind-protect
                                (progn
                                        (sb-posix:setenv name value 1)
                                        (funcall thunk))
                        (if previous
                                        (sb-posix:setenv name previous 1)
                                        (sb-posix:unsetenv name)))))

#-sbcl
(defun %call-with-environment-variable (name value thunk)
        (declare (ignore name value))
        (funcall thunk))

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

(defun %rewrite-snapshot-created-at (directory snapshot-id created-at)
        (let* ((path (%snapshot-path-for-test directory snapshot-id))
                                 (snapshot (load-registry-snapshot snapshot-id :directory directory))
                                 (entry (assoc "created-at" (cdr snapshot) :test #'string=)))
                (setf (cdr entry) created-at)
                (with-open-file (stream path
                                                                                                                :direction :output
                                                                                                                :if-exists :supersede
                                                                                                                :if-does-not-exist :create)
                        (write-string (emit-json snapshot) stream)
                        (terpri stream))))

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

(defun %native-store-lifecycle-test ()
  (%with-temporary-store-directory
   (lambda (directory)
     (save-registry-snapshot :directory directory :snapshot-id "snapshot-001")
     (save-registry-snapshot :directory directory :snapshot-id "snapshot-002")
     (save-registry-snapshot :directory directory :snapshot-id "snapshot-003")
                 (%rewrite-snapshot-created-at directory "snapshot-001" "2026-03-29T10:00:00Z")
                 (%rewrite-snapshot-created-at directory "snapshot-002" "2026-03-30T10:00:00Z")
                 (%rewrite-snapshot-created-at directory "snapshot-003" "2026-03-31T10:00:00Z")
                 (handler-case
                                 (delete-registry-snapshot "snapshot-002" :directory directory)
                         (cl-py:adapter-error ()
         (%check t "native store delete requires explicit confirmation"))
       (:no-error (&rest values)
         (declare (ignore values))
         (%check nil "native store delete requires explicit confirmation")))
     (handler-case
         (prune-registry-snapshots 1 :directory directory)
                         (cl-py:adapter-error ()
         (%check t "native store prune requires explicit confirmation"))
       (:no-error (&rest values)
         (declare (ignore values))
         (%check nil "native store prune requires explicit confirmation")))
     (let* ((dry-run-deleted (delete-registry-snapshot "snapshot-002" :directory directory :dry-run t))
             (created-before-dry-run-deleted (delete-registry-snapshots nil :directory directory :created-before "2026-03-31T00:00:00Z" :dry-run t))
             (created-window-dry-run-deleted (delete-registry-snapshots nil :directory directory :created-after "2026-03-29T12:00:00Z" :created-before "2026-03-31T00:00:00Z" :dry-run t))
             (prefix-dry-run-deleted (delete-registry-snapshots nil :directory directory :prefixes '("snapshot-00") :dry-run t))
            (bulk-dry-run-deleted (delete-registry-snapshots '("snapshot-001" "snapshot-003") :directory directory :dry-run t))
            (after-dry-run-delete (list-registry-snapshots :directory directory))
            (deleted (delete-registry-snapshot "snapshot-002" :directory directory :force t))
            (bulk-deleted (delete-registry-snapshots '("snapshot-001" "snapshot-003") :directory directory :force t))
            (after-delete (list-registry-snapshots :directory directory))
            (dry-run-delete-matched (%json-object-entry dry-run-deleted "matched"))
            (created-before-dry-run-delete-matched (%json-object-entry created-before-dry-run-deleted "matched"))
            (created-window-dry-run-delete-matched (%json-object-entry created-window-dry-run-deleted "matched"))
            (prefix-dry-run-delete-matched (%json-object-entry prefix-dry-run-deleted "matched"))
            (bulk-dry-run-delete-matched (%json-object-entry bulk-dry-run-deleted "matched"))
            (dry-run-delete-audit (%json-object-entry dry-run-deleted "audit"))
            (created-before-dry-run-delete-audit (%json-object-entry created-before-dry-run-deleted "audit"))
             (created-window-dry-run-delete-audit (%json-object-entry created-window-dry-run-deleted "audit"))
             (prefix-dry-run-delete-audit (%json-object-entry prefix-dry-run-deleted "audit"))
            (bulk-dry-run-delete-audit (%json-object-entry bulk-dry-run-deleted "audit"))
            (delete-audit (%json-object-entry deleted "audit"))
            (bulk-delete-audit (%json-object-entry bulk-deleted "audit"))
            (created-before-dry-run-snapshot-ids (%json-object-entry created-before-dry-run-deleted "snapshot-ids"))
             (created-window-dry-run-snapshot-ids (%json-object-entry created-window-dry-run-deleted "snapshot-ids"))
             (prefix-dry-run-snapshot-ids (%json-object-entry prefix-dry-run-deleted "snapshot-ids"))
            (bulk-dry-run-snapshot-ids (%json-object-entry bulk-dry-run-deleted "snapshot-ids"))
            (bulk-deleted-snapshot-ids (%json-object-entry bulk-deleted "snapshot-ids")))
       (%check (eq :true (%json-object-entry dry-run-deleted "dry-run"))
               "native store delete dry-run reports preview mode")
       (%check (string= "delete-registry" (%json-object-entry dry-run-delete-audit "operation"))
               "native store delete audit reports the lifecycle operation")
       (%check (string= "dry-run" (%json-object-entry dry-run-delete-audit "mode"))
               "native store delete audit reports preview mode")
       (%check (search "T" (%json-object-entry dry-run-delete-audit "executed-at"))
               "native store delete audit includes an execution timestamp")
       (%check (and (vectorp (%json-object-entry dry-run-delete-matched "explicit-snapshot-ids"))
                    (= 1 (%json-object-entry dry-run-delete-matched "explicit-count"))
                    (= 0 (%json-object-entry dry-run-delete-matched "prefix-count"))
                    (= 0 (%json-object-entry dry-run-delete-matched "created-window-count")))
               "native store delete reports explicit selector matches")
       (%check (= 3 (%json-object-entry dry-run-deleted "before-count"))
               "native store delete dry-run reports the pre-delete snapshot count")
       (%check (= 3 (%json-object-entry dry-run-deleted "after-count"))
               "native store delete dry-run preserves the current snapshot count")
       (%check (= 2 (%json-object-entry dry-run-deleted "would-after-count"))
               "native store delete dry-run reports the projected snapshot count")
       (%check (eq :false (%json-object-entry dry-run-deleted "deleted"))
               "native store delete dry-run does not report actual deletion")
       (%check (equal '("snapshot-003" "snapshot-002" "snapshot-001") after-dry-run-delete)
               "native store delete dry-run leaves snapshots on disk")
       (%check (and (vectorp created-before-dry-run-snapshot-ids)
                    (= 2 (length created-before-dry-run-snapshot-ids))
                    (string= "snapshot-001" (aref created-before-dry-run-snapshot-ids 0))
                    (string= "snapshot-002" (aref created-before-dry-run-snapshot-ids 1)))
               "native store created-before delete dry-run expands older snapshot ids")
       (%check (string= "dry-run" (%json-object-entry created-before-dry-run-delete-audit "mode"))
               "native store created-before delete audit reports preview mode")
       (%check (and (vectorp (%json-object-entry created-before-dry-run-delete-matched "created-window-snapshot-ids"))
                    (= 0 (%json-object-entry created-before-dry-run-delete-matched "explicit-count"))
                    (= 0 (%json-object-entry created-before-dry-run-delete-matched "prefix-count"))
                    (= 2 (%json-object-entry created-before-dry-run-delete-matched "created-window-count")))
               "native store created-before delete reports time-window selector matches")
       (%check (and (vectorp created-window-dry-run-snapshot-ids)
                    (= 1 (length created-window-dry-run-snapshot-ids))
                    (string= "snapshot-002" (aref created-window-dry-run-snapshot-ids 0)))
               "native store created window delete dry-run narrows snapshots by both bounds")
       (%check (string= "dry-run" (%json-object-entry created-window-dry-run-delete-audit "mode"))
               "native store created window delete audit reports preview mode")
       (%check (and (vectorp (%json-object-entry created-window-dry-run-delete-matched "created-window-snapshot-ids"))
                    (= 1 (%json-object-entry created-window-dry-run-delete-matched "created-window-count")))
               "native store created window delete reports narrowed time-window matches")
       (%check (and (vectorp prefix-dry-run-snapshot-ids)
                    (= 3 (length prefix-dry-run-snapshot-ids))
                    (string= "snapshot-001" (aref prefix-dry-run-snapshot-ids 0))
                    (string= "snapshot-002" (aref prefix-dry-run-snapshot-ids 1))
                    (string= "snapshot-003" (aref prefix-dry-run-snapshot-ids 2)))
               "native store prefix delete dry-run expands matching snapshot ids")
       (%check (string= "dry-run" (%json-object-entry prefix-dry-run-delete-audit "mode"))
               "native store prefix delete audit reports preview mode")
       (%check (and (vectorp (%json-object-entry prefix-dry-run-delete-matched "prefix-snapshot-ids"))
                    (= 0 (%json-object-entry prefix-dry-run-delete-matched "explicit-count"))
                    (= 3 (%json-object-entry prefix-dry-run-delete-matched "prefix-count"))
                    (= 0 (%json-object-entry prefix-dry-run-delete-matched "created-window-count")))
               "native store prefix delete reports prefix selector matches")
       (%check (and (vectorp bulk-dry-run-snapshot-ids)
                    (= 2 (length bulk-dry-run-snapshot-ids))
                    (string= "snapshot-001" (aref bulk-dry-run-snapshot-ids 0))
                    (string= "snapshot-003" (aref bulk-dry-run-snapshot-ids 1)))
               "native store bulk delete dry-run returns all requested snapshot ids")
       (%check (string= "dry-run" (%json-object-entry bulk-dry-run-delete-audit "mode"))
               "native store bulk delete audit reports preview mode")
       (%check (and (vectorp (%json-object-entry bulk-dry-run-delete-matched "explicit-snapshot-ids"))
                    (= 2 (%json-object-entry bulk-dry-run-delete-matched "explicit-count"))
                    (= 0 (%json-object-entry bulk-dry-run-delete-matched "prefix-count"))
                    (= 0 (%json-object-entry bulk-dry-run-delete-matched "created-window-count")))
               "native store bulk delete reports explicit selector matches")
       (%check (= 3 (%json-object-entry bulk-dry-run-deleted "before-count"))
               "native store bulk delete dry-run reports the pre-delete snapshot count")
       (%check (= 1 (%json-object-entry bulk-dry-run-deleted "would-after-count"))
               "native store bulk delete dry-run reports the projected snapshot count")
       (%check (eq :true (%json-object-entry deleted "forced"))
               "native store delete force reports explicit confirmation")
       (%check (string= "force" (%json-object-entry delete-audit "mode"))
               "native store delete audit reports force mode")
       (%check (= 2 (%json-object-entry deleted "after-count"))
               "native store delete force reports the current snapshot count after deletion")
       (%check (eq :true (%json-object-entry deleted "deleted"))
               "native store can delete a registry snapshot")
       (%check (and (vectorp bulk-deleted-snapshot-ids)
                    (= 2 (length bulk-deleted-snapshot-ids))
                    (string= "snapshot-001" (aref bulk-deleted-snapshot-ids 0))
                    (string= "snapshot-003" (aref bulk-deleted-snapshot-ids 1)))
               "native store bulk delete force reports deleted snapshot ids")
       (%check (string= "force" (%json-object-entry bulk-delete-audit "mode"))
               "native store bulk delete audit reports force mode")
       (%check (= 0 (%json-object-entry bulk-deleted "after-count"))
               "native store bulk delete force reports the current snapshot count after deletion")
       (%check (equal '() after-delete)
               "native store removes deleted snapshots from the listing"))
       (save-registry-snapshot :directory directory :snapshot-id "snapshot-001")
       (save-registry-snapshot :directory directory :snapshot-id "snapshot-002")
       (save-registry-snapshot :directory directory :snapshot-id "snapshot-003")
       (let* ((dry-run-pruned (prune-registry-snapshots 1 :directory directory :dry-run t))
              (after-dry-run-prune (list-registry-snapshots :directory directory))
              (pruned (prune-registry-snapshots 1 :directory directory :force t))
              (after-prune (list-registry-snapshots :directory directory))
              (dry-run-prune-audit (%json-object-entry dry-run-pruned "audit"))
              (prune-audit (%json-object-entry pruned "audit"))
              (dry-run-deleted-ids (%json-object-entry dry-run-pruned "deleted-snapshot-ids"))
              (deleted-ids (%json-object-entry pruned "deleted-snapshot-ids"))
              (kept-ids (%json-object-entry pruned "kept-snapshot-ids")))
       (%check (eq :true (%json-object-entry dry-run-pruned "dry-run"))
               "native store prune dry-run reports preview mode")
       (%check (string= "prune-registry" (%json-object-entry dry-run-prune-audit "operation"))
               "native store prune audit reports the lifecycle operation")
       (%check (string= "dry-run" (%json-object-entry dry-run-prune-audit "mode"))
               "native store prune audit reports preview mode")
       (%check (= 3 (%json-object-entry dry-run-pruned "before-count"))
               "native store prune dry-run reports the pre-prune snapshot count")
       (%check (= 3 (%json-object-entry dry-run-pruned "after-count"))
               "native store prune dry-run preserves the current snapshot count")
       (%check (= 1 (%json-object-entry dry-run-pruned "would-after-count"))
               "native store prune dry-run reports the projected snapshot count")
       (%check (and (vectorp dry-run-deleted-ids)
                    (= 2 (length dry-run-deleted-ids))
                    (string= "snapshot-002" (aref dry-run-deleted-ids 0))
                    (string= "snapshot-001" (aref dry-run-deleted-ids 1)))
               "native store prune dry-run previews deleted snapshot ids")
       (%check (equal '("snapshot-003" "snapshot-002" "snapshot-001") after-dry-run-prune)
               "native store prune dry-run leaves snapshots on disk")
       (%check (eq :true (%json-object-entry pruned "forced"))
               "native store prune force reports explicit confirmation")
       (%check (string= "force" (%json-object-entry prune-audit "mode"))
               "native store prune audit reports force mode")
       (%check (= 1 (%json-object-entry pruned "after-count"))
               "native store prune force reports the current snapshot count after pruning")
       (%check (= 1 (%json-object-entry pruned "keep-count"))
               "native store prune reports the requested keep count")
       (%check (= 1 (%json-object-entry pruned "kept-count"))
               "native store prune reports the number of kept snapshots")
       (%check (= 2 (%json-object-entry pruned "deleted-count"))
               "native store prune reports the number of deleted snapshots")
       (%check (and (vectorp kept-ids)
                    (= 1 (length kept-ids))
                    (string= "snapshot-003" (aref kept-ids 0)))
               "native store prune keeps the most recent snapshots")
          (%check (and (vectorp deleted-ids)
                                (= 2 (length deleted-ids))
                                (string= "snapshot-002" (aref deleted-ids 0))
                                (string= "snapshot-001" (aref deleted-ids 1)))
               "native store prune reports deleted snapshot ids")
       (%check (equal '("snapshot-003") after-prune)
               "native store prune removes older snapshots from disk")))))

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
           (let* ((all-adapters (coerce (cdr (assoc "adapters" entries :test #'string=)) 'list))
                        (nightly-adapters (remove-if (lambda (adapter)
                                                                (member (%json-object-entry adapter "id")
                                                                          '("jsonschema" "slugify")
                                                                          :test #'string=))
                                                            all-adapters)))
         (write-string
          (emit-json
           (list :object
                 (cons "snapshot-id" "nightly")
                 (cons "created-at" (cdr (assoc "created-at" entries :test #'string=)))
                     (cons "adapter-count" (length nightly-adapters))
                     (cons "adapters" (coerce nightly-adapters 'vector))))
          stream)
           )
         (terpri stream))
       (let* ((latest (latest-registry-snapshot-id :directory directory))
              (summary (summarize-registry-snapshot "baseline" :directory directory))
              (diff (diff-registry-snapshots "baseline" "nightly" :directory directory))
              (history (registry-adapter-history "jsonschema" :directory directory))
              (report (report-registry-snapshot "baseline" :directory directory))
              (sorted-report (report-registry-snapshot "baseline"
                                                      :directory directory
                                                      :sort "count-desc"))
              (group-sorted-report (report-registry-snapshot "baseline"
                                                             :directory directory
                                                             :sort "name"
                                                             :license-sort "count-desc"
                                                             :capability-sort "count-asc"))
              (limited-report (report-registry-snapshot "baseline"
                                                       :directory directory
                                                       :sort "count-desc"
                                                       :limit 2))
              (offset-report (report-registry-snapshot "baseline"
                                                      :directory directory
                                                      :sort "count-desc"
                                                      :offset 1
                                                      :limit 2))
              (group-paged-report (report-registry-snapshot "baseline"
                                                            :directory directory
                                                            :sort "count-desc"
                                                            :license-limit 1
                                                            :capability-offset 1
                                                            :capability-limit 2))
              (filtered-report (report-registry-snapshot "baseline"
                                                         :directory directory
                                                         :capability "slugify-text"))
              (license-only-report (report-registry-snapshot "baseline"
                                                             :directory directory
                                                             :group "license"))
              (excluded-report (report-registry-snapshot "baseline"
                                                         :directory directory
                                                         :exclude-capability "metadata"))
              (multi-filtered-report (report-registry-snapshot "baseline"
                                                               :directory directory
                                                               :capabilities '("slugify-text" "validate-instance")))
              (report-diff (diff-registry-snapshot-reports "baseline"
                                                           "nightly"
                                                           :directory directory))
              (sorted-report-diff (diff-registry-snapshot-reports "baseline"
                                                                  "nightly"
                                                                  :directory directory
                                                                  :sort "delta-asc"))
              (group-sorted-report-diff (diff-registry-snapshot-reports "baseline"
                                                                    "nightly"
                                                                    :directory directory
                                                                    :sort "delta-asc"
                                                                    :license-sort "delta-desc"
                                                                    :capability-sort "name"))
              (abs-sorted-report-diff (diff-registry-snapshot-reports "baseline"
                                                                      "nightly"
                                                                      :directory directory
                                                                      :sort "abs-delta-desc"))
              (offset-report-diff (diff-registry-snapshot-reports "baseline"
                                                                  "nightly"
                                                                  :directory directory
                                                                  :sort "abs-delta-desc"
                                                                  :offset 1
                                                                  :limit 1))
              (group-paged-report-diff (diff-registry-snapshot-reports "baseline"
                                                                     "nightly"
                                                                     :directory directory
                                                                     :license-limit 1
                                                                     :capability-limit 2))
              (limited-report-diff (diff-registry-snapshot-reports "baseline"
                                                                   "nightly"
                                                                   :directory directory
                                                                   :sort "delta-asc"
                                                                   :limit 1))
              (filtered-report-diff (diff-registry-snapshot-reports "baseline"
                                                                    "nightly"
                                                                    :directory directory
                                                                    :capability "validate-instance"))
              (license-only-report-diff (diff-registry-snapshot-reports "baseline"
                                                                       "nightly"
                                                                       :directory directory
                                                                       :group "license"))
              (excluded-report-diff (diff-registry-snapshot-reports "baseline"
                                                                    "nightly"
                                                                    :directory directory
                                                                    :exclude-license "MIT"))
              (multi-filtered-report-diff (diff-registry-snapshot-reports "baseline"
                                                                         "nightly"
                                                                         :directory directory
                                                                         :capabilities '("slugify-text" "validate-instance")))
              (summary-entries (cdr summary))
              (diff-entries (cdr diff))
              (report-entries (cdr report))
              (sorted-report-entries (cdr sorted-report))
              (limited-report-entries (cdr limited-report))
              (offset-report-entries (cdr offset-report))
              (filtered-report-entries (cdr filtered-report))
              (excluded-report-entries (cdr excluded-report))
              (multi-filtered-report-entries (cdr multi-filtered-report))
              (filtered-filters (%json-object-entry filtered-report "filters"))
              (license-only-report-licenses (%json-object-entry license-only-report "license-counts"))
              (excluded-filters (%json-object-entry excluded-report "filters"))
              (multi-filtered-filters (%json-object-entry multi-filtered-report "filters"))
              (filtered-capabilities (%json-object-entry filtered-report "capability-counts"))
              (excluded-capabilities (%json-object-entry excluded-report "capability-counts"))
              (report-diff-capabilities (%json-object-entry report-diff "capability-count-diff"))
              (sorted-report-capabilities (%json-object-entry sorted-report "capability-counts"))
              (group-sorted-report-licenses (%json-object-entry group-sorted-report "license-counts"))
              (group-sorted-report-capabilities (%json-object-entry group-sorted-report "capability-counts"))
              (limited-report-capabilities (%json-object-entry limited-report "capability-counts"))
              (limited-report-license-page (%json-object-entry limited-report "license-counts-page"))
              (limited-report-capability-page (%json-object-entry limited-report "capability-counts-page"))
              (offset-report-capabilities (%json-object-entry offset-report "capability-counts"))
              (group-paged-report-licenses (%json-object-entry group-paged-report "license-counts"))
              (group-paged-report-capabilities (%json-object-entry group-paged-report "capability-counts"))
              (group-paged-report-license-page (%json-object-entry group-paged-report "license-counts-page"))
              (group-paged-report-capability-page (%json-object-entry group-paged-report "capability-counts-page"))
              (offset-report-capability-page (%json-object-entry offset-report "capability-counts-page"))
              (sorted-report-diff-capabilities (%json-object-entry sorted-report-diff "capability-count-diff"))
              (group-sorted-report-diff-entries (cdr group-sorted-report-diff))
              (abs-sorted-report-diff-capabilities (%json-object-entry abs-sorted-report-diff "capability-count-diff"))
              (offset-report-diff-capabilities (%json-object-entry offset-report-diff "capability-count-diff"))
              (offset-report-diff-capability-page (%json-object-entry offset-report-diff "capability-count-diff-page"))
              (group-paged-report-diff-licenses (%json-object-entry group-paged-report-diff "license-count-diff"))
              (group-paged-report-diff-capabilities (%json-object-entry group-paged-report-diff "capability-count-diff"))
              (group-paged-report-diff-license-page (%json-object-entry group-paged-report-diff "license-count-diff-page"))
              (group-paged-report-diff-capability-page (%json-object-entry group-paged-report-diff "capability-count-diff-page"))
              (limited-report-diff-capabilities (%json-object-entry limited-report-diff "capability-count-diff"))
              (limited-report-diff-capability-page (%json-object-entry limited-report-diff "capability-count-diff-page"))
              (filtered-report-diff-capabilities (%json-object-entry filtered-report-diff "capability-count-diff"))
              (license-only-report-diff-licenses (%json-object-entry license-only-report-diff "license-count-diff"))
              (filtered-report-diff-filters (%json-object-entry filtered-report-diff "filters"))
              (excluded-report-diff-filters (%json-object-entry excluded-report-diff "filters"))
              (excluded-report-diff-licenses (%json-object-entry excluded-report-diff "license-count-diff"))
              (multi-filtered-report-diff-capabilities (%json-object-entry multi-filtered-report-diff "capability-count-diff"))
              (multi-filtered-report-diff-filters (%json-object-entry multi-filtered-report-diff "filters")))
         (%check (string= "nightly" latest)
                 "native store queries return the latest snapshot id")
         (%check (vectorp (cdr (assoc "adapter-ids" summary-entries :test #'string=)))
                 "native store summary returns adapter id vectors")
         (%check (= 2 (length (cdr (assoc "removed-adapter-ids" diff-entries :test #'string=))))
                 "native store diff reports removed adapters between snapshots")
         (%check (= 2 (length history))
                 "native store adapter history returns one record per snapshot")
         (%check (eq :false (cdr (assoc "present" (cdr (aref history 1)) :test #'string=)))
                 "native store adapter history records adapter absence in later snapshots")
         (%check (vectorp (cdr (assoc "license-counts" report-entries :test #'string=)))
                 "native store report returns license aggregates")
         (%check (vectorp (cdr (assoc "capability-counts" report-entries :test #'string=)))
                 "native store report returns capability aggregates")
         (%check (string= "count-desc" (%json-object-entry sorted-report "sort"))
                 "native store report returns the applied sort mode")
         (%check (string= "metadata" (%json-object-entry (aref sorted-report-capabilities 0) "name"))
                 "native store report can sort aggregate rows by descending count")
         (%check (string= "count-desc" (%json-object-entry group-sorted-report "license-sort"))
                 "native store report returns the effective per-license sort mode")
         (%check (string= "count-asc" (%json-object-entry group-sorted-report "capability-sort"))
                 "native store report returns the effective per-capability sort mode")
         (%check (string= "MIT" (%json-object-entry (aref group-sorted-report-licenses 0) "name"))
                 "native store report can override license sorting independently")
         (%check (string= "normalize-version" (%json-object-entry (aref group-sorted-report-capabilities 0) "name"))
                 "native store report can override capability sorting independently")
         (%check (= 2 (%json-object-entry limited-report "limit"))
                 "native store report returns the applied row limit")
         (%check (= 2 (length limited-report-capabilities))
                 "native store report can limit aggregate rows after sorting")
         (%check (= 2 (%json-object-entry limited-report-license-page "returned-count"))
                 "native store report includes pagination metadata for license aggregates")
         (%check (= (%json-object-entry limited-report-capability-page "total-count")
                    (+ (%json-object-entry limited-report-capability-page "returned-count")
                       (%json-object-entry limited-report-capability-page "remaining-count")))
                 "native store report pagination metadata tracks total and remaining rows")
         (%check (= 1 (%json-object-entry offset-report "offset"))
                 "native store report returns the applied row offset")
         (%check (string= "version" (%json-object-entry (aref offset-report-capabilities 0) "name"))
                 "native store report can offset rows after sorting")
         (%check (= (%json-object-entry offset-report-capability-page "total-count")
                    (+ (%json-object-entry offset-report-capability-page "offset")
                       (%json-object-entry offset-report-capability-page "returned-count")
                       (%json-object-entry offset-report-capability-page "remaining-count")))
                 "native store report pagination metadata accounts for offsets")
         (%check (= 1 (%json-object-entry group-paged-report-license-page "limit"))
                 "native store report can override license row limits independently")
         (%check (= 1 (length group-paged-report-licenses))
                 "native store report applies the license-specific row limit")
         (%check (= 1 (%json-object-entry group-paged-report-capability-page "offset"))
                 "native store report can override capability row offsets independently")
         (%check (= 2 (%json-object-entry group-paged-report-capability-page "limit"))
                 "native store report can override capability row limits independently")
         (%check (= 2 (length group-paged-report-capabilities))
                 "native store report applies capability-specific paging")
         (%check (= 1 (%json-object-entry filtered-report "adapter-count"))
                 "native store report can filter adapters by capability")
         (%check (string= "license" (%json-object-entry license-only-report "group"))
                 "native store report can select a single aggregate group")
         (%check (and (vectorp license-only-report-licenses)
                      (null (%json-object-entry license-only-report "capability-counts")))
                 "native store report omits non-selected aggregate groups")
         (%check (= 0 (%json-object-entry excluded-report "adapter-count"))
                 "native store report can exclude adapters by capability")
         (%check (= 2 (%json-object-entry multi-filtered-report "adapter-count"))
                 "native store report can filter adapters by multiple capabilities")
         (%check (= 4 (%json-object-entry filtered-report "total-adapter-count"))
                 "native store report preserves total snapshot size when filtered")
         (%check (string= "slugify-text" (%json-object-entry filtered-filters "capability"))
                 "native store report includes applied capability filters")
         (%check (= 2 (length (%json-object-entry multi-filtered-filters "capabilities")))
                 "native store report exposes multiple capability filters")
         (%check (string= "metadata" (%json-object-entry excluded-filters "exclude-capability"))
                 "native store report includes applied exclusion filters")
         (%check (and (vectorp filtered-capabilities)
                      (find "slugify-text" filtered-capabilities
                            :test #'string=
                            :key (lambda (entry)
                                   (%json-object-entry entry "name"))))
                 "native store report narrows aggregate rows after filtering")
         (%check (= 0 (length excluded-capabilities))
                 "native store report removes excluded capability aggregates")
         (%check (and (vectorp report-diff-capabilities)
                      (find "validate-instance" report-diff-capabilities
                            :test #'string=
                            :key (lambda (entry)
                                   (%json-object-entry entry "name"))))
                 "native store report diff captures changed capability counts")
         (%check (string= "delta-asc" (%json-object-entry sorted-report-diff "sort"))
                 "native store report diff returns the applied sort mode")
         (%check (string= "metadata" (%json-object-entry (aref sorted-report-diff-capabilities 0) "name"))
                 "native store report diff can sort rows by ascending delta")
         (%check (string= "delta-desc" (%json-object-entry group-sorted-report-diff "license-sort"))
                 "native store report diff returns the effective per-license diff sort mode")
         (%check (string= "name" (%json-object-entry group-sorted-report-diff "capability-sort"))
                 "native store report diff returns the effective per-capability diff sort mode")
         (%check (string= "abs-delta-desc" (%json-object-entry abs-sorted-report-diff "sort"))
                 "native store report diff returns the applied abs-delta sort mode")
         (%check (string= "metadata" (%json-object-entry (aref abs-sorted-report-diff-capabilities 0) "name"))
                 "native store report diff can sort rows by descending absolute delta")
         (%check (= 1 (%json-object-entry offset-report-diff "offset"))
                 "native store report diff returns the applied row offset")
         (%check (string= "version" (%json-object-entry (aref offset-report-diff-capabilities 0) "name"))
                 "native store report diff can offset rows after sorting")
         (%check (= 1 (%json-object-entry limited-report-diff "limit"))
                 "native store report diff returns the applied row limit")
         (%check (= 1 (length limited-report-diff-capabilities))
                 "native store report diff can limit rows after sorting")
         (%check (= 1 (%json-object-entry limited-report-diff-capability-page "returned-count"))
                 "native store report diff includes pagination metadata for diff rows")
         (%check (= 1 (%json-object-entry group-paged-report-diff-license-page "limit"))
                 "native store report diff can override license diff limits independently")
         (%check (= 1 (length group-paged-report-diff-licenses))
                 "native store report diff applies the license-specific diff limit")
         (%check (= 2 (%json-object-entry group-paged-report-diff-capability-page "limit"))
                 "native store report diff can override capability diff limits independently")
         (%check (= 2 (length group-paged-report-diff-capabilities))
                 "native store report diff applies capability-specific diff limits")
         (%check (string= "license" (%json-object-entry license-only-report-diff "group"))
                 "native store report diff can select a single aggregate group")
         (%check (and (vectorp license-only-report-diff-licenses)
                      (null (%json-object-entry license-only-report-diff "capability-count-diff")))
                 "native store report diff omits non-selected diff groups")
         (%check (and (vectorp filtered-report-diff-capabilities)
                         (find "validate-instance" filtered-report-diff-capabilities
                                :test #'string=
                                :key (lambda (entry)
                                        (%json-object-entry entry "name")))
                         (= -1 (%json-object-entry
                                 (find "validate-instance" filtered-report-diff-capabilities
                                        :test #'string=
                                        :key (lambda (entry)
                                                (%json-object-entry entry "name")))
                                 "delta")))
                 "native store report diff applies capability filters before diffing")
         (%check (string= "validate-instance"
                          (%json-object-entry filtered-report-diff-filters "capability"))
                 "native store report diff returns applied filters")
         (%check (string= "MIT" (%json-object-entry excluded-report-diff-filters "exclude-license"))
                 "native store report diff returns exclusion filters")
         (%check (= 0 (length excluded-report-diff-licenses))
                 "native store report diff excludes matching license rows before diffing")
         (%check (and (vectorp multi-filtered-report-diff-capabilities)
                      (find "validate-instance" multi-filtered-report-diff-capabilities
                            :test #'string=
                            :key (lambda (entry)
                                   (%json-object-entry entry "name"))))
                 "native store report diff supports multiple capability filters")
         (%check (= 2 (length (%json-object-entry multi-filtered-report-diff-filters "capabilities")))
                 "native store report diff exposes multiple capability filters")
         (%check (= (%json-object-entry offset-report-diff-capability-page "total-count")
                    (+ (%json-object-entry offset-report-diff-capability-page "offset")
                       (%json-object-entry offset-report-diff-capability-page "returned-count")
                       (%json-object-entry offset-report-diff-capability-page "remaining-count")))
                 "native store report diff pagination metadata accounts for offsets")
         (let* ((report-output-path (merge-pathnames "exports/report.json" directory))
                (diff-output-path (merge-pathnames "exports/diff.json" directory))
                (report-command-output
                  (%capture-output
                   (lambda ()
                                                                                 (%call-with-environment-variable
                                                                                        "CL_PY_STORE_DIR"
                                                                                        (namestring directory)
                                                                                        (lambda ()
                                                                                                (cl-py.internal:dispatch-top-level-command
                                                                                                 (list "store" "report-registry" "baseline" "--output" (namestring report-output-path))))))))
                (diff-command-output
                  (%capture-output
                   (lambda ()
                                                                                 (%call-with-environment-variable
                                                                                        "CL_PY_STORE_DIR"
                                                                                        (namestring directory)
                                                                                        (lambda ()
                                                                                                (cl-py.internal:dispatch-top-level-command
                                                                                                 (list "store" "diff-report-registry" "baseline" "nightly" "--output" (namestring diff-output-path))))))))
                (report-output-json (uiop:read-file-string report-output-path))
                (diff-output-json (uiop:read-file-string diff-output-path)))
           (%check (probe-file report-output-path)
                   "native store report can export output to a file")
           (%check (search (namestring report-output-path) report-command-output)
                   "native store report prints the export path when writing a file")
           (%check (search "\"snapshot-id\":\"baseline\"" report-output-json)
                   "native store report export writes the JSON payload")
           (%check (probe-file diff-output-path)
                   "native store report diff can export output to a file")
           (%check (search (namestring diff-output-path) diff-command-output)
                   "native store report diff prints the export path when writing a file")
           (%check (search "\"left-snapshot-id\":\"baseline\"" diff-output-json)
                   "native store report diff export writes the JSON payload")))))))

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
                        (%check t "cli dispatch rejects unknown top-level commands")))
        (handler-case
                        (progn
                                (cl-py.internal:dispatch-top-level-command '("store" "delete-registry"))
                                (%check nil "cli store delete requires explicit confirmation flags"))
                (cl-py:cli-usage-error ()
                        (%check t "cli store delete requires explicit confirmation flags")))
        (handler-case
                        (progn
                                (cl-py.internal:dispatch-top-level-command '("store" "prune-registry" "5"))
                                (%check nil "cli store prune requires explicit confirmation flags"))
                (cl-py:cli-usage-error ()
                        (%check t "cli store prune requires explicit confirmation flags"))))

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
    (%check (search "delete-registry" output)
            "store help prints snapshot delete subcommands")
    (%check (search "prune-registry" output)
            "store help prints snapshot prune subcommands")
    (%check (search "--dry-run" output)
            "store help prints lifecycle dry-run flags")
    (%check (search "--force" output)
            "store help prints lifecycle force flags")
    (%check (search "--prefix" output)
            "store help prints lifecycle prefix selectors")
    (%check (search "--created-before" output)
            "store help prints lifecycle time selectors")
    (%check (search "--created-after" output)
            "store help prints lifecycle lower-bound time selectors")
    (%check (search "diff-registry" output)
            "store help prints query subcommands")
    (%check (search "adapter-history" output)
            "store help prints adapter history queries")
    (%check (search "report-registry" output)
            "store help prints aggregate report queries")
    (%check (search "diff-report-registry" output)
            "store help prints aggregate report diff queries")
    (%check (search "--capability" output)
            "store help prints report capability filters")
    (%check (search "--license" output)
            "store help prints report license filters")
    (%check (search "--exclude-license" output)
            "store help prints report exclusion filters")
    (%check (search "--exclude-capability" output)
            "store help prints report capability exclusions")
    (%check (search "--group" output)
            "store help prints aggregate group filters")
    (%check (search "--sort" output)
            "store help prints report sort flags")
    (%check (search "--license-sort" output)
            "store help prints per-license sort flags")
    (%check (search "--capability-sort" output)
            "store help prints per-capability sort flags")
    (%check (search "--offset" output)
            "store help prints report row offsets")
    (%check (search "--limit" output)
            "store help prints report row limits")
    (%check (search "--license-limit" output)
            "store help prints per-license row limits")
    (%check (search "--capability-offset" output)
            "store help prints per-capability row offsets")
    (%check (search "--output" output)
            "store help prints report output paths")
    (%check (search "--capability slugify-text --capability validate-instance" output)
            "store help demonstrates repeated capability filters")
    (%check (search "--group capability" output)
            "store help demonstrates selecting a single aggregate group")
    (%check (search "--license-sort count-desc --capability-sort count-asc" output)
            "store help demonstrates per-group sort overrides")
    (%check (search "--license-limit 1 --capability-offset 1" output)
            "store help demonstrates per-group paging overrides")
    (%check (search "store delete-registry nightly --force" output)
            "store help demonstrates deleting a snapshot")
    (%check (search "store delete-registry nightly snapshot-20260330 --dry-run" output)
            "store help demonstrates deleting multiple snapshots")
    (%check (search "store delete-registry --prefix nightly- --dry-run" output)
            "store help demonstrates deleting snapshots by prefix")
    (%check (search "store delete-registry --created-before 2026-03-30T00:00:00Z --dry-run" output)
            "store help demonstrates deleting snapshots by creation time")
    (%check (search "store delete-registry --created-after 2026-03-29T12:00:00Z --created-before 2026-03-31T00:00:00Z --dry-run" output)
            "store help demonstrates deleting snapshots by creation window")
    (%check (search "store delete-registry nightly --dry-run" output)
            "store help demonstrates dry-run deletion")
    (%check (search "store prune-registry 5 --force" output)
            "store help demonstrates pruning snapshots")
    (%check (search "store prune-registry 5 --dry-run" output)
            "store help demonstrates dry-run pruning")
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
        (%native-store-lifecycle-test)
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