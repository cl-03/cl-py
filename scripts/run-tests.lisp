(require "asdf")

(let* ((root (uiop:pathname-parent-directory-pathname (uiop:pathname-parent-directory-pathname *load-truename*)))
       (system-a (merge-pathnames "cl-py.asd" root))
       (system-b (merge-pathnames "cl-py-tests.asd" root)))
  (asdf:load-asd system-a)
  (asdf:load-asd system-b)
  (asdf:test-system #:cl-py-tests))
