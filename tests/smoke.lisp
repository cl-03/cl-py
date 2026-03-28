(defpackage #:cl-py-tests
  (:use #:cl)
  (:import-from #:cl-py
                #:adapter-id
                #:adapter-metadata
                #:find-adapter
                #:list-adapters
                #:normalize-packaging-version)
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
    "packaging adapter is registered"))

(defun %adapter-ids-test ()
  (%check (member "packaging"
      (mapcar #'cl-py:adapter-id (cl-py:list-adapters))
      :test #'string=)
    "registry exposes packaging adapter id"))

(defun %metadata-test ()
  (let ((metadata (cl-py:adapter-metadata "packaging")))
    (%check (string= "packaging" (getf metadata :id))
            "metadata exposes packaging adapter id")
    (%check (member "normalize-version" (getf metadata :capabilities) :test #'string=)
            "metadata exposes normalize-version capability")))

(defun %optional-packaging-integration-test ()
  (handler-case
      (%check (string= "1.0rc1" (normalize-packaging-version "1.0rc1"))
              "packaging integration normalizes version strings")
    (error (condition)
      (declare (ignore condition))
      (format t "SKIP packaging integration requires Python + packaging~%"))))

(defun run-tests ()
  (setf *failures* 0)
  (%adapter-registry-test)
  (%adapter-ids-test)
  (%metadata-test)
  (%optional-packaging-integration-test)
  (when (plusp *failures*)
    (error "Smoke tests failed: ~D" *failures*))
  (format t "All smoke tests completed.~%"))