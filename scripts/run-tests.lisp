(require "asdf")

(let* ((root (uiop:pathname-parent-directory-pathname *load-truename*))
       (system-a (merge-pathnames "cl-py.asd" root))
       (system-b (merge-pathnames "cl-py-tests.asd" root)))
     (load system-a)
     (load system-b)
   (asdf:load-system "cl-py-tests")
   (uiop:symbol-call :cl-py-tests :run-tests))
