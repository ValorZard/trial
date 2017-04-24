#|
 This file is a part of trial
 (c) 2016 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.fraf.trial)
(in-readtable :qtools)

(defvar *context* NIL)

(defmacro with-context ((context &key force reentrant) &body body)
  (let* ((cont (gensym "CONTEXT"))
         (acquiring-body `(progn
                            (acquire-context ,cont :force ,force)
                            (unwind-protect
                                 (progn ,@body)
                              (release-context ,cont :reentrant ,reentrant)))))
    `(let ((,cont ,context))
       ,(if reentrant
            acquiring-body
            `(if (eql *context* ,cont)
                 (progn ,@body)
                 (let ((*context* *context*))
                   ,acquiring-body))))))

(define-widget context (QGLWidget)
  ((glformat :initform NIL :reader glformat)
   (glcontext :initform NIL :reader glcontext)
   (current-thread :initform NIL :accessor current-thread)
   (waiting :initform 0 :accessor context-waiting)
   (lock :initform (bt:make-lock "Context lock") :reader context-lock)
   (wait-lock :initform (bt:make-lock "Context wait lock") :reader context-wait-lock)
   (context-needs-recreation :initform NIL :accessor context-needs-recreation)
   (assets :initform (make-hash-table :test 'eq) :accessor assets)))

(defmethod print-object ((context context) stream)
  (print-unreadable-object (context stream :type T :identity T)))

(defmethod construct ((context context))
  (new context (glformat context))
  (let ((glcontext (q+:context context)))
    (if (q+:is-valid glcontext)
        (v:info :trial.context "~a successfully created context." context)
        (error "Failed to create context."))
    (acquire-context context)
    (context-note-debug-info context)))

(defmethod shared-initialize :after ((context context)
                                     slots
                                     &key (accumulation-buffer NIL)
                                          (alpha-buffer T)
                                          (depth-buffer T)
                                          (stencil-buffer T)
                                          (stereo-buffer NIL)
                                          (direct-rendering T)
                                          (double-buffering T)
                                          (overlay NIL)
                                          (plane 0)
                                          (multisampling T)
                                          (samples 1)
                                          (swap-interval 0)
                                          (profile :core)
                                          (version '(3 3)))
  (let ((initialized (glformat context)))
    (unless initialized (setf (slot-value context 'glformat) (q+:make-qglformat)))
    (macrolet ((format-set (value &optional (accessor value))
                 (let ((keyword (intern (string value) :keyword)))
                   `(cond ((eql :keep ,value))
                          ((not initialized) (setf (,accessor context) ,value))
                          (T (setf (,accessor context) ,value))))))
      (format-set accumulation-buffer)
      (format-set alpha-buffer)
      (format-set depth-buffer)
      (format-set stencil-buffer)
      (format-set stereo-buffer)
      (format-set direct-rendering)
      (format-set double-buffering)
      (format-set overlay)
      (format-set plane)
      (format-set multisampling)
      (format-set samples)
      (format-set swap-interval)
      (format-set version)
      (format-set profile))))

(defmethod initialize-instance :after ((context context) &key)
  (setf (context-needs-recreation context) NIL)
  (setf (q+:updates-enabled context) NIL)
  (setf (q+:auto-buffer-swap context) NIL)
  (setf (q+:focus-policy context) (q+:qt.strong-focus))
  (setf (q+:mouse-tracking context) T))

(defmethod reinitialize-instance :after ((context context) &key)
  (when (context-needs-recreation context)
    (with-context (context)
      (destroy-context context)
      (create-context context))))

