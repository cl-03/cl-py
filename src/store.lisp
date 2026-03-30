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

(defun %store-lifecycle-mode (dry-run force)
  (declare (ignore force))
  (if dry-run
      "dry-run"
      "force"))

(defun %store-lifecycle-audit-object (operation directory dry-run force &rest fields)
  (append (list :object
                (cons "operation" operation)
                (cons "mode" (%store-lifecycle-mode dry-run force))
                (cons "executed-at" (%snapshot-timestamp-string))
                (cons "store-root" (namestring (%store-root directory))))
          fields))

(defun %ensure-delete-confirmation (dry-run force)
  (unless (or dry-run force)
    (%store-error "Deleting a registry snapshot requires :force t or :dry-run t")))

(defun %snapshot-id-prefix-p (prefix snapshot-id)
  (let ((prefix-length (length prefix)))
    (and (<= prefix-length (length snapshot-id))
         (string= prefix snapshot-id :end1 prefix-length :end2 prefix-length))))

(defun %snapshot-ids-matching-prefixes (prefixes directory)
  (let ((normalized-prefixes (%normalize-filter-values prefixes)))
    (loop for snapshot-id in (list-registry-snapshots :directory directory)
          when (loop for prefix in normalized-prefixes
                     thereis (%snapshot-id-prefix-p prefix snapshot-id))
          collect snapshot-id)))

(defun %timestamp-universal-time (timestamp)
  (encode-universal-time (%timestamp-field timestamp :second)
                         (%timestamp-field timestamp :minute)
                         (%timestamp-field timestamp :hour)
                         (%timestamp-field timestamp :day)
                         (%timestamp-field timestamp :month)
                         (%timestamp-field timestamp :year)
                         (- (/ (%timestamp-field timestamp :offset-minutes) 60))))

(defun %snapshot-created-before-p (snapshot-id threshold directory)
  (< (%timestamp-universal-time (parse-iso-timestamp (%snapshot-created-at (load-registry-snapshot snapshot-id :directory directory))))
     (%timestamp-universal-time (parse-iso-timestamp threshold))))

(defun %snapshot-created-after-p (snapshot-id threshold directory)
  (> (%timestamp-universal-time (parse-iso-timestamp (%snapshot-created-at (load-registry-snapshot snapshot-id :directory directory))))
     (%timestamp-universal-time (parse-iso-timestamp threshold))))


(defun %snapshot-matches-created-window-p (snapshot-id directory created-before created-after)
  (and (or (null created-before)
           (%snapshot-created-before-p snapshot-id created-before directory))
       (or (null created-after)
           (%snapshot-created-after-p snapshot-id created-after directory))))

(defun %snapshot-ids-created-within-window (directory created-before created-after)
  (if (or created-before created-after)
      (loop for snapshot-id in (list-registry-snapshots :directory directory)
            when (%snapshot-matches-created-window-p snapshot-id directory created-before created-after)
            collect snapshot-id)
      nil))

