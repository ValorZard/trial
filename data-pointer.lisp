#|
 This file is a part of trial
 (c) 2017 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.fraf.trial)

(defun free-data (data)
  (etypecase data
    (cffi:foreign-pointer
     (cffi:foreign-free data))
    (vector
     (maybe-free-static-vector data))
    (cons
     (mapc #'free-data data))))

(defmacro with-pointer-to-vector-data ((ptr data &optional element-type) &body body)
  (let ((datag (gensym "DATA")) (thunk (gensym "THUNK"))
        (type (gensym "TYPE")) (i (gensym "I")))
    `(let ((,datag ,data))
       (flet ((,thunk (,ptr)
                (declare (type cffi:foreign-pointer ,ptr))
                ,@body))
         (declare (dynamic-extent #',thunk))
         (cond ((static-vector-p ,datag)
                (let ((,ptr (static-vector-pointer ,datag)))
                  (,thunk ,ptr)))
               #+sbcl
               ((typep ,datag 'sb-kernel:simple-unboxed-array)
                (sb-sys:with-pinned-objects (,datag)
                  (,thunk (sb-sys:vector-sap ,datag))))
               #+sbcl
               ((typep ,datag '(and vector (not simple-array)))
                (let ((,ptr (sb-ext:array-storage-vector ,datag)))
                  (sb-sys:with-pinned-objects (,ptr)
                    (,thunk (sb-sys:vector-sap ,ptr)))))
               (T
                (let ((,type (cl-type->gl-type ,(or element-type `(array-element-type ,datag)))))
                  (cffi:with-foreign-object (,ptr ,type (length ,datag))
                    (dotimes (,i (length ,datag))
                      (setf (cffi:mem-aref ,ptr ,type ,i) (aref ,datag ,i)))
                    (,thunk ,ptr)))))))))

(defgeneric call-with-data-ptr (function data &key offset &allow-other-keys))

