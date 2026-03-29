(in-package #:cl-py)

(defun validate-jsonschema-instance (schema-json instance-json)
  (let ((lines (apply #'cl-py.internal:call-python-lines
                      (concatenate
                       'string
                       "import json, sys~%"
                       "import jsonschema~%"
                       "schema = json.loads(sys.argv[1])~%"
                       "instance = json.loads(sys.argv[2])~%"
                       "jsonschema.validate(instance=instance, schema=schema)~%"
                       "print('valid')")
                      (list schema-json instance-json))))
    (first lines)))

(cl-py.internal:register-cli-command
 "jsonschema"
 "validate-instance"
 #'validate-jsonschema-instance
 :usage "validate-instance <schema-json> <instance-json>"
 :summary "Validate a JSON instance against a JSON Schema"
 :min-args 2)