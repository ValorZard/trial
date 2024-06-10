(in-package #:org.shirakumo.fraf.trial)

(defclass pose (sequences:sequence standard-object)
  ((joints :initform #() :accessor joints)
   (weights :initform #() :accessor weights)
   (parents :initform (make-array 0 :element-type '(signed-byte 16)) :accessor parents)
   (data :initform (make-hash-table :test 'eql) :initarg :data :accessor data)))

(defmethod shared-initialize :after ((pose pose) slots &key size source)
  (cond (source
         (pose<- pose source))
        (size
         (sequences:adjust-sequence pose size))))

(defmethod print-object ((pose pose) stream)
  (print-unreadable-object (pose stream :type T :identity T)))

(defmethod clone ((pose pose) &key)
  (pose<- (make-instance 'pose) pose))

(defun pose<- (target source)
  (let* ((orig-joints (joints source))
         (orig-parents (parents source))
         (size (length orig-joints))
         (joints (joints target))
         (parents (parents target)))
    (let ((old (length joints)))
      (when (/= old size)
        (setf (joints target) (setf joints (adjust-array joints size)))
        (setf (parents target) (setf parents (adjust-array parents size)))
        (loop for i from old below size
              do (setf (svref joints i) (transform)))))
    (loop for i from 0 below size
          do (setf (aref parents i) (aref orig-parents i))
             (t<- (aref joints i) (aref orig-joints i)))
    (setf (weights target) (copy-seq (weights source)))
    target))

(defun pose= (a b)
  (let ((a-joints (joints a))
        (b-joints (joints b))
        (a-parents (parents a))
        (b-parents (parents b)))
    (and (= (length a-joints) (length b-joints))
         (loop for i from 0 below (length a-joints)
               always (and (= (aref a-parents i) (aref b-parents i))
                           (t= (svref a-joints i) (svref b-joints i)))))))

(defmethod sequences:length ((pose pose))
  (length (joints pose)))

(defmethod sequences:adjust-sequence ((pose pose) length &rest args)
  (declare (ignore args))
  (let ((old (length (joints pose))))
    (setf (joints pose) (adjust-array (joints pose) length))
    (when (< old length)
      (loop for i from old below length
            do (setf (svref (joints pose) i) (transform)))))
  (setf (parents pose) (adjust-array (parents pose) length :initial-element 0))
  pose)

(defmethod check-consistent ((pose pose))
  (let ((parents (parents pose))
        (visit (make-array (length pose) :element-type 'bit)))
    (dotimes (i (length parents) pose)
      (fill visit 0)
      (loop for parent = (aref parents i) then (aref parents parent)
            while (<= 0 parent)
            do (when (= 1 (aref visit parent))
                 (error "Bone ~a has a cycle in its parents chain." i))
               (setf (aref visit parent) 1)))))

(defmethod sequences:elt ((pose pose) index)
  (svref (joints pose) index))

(defmethod (setf sequences:elt) ((transform transform) (pose pose) index)
  (setf (svref (joints pose) index) transform))

(defmethod (setf sequences:elt) ((parent integer) (pose pose) index)
  (setf (aref (parents pose) index) parent))

(defmethod parent-joint ((pose pose) i)
  (aref (parents pose) i))

(defmethod (setf parent-joint) (value (pose pose) i)
  (setf (aref (parents pose) i) value))

(defmethod global-transform ((pose pose) i &optional (result (transform)))
  (let* ((joints (joints pose))
         (parents (parents pose)))
    (t<- result (svref joints i))
    (loop for parent = (aref parents i) then (aref parents parent)
          while (<= 0 parent)
          do (!t+ result (svref joints parent) result))
    result))

(defmethod global-quat2 ((pose pose) i &optional (result (quat2)))
  (let* ((joints (joints pose))
         (parents (parents pose)))
    (tquat2 (svref joints i) result)
    (loop for parent = (aref parents i) then (aref parents parent)
          while (<= 0 parent)
          do (let ((temp (quat2)))
               (declare (dynamic-extent temp))
               (nq2* result (tquat2 (svref joints parent) temp))))
    result))

(defmethod matrix-palette ((pose pose) result)
  (let ((length (length (joints pose)))
        (joints (joints pose))
        (parents (parents pose))
        (i 0))
    (setf result (%adjust-array result length (lambda () (meye 4))))
    (loop while (< i length)
          for parent = (aref parents i)
          do (when (< i parent) (return))
             (let ((global (!tmat (svref result i) (aref joints i))))
               (when (<= 0 parent)
                 (n*m (aref result parent) global)))
             (incf i))
    (loop while (< i length)
          do (!tmat (svref result i) (global-transform pose i))
             (incf i))
    result))

(defmethod quat2-palette ((pose pose) result)
  (let ((length (length (joints pose)))
        (joints (joints pose))
        (parents (parents pose)))
    (setf result (%adjust-array result length #'quat2))
    (loop for i from 0 below length
          for res = (svref result i)
          do (tquat2 (svref joints i) res)
             (loop for parent = (aref parents i) then (aref parents parent)
                   while (<= 0 parent)
                   do (let ((temp (quat2)))
                        (declare (dynamic-extent temp))
                        (nq* res (tquat2 (svref joints parent) temp)))))
    result))

(defmethod descendant-joint-p (joint root (pose pose))
  (or (= joint root)
      (loop with parents = (parents pose)
            for parent = (aref parents joint) then (aref parents parent)
            while (<= 0 parent)
            do (when (= parent root) (return T)))))

(defmethod blend-into ((target pose) (a pose) (b pose) x &key (root -1))
  (let ((x (float x 0f0)))
    (dotimes (i (length target) target)
      (unless (and (<= 0 root)
                   (descendant-joint-p i root target))
        (ninterpolate (elt target i) (elt a i) (elt b i) x)))))

;;                     Output,       Base Pose,Current Additive,Base Additive
(defmethod layer-onto ((target pose) (in pose) (add pose) (base pose) &key (root -1) (strength 1.0))
  (let ((temp (transform)))
    (declare (dynamic-extent temp))
    (dotimes (i (length add) target)
      (unless (and (<= 0 root)
                   (not (descendant-joint-p i root add)))
        (let ((output (elt target i))
              (input (elt in i))
              (additive (elt add i))
              (additive-base (elt base i)))
          (v<- (tlocation temp) (tlocation input))
          (nv+ (tlocation temp) (tlocation additive))
          (nv- (tlocation temp) (tlocation additive-base))
          (v<- (tscaling temp) (tscaling input))
          (nv+ (tscaling temp) (tscaling additive))
          (nv- (tscaling temp) (tscaling additive-base))
          (q<- (trotation temp) (trotation input))
          (nq* (trotation temp) (trotation additive))
          (nq* (trotation temp) (qinv (trotation additive-base)))
          (nqunit* (trotation temp))
          (ninterpolate output output temp strength))))))

(defmethod replace-vertex-data ((lines lines) (pose pose) &rest args)
  (let ((points ()))
    (dotimes (i (length pose))
      (let ((parent (parent-joint pose i)))
        (when (<= 0 parent)
          (push (tlocation (global-transform pose i)) points)
          (push (tlocation (global-transform pose parent)) points))))
    (apply #'replace-vertex-data lines (nreverse points) args)))

;;; Minor optimisation to avoid sequence accessor overhead
(defmethod sample ((pose pose) (clip clip) time &key)
  (declare (type single-float time))
  (declare (optimize speed))
  (if (< 0.0 (the single-float (end-time clip)))
      (let ((time (fit-to-clip clip time))
            (tracks (tracks clip))
            (loop-p (loop-p clip))
            (joints (joints pose)))
        (declare (type single-float time))
        (declare (type simple-vector tracks joints))
        (loop for i from 0 below (length tracks)
              for track = (svref tracks i)
              for name = (name track)
              do (etypecase name
                   ((unsigned-byte 32) (sample (aref joints name) track time :loop-p loop-p))
                   (T (sample (data pose) track time :loop-p loop-p))))
        time)
      0.0))
