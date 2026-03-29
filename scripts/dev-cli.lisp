(require "asdf")

(let* ((root (uiop:pathname-parent-directory-pathname *load-truename*))
       (system (merge-pathnames "cl-py.asd" root)))
     (load system)
     (asdf:load-system "cl-py")
     (uiop:symbol-call :cl-py :main))