(defmethod call-with-data-ptr (function data &key (offset 0))
  #-elide-buffer-access-checks
  (unless (typep data 'cffi:foreign-pointer)
    (no-applicable-method #'call-with-data-ptr function data :offset offset))
  (funcall function (cffi:inc-pointer data offset) most-positive-fixnum))

(defmethod call-with-data-ptr (function (data real) &key (offset 0))
  #-elide-buffer-access-checks
  (when (/= offset 0) (error "OFFSET must be zero for reals."))
  (let ((type (cl-type->gl-type (type-of data))))
    (cffi:with-foreign-object (ptr type)
      (setf (cffi:mem-ref ptr type) data)
      (funcall function ptr (gl-type-size type)))))

(defmethod call-with-data-ptr (function (data vec2) &key (offset 0))
  #-elide-buffer-access-checks
  (when (/= offset 0) (error "OFFSET must be zero for vectors."))
  (cffi:with-foreign-object (ptr :float 2)
    (setf (cffi:mem-aref ptr :float 0) (vx2 data))
    (setf (cffi:mem-aref ptr :float 1) (vy2 data))
    (funcall function ptr (gl-type-size :vec2))))

(defmethod call-with-data-ptr (function (data vec3) &key (offset 0))
  #-elide-buffer-access-checks
  (when (/= offset 0) (error "OFFSET must be zero for vectors."))
  (cffi:with-foreign-object (ptr :float 3)
    (setf (cffi:mem-aref ptr :float 0) (vx3 data))
    (setf (cffi:mem-aref ptr :float 1) (vy3 data))
    (setf (cffi:mem-aref ptr :float 2) (vz3 data))
    (funcall function ptr (gl-type-size :vec3))))

(defmethod call-with-data-ptr (function (data vec4) &key (offset 0))
  #-elide-buffer-access-checks
  (when (/= offset 0) (error "OFFSET must be zero for vectors."))
  (cffi:with-foreign-object (ptr :float 4)
    (setf (cffi:mem-aref ptr :float 0) (vx4 data))
    (setf (cffi:mem-aref ptr :float 1) (vy4 data))
    (setf (cffi:mem-aref ptr :float 2) (vz4 data))
    (setf (cffi:mem-aref ptr :float 3) (vw4 data))
    (funcall function ptr (gl-type-size :vec4))))

(defmethod call-with-data-ptr (function (data mat2) &key (offset 0))
  (call-with-data-ptr function (marr2 data) :offset offset))

(defmethod call-with-data-ptr (function (data mat3) &key (offset 0))
  (call-with-data-ptr function (marr3 data) :offset offset))

(defmethod call-with-data-ptr (function (data mat4) &key (offset 0))
  (call-with-data-ptr function (marr4 data) :offset offset))

(defmethod call-with-data-ptr (function (data matn) &key (offset 0))
  (call-with-data-ptr function (marrn data) :offset offset))

(defmethod call-with-data-ptr ((function function) (data vector) &key (offset 0) gl-type)
  (declare (optimize speed))
  (declare (type (unsigned-byte 32) offset))
  (let* ((type (or gl-type (cl-type->gl-type (array-element-type data))))
         (type-size (the (unsigned-byte 16) (gl-type-size type)))
         (offset (* offset type-size))
         (size (- (the (unsigned-byte 32) (* (length data) type-size)) offset)))
    (with-pointer-to-vector-data (ptr data)
      (funcall function (cffi:inc-pointer ptr offset) size))))

(defmethod call-with-data-ptr (function (data pathname) &key (offset 0))
  (mmap:with-mmap (ptr fd size data)
    (funcall function (cffi:inc-pointer ptr offset) size)))

(defmacro with-data-ptr ((ptr size data &rest args) &body body)
  (let ((thunk (gensym "THUNK")))
    `(flet ((,thunk (,ptr ,size)
              (declare (type cffi:foreign-pointer ,ptr))
              (declare (type fixnum ,size))
              (declare (ignorable ,size))
              ,@body))
       (declare (dynamic-extent #',thunk))
       (call-with-data-ptr #',thunk ,data ,@args))))

;; FIXME: Put this into a library?

(declaim (inline memory-region memory-region-start memory-region-size))
(defstruct (memory-region
            (:constructor memory-region (start size)))
  (start NIL :type cffi:foreign-pointer :read-only T)
  (size 0 :type fixnum :read-only T))

(defmethod start ((region memory-region)) (memory-region-start region))
(defmethod end ((region memory-region)) (cffi:inc-pointer (memory-region-start region) (memory-region-size region)))
(defmethod size ((region memory-region)) (memory-region-size region))

(defmethod print-object ((region memory-region) stream)
  (print (list 'memory-region (memory-region-start region) (memory-region-size region)) stream))

(defmethod call-with-data-ptr (function (region memory-region) &key (offset 0))
  (funcall function (cffi:inc-pointer (memory-region-start region) offset)
           (memory-region-size region)))

(defclass memory-region-stream (trivial-gray-streams:fundamental-binary-input-stream
                                trivial-gray-streams:fundamental-binary-output-stream)
  ((start :initarg :start :accessor start)
   (size :initarg :size :accessor size)
   (index :initarg :index :initform 0 :accessor index
          :accessor trivial-gray-streams:stream-file-position)))

(defun memory-region-to-stream (memory-region &key (start 0))
  (make-instance 'memory-region-stream :start (memory-region-start memory-region)
                                       :size (memory-region-size memory-region)
                                       :index start))

(defmethod trivial-gray-streams:stream-read-byte ((stream memory-region-stream))
  (let ((start (start stream))
        (index (index stream))
        (size (size stream)))
    (when (<= size index)
      (error 'end-of-file :stream stream))
    (setf (index stream) (1+ index))
    (cffi:mem-aref start :uint8 index)))

(defmethod trivial-gray-streams:stream-write-byte ((stream memory-region-stream) integer)
  (let ((start (start stream))
        (index (index stream))
        (size (size stream)))
    (when (<= size index)
      (error 'end-of-file :stream stream))
    (setf (index stream) (1+ index))
    (setf (cffi:mem-aref start :uint8 index) integer)))

(defmethod trivial-gray-streams:stream-read-sequence ((stream memory-region-stream) (sequence vector) start end &key)
  (let* ((tstart (or start 0))
         (tend (or end (length sequence)))
         (start (start stream))
         (index (index stream))
         (size (size stream))
         (to-copy (min (- tend tstart) (- size index))))
    (cond #+sbcl
          ((typep sequence 'sb-kernel:simple-unboxed-array)
           (sb-sys:with-pinned-objects (sequence)
             (static-vectors:replace-foreign-memory 
              (sb-sys:vector-sap sequence) (cffi:inc-pointer start index) to-copy)))
          #+sbcl
          ((typep sequence '(and vector (not simple-array)))
           (let ((sequence (sb-ext:array-storage-vector sequence)))
             (sb-sys:with-pinned-objects (sequence)
               (static-vectors:replace-foreign-memory 
                (sb-sys:vector-sap sequence) (cffi:inc-pointer start index) to-copy))))
          (T
           (dotimes (i to-copy)
             (setf (aref sequence (+ i tstart)) (cffi:mem-aref start :uint8 (+ index i))))
           (setf (index stream) (+ index to-copy))))
    to-copy))

(defmethod trivial-gray-streams:stream-write-sequence ((stream memory-region-stream) (sequence vector) start end &key)
  (let* ((tstart (or start 0))
         (tend (or end (length sequence)))
         (start (start stream))
         (index (index stream))
         (size (size stream))
         (to-copy (min (- tend tstart) (- size index))))
    (cond #+sbcl
          ((typep sequence 'sb-kernel:simple-unboxed-array)
           (sb-sys:with-pinned-objects (sequence)
             (static-vectors:replace-foreign-memory 
              (cffi:inc-pointer start index) (sb-sys:vector-sap sequence) to-copy)))
          #+sbcl
          ((typep sequence '(and vector (not simple-array)))
           (let ((sequence (sb-ext:array-storage-vector sequence)))
             (sb-sys:with-pinned-objects (sequence)
               (static-vectors:replace-foreign-memory 
                (cffi:inc-pointer start index) (sb-sys:vector-sap sequence) to-copy))))
          (T
           (dotimes (i to-copy)
             (setf (cffi:mem-aref start :uint8 (+ index i)) (aref sequence (+ i tstart))))
           (setf (index stream) (+ index to-copy))))
    to-copy))
