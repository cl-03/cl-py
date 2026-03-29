(defpackage #:cl-py
  (:use #:cl)
  (:export
   #:adapter-error
   #:adapter-not-found
   #:python-execution-error
   #:adapter-id
    #:adapter-manifest-version
   #:adapter-name
    #:adapter-upstream-url
    #:adapter-license
   #:adapter-python-module
     #:adapter-python-distribution
    #:adapter-python-requirement
   #:adapter-capabilities
   #:list-adapters
   #:find-adapter
   #:adapter-metadata
   #:adapter-module-version
   #:parse-json
   #:emit-json
   #:normalize-json
   #:parse-iso-timestamp
   #:format-iso-timestamp
   #:normalize-packaging-version
     #:parse-dateutil-isodatetime
     #:slugify-text
    #:validate-jsonschema-instance
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
        #:adapter-manifest-version
   #:adapter-name
        #:adapter-upstream-url
        #:adapter-license
   #:adapter-python-module
     #:adapter-python-distribution
        #:adapter-python-requirement
   #:adapter-capabilities
   #:adapter-summary
   #:register-adapter
        #:load-adapter-manifests
     #:register-cli-command
     #:dispatch-adapter-command
   #:call-python-lines
   #:find-adapter-or-die
   #:print-cli-usage
   #:string-join))