(defmacro define-context-accessor (name reader &optional (writer reader))
  `(progn (defmethod ,name ((context context))
            (q+ ,reader (glformat context)))
          (defmethod (setf ,name) (value (context context))
            (setf (q+ ,writer (glformat context)) value)
            (setf (context-needs-recreation context) T)
            value)))

(define-context-accessor accumulation-buffer accum)
(define-context-accessor alpha-buffer alpha)
(define-context-accessor depth-buffer depth)
(define-context-accessor stencil-buffer stencil)
(define-context-accessor stereo-buffer stereo)
(define-context-accessor direct-rendering direct-rendering)
(define-context-accessor double-buffering double-buffer)
(define-context-accessor overlay has-overlay overlay)
(define-context-accessor plane plane)
(define-context-accessor multisampling sample-buffers)
(define-context-accessor samples samples)
(define-context-accessor swap-interval swap-interval)

(defmethod profile ((context context))
  (qtenumcase (q+:profile (glformat context))
    ((q+:qglformat.no-profile) NIL)
    ((q+:qglformat.core-profile) :core)
    ((q+:qglformat.compatibility-profile) :compatibility)))

(defmethod (setf profile) (profile (context context))
  (setf (q+:profile (glformat context))
        (ecase profile
          (NIL (q+:qglformat.no-profile))
          (:core (q+:qglformat.core-profile))
          (:compatibility (q+:qglformat.compatibility-profile))))
  (setf (context-needs-recreation context) T)
  profile)

(defmethod version ((context context))
  (list (q+:major-version (glformat context))
        (q+:minor-version (glformat context))))

(defmethod (setf version) (version (context context))
  (setf (q+:version (glformat context)) (values (first version) (second version)))
  (setf (context-needs-recreation context) T)
  version)

(defmethod finalize ((context context))
  (destroy-context context)
  (call-next-method)
  (finalize (glformat context)))

(defmethod destroy-context :around ((context context))
  (with-context (context)
    (call-next-method)))

(defmethod destroy-context ((context context))
  (when (q+:is-valid context)
    (v:info :trial.context "Destroying context.")
    (q+:hide context)
    (clear-asset-cache)
    (loop for asset being the hash-values of (assets context)
          do (offload asset))
    (q+:reset (q+:context context))))

(defmethod create-context :around ((context context))
  (with-context (context)
    (call-next-method)))

(defmethod create-context ((context context))
  (unless (q+:is-valid context)
    (if (q+:create (q+:context context))
        (v:info :trial.context "Recreated context successfully.")
        (error "Failed to recreate context. Game over."))
    (q+:make-current context)
    (context-note-debug-info context)
    (setf (context-needs-recreation context) NIL)
    (dolist (pool (pools))
      (dolist (asset (assets pool))
        (let ((resource (resource asset)))
          (when resource
            (setf (slot-value resource 'data) (load-data asset))))))
    (q+:show context)))

(defmethod (setf parent) (parent (context context))
  ;; This is so annoying because Microsoft® Windows®™©
  (with-context (context)
    #+windows (destroy-context context)
    (setf (q+:parent context) parent)
    #+windows (create-context context)))

(defmethod acquire-context ((context context) &key force)
  (let ((current (current-thread context))
        (this (bt:current-thread)))
    (when (or force (not (eql this current)))
      (cond ((and force current)
             (v:warn :trial.context "~a stealing ~a from ~a." this context current))
            (current
             (bt:with-lock-held ((context-wait-lock context))
               (incf (context-waiting context))
               (v:info :trial.context "~a waiting to acquire ~a (~a in queue)..." this context (context-waiting context)))
             (bt:acquire-lock (context-lock context))
             (bt:with-lock-held ((context-wait-lock context))
               (decf (context-waiting context))))
            (T
             (bt:acquire-lock (context-lock context))))
      (unless (q+:is-valid context)
        (error "Attempting to acquire invalid context ~a" context))
      (v:info :trial.context "~a acquiring ~a." this context)
      (setf (current-thread context) this)
      (setf *context* context)
      (q+:make-current context))))

(defmethod release-context ((context context) &key reentrant)
  (let ((current (current-thread context))
        (this (bt:current-thread)))
    (when (and (eql this current)
               (or (not reentrant) (< 0 (context-waiting context))))
      (cond ((eql *context* context)
             (v:info :trial.context "~a releasing ~a." this context)
             (setf (current-thread context) NIL)
             (when (q+:is-valid context)
               (q+:done-current context))
             (bt:release-lock (context-lock context))
             (setf *context* NIL))
            (T
             (v:warn :trial.context "~a attempted to release ~a even through ~a is active."
                     this context *context*))))))

(defmethod describe-object :after ((context context) stream)
  (context-info context stream))

(defun context-info (context stream)
  (format stream "~&~%Running GL~a.~a ~a~%~
                    Sample buffers:     ~a (~a sample~:p)~%~
                    Max texture size:   ~a~%~
                    Max texture units:  ~a ~a ~a ~a ~a ~a~%~
                    GL Vendor:          ~a~%~
                    GL Renderer:        ~a~%~
                    GL Version:         ~a~%~
                    GL Shader Language: ~a~%~
                    GL Extensions:      ~{~a~^ ~}~%"
          (gl:get* :major-version)
          (gl:get* :minor-version)
          (profile context)
          (ignore-errors (gl:get* :sample-buffers))
          (ignore-errors (gl:get* :samples))
          (ignore-errors (gl:get* :max-texture-size))
          (ignore-errors (gl:get* :max-vertex-texture-image-units))
          ;; Fuck you, GL, and your stupid legacy crap.
          (ignore-errors (gl:get* :max-texture-image-units))
          (ignore-errors (gl:get* :max-tess-control-texture-image-units))
          (ignore-errors (gl:get* :max-tess-evaluation-texture-image-units))
          (ignore-errors (gl:get* :max-geometry-texture-image-units))
          (ignore-errors (gl:get* :max-compute-texture-image-units))
          (gl:get-string :vendor)
          (gl:get-string :renderer)
          (gl:get-string :version)
          (gl:get-string :shading-language-version)
          (loop for i from 0 below (gl:get* :num-extensions)
                collect (gl:get-string-i :extensions i))))

(defun context-note-debug-info (context)
  (v:debug :trial.context "Context information: ~a"
           (let ((*print-right-margin* 1000)) ; SBCL fails otherwise. Huh?
             (with-output-to-string (out)
               (context-info context out)))))
