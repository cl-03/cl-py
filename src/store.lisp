(in-package #:cl-py)

(defun %store-error (message &rest args)
  (error 'adapter-error :message (apply #'format nil message args)))

(defun %store-root (&optional directory)
  (uiop:ensure-directory-pathname
   (or directory
       (let ((override (uiop:getenv "CL_PY_STORE_DIR")))
         (if override
             override
             (merge-pathnames ".cl-py-store/" (cl-py.internal::%repo-root)))))))

(defun %registry-store-directory (&optional directory)
  (let ((path (uiop:ensure-directory-pathname
               (merge-pathnames "registry/" (%store-root directory)))))
    (ensure-directories-exist (merge-pathnames "snapshot.json" path))
    path))

(defun %snapshot-timestamp-string ()
  (multiple-value-bind (second minute hour day month year)
      (decode-universal-time (get-universal-time) 0)
    (format nil "~4,'0D~2,'0D~2,'0DT~2,'0D~2,'0D~2,'0DZ"
            year month day hour minute second)))

(defun %sanitize-snapshot-id (text)
  (coerce (loop for character across text
                collect (if (or (alphanumericp character)
                                (find character "-_." :test #'char=))
                            character
                            #\-))
          'string))

(defun %registry-snapshot-id (&optional requested-id)
  (let ((candidate (or requested-id
                       (format nil "registry-~A" (%snapshot-timestamp-string)))))
    (when (string= candidate "")
      (%store-error "Snapshot id must not be empty"))
    (%sanitize-snapshot-id candidate)))

(defun %registry-snapshot-path (snapshot-id &optional directory)
  (merge-pathnames (format nil "~A.json" snapshot-id)
                   (%registry-store-directory directory)))

(defun %adapter-snapshot-object (adapter)
  (list :object
        (cons "id" (adapter-id adapter))
        (cons "manifest-version" (adapter-manifest-version adapter))
        (cons "name" (adapter-name adapter))
        (cons "upstream-url" (adapter-upstream-url adapter))
        (cons "license" (adapter-license adapter))
        (cons "python-module" (adapter-python-module adapter))
        (cons "python-distribution" (adapter-python-distribution adapter))
        (cons "python-requirement" (adapter-python-requirement adapter))
        (cons "capabilities" (coerce (adapter-capabilities adapter) 'vector))
        (cons "summary" (cl-py.internal:adapter-summary adapter))))

(defun %registry-snapshot-object (snapshot-id)
  (let ((adapters (list-adapters)))
    (list :object
          (cons "snapshot-id" snapshot-id)
          (cons "created-at" (%snapshot-timestamp-string))
          (cons "adapter-count" (length adapters))
          (cons "adapters" (coerce (mapcar #'%adapter-snapshot-object adapters) 'vector)))))

(defun save-registry-snapshot (&key directory snapshot-id)
  (let* ((resolved-id (%registry-snapshot-id snapshot-id))
         (path (%registry-snapshot-path resolved-id directory))
         (payload (emit-json (%registry-snapshot-object resolved-id))))
    (with-open-file (stream path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string payload stream)
      (terpri stream))
    path))

(defun list-registry-snapshots (&key directory)
  (mapcar (lambda (path)
            (pathname-name path))
          (sort (copy-list (uiop:directory-files (%registry-store-directory directory) "*.json"))
                #'string>
                :key #'pathname-name)))

(defun load-registry-snapshot (snapshot-id &key directory)
  (let ((path (%registry-snapshot-path snapshot-id directory)))
    (unless (probe-file path)
      (%store-error "Registry snapshot was not found: ~A" snapshot-id))
    (parse-json (uiop:read-file-string path))))

(defun latest-registry-snapshot-id (&key directory)
  (first (list-registry-snapshots :directory directory)))

(defun %snapshot-entry (snapshot key)
  (cdr (assoc key (cdr snapshot) :test #'string=)))

(defun %snapshot-adapters (snapshot)
  (%snapshot-entry snapshot "adapters"))

(defun %snapshot-adapter-id (adapter-object)
  (cdr (assoc "id" (cdr adapter-object) :test #'string=)))

(defun %snapshot-adapter-table (snapshot)
  (let ((table (make-hash-table :test #'equal)))
    (loop for adapter across (%snapshot-adapters snapshot)
          do (setf (gethash (%snapshot-adapter-id adapter) table) adapter))
    table))

(defun %snapshot-created-at (snapshot)
  (%snapshot-entry snapshot "created-at"))

(defun %find-snapshot-adapter (snapshot adapter-id)
  (find adapter-id (%snapshot-adapters snapshot)
        :key #'%snapshot-adapter-id
        :test #'string=))

(defun summarize-registry-snapshot (snapshot-id &key directory)
  (let* ((snapshot (load-registry-snapshot snapshot-id :directory directory))
         (adapters (%snapshot-adapters snapshot))
         (adapter-ids (sort (loop for adapter across adapters
                                  collect (%snapshot-adapter-id adapter))
                            #'string<)))
    (list :object
          (cons "snapshot-id" (%snapshot-entry snapshot "snapshot-id"))
          (cons "created-at" (%snapshot-entry snapshot "created-at"))
          (cons "adapter-count" (%snapshot-entry snapshot "adapter-count"))
          (cons "adapter-ids" (coerce adapter-ids 'vector)))))

(defun diff-registry-snapshots (left-snapshot-id right-snapshot-id &key directory)
  (let* ((left (load-registry-snapshot left-snapshot-id :directory directory))
         (right (load-registry-snapshot right-snapshot-id :directory directory))
         (left-table (%snapshot-adapter-table left))
         (right-table (%snapshot-adapter-table right))
         (left-ids (sort (loop for key being the hash-keys of left-table collect key) #'string<))
         (right-ids (sort (loop for key being the hash-keys of right-table collect key) #'string<))
         (added (loop for adapter-id in right-ids
                      unless (gethash adapter-id left-table)
                      collect adapter-id))
         (removed (loop for adapter-id in left-ids
                        unless (gethash adapter-id right-table)
                        collect adapter-id))
         (shared (loop for adapter-id in left-ids
                       when (gethash adapter-id right-table)
                       collect adapter-id))
         (changed nil))
    (dolist (adapter-id shared)
      (unless (string=
               (emit-json (gethash adapter-id left-table))
               (emit-json (gethash adapter-id right-table)))
        (push adapter-id changed)))
    (list :object
          (cons "left-snapshot-id" left-snapshot-id)
          (cons "right-snapshot-id" right-snapshot-id)
          (cons "added-adapter-ids" (coerce added 'vector))
          (cons "removed-adapter-ids" (coerce removed 'vector))
          (cons "changed-adapter-ids" (coerce (nreverse changed) 'vector)))))

        (defun registry-adapter-history (adapter-id &key directory)
          (coerce
           (loop for snapshot-id in (reverse (list-registry-snapshots :directory directory))
             for snapshot = (load-registry-snapshot snapshot-id :directory directory)
             for adapter = (%find-snapshot-adapter snapshot adapter-id)
             collect (append
              (list :object
                (cons "snapshot-id" snapshot-id)
                (cons "created-at" (%snapshot-created-at snapshot))
                (cons "present" (if adapter :true :false)))
              (when adapter
                (list (cons "name" (cdr (assoc "name" (cdr adapter) :test #'string=)))
                  (cons "license" (cdr (assoc "license" (cdr adapter) :test #'string=)))
                  (cons "python-requirement" (cdr (assoc "python-requirement" (cdr adapter) :test #'string=)))
                  (cons "summary" (cdr (assoc "summary" (cdr adapter) :test #'string=)))))))
           'vector))

(defun %print-store-usage ()
  (format t "  store snapshot-registry [snapshot-id]~%")
  (format t "  store list-registry~%")
  (format t "  store show-registry <snapshot-id>~%")
  (format t "  store latest-registry~%")
  (format t "  store summarize-registry <snapshot-id>~%")
          (format t "  store diff-registry <left-snapshot-id> <right-snapshot-id>~%")
          (format t "  store adapter-history <adapter-id>~%"))

(defun %print-store-help ()
  (%print-store-usage)
  (format t "~%Storage:~%")
  (format t "  Default root is .cl-py-store under the repository root~%")
  (format t "  Override with CL_PY_STORE_DIR to use another directory~%")
  (format t "~%Examples:~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store snapshot-registry~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store snapshot-registry nightly~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store list-registry~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store show-registry nightly~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store latest-registry~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store summarize-registry nightly~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store diff-registry baseline nightly~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store adapter-history slugify~%"))

(defun %store-cli-snapshot-registry (args)
  (if (> (length args) 1)
      (cl-py.internal:signal-cli-usage-error
       "store snapshot-registry accepts at most one snapshot id"
       #'%print-store-usage)
      (format t "~A~%" (save-registry-snapshot :snapshot-id (first args)))))

(defun %store-cli-list-registry ()
  (dolist (snapshot-id (list-registry-snapshots))
    (format t "~A~%" snapshot-id)))

(defun %store-cli-show-registry (snapshot-id)
  (format t "~A~%" (emit-json (load-registry-snapshot snapshot-id))))

(defun %store-cli-latest-registry ()
  (let ((snapshot-id (latest-registry-snapshot-id)))
    (if snapshot-id
        (format t "~A~%" snapshot-id)
        (%store-error "No registry snapshots are available"))))

(defun %store-cli-summarize-registry (snapshot-id)
  (format t "~A~%" (emit-json (summarize-registry-snapshot snapshot-id))))

(defun %store-cli-diff-registry (left-snapshot-id right-snapshot-id)
  (format t "~A~%" (emit-json (diff-registry-snapshots left-snapshot-id right-snapshot-id))))

(defun %store-cli-adapter-history (adapter-id)
  (format t "~A~%" (emit-json (registry-adapter-history adapter-id))))

(defun dispatch-store-command (args)
  (cond
    ((null args)
     (cl-py.internal:signal-cli-usage-error "store requires a subcommand" #'%print-store-usage))
    ((cl-py.internal:help-flag-p (first args))
     (%print-store-help))
    ((string= (first args) "snapshot-registry")
     (%store-cli-snapshot-registry (rest args)))
    ((string= (first args) "list-registry")
     (if (rest args)
         (cl-py.internal:signal-cli-usage-error
          "store list-registry does not accept positional arguments"
          #'%print-store-usage)
         (%store-cli-list-registry)))
    ((string= (first args) "show-registry")
     (if (= (length (rest args)) 1)
         (%store-cli-show-registry (second args))
         (cl-py.internal:signal-cli-usage-error
          "store show-registry requires exactly one snapshot id"
          #'%print-store-usage)))
    ((string= (first args) "latest-registry")
     (if (rest args)
       (cl-py.internal:signal-cli-usage-error
        "store latest-registry does not accept positional arguments"
        #'%print-store-usage)
       (%store-cli-latest-registry)))
    ((string= (first args) "summarize-registry")
     (if (= (length (rest args)) 1)
       (%store-cli-summarize-registry (second args))
       (cl-py.internal:signal-cli-usage-error
        "store summarize-registry requires exactly one snapshot id"
        #'%print-store-usage)))
    ((string= (first args) "diff-registry")
     (if (= (length (rest args)) 2)
       (%store-cli-diff-registry (second args) (third args))
       (cl-py.internal:signal-cli-usage-error
        "store diff-registry requires exactly two snapshot ids"
        #'%print-store-usage)))
    ((string= (first args) "adapter-history")
     (if (= (length (rest args)) 1)
       (%store-cli-adapter-history (second args))
       (cl-py.internal:signal-cli-usage-error
        "store adapter-history requires exactly one adapter id"
        #'%print-store-usage)))
    (t
     (cl-py.internal:signal-cli-usage-error
      (format nil "Unknown store subcommand: ~A" (first args))
      #'%print-store-usage))))

(cl-py.internal:register-top-level-cli-command
 "store"
 #'dispatch-store-command
 :usage "store <subcommand>"
 :summary "Persist and inspect local registry snapshots"
 :detail-printer #'%print-store-help)