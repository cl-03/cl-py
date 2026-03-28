(asdf:defsystem #:cl-py
  :description "Common Lisp-first adapters for selected Python libraries"
  :author "cl-03"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on (#:uiop)
  :components ((:file "src/package")
               (:file "src/conditions")
               (:file "src/process")
               (:file "src/registry")
               (:file "src/adapter")
               (:file "src/adapters/packaging")
               (:file "src/cli")))
