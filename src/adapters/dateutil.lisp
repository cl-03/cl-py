(in-package #:cl-py)

(defun parse-dateutil-isodatetime (value)
  (let ((lines (apply #'cl-py.internal:call-python-lines
                      "from dateutil.parser import isoparse~%import sys~%print(isoparse(sys.argv[1]).isoformat())"
                      (list value))))
    (first lines)))