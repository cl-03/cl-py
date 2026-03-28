(in-package #:cl-py)

(defun normalize-packaging-version (value)
  (let ((lines (apply #'cl-py.internal:call-python-lines
                      "from packaging.version import Version~%import sys~%print(str(Version(sys.argv[1])))"
                      (list value))))
    (first lines)))
