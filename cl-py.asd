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
               (:file "src/manifest")
               (:file "src/registry")
               (:file "src/adapter")
               (:file "src/cli-util")
               (:file "src/json")
               (:file "src/time")
               (:file "src/uri-http")
               (:file "src/yaml")
               (:file "src/store")
               (:file "src/concurrency")
               (:file "src/adapters/packaging")
               (:file "src/adapters/dateutil")
               (:file "src/adapters/slugify")
               (:file "src/adapters/jsonschema")
               (:file "src/cli")))
