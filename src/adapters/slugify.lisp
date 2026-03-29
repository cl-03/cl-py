(in-package #:cl-py)

(defun slugify-text (value)
  (let ((lines (apply #'cl-py.internal:call-python-lines
                      "from slugify import slugify~%import sys~%print(slugify(sys.argv[1]))"
                      (list value))))
    (first lines)))

(cl-py.internal:register-cli-command
 "slugify"
 "slugify-text"
 #'slugify-text
 :usage "slugify-text <value>"
 :summary "Convert text into a URL-friendly slug via python-slugify"
 :min-args 1)