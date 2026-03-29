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

(defun delete-registry-snapshot (snapshot-id &key directory)
  (let ((path (%registry-snapshot-path snapshot-id directory)))
    (unless (probe-file path)
      (%store-error "Registry snapshot was not found: ~A" snapshot-id))
    (delete-file path)
    (list :object
          (cons "deleted" :true)
          (cons "snapshot-id" snapshot-id)
          (cons "path" (namestring path)))))

(defun prune-registry-snapshots (keep-count &key directory)
  (unless (and (integerp keep-count) (>= keep-count 0))
    (%store-error "Keep count must be a non-negative integer"))
  (let* ((snapshot-ids (list-registry-snapshots :directory directory))
         (kept-snapshot-ids (subseq snapshot-ids 0 (min keep-count (length snapshot-ids))))
         (deleted-snapshot-ids (nthcdr (length kept-snapshot-ids) snapshot-ids)))
    (dolist (snapshot-id deleted-snapshot-ids)
      (delete-file (%registry-snapshot-path snapshot-id directory)))
    (list :object
          (cons "keep-count" keep-count)
          (cons "kept-count" (length kept-snapshot-ids))
          (cons "deleted-count" (length deleted-snapshot-ids))
          (cons "kept-snapshot-ids" (coerce kept-snapshot-ids 'vector))
          (cons "deleted-snapshot-ids" (coerce deleted-snapshot-ids 'vector)))))

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

(defun %adapter-entry (adapter key)
  (cdr (assoc key (cdr adapter) :test #'string=)))

(defun %adapter-has-capability-p (adapter capability)
  (find capability (%adapter-entry adapter "capabilities") :test #'string=))

(defun %normalize-filter-values (values)
  (sort (remove-duplicates (remove nil (copy-list values)) :test #'string=)
        #'string<))

(defun %effective-filter-values (single multiple)
  (%normalize-filter-values
   (append (when single (list single))
           (copy-list multiple))))

(defun %single-or-null (values)
  (if (= (length values) 1)
      (first values)
      :null))

(defun %normalize-report-groups (values)
  (let ((requested (%normalize-filter-values values)))
    (dolist (value requested)
      (unless (member value '("license" "capability") :test #'string=)
        (%store-error "Unsupported report group: ~A" value)))
    (let ((groups nil))
      (when (member "license" requested :test #'string=)
        (push "license" groups))
      (when (member "capability" requested :test #'string=)
        (push "capability" groups))
      (nreverse groups))))

(defun %effective-report-groups (single multiple)
  (let ((groups (%normalize-report-groups
                 (append (when single (list single))
                         (copy-list multiple)))))
    (if groups
        groups
        '("license" "capability"))))

(defun %report-has-group-p (groups group)
  (member group groups :test #'string=))

(defun %report-entry-name (entry)
  (%snapshot-entry entry "name"))

(defun %report-entry-count (entry)
  (%snapshot-entry entry "count"))

(defun %report-diff-entry-delta (entry)
  (%snapshot-entry entry "delta"))

(defun %report-diff-entry-abs-delta (entry)
  (abs (%report-diff-entry-delta entry)))

(defun %report-matches-filters-p (adapter licenses capabilities excluded-licenses excluded-capabilities)
  (and (or (null licenses)
           (member (%adapter-entry adapter "license") licenses :test #'string=))
       (or (null capabilities)
           (loop for capability in capabilities
                 thereis (%adapter-has-capability-p adapter capability)))
       (not (member (%adapter-entry adapter "license") excluded-licenses :test #'string=))
       (not (loop for capability in excluded-capabilities
                  thereis (%adapter-has-capability-p adapter capability)))))

(defun %count-values (values)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (value values)
      (when value
        (incf (gethash value table 0))))
    (loop for key being the hash-keys of table
          collect (list :object
                        (cons "name" key)
                        (cons "count" (gethash key table))))))

(defun %report-filter-object (licenses capabilities excluded-licenses excluded-capabilities)
  (list :object
  (cons "license" (%single-or-null licenses))
        (cons "licenses" (coerce licenses 'vector))
  (cons "capability" (%single-or-null capabilities))
  (cons "capabilities" (coerce capabilities 'vector))
  (cons "exclude-license" (%single-or-null excluded-licenses))
  (cons "exclude-licenses" (coerce excluded-licenses 'vector))
  (cons "exclude-capability" (%single-or-null excluded-capabilities))
  (cons "exclude-capabilities" (coerce excluded-capabilities 'vector))))

(defun %sort-report-rows (rows sort-mode)
  (sort (copy-list rows)
        (cond
          ((string= sort-mode "count-asc")
           (lambda (left right)
             (or (< (%report-entry-count left) (%report-entry-count right))
                 (and (= (%report-entry-count left) (%report-entry-count right))
                      (string< (%report-entry-name left) (%report-entry-name right))))))
          ((string= sort-mode "count-desc")
           (lambda (left right)
             (or (> (%report-entry-count left) (%report-entry-count right))
                 (and (= (%report-entry-count left) (%report-entry-count right))
                      (string< (%report-entry-name left) (%report-entry-name right))))))
          (t
           (lambda (left right)
             (string< (%report-entry-name left) (%report-entry-name right)))))))

(defun %sort-diff-report-rows (rows sort-mode)
  (sort (copy-list rows)
        (cond
          ((string= sort-mode "delta-asc")
           (lambda (left right)
             (or (< (%report-diff-entry-delta left) (%report-diff-entry-delta right))
                 (and (= (%report-diff-entry-delta left) (%report-diff-entry-delta right))
                      (string< (%report-entry-name left) (%report-entry-name right))))))
          ((string= sort-mode "delta-desc")
           (lambda (left right)
             (or (> (%report-diff-entry-delta left) (%report-diff-entry-delta right))
                 (and (= (%report-diff-entry-delta left) (%report-diff-entry-delta right))
                      (string< (%report-entry-name left) (%report-entry-name right))))))
          ((string= sort-mode "abs-delta-asc")
           (lambda (left right)
             (or (< (%report-diff-entry-abs-delta left) (%report-diff-entry-abs-delta right))
                 (and (= (%report-diff-entry-abs-delta left) (%report-diff-entry-abs-delta right))
                      (string< (%report-entry-name left) (%report-entry-name right))))))
          ((string= sort-mode "abs-delta-desc")
           (lambda (left right)
             (or (> (%report-diff-entry-abs-delta left) (%report-diff-entry-abs-delta right))
                 (and (= (%report-diff-entry-abs-delta left) (%report-diff-entry-abs-delta right))
                      (string< (%report-entry-name left) (%report-entry-name right))))))
          (t
           (lambda (left right)
             (string< (%report-entry-name left) (%report-entry-name right)))))))

(defun %validate-report-sort-mode (sort-mode command-name)
  (unless (member sort-mode '("name" "count-asc" "count-desc") :test #'string=)
    (cl-py.internal:signal-cli-usage-error
     (format nil "~A requires --sort to be one of: name, count-asc, count-desc" command-name)
     #'%print-store-usage))
  sort-mode)

(defun %validate-report-group (group command-name)
  (unless (member group '("license" "capability") :test #'string=)
    (cl-py.internal:signal-cli-usage-error
     (format nil "~A requires --group to be one of: license, capability" command-name)
     #'%print-store-usage))
  group)

(defun %validate-diff-report-sort-mode (sort-mode)
  (unless (member sort-mode '("name" "delta-asc" "delta-desc" "abs-delta-asc" "abs-delta-desc") :test #'string=)
    (cl-py.internal:signal-cli-usage-error
     "store diff-report-registry requires --sort to be one of: name, delta-asc, delta-desc, abs-delta-asc, abs-delta-desc"
     #'%print-store-usage))
  sort-mode)

(defun %validate-report-limit (limit command-name)
  (unless (and (integerp limit) (>= limit 0))
    (cl-py.internal:signal-cli-usage-error
     (format nil "~A requires --limit to be a non-negative integer" command-name)
     #'%print-store-usage))
  limit)

(defun %parse-non-negative-integer (text command-name)
  (let ((value (ignore-errors (parse-integer text :junk-allowed nil))))
    (%validate-report-limit value command-name)))

(defun %parse-keep-count (text command-name)
  (%parse-non-negative-integer text command-name))

(defun %limit-rows (rows limit)
  (if limit
      (subseq rows 0 (min limit (length rows)))
      rows))

(defun %offset-rows (rows offset)
  (if offset
      (subseq rows (min offset (length rows)))
      rows))

(defun %pagination-object (rows offset limit paged-rows)
  (let* ((total-count (length rows))
         (returned-count (length paged-rows))
         (effective-offset (or offset 0))
         (remaining-count (max 0 (- total-count (+ effective-offset returned-count)))))
    (list :object
          (cons "total-count" total-count)
          (cons "returned-count" returned-count)
          (cons "remaining-count" remaining-count)
          (cons "offset" (or offset :null))
          (cons "limit" (or limit :null)))))

(defun %paginate-rows (rows offset limit)
  (let* ((offset-rows (%offset-rows rows offset))
         (paged-rows (%limit-rows offset-rows limit)))
    (values paged-rows (%pagination-object rows offset limit paged-rows))))

(defun %group-offset (group offset license-offset capability-offset)
  (cond
    ((string= group "license") (or license-offset offset))
    ((string= group "capability") (or capability-offset offset))
    (t offset)))

(defun %group-limit (group limit license-limit capability-limit)
  (cond
    ((string= group "license") (or license-limit limit))
    ((string= group "capability") (or capability-limit limit))
    (t limit)))

(defun %group-sort (group sort license-sort capability-sort)
  (cond
    ((string= group "license") (or license-sort sort))
    ((string= group "capability") (or capability-sort sort))
    (t sort)))

(defun %write-output-file (output-path payload)
  (let ((path (pathname output-path)))
    (ensure-directories-exist path)
    (with-open-file (stream path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string payload stream)
      (terpri stream))
    path))

(defun %emit-cli-json-output (value &key output-path)
  (let ((payload (emit-json value)))
    (if output-path
        (format t "~A~%" (namestring (%write-output-file output-path payload)))
        (format t "~A~%" payload))))

(defun %counts-vector-table (entries)
  (let ((table (make-hash-table :test #'equal)))
    (when entries
      (loop for entry across entries
            do (setf (gethash (%snapshot-entry entry "name") table)
                     (%snapshot-entry entry "count"))))
    table))

(defun %diff-count-vectors (left right)
  (let* ((left-table (%counts-vector-table left))
         (right-table (%counts-vector-table right))
         (names (sort (remove-duplicates
                       (append (loop for key being the hash-keys of left-table collect key)
                               (loop for key being the hash-keys of right-table collect key))
                       :test #'string=)
                      #'string<)))
    (coerce
     (loop for name in names
           for left-count = (gethash name left-table 0)
           for right-count = (gethash name right-table 0)
           unless (= left-count right-count)
           collect (list :object
                         (cons "name" name)
                         (cons "left-count" left-count)
                         (cons "right-count" right-count)
                         (cons "delta" (- right-count left-count))))
     'vector)))

(defun %parse-report-registry-args (args)
  (let ((snapshot-id nil)
        (licenses nil)
        (capabilities nil)
        (excluded-licenses nil)
        (excluded-capabilities nil)
        (groups nil)
        (sort-mode "name")
          (license-sort nil)
          (capability-sort nil)
        (limit nil)
        (offset nil)
  (license-limit nil)
  (license-offset nil)
  (capability-limit nil)
  (capability-offset nil)
        (output-path nil))
    (loop while args
          for argument = (pop args)
          do (cond
               ((string= argument "--license")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store report-registry requires a value after --license"
                   #'%print-store-usage))
                (push (pop args) licenses))
               ((string= argument "--capability")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store report-registry requires a value after --capability"
                   #'%print-store-usage))
                (push (pop args) capabilities))
               ((string= argument "--exclude-license")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store report-registry requires a value after --exclude-license"
                   #'%print-store-usage))
                (push (pop args) excluded-licenses))
               ((string= argument "--exclude-capability")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store report-registry requires a value after --exclude-capability"
                   #'%print-store-usage))
                (push (pop args) excluded-capabilities))
               ((string= argument "--group")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store report-registry requires a value after --group"
                   #'%print-store-usage))
                (push (%validate-report-group (pop args) "store report-registry") groups))
               ((string= argument "--sort")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store report-registry requires a value after --sort"
                   #'%print-store-usage))
                (setf sort-mode (%validate-report-sort-mode (pop args) "store report-registry")))
               ((string= argument "--license-sort")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store report-registry requires a value after --license-sort"
                   #'%print-store-usage))
                (setf license-sort (%validate-report-sort-mode (pop args) "store report-registry")))
               ((string= argument "--capability-sort")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store report-registry requires a value after --capability-sort"
                   #'%print-store-usage))
                (setf capability-sort (%validate-report-sort-mode (pop args) "store report-registry")))
               ((string= argument "--limit")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store report-registry requires a value after --limit"
                   #'%print-store-usage))
                (setf limit (%parse-non-negative-integer (pop args) "store report-registry")))
               ((string= argument "--offset")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store report-registry requires a value after --offset"
                   #'%print-store-usage))
                (setf offset (%parse-non-negative-integer (pop args) "store report-registry")))
               ((string= argument "--license-limit")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store report-registry requires a value after --license-limit"
                   #'%print-store-usage))
                (setf license-limit (%parse-non-negative-integer (pop args) "store report-registry")))
               ((string= argument "--license-offset")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store report-registry requires a value after --license-offset"
                   #'%print-store-usage))
                (setf license-offset (%parse-non-negative-integer (pop args) "store report-registry")))
               ((string= argument "--capability-limit")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store report-registry requires a value after --capability-limit"
                   #'%print-store-usage))
                (setf capability-limit (%parse-non-negative-integer (pop args) "store report-registry")))
               ((string= argument "--capability-offset")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store report-registry requires a value after --capability-offset"
                   #'%print-store-usage))
                (setf capability-offset (%parse-non-negative-integer (pop args) "store report-registry")))
               ((string= argument "--output")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store report-registry requires a value after --output"
                   #'%print-store-usage))
                (setf output-path (pop args)))
               ((null snapshot-id)
                (setf snapshot-id argument))
               (t
                (cl-py.internal:signal-cli-usage-error
                 "store report-registry accepts exactly one snapshot id and optional filters"
                 #'%print-store-usage))))
    (unless snapshot-id
      (cl-py.internal:signal-cli-usage-error
       "store report-registry requires a snapshot id"
       #'%print-store-usage))
    (values snapshot-id
            (%normalize-filter-values (nreverse licenses))
            (%normalize-filter-values (nreverse capabilities))
            (%normalize-filter-values (nreverse excluded-licenses))
            (%normalize-filter-values (nreverse excluded-capabilities))
            (%effective-report-groups nil (nreverse groups))
            sort-mode
            license-sort
            capability-sort
            limit
            offset
            license-limit
            license-offset
            capability-limit
            capability-offset
            output-path)))

(defun %parse-diff-report-registry-args (args)
  (let ((left-snapshot-id nil)
        (right-snapshot-id nil)
        (licenses nil)
        (capabilities nil)
        (excluded-licenses nil)
        (excluded-capabilities nil)
        (groups nil)
        (sort-mode "name")
        (license-sort nil)
        (capability-sort nil)
        (limit nil)
        (offset nil)
  (license-limit nil)
  (license-offset nil)
  (capability-limit nil)
  (capability-offset nil)
        (output-path nil))
    (loop while args
          for argument = (pop args)
          do (cond
               ((string= argument "--license")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store diff-report-registry requires a value after --license"
                   #'%print-store-usage))
                (push (pop args) licenses))
               ((string= argument "--capability")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store diff-report-registry requires a value after --capability"
                   #'%print-store-usage))
                (push (pop args) capabilities))
               ((string= argument "--exclude-license")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store diff-report-registry requires a value after --exclude-license"
                   #'%print-store-usage))
                (push (pop args) excluded-licenses))
               ((string= argument "--exclude-capability")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store diff-report-registry requires a value after --exclude-capability"
                   #'%print-store-usage))
                (push (pop args) excluded-capabilities))
               ((string= argument "--group")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store diff-report-registry requires a value after --group"
                   #'%print-store-usage))
                (push (%validate-report-group (pop args) "store diff-report-registry") groups))
               ((string= argument "--sort")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store diff-report-registry requires a value after --sort"
                   #'%print-store-usage))
                (setf sort-mode (%validate-diff-report-sort-mode (pop args))))
               ((string= argument "--license-sort")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store diff-report-registry requires a value after --license-sort"
                   #'%print-store-usage))
                (setf license-sort (%validate-diff-report-sort-mode (pop args))))
               ((string= argument "--capability-sort")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store diff-report-registry requires a value after --capability-sort"
                   #'%print-store-usage))
                (setf capability-sort (%validate-diff-report-sort-mode (pop args))))
               ((string= argument "--limit")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store diff-report-registry requires a value after --limit"
                   #'%print-store-usage))
                (setf limit (%parse-non-negative-integer (pop args) "store diff-report-registry")))
               ((string= argument "--offset")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store diff-report-registry requires a value after --offset"
                   #'%print-store-usage))
                (setf offset (%parse-non-negative-integer (pop args) "store diff-report-registry")))
               ((string= argument "--license-limit")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store diff-report-registry requires a value after --license-limit"
                   #'%print-store-usage))
                (setf license-limit (%parse-non-negative-integer (pop args) "store diff-report-registry")))
               ((string= argument "--license-offset")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store diff-report-registry requires a value after --license-offset"
                   #'%print-store-usage))
                (setf license-offset (%parse-non-negative-integer (pop args) "store diff-report-registry")))
               ((string= argument "--capability-limit")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store diff-report-registry requires a value after --capability-limit"
                   #'%print-store-usage))
                (setf capability-limit (%parse-non-negative-integer (pop args) "store diff-report-registry")))
               ((string= argument "--capability-offset")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store diff-report-registry requires a value after --capability-offset"
                   #'%print-store-usage))
                (setf capability-offset (%parse-non-negative-integer (pop args) "store diff-report-registry")))
               ((string= argument "--output")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store diff-report-registry requires a value after --output"
                   #'%print-store-usage))
                (setf output-path (pop args)))
               ((null left-snapshot-id)
                (setf left-snapshot-id argument))
               ((null right-snapshot-id)
                (setf right-snapshot-id argument))
               (t
                (cl-py.internal:signal-cli-usage-error
                 "store diff-report-registry accepts exactly two snapshot ids and optional filters"
                 #'%print-store-usage))))
    (unless left-snapshot-id
      (cl-py.internal:signal-cli-usage-error
       "store diff-report-registry requires a left snapshot id"
       #'%print-store-usage))
    (unless right-snapshot-id
      (cl-py.internal:signal-cli-usage-error
       "store diff-report-registry requires a right snapshot id"
       #'%print-store-usage))
    (values left-snapshot-id
            right-snapshot-id
            (%normalize-filter-values (nreverse licenses))
            (%normalize-filter-values (nreverse capabilities))
            (%normalize-filter-values (nreverse excluded-licenses))
            (%normalize-filter-values (nreverse excluded-capabilities))
            (%effective-report-groups nil (nreverse groups))
            sort-mode
            license-sort
            capability-sort
            limit
            offset
            license-limit
            license-offset
            capability-limit
            capability-offset
            output-path)))

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

(defun report-registry-snapshot (snapshot-id &key directory license capability licenses capabilities exclude-license exclude-capability exclude-licenses exclude-capabilities group groups (sort "name") license-sort capability-sort limit offset license-limit license-offset capability-limit capability-offset)
  (let* ((snapshot (load-registry-snapshot snapshot-id :directory directory))
         (effective-licenses (%effective-filter-values license licenses))
         (effective-capabilities (%effective-filter-values capability capabilities))
         (effective-excluded-licenses (%effective-filter-values exclude-license exclude-licenses))
         (effective-excluded-capabilities (%effective-filter-values exclude-capability exclude-capabilities))
         (effective-groups (%effective-report-groups group groups))
         (all-adapters (coerce (%snapshot-adapters snapshot) 'list))
         (adapters (remove-if-not (lambda (adapter)
                                    (%report-matches-filters-p adapter effective-licenses effective-capabilities effective-excluded-licenses effective-excluded-capabilities))
                                  all-adapters))
         (license-counts (%count-values (mapcar (lambda (adapter)
                                                  (%adapter-entry adapter "license"))
                                                adapters)))
         (capability-counts (%count-values
                             (loop for adapter in adapters
                                   append (coerce (%adapter-entry adapter "capabilities") 'list)))))
    (%validate-report-sort-mode sort "report-registry-snapshot")
    (when limit
      (%validate-report-limit limit "report-registry-snapshot"))
    (when offset
      (%validate-report-limit offset "report-registry-snapshot"))
    (when license-limit
      (%validate-report-limit license-limit "report-registry-snapshot"))
    (when license-offset
      (%validate-report-limit license-offset "report-registry-snapshot"))
    (when capability-limit
      (%validate-report-limit capability-limit "report-registry-snapshot"))
    (when capability-offset
      (%validate-report-limit capability-offset "report-registry-snapshot"))
    (multiple-value-bind (paged-license-counts license-counts-page)
        (%paginate-rows (%sort-report-rows license-counts (%group-sort "license" sort license-sort capability-sort))
                        (%group-offset "license" offset license-offset capability-offset)
                        (%group-limit "license" limit license-limit capability-limit))
      (multiple-value-bind (paged-capability-counts capability-counts-page)
          (%paginate-rows (%sort-report-rows capability-counts (%group-sort "capability" sort license-sort capability-sort))
                          (%group-offset "capability" offset license-offset capability-offset)
                          (%group-limit "capability" limit license-limit capability-limit))
        (append
         (list :object
           (cons "snapshot-id" (%snapshot-entry snapshot "snapshot-id"))
           (cons "created-at" (%snapshot-created-at snapshot))
           (cons "adapter-count" (length adapters))
           (cons "total-adapter-count" (%snapshot-entry snapshot "adapter-count"))
           (cons "group" (%single-or-null effective-groups))
           (cons "groups" (coerce effective-groups 'vector))
           (cons "sort" sort)
           (cons "license-sort" (%group-sort "license" sort license-sort capability-sort))
           (cons "capability-sort" (%group-sort "capability" sort license-sort capability-sort))
           (cons "limit" (or limit :null))
           (cons "offset" (or offset :null))
           (cons "license-limit" (or license-limit :null))
           (cons "license-offset" (or license-offset :null))
           (cons "capability-limit" (or capability-limit :null))
           (cons "capability-offset" (or capability-offset :null))
           (cons "filters" (%report-filter-object effective-licenses effective-capabilities effective-excluded-licenses effective-excluded-capabilities)))
         (when (%report-has-group-p effective-groups "license")
           (list (cons "license-counts-page" license-counts-page)
             (cons "license-counts" (coerce paged-license-counts 'vector))))
         (when (%report-has-group-p effective-groups "capability")
           (list (cons "capability-counts-page" capability-counts-page)
             (cons "capability-counts" (coerce paged-capability-counts 'vector)))))))))

(defun diff-registry-snapshot-reports (left-snapshot-id right-snapshot-id
                   &key directory license capability licenses capabilities exclude-license exclude-capability exclude-licenses exclude-capabilities group groups (sort "name") license-sort capability-sort limit offset license-limit license-offset capability-limit capability-offset)
  (let* ((left-report (report-registry-snapshot left-snapshot-id
                                                :directory directory
                                                :license license
                                                :capability capability
                                                :licenses licenses
                                                :capabilities capabilities
                                                :exclude-license exclude-license
                                                :exclude-capability exclude-capability
                                                :exclude-licenses exclude-licenses
                                                :exclude-capabilities exclude-capabilities
                                                :group group
                                                :groups groups))
         (right-report (report-registry-snapshot right-snapshot-id
                                                 :directory directory
                                                 :license license
                                                 :capability capability
                                                 :licenses licenses
                                                 :capabilities capabilities
                                                 :exclude-license exclude-license
                                                 :exclude-capability exclude-capability
                                                 :exclude-licenses exclude-licenses
                                                 :exclude-capabilities exclude-capabilities
                                                 :group group
                                                 :groups groups))
         (effective-licenses (%effective-filter-values license licenses))
         (effective-capabilities (%effective-filter-values capability capabilities))
         (effective-excluded-licenses (%effective-filter-values exclude-license exclude-licenses))
         (effective-excluded-capabilities (%effective-filter-values exclude-capability exclude-capabilities))
         (effective-groups (%effective-report-groups group groups))
         (license-count-diff-rows (coerce (%diff-count-vectors (%snapshot-entry left-report "license-counts")
                                                                (%snapshot-entry right-report "license-counts"))
                                          'list))
         (capability-count-diff-rows (coerce (%diff-count-vectors (%snapshot-entry left-report "capability-counts")
                                                                   (%snapshot-entry right-report "capability-counts"))
                                             'list)))
    (%validate-diff-report-sort-mode sort)
    (when limit
      (%validate-report-limit limit "diff-registry-snapshot-reports"))
    (when offset
      (%validate-report-limit offset "diff-registry-snapshot-reports"))
    (when license-limit
      (%validate-report-limit license-limit "diff-registry-snapshot-reports"))
    (when license-offset
      (%validate-report-limit license-offset "diff-registry-snapshot-reports"))
    (when capability-limit
      (%validate-report-limit capability-limit "diff-registry-snapshot-reports"))
    (when capability-offset
      (%validate-report-limit capability-offset "diff-registry-snapshot-reports"))
    (multiple-value-bind (paged-license-count-diff license-count-diff-page)
        (%paginate-rows (%sort-diff-report-rows license-count-diff-rows (%group-sort "license" sort license-sort capability-sort))
                        (%group-offset "license" offset license-offset capability-offset)
                        (%group-limit "license" limit license-limit capability-limit))
      (multiple-value-bind (paged-capability-count-diff capability-count-diff-page)
          (%paginate-rows (%sort-diff-report-rows capability-count-diff-rows (%group-sort "capability" sort license-sort capability-sort))
                          (%group-offset "capability" offset license-offset capability-offset)
                          (%group-limit "capability" limit license-limit capability-limit))
        (append
         (list :object
           (cons "left-snapshot-id" left-snapshot-id)
           (cons "right-snapshot-id" right-snapshot-id)
           (cons "group" (%single-or-null effective-groups))
           (cons "groups" (coerce effective-groups 'vector))
           (cons "sort" sort)
           (cons "license-sort" (%group-sort "license" sort license-sort capability-sort))
           (cons "capability-sort" (%group-sort "capability" sort license-sort capability-sort))
           (cons "limit" (or limit :null))
           (cons "offset" (or offset :null))
           (cons "license-limit" (or license-limit :null))
           (cons "license-offset" (or license-offset :null))
           (cons "capability-limit" (or capability-limit :null))
           (cons "capability-offset" (or capability-offset :null))
           (cons "filters" (%report-filter-object effective-licenses effective-capabilities effective-excluded-licenses effective-excluded-capabilities))
           (cons "left-adapter-count" (%snapshot-entry left-report "adapter-count"))
           (cons "right-adapter-count" (%snapshot-entry right-report "adapter-count"))
           (cons "left-total-adapter-count" (%snapshot-entry left-report "total-adapter-count"))
           (cons "right-total-adapter-count" (%snapshot-entry right-report "total-adapter-count")))
         (when (%report-has-group-p effective-groups "license")
           (list (cons "license-count-diff-page" license-count-diff-page)
             (cons "license-count-diff" (coerce paged-license-count-diff 'vector))))
         (when (%report-has-group-p effective-groups "capability")
           (list (cons "capability-count-diff-page" capability-count-diff-page)
             (cons "capability-count-diff" (coerce paged-capability-count-diff 'vector)))))))))

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
  (format t "  store delete-registry <snapshot-id>~%")
  (format t "  store prune-registry <keep-count>~%")
  (format t "  store show-registry <snapshot-id>~%")
  (format t "  store latest-registry~%")
  (format t "  store summarize-registry <snapshot-id>~%")
  (format t "  store diff-registry <left-snapshot-id> <right-snapshot-id>~%")
  (format t "  store adapter-history <adapter-id>~%")
  (format t "  store report-registry <snapshot-id> [--license <license>] [--capability <capability>] [--exclude-license <license>] [--exclude-capability <capability>] [--group <license|capability>] [--sort <name|count-asc|count-desc>] [--license-sort <name|count-asc|count-desc>] [--capability-sort <name|count-asc|count-desc>] [--offset <n>] [--limit <n>] [--license-offset <n>] [--license-limit <n>] [--capability-offset <n>] [--capability-limit <n>] [--output <path>]~%")
  (format t "  store diff-report-registry <left-snapshot-id> <right-snapshot-id> [--license <license>] [--capability <capability>] [--exclude-license <license>] [--exclude-capability <capability>] [--group <license|capability>] [--sort <name|delta-asc|delta-desc|abs-delta-asc|abs-delta-desc>] [--license-sort <name|delta-asc|delta-desc|abs-delta-asc|abs-delta-desc>] [--capability-sort <name|delta-asc|delta-desc|abs-delta-asc|abs-delta-desc>] [--offset <n>] [--limit <n>] [--license-offset <n>] [--license-limit <n>] [--capability-offset <n>] [--capability-limit <n>] [--output <path>]~%"))

(defun %print-store-help ()
  (%print-store-usage)
  (format t "~%Storage:~%")
  (format t "  Default root is .cl-py-store under the repository root~%")
  (format t "  Override with CL_PY_STORE_DIR to use another directory~%")
  (format t "~%Examples:~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store snapshot-registry~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store snapshot-registry nightly~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store list-registry~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store delete-registry nightly~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store prune-registry 5~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store show-registry nightly~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store latest-registry~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store summarize-registry nightly~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store diff-registry baseline nightly~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store adapter-history slugify~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store report-registry nightly~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store report-registry nightly --capability slugify-text~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store report-registry nightly --capability slugify-text --capability validate-instance~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store report-registry nightly --exclude-capability metadata~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store report-registry nightly --group capability~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store report-registry nightly --license-sort count-desc --capability-sort count-asc~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store report-registry nightly --license-limit 1 --capability-offset 1~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store report-registry nightly --sort count-desc~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store report-registry nightly --sort count-desc --offset 1 --limit 2~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store report-registry nightly --output reports/nightly.json~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store report-registry nightly --sort count-desc --limit 2~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store report-registry nightly --license python-slugify~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --capability validate-instance~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --exclude-license MIT~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --group license~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --license-sort delta-desc --capability-sort name~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --license-limit 1 --capability-limit 2~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --sort delta-asc~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --sort abs-delta-desc~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --sort abs-delta-desc --offset 1 --limit 1~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --output reports/diff.json~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --sort delta-asc --limit 1~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store diff-report-registry baseline nightly --license MIT --license Apache-2.0~%"))

(defun %store-cli-snapshot-registry (args)
  (if (> (length args) 1)
      (cl-py.internal:signal-cli-usage-error
       "store snapshot-registry accepts at most one snapshot id"
       #'%print-store-usage)
      (format t "~A~%" (save-registry-snapshot :snapshot-id (first args)))))

(defun %store-cli-list-registry ()
  (dolist (snapshot-id (list-registry-snapshots))
    (format t "~A~%" snapshot-id)))

(defun %store-cli-delete-registry (snapshot-id)
  (format t "~A~%" (emit-json (delete-registry-snapshot snapshot-id))))

(defun %store-cli-prune-registry (keep-count)
  (format t "~A~%" (emit-json (prune-registry-snapshots keep-count))))

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

(defun %store-cli-report-registry (args)
  (multiple-value-bind (snapshot-id licenses capabilities excluded-licenses excluded-capabilities groups sort-mode license-sort capability-sort limit offset license-limit license-offset capability-limit capability-offset output-path)
      (%parse-report-registry-args args)
    (%emit-cli-json-output
     (report-registry-snapshot snapshot-id
                               :licenses licenses
                               :capabilities capabilities
                               :exclude-licenses excluded-licenses
                               :exclude-capabilities excluded-capabilities
                               :groups groups
                               :sort sort-mode
                               :license-sort license-sort
                               :capability-sort capability-sort
                               :limit limit
                               :offset offset
                               :license-limit license-limit
                               :license-offset license-offset
                               :capability-limit capability-limit
                               :capability-offset capability-offset)
     :output-path output-path)))

(defun %store-cli-diff-report-registry (args)
  (multiple-value-bind (left-snapshot-id right-snapshot-id licenses capabilities excluded-licenses excluded-capabilities groups sort-mode license-sort capability-sort limit offset license-limit license-offset capability-limit capability-offset output-path)
      (%parse-diff-report-registry-args args)
    (%emit-cli-json-output
     (diff-registry-snapshot-reports left-snapshot-id
                                     right-snapshot-id
                                     :licenses licenses
                                     :capabilities capabilities
                                     :exclude-licenses excluded-licenses
                                     :exclude-capabilities excluded-capabilities
                                     :groups groups
                                     :sort sort-mode
                                     :license-sort license-sort
                                     :capability-sort capability-sort
                                     :limit limit
                                     :offset offset
                                     :license-limit license-limit
                                     :license-offset license-offset
                                     :capability-limit capability-limit
                                     :capability-offset capability-offset)
     :output-path output-path)))

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
    ((string= (first args) "delete-registry")
     (if (= (length (rest args)) 1)
       (%store-cli-delete-registry (second args))
       (cl-py.internal:signal-cli-usage-error
        "store delete-registry requires exactly one snapshot id"
        #'%print-store-usage)))
    ((string= (first args) "prune-registry")
     (if (= (length (rest args)) 1)
       (%store-cli-prune-registry (%parse-keep-count (second args) "store prune-registry"))
       (cl-py.internal:signal-cli-usage-error
        "store prune-registry requires exactly one keep count"
        #'%print-store-usage)))
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
    ((string= (first args) "report-registry")
     (%store-cli-report-registry (rest args)))
    ((string= (first args) "diff-report-registry")
     (%store-cli-diff-report-registry (rest args)))
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