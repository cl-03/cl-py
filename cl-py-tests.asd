(asdf:defsystem #:cl-py-tests
  :description "Smoke tests for cl-py"
  :author "cl-03"
  :license "MIT"
  :version "0.1.0"
  :depends-on (#:cl-py #:uiop)
  :serial t
  :components ((:file "tests/smoke"))
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (uiop:symbol-call :cl-py-tests :run-tests)))
