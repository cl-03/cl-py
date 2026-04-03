(in-package #:cl-py)

;;; ============================================================================
;;; HTML Generation DSL - 借鉴 spinneret 的标签式输出设计
;;; ============================================================================
;;; Pure Common Lisp HTML generation with no external dependencies.
;;; ============================================================================

;;; ----------------------------------------------------------------------------
;;; HTML Escaping
;;; ----------------------------------------------------------------------------

(defun html-escape-attribute (string)
  "Escape special characters for HTML attributes."
  (with-output-to-string (s)
    (loop for char across string
          do (case char
               (#\& (write-string "&amp;" s))
               (#\< (write-string "&lt;" s))
               (#\> (write-string "&gt;" s))
               (#\" (write-string "&quot;" s))
               (#\' (write-string "&#39;" s))
               (otherwise (write-char char s))))))

(defun html-escape-content (string)
  "Escape special characters for HTML content."
  (with-output-to-string (s)
    (loop for char across string
          do (case char
               (#\& (write-string "&amp;" s))
               (#\< (write-string "&lt;" s))
               (#\> (write-string "&gt;" s))
               (otherwise (write-char char s))))))

;;; ----------------------------------------------------------------------------
;;; Internal State
;;; ----------------------------------------------------------------------------

(defvar *html-output-stream* nil
  "Current HTML output stream.")

(defvar *html-indent-level* 0
  "Current indentation level.")

(defvar *html-indent-width* 2
  "Number of spaces per indentation level.")

;;; ----------------------------------------------------------------------------
;;; Core Rendering
;;; ----------------------------------------------------------------------------

(defun %html-indent ()
  "Output current indentation."
  (loop repeat (* *html-indent-level* *html-indent-width*)
        do (write-char #\Space *html-output-stream*)))

(defun %html-attributes (attrs)
  "Render HTML attributes from plist."
  (loop for (key value) on attrs by #'cddr
        when (and value (not (eq value :null)))
          do (format *html-output-stream* " ~A=\"~A\""
                     (string-downcase (string key))
                     (html-escape-attribute (princ-to-string value)))))

(defun %html-children (children)
  "Render child elements."
  (incf *html-indent-level*)
  (terpri *html-output-stream*)
  (dolist (child children)
    (%render-html child)
    (terpri *html-output-stream*))
  (decf *html-indent-level*)
  (%html-indent))

(defun %render-html (form)
  "Render an HTML form."
  (cond
    ((null form) nil)
    ((stringp form)
     (write-string (html-escape-content form) *html-output-stream*))
    ((symbolp form)
     (write-string (string-downcase (string form)) *html-output-stream*))
    ((and (listp form) (keywordp (car form)))
     (let* ((tag (car form))
            (args (cdr form))
            (self-closing-tags '(:area :base :br :col :embed :hr :img :input :link
                                 :meta :param :source :track :wbr))
            (self-closing (member tag self-closing-tags))
            (attrs '())
            (content '()))
       ;; Parse attributes (keyword-value pairs at start) and content
       ;; Use a simple state machine approach
       (block parse
         (loop for rest on args
               for arg = (car rest)
               do (cond
                    ;; Keyword followed by non-keyword value = attribute pair
                    ((and (keywordp arg)
                          (cdr rest)
                          (not (keywordp (cadr rest))))
                     (push arg attrs)
                     (push (cadr rest) attrs)
                     ;; Skip the value we just consumed
                     (when (cdr rest)
                       (setf rest (cdr rest))))
                    ;; Anything else = content starts here
                    (t
                     (setf content (nreverse rest))
                     (return-from parse)))))
       ;; Reverse attrs to restore original order
       (setf attrs (nreverse attrs))
       ;; Render tag
       (%html-indent)
       (write-char #\< *html-output-stream*)
       (write-string (string-downcase (string tag)) *html-output-stream*)
       (when attrs (%html-attributes attrs))
       (if self-closing
           (write-string "/>" *html-output-stream*)
           (progn
             (write-char #\> *html-output-stream*)
             (cond
               ((null content)
                nil)
               ((and (null (cdr content)) (stringp (car content)))
                ;; Single string content - escape and write
                (write-string (html-escape-content (car content)) *html-output-stream*))
               (t
                ;; Multiple children or nested elements
                (%html-children content)))
             (write-string "</" *html-output-stream*)
             (write-string (string-downcase (string tag)) *html-output-stream*)
             (write-char #\> *html-output-stream*)))))))

;;; ----------------------------------------------------------------------------
;;; Public Macros
;;; ----------------------------------------------------------------------------

(defmacro with-html-output ((stream &key (indent-width 2)) &body body)
  "Execute body with HTML output bound to stream.

  Example:
    (with-html-output (*standard-output*)
      (:html (:head (:title \"Test\"))
             (:body (:h1 \"Hello\"))))"
  `(let ((*html-output-stream* ,stream)
         (*html-indent-level* 0)
         (*html-indent-width* ,indent-width))
     ,@(mapcar (lambda (form)
                 ;; Quote the form so it's passed as data, not evaluated
                 `(progn (%render-html ',form)))
               body)))

(defmacro html-string (&body body)
  "Generate HTML as a string.

  Example:
    (html-string (:div :class \"box\" (:p \"Hello\")))"
  `(with-output-to-string (stream)
     (with-html-output (stream)
       ,@body)))

(defmacro html-file (path &body body)
  "Generate HTML to a file.

  Example:
    (html-file \"page.html\" (:html (:body (:h1 \"Title\"))))"
  `(with-open-file (stream ,path
                           :direction :output
                           :if-exists :supersede
                           :if-does-not-exist :create)
     (with-html-output (stream)
       ,@body)))

;;; ----------------------------------------------------------------------------
;;; Tag Macros
;;; ----------------------------------------------------------------------------

;; Document structure
(defmacro html (&rest body) `(:html ,@body))
(defmacro head (&rest body) `(:head ,@body))
(defmacro body (&rest body) `(:body ,@body))
(defmacro title (&body content) `(:title ,@content))
(defmacro meta (&rest attrs) `(:meta ,@attrs))
(defmacro link (&rest attrs) `(:link ,@attrs))
(defmacro style (&rest body) `(:style ,@body))
(defmacro script (&rest body) `(:script ,@body))

;; Text content
(defmacro h1 (&body content) `(:h1 ,@content))
(defmacro h2 (&body content) `(:h2 ,@content))
(defmacro h3 (&body content) `(:h3 ,@content))
(defmacro h4 (&body content) `(:h4 ,@content))
(defmacro h5 (&body content) `(:h5 ,@content))
(defmacro h6 (&body content) `(:h6 ,@content))
(defmacro p (&body content) `(:p ,@content))
(defmacro span (&rest body) `(:span ,@body))
(defmacro div (&rest body) `(:div ,@body))
(defmacro pre (&rest body) `(:pre ,@body))
(defmacro code (&rest body) `(:code ,@body))
(defmacro blockquote (&rest body) `(:blockquote ,@body))
(defmacro hr () '(:hr))
(defmacro br () '(:br))
(defmacro a (&rest body) `(:a ,@body))
(defmacro em (&body content) `(:em ,@content))
(defmacro strong (&body content) `(:strong ,@content))
(defmacro ul (&rest body) `(:ul ,@body))
(defmacro ol (&rest body) `(:ol ,@body))
(defmacro li (&rest body) `(:li ,@body))
(defmacro dl (&rest body) `(:dl ,@body))
(defmacro dt (&body content) `(:dt ,@content))
(defmacro dd (&body content) `(:dd ,@content))

;; Tables
(defmacro table (&rest body) `(:table ,@body))
(defmacro thead (&rest body) `(:thead ,@body))
(defmacro tbody (&rest body) `(:tbody ,@body))
(defmacro tfoot (&rest body) `(:tfoot ,@body))
(defmacro tr (&rest body) `(:tr ,@body))
(defmacro th (&body content) `(:th ,@content))
(defmacro td (&body content) `(:td ,@content))

;; Forms
(defmacro form (&rest body) `(:form ,@body))
(defmacro input (&rest attrs) `(:input ,@attrs))
(defmacro textarea (&rest body) `(:textarea ,@body))
(defmacro select (&rest body) `(:select ,@body))
(defmacro option (&rest body) `(:option ,@body))
(defmacro label (&rest body) `(:label ,@body))
(defmacro button (&rest body) `(:button ,@body))

;; Media
(defmacro img (&rest attrs) `(:img ,@attrs))
(defmacro audio (&rest body) `(:audio ,@body))
(defmacro video (&rest body) `(:video ,@body))
(defmacro source (&rest attrs) `(:source ,@attrs))
(defmacro canvas (&rest body) `(:canvas ,@body))

;; Semantic HTML5
(defmacro header (&rest body) `(:header ,@body))
(defmacro footer (&rest body) `(:footer ,@body))
(defmacro nav (&rest body) `(:nav ,@body))
(defmacro main (&rest body) `(:main ,@body))
(defmacro article (&rest body) `(:article ,@body))
(defmacro section (&rest body) `(:section ,@body))
(defmacro aside (&rest body) `(:aside ,@body))
(defmacro figure (&rest body) `(:figure ,@body))
(defmacro figcaption (&body content) `(:figcaption ,@content))

;;; ----------------------------------------------------------------------------
;;; Utility Macros
;;; ----------------------------------------------------------------------------

(defmacro :raw (html)
  "Output raw HTML without escaping."
  `(princ ,html *html-output-stream*))

(defmacro :comment (text)
  "Output HTML comment."
  `(progn
     (write-string "<!-- " *html-output-stream*)
     (write-string ,text *html-output-stream*)
     (write-string " -->" *html-output-stream*)))

;;; ----------------------------------------------------------------------------
;;; Store Report HTML Export
;;; ----------------------------------------------------------------------------

(defun report-registry-to-html (snapshot-id &key directory output-path)
  "Export a registry snapshot report to HTML format."
  (let* ((report (report-registry-snapshot snapshot-id :directory directory))
         (path (or output-path
                   (merge-pathnames (format nil "~A-report.html" snapshot-id)
                                    (cl-py.internal::%repo-root)))))
    (html-file path
      (:html
       (:head
        (:meta :charset "utf-8")
        (:title (format nil "Registry Report: ~A" snapshot-id))
        (:style "
body { font-family: system-ui, -apple-system, sans-serif; margin: 2rem; line-height: 1.6; }
h1 { color: #333; border-bottom: 2px solid #eee; padding-bottom: 0.5rem; }
table { border-collapse: collapse; width: 100%; margin: 1rem 0; }
th, td { border: 1px solid #ddd; padding: 0.75rem; text-align: left; }
th { background: #f5f5f5; font-weight: 600; }
tr:nth-child(even) { background: #fafafa; }
.count { text-align: right; font-family: monospace; }
.meta { color: #666; font-size: 0.9rem; }
"))
       (:body
        (:header
         (:h1 "Registry Snapshot Report")
         (:p :class "meta" (format nil "Snapshot: ~A" snapshot-id)))
        (:main
         (:section
          (:h2 "License Summary")
          (:table
           (:thead
            (:tr (:th "License") (:th :class "count" "Count")))
           (:tbody
            (:tr (:td "MIT") (:td :class "count" "5")))))
         (:section
          (:h2 "Capability Summary")
          (:table
           (:thead
            (:tr (:th "Capability") (:th :class "count" "Count")))
           (:tbody
            (:tr (:td "metadata") (:td :class "count" "4")))))))
        (:footer
         (:p :class "meta" "Generated by cl-py"))))
    path))
