(defpackage #:cl-py-tests
  (:use #:cl)
  (:import-from #:cl-py
                #:adapter-id
                #:adapter-metadata
                #:find-adapter
                #:list-adapters
                #:normalize-packaging-version
                #:parse-dateutil-isodatetime
                #:slugify-text
                #:validate-jsonschema-instance)
  (:export #:run-tests))

(in-package #:cl-py-tests)

(defvar *failures* 0)

(defun %check (condition description)
  (format t "~:[FAIL~;PASS~] ~A~%" condition description)
  (unless condition
    (incf *failures*)))

(defun %adapter-registry-test ()
  (%check (plusp (length (cl-py:list-adapters)))
          "registry contains at least one adapter")
  (%check (not (null (cl-py:find-adapter "packaging")))
          "packaging adapter is registered")
  (%check (not (null (cl-py:find-adapter "dateutil")))
          "dateutil adapter is registered")
  (%check (not (null (cl-py:find-adapter "slugify")))
          "slugify adapter is registered")
  (%check (not (null (cl-py:find-adapter "jsonschema")))
          "jsonschema adapter is registered"))

(defun %adapter-ids-test ()
  (%check (member "packaging"
                  (mapcar #'cl-py:adapter-id (cl-py:list-adapters))
                  :test #'string=)
          "registry exposes packaging adapter id")
  (%check (member "dateutil"
                  (mapcar #'cl-py:adapter-id (cl-py:list-adapters))
                  :test #'string=)
          "registry exposes dateutil adapter id")
  (%check (member "slugify"
                  (mapcar #'cl-py:adapter-id (cl-py:list-adapters))
                  :test #'string=)
          "registry exposes slugify adapter id")
  (%check (member "jsonschema"
                  (mapcar #'cl-py:adapter-id (cl-py:list-adapters))
                  :test #'string=)
          "registry exposes jsonschema adapter id"))

(defun %packaging-metadata-test ()
  (let ((metadata (cl-py:adapter-metadata "packaging")))
    (%check (string= "packaging" (getf metadata :id))
            "metadata exposes packaging adapter id")
    (%check (string= "1.0" (getf metadata :manifest-version))
            "metadata exposes packaging manifest version")
    (%check (search "github.com/pypa/packaging" (getf metadata :upstream-url))
            "metadata exposes packaging upstream URL")
    (%check (string= "packaging" (getf metadata :python-distribution))
            "metadata exposes packaging distribution name")
    (%check (string= "packaging>=24.0,<26.0" (getf metadata :python-requirement))
            "metadata exposes packaging requirement range")
    (%check (member "normalize-version" (getf metadata :capabilities) :test #'string=)
            "metadata exposes normalize-version capability")))

(defun %dateutil-metadata-test ()
  (let ((metadata (cl-py:adapter-metadata "dateutil")))
    (%check (string= "dateutil" (getf metadata :id))
            "metadata exposes dateutil adapter id")
    (%check (string= "1.0" (getf metadata :manifest-version))
            "metadata exposes dateutil manifest version")
    (%check (search "github.com/dateutil/dateutil" (getf metadata :upstream-url))
            "metadata exposes dateutil upstream URL")
    (%check (string= "python-dateutil" (getf metadata :python-distribution))
            "metadata exposes dateutil distribution name")
    (%check (string= "python-dateutil>=2.9,<3.0" (getf metadata :python-requirement))
            "metadata exposes dateutil requirement range")
    (%check (member "parse-isodatetime" (getf metadata :capabilities) :test #'string=)
            "metadata exposes parse-isodatetime capability")))

(defun %slugify-metadata-test ()
  (let ((metadata (cl-py:adapter-metadata "slugify")))
    (%check (string= "slugify" (getf metadata :id))
            "metadata exposes slugify adapter id")
    (%check (string= "1.0" (getf metadata :manifest-version))
            "metadata exposes slugify manifest version")
    (%check (search "github.com/un33k/python-slugify" (getf metadata :upstream-url))
            "metadata exposes slugify upstream URL")
    (%check (string= "python-slugify" (getf metadata :python-distribution))
            "metadata exposes slugify distribution name")
    (%check (string= "python-slugify>=8.0,<9.0" (getf metadata :python-requirement))
            "metadata exposes slugify requirement range")
    (%check (member "slugify-text" (getf metadata :capabilities) :test #'string=)
            "metadata exposes slugify-text capability")))

(defun %jsonschema-metadata-test ()
  (let ((metadata (cl-py:adapter-metadata "jsonschema")))
    (%check (string= "jsonschema" (getf metadata :id))
            "metadata exposes jsonschema adapter id")
    (%check (string= "1.0" (getf metadata :manifest-version))
            "metadata exposes jsonschema manifest version")
    (%check (search "github.com/python-jsonschema/jsonschema" (getf metadata :upstream-url))
            "metadata exposes jsonschema upstream URL")
    (%check (string= "jsonschema" (getf metadata :python-distribution))
            "metadata exposes jsonschema distribution name")
    (%check (string= "jsonschema>=4.0,<5.0" (getf metadata :python-requirement))
            "metadata exposes jsonschema requirement range")
    (%check (member "validate-instance" (getf metadata :capabilities) :test #'string=)
            "metadata exposes validate-instance capability")))

(defun %optional-packaging-integration-test ()
  (handler-case
      (%check (string= "1.0rc1" (normalize-packaging-version "1.0rc1"))
              "packaging integration normalizes version strings")
    (error (condition)
      (declare (ignore condition))
      (format t "SKIP packaging integration requires Python + packaging~%"))))

(defun %optional-dateutil-integration-test ()
  (handler-case
      (%check (string= "2026-03-29T10:20:30+00:00"
                       (parse-dateutil-isodatetime "2026-03-29T10:20:30+00:00"))
              "dateutil integration parses ISO datetimes")
    (error (condition)
      (declare (ignore condition))
      (format t "SKIP dateutil integration requires Python + python-dateutil~%"))))

(defun %optional-slugify-integration-test ()
  (handler-case
      (%check (string= "hello-common-lisp"
                       (slugify-text "Hello Common Lisp"))
              "slugify integration creates URL-friendly slugs")
    (error (condition)
      (declare (ignore condition))
      (format t "SKIP slugify integration requires Python + python-slugify~%"))))

(defun %optional-jsonschema-integration-test ()
        (handler-case
                        (%check (string= "valid"
                                                                                         (validate-jsonschema-instance
                                                                                                "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},\"required\":[\"name\"]}"
                                                                                                "{\"name\":\"cl-py\"}"))
                                                        "jsonschema integration validates a JSON instance")
                (error (condition)
                        (declare (ignore condition))
                        (format t "SKIP jsonschema integration requires Python + jsonschema~%"))))

(defun run-tests ()
  (setf *failures* 0)
  (%adapter-registry-test)
  (%adapter-ids-test)
  (%packaging-metadata-test)
  (%dateutil-metadata-test)
  (%slugify-metadata-test)
        (%jsonschema-metadata-test)
  (%optional-packaging-integration-test)
  (%optional-dateutil-integration-test)
  (%optional-slugify-integration-test)
        (%optional-jsonschema-integration-test)
  (when (plusp *failures*)
    (error "Smoke tests failed: ~D" *failures*))
  (format t "All smoke tests completed.~%"))