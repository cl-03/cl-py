(in-package #:cl-py.internal)

(defstruct adapter
  id
  manifest-version
  name
  upstream-url
  license
  python-module
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
  (or (find adapter-id *adapter-registry* :key #'adapter-id :test #'string=)
      (error 'cl-py:adapter-not-found
             :message "Adapter was not found"
             :adapter-id adapter-id)))

(in-package #:cl-py)

(defun list-adapters ()
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
          :python-requirement (adapter-python-requirement adapter)
          :capabilities (adapter-capabilities adapter)
          :summary (cl-py.internal:adapter-summary adapter))))

(defun adapter-module-version (adapter-id)
  (let* ((adapter (cl-py.internal:find-adapter-or-die adapter-id))
         (module (adapter-python-module adapter))
         (lines (cl-py.internal:call-python-lines
                 (format nil
                         "import importlib.metadata~%print(importlib.metadata.version(~S))"
                         module))))
    (first lines)))

  (cl-py.internal:load-adapter-manifests)
