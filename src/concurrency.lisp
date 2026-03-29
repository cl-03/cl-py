(in-package #:cl-py)

(defun %concurrency-error (message &rest args)
  (error 'adapter-error :message (apply #'format nil message args)))

(defun %validate-max-concurrency (max-concurrency)
  (unless (and (integerp max-concurrency)
               (> max-concurrency 0))
    (%concurrency-error "max-concurrency must be a positive integer, got ~S" max-concurrency))
  max-concurrency)

(defun %task-success-result (index value)
  (list :index index :status "ok" :value value))

(defun %task-error-result (index condition)
  (list :index index :status "error" :message (princ-to-string condition)))

#+sbcl
(defun %run-bounded-task-batch-sbcl (tasks max-concurrency)
  (let* ((task-count (length tasks))
         (results (make-array task-count))
         (semaphore (sb-thread:make-semaphore :count max-concurrency))
         (threads nil))
    (loop for task in tasks
          for index from 0
          do (sb-thread:wait-on-semaphore semaphore)
         (let ((task-fn task)
           (task-index index))
           (push (sb-thread:make-thread
              (lambda ()
            (unwind-protect
                 (handler-case
                 (setf (aref results task-index)
                   (%task-success-result task-index (funcall task-fn)))
               (error (condition)
                 (setf (aref results task-index)
                   (%task-error-result task-index condition))))
              (sb-thread:signal-semaphore semaphore)))
              :name (format nil "cl-py-task-~D" task-index))
             threads)))
    (dolist (thread threads)
      (sb-thread:join-thread thread))
    (coerce results 'list)))

#-sbcl
(defun %run-bounded-task-batch-sbcl (tasks max-concurrency)
  (declare (ignore max-concurrency))
  (loop for task in tasks
        for index from 0
        collect (handler-case
                    (%task-success-result index (funcall task))
                  (error (condition)
                    (%task-error-result index condition)))))

(defun run-bounded-task-batch (tasks &key (max-concurrency 4))
  (%validate-max-concurrency max-concurrency)
  (unless (listp tasks)
    (%concurrency-error "tasks must be a list of zero-argument functions"))
  (dolist (task tasks)
    (unless (functionp task)
      (%concurrency-error "tasks must contain only functions, got ~S" task)))
  (%run-bounded-task-batch-sbcl tasks max-concurrency))

(defun %demo-task-batch ()
  (list (lambda ()
          (sleep 0.05)
          "alpha")
        (lambda ()
          (sleep 0.02)
          "bravo")
        (lambda ()
          (sleep 0.01)
          (%concurrency-error "demo failure for charlie"))
        (lambda ()
          (sleep 0.03)
          "delta")))

(defun %parse-max-concurrency (text)
  (handler-case
      (%validate-max-concurrency (parse-integer text))
    (error ()
      (%concurrency-error "Unable to parse max-concurrency from ~S" text))))

(defun %print-jobs-usage ()
  (format t "  jobs demo-batch [max-concurrency]~%"))

(defun %print-jobs-help ()
  (%print-jobs-usage)
  (format t "~%Behavior:~%")
  (format t "  Runs a deterministic batch of tasks with structured success/error results~%")
  (format t "  Preserves input order in the returned result array~%")
  (format t "~%Examples:~%")
  (format t "  sbcl --script scripts/dev-cli.lisp jobs demo-batch~%")
  (format t "  sbcl --script scripts/dev-cli.lisp jobs demo-batch 2~%"))

(defun %jobs-cli-demo-batch (args)
  (if (> (length args) 1)
      (cl-py.internal:signal-cli-usage-error
       "jobs demo-batch accepts at most one max-concurrency argument"
       #'%print-jobs-usage)
      (let* ((max-concurrency (if args
                                  (%parse-max-concurrency (first args))
                                  2))
             (results (run-bounded-task-batch (%demo-task-batch)
                                              :max-concurrency max-concurrency)))
        (format t "~A~%"
                (emit-json
             (coerce
              (mapcar (lambda (result)
                  (append (list :object
                          (cons "index" (getf result :index))
                          (cons "status" (getf result :status)))
                      (if (string= "ok" (getf result :status))
                        (list (cons "value" (getf result :value)))
                        (list (cons "message" (getf result :message))))))
                  results)
              'vector))))))

(defun dispatch-jobs-command (args)
  (cond
    ((null args)
     (cl-py.internal:signal-cli-usage-error "jobs requires a subcommand" #'%print-jobs-usage))
    ((cl-py.internal:help-flag-p (first args))
     (%print-jobs-help))
    ((string= (first args) "demo-batch")
     (%jobs-cli-demo-batch (rest args)))
    (t
     (cl-py.internal:signal-cli-usage-error
      (format nil "Unknown jobs subcommand: ~A" (first args))
      #'%print-jobs-usage))))

(cl-py.internal:register-top-level-cli-command
 "jobs"
 #'dispatch-jobs-command
 :usage "jobs <subcommand>"
 :summary "Run bounded task batches with ordered structured results"
 :detail-printer #'%print-jobs-help)