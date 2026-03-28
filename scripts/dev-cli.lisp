(require "asdf")

(let* ((root (uiop:pathname-parent-directory-pathname (uiop:pathname-parent-directory-pathname *load-truename*)))
       (system (merge-pathnames "cl-py.asd" root)))
  (asdf:load-asd system)
  (asdf:load-system #:cl-py)
  (cl-py:main))