(defun %lifecycle-match-object (explicit-snapshot-ids prefix-snapshot-ids created-window-snapshot-ids)
  (let* ((resolved-explicit-snapshot-ids (%normalize-filter-values explicit-snapshot-ids))
         (resolved-prefix-snapshot-ids (%normalize-filter-values prefix-snapshot-ids))
         (resolved-created-window-snapshot-ids (%normalize-filter-values created-window-snapshot-ids))
         (resolved-total-matched-snapshot-ids
           (%normalize-filter-values
            (append resolved-explicit-snapshot-ids
                    resolved-prefix-snapshot-ids
                    resolved-created-window-snapshot-ids))))
    (list :object
          (cons "explicit-snapshot-ids" (coerce resolved-explicit-snapshot-ids 'vector))
          (cons "explicit-count" (length resolved-explicit-snapshot-ids))
          (cons "prefix-snapshot-ids" (coerce resolved-prefix-snapshot-ids 'vector))
          (cons "prefix-count" (length resolved-prefix-snapshot-ids))
          (cons "created-window-snapshot-ids" (coerce resolved-created-window-snapshot-ids 'vector))
          (cons "created-window-count" (length resolved-created-window-snapshot-ids))
          (cons "total-matched-count" (length resolved-total-matched-snapshot-ids)))))

        (defun %lifecycle-match-request-object (explicit-snapshot-ids prefixes created-before created-after)
          (let ((resolved-explicit-snapshot-ids (%normalize-filter-values explicit-snapshot-ids))
            (resolved-prefixes (%normalize-filter-values prefixes)))
            (list :object
              (cons "explicit-snapshot-ids" (coerce resolved-explicit-snapshot-ids 'vector))
              (cons "explicit-count" (length resolved-explicit-snapshot-ids))
              (cons "prefixes" (coerce resolved-prefixes 'vector))
              (cons "prefix-count" (length resolved-prefixes))
              (cons "created-before" (or created-before :null))
              (cons "created-after" (or created-after :null)))))

(defun %lifecycle-prune-request-object (keep-count)
  (list :object
        (cons "keep-count" keep-count)))

(defun %lifecycle-prune-match-object (kept-snapshot-ids deleted-snapshot-ids)
  (let ((resolved-kept-snapshot-ids (%stable-unique-values kept-snapshot-ids))
    (resolved-deleted-snapshot-ids (%stable-unique-values deleted-snapshot-ids)))
    (list :object
          (cons "kept-snapshot-ids" (coerce resolved-kept-snapshot-ids 'vector))
          (cons "kept-count" (length resolved-kept-snapshot-ids))
          (cons "deleted-snapshot-ids" (coerce resolved-deleted-snapshot-ids 'vector))
          (cons "deleted-count" (length resolved-deleted-snapshot-ids)))))

(defun %stable-unique-values (values)
  (remove-duplicates (remove nil (copy-list values)) :test #'string= :from-end t))

(defun %lifecycle-summary-object (affected-count before-count after-count would-after-count &key affected-snapshot-ids extra-fields)
  (append (list :object
                (cons "affected-count" affected-count)
                (cons "affected-snapshot-ids" (coerce (%stable-unique-values affected-snapshot-ids) 'vector))
                (cons "before-count" before-count)
                (cons "after-count" after-count)
                (cons "would-after-count" would-after-count))
          extra-fields))

(defun %object-field (object key)
  (cdr (assoc key (rest object) :test #'string=)))

(defun %lifecycle-legacy-count-fields (summary)
  (list (cons "before-count" (%object-field summary "before-count"))
        (cons "after-count" (%object-field summary "after-count"))
        (cons "would-after-count" (%object-field summary "would-after-count"))))

(defun %lifecycle-delete-legacy-fields (summary)
  (append (%lifecycle-legacy-count-fields summary)
          (list (cons "deleted-count" (%object-field summary "deleted-count")))))

(defun %lifecycle-prune-legacy-fields (summary)
  (append (%lifecycle-legacy-count-fields summary)
          (list (cons "keep-count" (%object-field summary "keep-count"))
                (cons "kept-count" (%object-field summary "kept-count"))
                (cons "deleted-count" (%object-field summary "deleted-count")))))

(defun %lifecycle-prune-legacy-id-fields (match-object)
  (list (cons "kept-snapshot-ids" (%object-field match-object "kept-snapshot-ids"))
        (cons "deleted-snapshot-ids" (%object-field match-object "deleted-snapshot-ids"))))

(defun %lifecycle-prune-audit-fields (match-request match-object)
  (list (cons "keep-count" (%object-field match-request "keep-count"))
        (cons "kept-count" (%object-field match-object "kept-count"))
        (cons "deleted-count" (%object-field match-object "deleted-count"))
        (cons "kept-snapshot-ids" (%object-field match-object "kept-snapshot-ids"))
        (cons "deleted-snapshot-ids" (%object-field match-object "deleted-snapshot-ids"))))

(defun %lifecycle-delete-selector-legacy-fields (match-request)
  (list (cons "prefixes" (%object-field match-request "prefixes"))
        (cons "created-before" (%object-field match-request "created-before"))
        (cons "created-after" (%object-field match-request "created-after"))))

(defun %lifecycle-delete-selector-audit-fields (match-request)
  (list (cons "explicit-snapshot-ids" (%object-field match-request "explicit-snapshot-ids"))
        (cons "explicit-count" (%object-field match-request "explicit-count"))
        (cons "prefixes" (%object-field match-request "prefixes"))
        (cons "prefix-count" (%object-field match-request "prefix-count"))
        (cons "created-before" (%object-field match-request "created-before"))
        (cons "created-after" (%object-field match-request "created-after"))))

(defun %resolve-registry-snapshot-paths (snapshot-ids directory &key prefixes created-before created-after)
  (let ((resolved-snapshot-ids
          (%normalize-filter-values
           (append snapshot-ids
                   (%snapshot-ids-matching-prefixes prefixes directory)
                   (%snapshot-ids-created-within-window directory created-before created-after)))))
    (unless resolved-snapshot-ids
      (%store-error "At least one registry snapshot id or matching selector is required"))
    (mapcar (lambda (snapshot-id)
              (let ((path (%registry-snapshot-path snapshot-id directory)))
                (unless (probe-file path)
                  (%store-error "Registry snapshot was not found: ~A" snapshot-id))
                (cons snapshot-id path)))
            resolved-snapshot-ids)))

(defun delete-registry-snapshot (snapshot-id &key directory dry-run force)
  (let* ((before-count (length (list-registry-snapshots :directory directory)))
         (path (%registry-snapshot-path snapshot-id directory))
         (would-after-count (max 0 (1- before-count)))
         (after-count (if dry-run before-count would-after-count))
         (match-request (%lifecycle-match-request-object (list snapshot-id) nil nil nil))
         (summary (%lifecycle-summary-object
                   1
                   before-count
                   after-count
                   would-after-count
                   :affected-snapshot-ids (list snapshot-id)
                   :extra-fields (list (cons "deleted-count" 1)))))
    (%ensure-delete-confirmation dry-run force)
    (unless (probe-file path)
      (%store-error "Registry snapshot was not found: ~A" snapshot-id))
    (unless dry-run
      (delete-file path))
        (append
         (list :object
           (cons "deleted" (if dry-run :false :true))
           (cons "dry-run" (if dry-run :true :false))
           (cons "forced" (if (and force (not dry-run)) :true :false))
           (cons "would-delete" (if dry-run :true :false)))
         (%lifecycle-delete-legacy-fields summary)
         (%lifecycle-delete-selector-legacy-fields match-request)
         (list (cons "summary" summary)
           (cons "matched"
                 (append (%lifecycle-match-object (list snapshot-id) nil nil)
                 (list (cons "request" match-request))))
           (cons "audit"
           (apply #'%store-lifecycle-audit-object
              "delete-registry"
              directory
              dry-run
              force
            (append (list (cons "snapshot-count" 1)
              (cons "snapshot-ids" (vector snapshot-id))
              (cons "snapshot-id" snapshot-id)
                    (cons "path" (namestring path)))
                  (%lifecycle-delete-selector-audit-fields match-request))))
             (cons "snapshot-ids" (vector snapshot-id))
             (cons "paths" (vector (namestring path)))
           (cons "snapshot-id" snapshot-id)
           (cons "path" (namestring path))))))

(defun delete-registry-snapshots (snapshot-ids &key directory dry-run force prefixes created-before created-after)
  (%ensure-delete-confirmation dry-run force)
  (let* ((resolved-explicit-snapshot-ids (%normalize-filter-values snapshot-ids))
         (resolved-prefixes (%normalize-filter-values prefixes))
         (before-count (length (list-registry-snapshots :directory directory)))
         (prefix-snapshot-ids (%snapshot-ids-matching-prefixes resolved-prefixes directory))
         (created-window-snapshot-ids (%snapshot-ids-created-within-window directory created-before created-after))
         (resolved-paths (%resolve-registry-snapshot-paths resolved-explicit-snapshot-ids directory :prefixes resolved-prefixes :created-before created-before :created-after created-after))
         (resolved-snapshot-ids (mapcar #'car resolved-paths))
         (resolved-pathnames (mapcar #'cdr resolved-paths))
         (would-after-count (max 0 (- before-count (length resolved-snapshot-ids))))
         (after-count (if dry-run before-count would-after-count))
         (match-request (%lifecycle-match-request-object resolved-explicit-snapshot-ids resolved-prefixes created-before created-after))
         (summary (%lifecycle-summary-object
                   (length resolved-snapshot-ids)
                   before-count
                   after-count
                   would-after-count
                   :affected-snapshot-ids resolved-snapshot-ids
                   :extra-fields (list (cons "deleted-count" (length resolved-snapshot-ids))))))
    (unless dry-run
      (dolist (path resolved-pathnames)
        (delete-file path)))
    (append
     (list :object
           (cons "deleted" (if dry-run :false :true))
           (cons "dry-run" (if dry-run :true :false))
           (cons "forced" (if (and force (not dry-run)) :true :false))
           (cons "would-delete" (if dry-run :true :false)))
     (%lifecycle-delete-legacy-fields summary)
         (%lifecycle-delete-selector-legacy-fields match-request)
     (list (cons "summary" summary)
           (cons "snapshot-ids" (coerce resolved-snapshot-ids 'vector))
           (cons "matched"
             (append (%lifecycle-match-object
              resolved-explicit-snapshot-ids
              prefix-snapshot-ids
              created-window-snapshot-ids)
             (list (cons "request" match-request))))
           (cons "paths" (coerce (mapcar #'namestring resolved-pathnames) 'vector))
           (cons "audit"
                 (apply #'%store-lifecycle-audit-object
                "delete-registry"
                directory
                dry-run
                force
                (append (list (cons "snapshot-count" (length resolved-snapshot-ids))
                      (cons "snapshot-ids" (coerce resolved-snapshot-ids 'vector)))
                    (%lifecycle-delete-selector-audit-fields match-request))))))))

(defun prune-registry-snapshots (keep-count &key directory dry-run force)
  (unless (and (integerp keep-count) (>= keep-count 0))
    (%store-error "Keep count must be a non-negative integer"))
  (unless (or dry-run force)
    (%store-error "Pruning registry snapshots requires :force t or :dry-run t"))
  (let* ((snapshot-ids (list-registry-snapshots :directory directory))
         (before-count (length snapshot-ids))
         (kept-snapshot-ids (subseq snapshot-ids 0 (min keep-count (length snapshot-ids))))
         (deleted-snapshot-ids (nthcdr (length kept-snapshot-ids) snapshot-ids))
         (would-after-count (length kept-snapshot-ids))
         (after-count (if dry-run before-count would-after-count))
         (match-request (%lifecycle-prune-request-object keep-count))
      (match-object (%lifecycle-prune-match-object kept-snapshot-ids deleted-snapshot-ids))
      (matched (append match-object
             (list (cons "request" match-request))))
         (summary (%lifecycle-summary-object
                   (length deleted-snapshot-ids)
                   before-count
                   after-count
                   would-after-count
                   :affected-snapshot-ids deleted-snapshot-ids
                   :extra-fields (list (cons "keep-count" keep-count)
                                       (cons "kept-count" (length kept-snapshot-ids))
                                       (cons "deleted-count" (length deleted-snapshot-ids))))))
    (unless dry-run
      (dolist (snapshot-id deleted-snapshot-ids)
        (delete-file (%registry-snapshot-path snapshot-id directory))))
    (append
     (list :object
           (cons "dry-run" (if dry-run :true :false))
           (cons "forced" (if (and force (not dry-run)) :true :false)))
     (%lifecycle-prune-legacy-fields summary)
         (%lifecycle-prune-legacy-id-fields match-object)
         (list (cons "summary" summary)
           (cons "matched" matched)
           (cons "audit"
             (apply #'%store-lifecycle-audit-object
            "prune-registry"
            directory
            dry-run
            force
            (%lifecycle-prune-audit-fields match-request match-object)))))))

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

(defun %parse-store-delete-registry-args (args)
  (let ((snapshot-ids nil)
    (prefixes nil)
      (created-before nil)
      (created-after nil)
        (dry-run nil)
        (force nil))
    (loop while args
          for argument = (pop args)
          do (cond
               ((string= argument "--dry-run")
                (setf dry-run t))
               ((string= argument "--force")
                (setf force t))
              ((string= argument "--prefix")
               (unless args
                (cl-py.internal:signal-cli-usage-error
                 "store delete-registry requires a value after --prefix"
                 #'%print-store-usage))
               (push (pop args) prefixes))
               ((string= argument "--created-before")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store delete-registry requires a value after --created-before"
                   #'%print-store-usage))
                (setf created-before (pop args))
                (parse-iso-timestamp created-before))
               ((string= argument "--created-after")
                (unless args
                  (cl-py.internal:signal-cli-usage-error
                   "store delete-registry requires a value after --created-after"
                   #'%print-store-usage))
                (setf created-after (pop args))
                (parse-iso-timestamp created-after))
              (t
               (push argument snapshot-ids))))
    (unless (or snapshot-ids prefixes created-before created-after)
      (cl-py.internal:signal-cli-usage-error
       "store delete-registry requires at least one snapshot id or selector"
       #'%print-store-usage))
    (when (and dry-run force)
      (cl-py.internal:signal-cli-usage-error
       "store delete-registry accepts either --dry-run or --force, not both"
       #'%print-store-usage))
    (unless (or dry-run force)
      (cl-py.internal:signal-cli-usage-error
       "store delete-registry requires --dry-run or --force"
       #'%print-store-usage))
       (values (nreverse snapshot-ids)
            (%normalize-filter-values (nreverse prefixes))
            created-before
            created-after
            dry-run
            force)))

(defun %parse-store-prune-registry-args (args)
  (let ((keep-count nil)
        (dry-run nil)
        (force nil))
    (loop while args
          for argument = (pop args)
          do (cond
               ((string= argument "--dry-run")
                (setf dry-run t))
               ((string= argument "--force")
                (setf force t))
               ((null keep-count)
                (setf keep-count (%parse-keep-count argument "store prune-registry")))
               (t
                (cl-py.internal:signal-cli-usage-error
                 "store prune-registry requires exactly one keep count and one of --dry-run or --force"
                 #'%print-store-usage))))
    (unless keep-count
      (cl-py.internal:signal-cli-usage-error
       "store prune-registry requires a keep count"
       #'%print-store-usage))
    (when (and dry-run force)
      (cl-py.internal:signal-cli-usage-error
       "store prune-registry accepts either --dry-run or --force, not both"
       #'%print-store-usage))
    (unless (or dry-run force)
      (cl-py.internal:signal-cli-usage-error
       "store prune-registry requires --dry-run or --force"
       #'%print-store-usage))
    (values keep-count dry-run force)))

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
  (format t "  store delete-registry <snapshot-id> [<snapshot-id> ...] [--prefix <text> ...] [--created-before <timestamp>] [--created-after <timestamp>] (--dry-run | --force)~%")
  (format t "  store prune-registry <keep-count> (--dry-run | --force)~%")
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
  (format t "  sbcl --script scripts/dev-cli.lisp store delete-registry nightly --force~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store delete-registry nightly snapshot-20260330 --dry-run~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store delete-registry --prefix nightly- --dry-run~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store delete-registry --created-before 2026-03-30T00:00:00Z --dry-run~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store delete-registry --created-after 2026-03-29T12:00:00Z --created-before 2026-03-31T00:00:00Z --dry-run~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store delete-registry nightly --dry-run~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store prune-registry 5 --force~%")
  (format t "  sbcl --script scripts/dev-cli.lisp store prune-registry 5 --dry-run~%")
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

(defun %store-cli-delete-registry (args)
  (multiple-value-bind (snapshot-ids prefixes created-before created-after dry-run force)
      (%parse-store-delete-registry-args args)
    (format t "~A~%"
            (emit-json
             (if (and (= (length snapshot-ids) 1)
                      (null prefixes)
                      (null created-before)
                      (null created-after))
                 (delete-registry-snapshot (first snapshot-ids) :dry-run dry-run :force force)
                 (delete-registry-snapshots snapshot-ids :dry-run dry-run :force force :prefixes prefixes :created-before created-before :created-after created-after))))))

(defun %store-cli-prune-registry (args)
  (multiple-value-bind (keep-count dry-run force)
      (%parse-store-prune-registry-args args)
    (format t "~A~%" (emit-json (prune-registry-snapshots keep-count :dry-run dry-run :force force)))))

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
     (%store-cli-delete-registry (rest args)))
    ((string= (first args) "prune-registry")
     (%store-cli-prune-registry (rest args)))
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