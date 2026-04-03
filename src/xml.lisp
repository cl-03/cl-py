(in-package #:cl-py)

;;; ============================================================================
;;; XML Processing - Pure Common Lisp XML Parse and Generate
;;; ============================================================================

;;; ----------------------------------------------------------------------------
;;; XML Data Structures
;;; ----------------------------------------------------------------------------

(defstruct xml-element
  "Represents an XML element with tag, attributes, and children."
  (tag "")
  (attributes nil)
  (children nil))

(defstruct xml-text
  "Represents XML text content."
  (content ""))

;;; ----------------------------------------------------------------------------
;;; XML Parsing
;;; ----------------------------------------------------------------------------

(defun %xml-skip-whitespace (text pos)
  "Skip whitespace characters, return new position."
  (loop for i from pos below (length text)
        while (member (char text i) '(#\Space #\Tab #\Newline #\Return))
        finally (return i)))

(defun %xml-parse-attributes (attr-string)
  "Parse XML attributes from a string like 'key=\"value\" key2=\"value2\"'."
  (let ((attrs '())
        (i 0)
        (len (length attr-string)))
    (loop while (< i len)
          do
          ;; Skip whitespace
          (setf i (%xml-skip-whitespace attr-string i))
          ;; Parse attribute name
          (when (< i len)
            (let ((name-start i))
              (loop while (and (< i len)
                               (alphanumericp (char attr-string i))
                               (char/= (char attr-string i) #\=))
                    do (incf i))
              (when (> i name-start)
                (let ((name (subseq attr-string name-start i)))
                  ;; Skip =
                  (when (< i len) (incf i))
                  ;; Skip whitespace
                  (setf i (%xml-skip-whitespace attr-string i))
                  ;; Parse attribute value
                  (when (< i len)
                    (let ((quote-char (char attr-string i))
                          (value-start (1+ i)))
                      (when (member quote-char '(#\" #\'))
                        (incf i)
                        (loop while (and (< i len)
                                         (char/= (char attr-string i) quote-char))
                              do (incf i))
                        (let ((value (subseq attr-string value-start i)))
                          (push (cons name value) attrs))
                        (incf i)))))))))
    (nreverse attrs)))

(defun %xml-strip-comments-and-decl (text)
  "Remove XML comments and declarations from text."
  (let ((result (make-string-output-stream))
        (i 0)
        (len (length text)))
    (loop while (< i len)
          do
          (cond
            ;; Comment <!--
            ((and (<= (+ i 4) len)
                  (char= (char text i) #\<)
                  (char= (char text (1+ i)) #\-)
                  (char= (char text (+ i 2)) #\-)
                  (char= (char text (+ i 3)) #\!))
             (loop for j from (+ i 4) below len
                   when (and (<= (+ j 3) len)
                             (char= (char text j) #\-)
                             (char= (char text (1+ j)) #\-)
                             (char= (char text (+ j 2)) #\>))
                   do (setf i (+ j 3))
                      (return)
                   finally (setf i len)))
            ;; Declaration <?
            ((and (<= (+ i 2) len)
                  (char= (char text i) #\<)
                  (char= (char text (1+ i)) #\?))
             (loop for j from (+ i 2) below len
                   when (and (<= (+ j 2) len)
                             (char= (char text j) #\?)
                             (char= (char text (1+ j)) #\>))
                   do (setf i (+ j 2))
                      (return)
                   finally (setf i len)))
            (t
             (write-char (char text i) result)
             (incf i))))
    (get-output-stream-string result)))

(defun %xml-find-closing-tag (text start tag-name)
  "Find matching closing tag, return position after it."
  (let ((close-tag (format nil "</~A>" tag-name))
        (i start)
        (len (length text)))
    (loop while (< i len)
          do
          (when (and (<= (+ i (length close-tag)) len)
                     (string= close-tag (subseq text i (+ i (length close-tag)))))
            (return-from %xml-find-closing-tag (+ i (length close-tag))))
          (incf i))
    len))

(defun %xml-parse-node (text start)
  "Parse an XML node starting at position START.
Returns (values node end-position)."
  ;; Skip whitespace
  (setf start (%xml-skip-whitespace text start))

  (when (>= start (length text))
    (return-from %xml-parse-node (values nil start)))

  ;; Check for text content
  (when (char/= (char text start) #\<)
    (let ((text-start start))
      (loop for i from start below (length text)
            when (char= (char text i) #\<) do (setf start i) (return))
      ;; If we didn't find any <, set start to end of text
      (when (= start text-start)
        (setf start (length text)))
      (let ((content (string-trim '(#\Space #\Tab #\Newline #\Return)
                                  (subseq text text-start start))))
        (if (string= content "")
            (return-from %xml-parse-node
              (%xml-parse-node text start))
            (return-from %xml-parse-node
              (values (make-xml-text :content content) start))))))

  ;; Must be a tag
  (let ((tag-start (1+ start))
        (pos (1+ start))
        (tag-name nil)
        (attributes nil)
        (self-closing nil)
        (children nil))

    ;; Find >
    (loop while (and (< pos (length text))
                     (char/= (char text pos) #\>))
          do (incf pos))

    (when (>= pos (length text))
      (return-from %xml-parse-node (values nil start)))

    ;; Check for self-closing
    (when (and (> pos tag-start)
               (char= (char text (1- pos)) #\/))
      (setf self-closing t)
      (decf pos))

    ;; Parse tag name and attributes
    (let* ((tag-string (subseq text tag-start pos))
           (space-pos (position #\Space tag-string)))
      (if space-pos
          (let ((name (subseq tag-string 0 space-pos))
                (attr-str (subseq tag-string (1+ space-pos))))
            (setf tag-name name)
            (setf attributes (%xml-parse-attributes attr-str)))
          (progn
            (setf tag-name tag-string)
            (setf attributes nil))))

    ;; Check if this is a closing tag (starts with /)
    (when (and (> (length tag-name) 0)
               (char= (char tag-name 0) #\/))
      ;; Return immediately as a closing tag marker
      (return-from %xml-parse-node
        (values (make-xml-element :tag tag-name :attributes attributes :children nil)
                (1+ pos))))

    (if self-closing
        ;; Self-closing tag
        (values (make-xml-element :tag tag-name :attributes attributes :children nil)
                (1+ (1+ pos)))  ; Skip / and >
        ;; Regular tag - parse children
        (progn
          (incf pos) ;; Skip >
          (loop
            (when (>= pos (length text))
              ;; Unexpected end of input
              (return-from %xml-parse-node
                (values (make-xml-element :tag tag-name
                                          :attributes attributes
                                          :children (nreverse children))
                        pos)))
            (multiple-value-bind (child new-pos) (%xml-parse-node text pos)
              (cond
                ((null child)
                 ;; End of input or error - return what we have
                 (return-from %xml-parse-node
                   (values (make-xml-element :tag tag-name
                                             :attributes attributes
                                             :children (nreverse children))
                           new-pos)))
                ((and (xml-element-p child)
                      (char= (char (xml-element-tag child) 0) #\/))
                 ;; Closing tag
                 (let ((close-name (subseq (xml-element-tag child) 1)))
                   (if (string= close-name tag-name)
                       (return-from %xml-parse-node
                         (values (make-xml-element :tag tag-name
                                                   :attributes attributes
                                                   :children (nreverse children))
                                 new-pos))
                       ;; Mismatched closing tag - treat as child
                       (push child children))))
                (t
                 ;; Regular child
                 (when child (push child children))
                 (setf pos new-pos)))))))))

(defun parse-xml (text)
  "Parse XML text into an S-expression structure."
  (let ((clean-text (%xml-strip-comments-and-decl text)))
    (multiple-value-bind (element _) (%xml-parse-node clean-text 0)
      (declare (ignore _))
      element)))

;;; ----------------------------------------------------------------------------
;;; XML Generation
;;; ----------------------------------------------------------------------------

(defvar *xml-indent-level* 0)
(defvar *xml-indent-width* 2)

(defun %xml-escape-string (string)
  "Escape special characters for XML content."
  (with-output-to-string (s)
    (loop for char across string
          do (case char
               (#\& (write-string "&amp;" s))
               (#\< (write-string "&lt;" s))
               (#\> (write-string "&gt;" s))
               (#\" (write-string "&quot;" s))
               (#\' (write-string "&apos;" s))
               (otherwise (write-char char s))))))

(defun %xml-indent (stream)
  "Output current indentation to stream."
  (loop repeat (* *xml-indent-level* *xml-indent-width*)
        do (write-char #\Space stream)))

(defun %xml-render-attributes (attrs stream)
  "Render XML attributes from plist."
  (loop for (key . value) in attrs
        do (format stream " ~A=\"~A\"" key (%xml-escape-string value))))

(defun %xml-render-children (children stream)
  "Render child elements."
  (incf *xml-indent-level*)
  (terpri stream)
  (dolist (child children)
    (%render-xml child stream)
    (terpri stream))
  (decf *xml-indent-level*)
  (%xml-indent stream))

(defun %render-xml (node stream)
  "Render an XML node to stream."
  (cond
    ((null node) nil)
    ((xml-text-p node)
     (write-string (%xml-escape-string (xml-text-content node)) stream))
    ((xml-element-p node)
     (let ((tag (xml-element-tag node))
           (attrs (xml-element-attributes node))
           (children (xml-element-children node)))
       (%xml-indent stream)
       (write-char #\< stream)
       (write-string tag stream)
       (when attrs (%xml-render-attributes attrs stream))
       (if (null children)
           (write-string "/>" stream)
           (progn
             (write-char #\> stream)
             (cond
               ((null children) nil)
               ((and (null (cdr children)) (xml-text-p (car children)))
                (%render-xml (car children) stream))
               (t (%xml-render-children children stream)))
             (write-string "</" stream)
             (write-string tag stream)
             (write-char #\> stream)))))))

(defun generate-xml (node &optional (stream *standard-output*))
  "Generate XML text from an xml-element or xml-text structure."
  (let ((*xml-indent-level* 0))
    (%render-xml node stream)))

(defun xml-to-string (node)
  "Generate XML as a string."
  (with-output-to-string (stream)
    (generate-xml node stream)))

;;; ----------------------------------------------------------------------------
;;; S-expression XML API
;;; ----------------------------------------------------------------------------

(defmacro xml-string (&body body)
  "Generate XML as a string from S-expression syntax."
  `(with-output-to-string (stream)
     (let ((*xml-indent-level* 0))
       ,@(mapcar (lambda (form) `(progn (%render-xml-form ',form stream))) body))))

(defun %render-xml-form (form stream)
  "Render an S-expression form as XML."
  (cond
    ((null form) nil)
    ((stringp form)
     (write-string (%xml-escape-string form) stream))
    ((symbolp form)
     (write-string (string form) stream))
    ((and (listp form) (keywordp (car form)))
     (let* ((tag (car form))
            (args (cdr form))
            (attrs '())
            (content '()))
       ;; Parse attributes
       (block parse
         (loop for rest on args
               for arg = (car rest)
               do (cond
                    ((and (keywordp arg) (cdr rest) (not (keywordp (cadr rest))))
                     (push (cons (string-downcase (string arg)) (cadr rest)) attrs)
                     (when (cdr rest) (setf rest (cdr rest))))
                    (t (setf content (nreverse rest)) (return-from parse)))))
       (setf attrs (nreverse attrs))
       ;; Render
       (write-char #\< stream)
       (write-string (string-downcase (string tag)) stream)
       (when attrs
         (loop for (key . value) in attrs
               do (format stream " ~A=\"~A\"" key (%xml-escape-string (princ-to-string value)))))
       (if (null content)
           (write-string "/>" stream)
           (progn
             (write-char #\> stream)
             (cond
               ((null content) nil)
               ((and (null (cdr content)) (stringp (car content)))
                (write-string (%xml-escape-string (car content)) stream))
               (t
                (incf *xml-indent-level*)
                (terpri stream)
                (dolist (child content)
                  (%render-xml-form child stream)
                  (terpri stream))
                (decf *xml-indent-level*)
                (%xml-indent stream)))
             (write-string "</" stream)
             (write-string (string-downcase (string tag)) stream)
             (write-char #\> stream)))))))

;;; ----------------------------------------------------------------------------
;;; Query Helpers
;;; ----------------------------------------------------------------------------

(defun xml-find-by-tag (node tag-name &key (recursive t))
  "Find elements by tag name."
  (let ((results nil))
    (labels ((search-node (n)
               (when (xml-element-p n)
                 (when (string= (xml-element-tag n) tag-name)
                   (push n results))
                 (when recursive
                   (dolist (child (xml-element-children n))
                     (search-node child))))))
      (search-node node))
    (nreverse results)))

(defun xml-get-attribute (node attribute-name)
  "Get attribute value from an XML element."
  (when (xml-element-p node)
    (cdr (assoc attribute-name (xml-element-attributes node) :test #'string=))))

(defun xml-get-text (node)
  "Get text content from an XML element."
  (cond
    ((xml-text-p node) (xml-text-content node))
    ((xml-element-p node)
     (with-output-to-string (s)
       (dolist (child (xml-element-children node))
         (when (xml-text-p child)
           (write-string (xml-text-content child) s)))))))
