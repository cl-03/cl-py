(in-package #:cl-py.internal)

(defun print-cli-usage ()
  (format t "cl-py development CLI~%~%")
  (format t "Commands:~%")
  (format t "  registry~%")
  (format t "  packaging metadata~%")
  (format t "  packaging version~%")
  (format t "  packaging normalize-version <value>~%"))
