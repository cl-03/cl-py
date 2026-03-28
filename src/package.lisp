(defpackage #:cl-py
  (:use #:cl)
  (:export
   #:adapter-error
   #:adapter-not-found
   #:python-execution-error
   #:adapter-id
   #:adapter-name
   #:adapter-python-module
   #:adapter-capabilities
   #:list-adapters
   #:find-adapter
   #:adapter-metadata
   #:adapter-module-version
   #:normalize-packaging-version
   #:main))

(defpackage #:cl-py.internal
  (:use #:cl)
  (:import-from #:uiop
                #:command-line-arguments
                #:getenv
                #:run-program)
  (:export
   #:*adapter-registry*
   #:adapter
   #:adapter-id
   #:adapter-name
   #:adapter-python-module
   #:adapter-capabilities
   #:adapter-summary
   #:register-adapter
   #:call-python-lines
   #:find-adapter-or-die
   #:print-cli-usage
   #:string-join))
