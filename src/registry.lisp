(in-package #:cl-py.internal)

(defstruct adapter
  id
  manifest-version
  name
  upstream-url
  license
  python-module
  python-distribution
  python-requirement
  capabilities
  summary)

(defparameter *adapter-registry* nil)

(defun register-adapter (adapter)
  (setf *adapter-registry*
        (append (remove (adapter-id adapter)
                        *adapter-registry*
                        :key #'adapter-id
                        :test #'string=)
                (list adapter)))
  adapter)

(defun find-adapter-or-die (adapter-id)
  (when (null *adapter-registry*)
    (load-adapter-manifests))
  (or (find adapter-id *adapter-registry* :key #'adapter-id :test #'string=)
      (error 'cl-py:adapter-not-found
             :message "Adapter was not found"
             :adapter-id adapter-id)))

(in-package #:cl-py)

(defun adapter-id (adapter)
  (cl-py.internal:adapter-id adapter))

(defun adapter-manifest-version (adapter)
  (cl-py.internal:adapter-manifest-version adapter))

(defun adapter-name (adapter)
  (cl-py.internal:adapter-name adapter))

(defun adapter-upstream-url (adapter)
  (cl-py.internal:adapter-upstream-url adapter))

(defun adapter-license (adapter)
  (cl-py.internal:adapter-license adapter))

(defun adapter-python-module (adapter)
  (cl-py.internal:adapter-python-module adapter))

(defun adapter-python-distribution (adapter)
  (cl-py.internal:adapter-python-distribution adapter))

(defun adapter-python-requirement (adapter)
  (cl-py.internal:adapter-python-requirement adapter))

(defun adapter-capabilities (adapter)
  (cl-py.internal:adapter-capabilities adapter))

(defun list-adapters ()
  (when (null cl-py.internal:*adapter-registry*)
    (cl-py.internal:load-adapter-manifests))
  cl-py.internal:*adapter-registry*)

(defun find-adapter (adapter-id)
  (find adapter-id (list-adapters) :key #'adapter-id :test #'string=))

(defun adapter-metadata (adapter-id)
  (let ((adapter (cl-py.internal:find-adapter-or-die adapter-id)))
    (list :id (adapter-id adapter)
          :manifest-version (adapter-manifest-version adapter)
          :name (adapter-name adapter)
          :upstream-url (adapter-upstream-url adapter)
          :license (adapter-license adapter)
          :python-module (adapter-python-module adapter)
          :python-distribution (adapter-python-distribution adapter)
          :python-requirement (adapter-python-requirement adapter)
          :capabilities (adapter-capabilities adapter)
          :summary (cl-py.internal:adapter-summary adapter))))

(defun adapter-module-version (adapter-id)
  (let* ((adapter (cl-py.internal:find-adapter-or-die adapter-id))
         (distribution (or (adapter-python-distribution adapter)
                           (adapter-python-module adapter)))
         (lines (cl-py.internal:call-python-lines
                 (format nil
                         "import importlib.metadata~%print(importlib.metadata.version(~S))"
                         distribution))))
    (first lines)))

(cl-py.internal:load-adapter-manifests)
