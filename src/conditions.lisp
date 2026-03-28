(in-package #:cl-py)

(define-condition adapter-error (error)
  ((message :initarg :message :reader adapter-error-message))
  (:report (lambda (condition stream)
             (write-string (adapter-error-message condition) stream))))

(define-condition adapter-not-found (adapter-error)
  ((adapter-id :initarg :adapter-id :reader missing-adapter-id))
  (:report (lambda (condition stream)
             (format stream "Unknown adapter: ~A" (missing-adapter-id condition)))))

(define-condition python-execution-error (adapter-error)
  ((command :initarg :command :reader failed-command)
   (output :initarg :output :reader failed-output))
  (:report (lambda (condition stream)
             (format stream "Python execution failed.~%Command: ~A~%Output:~%~A"
                     (failed-command condition)
                     (failed-output condition)))))
