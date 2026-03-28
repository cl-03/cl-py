(in-package #:cl-py.internal)

(defun %repo-root ()
  (uiop:pathname-parent-directory-pathname
   (uiop:pathname-parent-directory-pathname
    (or *load-truename* *compile-file-truename*))))

(defun %manifest-directory ()
  (merge-pathnames "adapters/manifests/" (%repo-root)))

(defun %manifest-files ()
  (uiop:directory-files (%manifest-directory) "*.sexp"))

(defun %read-manifest-file (path)
  (with-open-file (stream path :direction :input)
    (read stream nil nil)))

(defun %manifest-value (manifest key path)
  (or (getf manifest key)
      (error 'cl-py:adapter-error
             :message (format nil "Missing manifest key ~A in ~A" key path))))

(defun manifest->adapter (manifest path)
  (make-adapter
   :id (%manifest-value manifest :id path)
   :manifest-version (or (getf manifest :manifest-version) "1.0")
   :name (%manifest-value manifest :name path)
   :upstream-url (%manifest-value manifest :upstream-url path)
   :license (%manifest-value manifest :license path)
   :python-module (%manifest-value manifest :python-module path)
   :python-requirement (%manifest-value manifest :python-requirement path)
   :capabilities (copy-list (%manifest-value manifest :capabilities path))
   :summary (%manifest-value manifest :summary path)))

(defun load-adapter-manifests ()
  (dolist (path (%manifest-files))
    (register-adapter (manifest->adapter (%read-manifest-file path) path)))
  *adapter-registry*)