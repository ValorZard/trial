(in-package #:org.shirakumo.fraf.trial)

(defclass base-animated-entity (mesh-entity)
  ((animation-controller :initform (make-instance 'animation-controller) :accessor animation-controller)))

(define-transfer base-animated-entity animation-controller)

(define-accessor-wrapper-methods clip (base-animated-entity (animation-controller base-animated-entity)))
(define-accessor-wrapper-methods skeleton (base-animated-entity (animation-controller base-animated-entity)))
(define-accessor-wrapper-methods pose (base-animated-entity (animation-controller base-animated-entity)))
(define-accessor-wrapper-methods palette (base-animated-entity (animation-controller base-animated-entity)))
(define-accessor-wrapper-methods palette-texture (base-animated-entity (animation-controller base-animated-entity)))

(defmethod (setf mesh-asset) :after ((asset asset) (entity base-animated-entity))
  (setf (model (animation-controller entity)) asset))

(defmethod stage :after ((entity base-animated-entity) (area staging-area))
  (register-load-observer area (animation-controller entity) (mesh-asset entity))
  (stage (animation-controller entity) area))

(defmethod play (thing (entity base-animated-entity))
  (play thing (animation-controller entity)))

(defmethod fade-to (thing (entity base-animated-entity) &rest args &key &allow-other-keys)
  (apply #'fade-to thing (animation-controller entity) args))

(defmethod add-layer (thing (entity base-animated-entity) &rest args)
  (apply #'add-layer thing (animation-controller entity) args))

(defmethod find-clip (thing (entity base-animated-entity) &optional (errorp T))
  (find-clip thing (animation-controller entity) errorp))

(defmethod list-clips ((entity base-animated-entity))
  (list-clips entity))

(define-shader-entity armature (base-animated-entity lines)
  ((color :initarg :color :initform (vec 0 0 0 1) :accessor color)))

(define-handler ((entity armature) (ev tick) :after) ()
  (replace-vertex-data entity (pose entity) :default-color (color entity)))

(define-gl-struct morph-data
  (size NIL :initarg :size :initform 8 :reader size)
  (morph-count :int :initform 0 :accessor morph-count :reader sequence:length)
  (weights (:array :float size))
  (indices (:array :int size)))

(defclass morph ()
  ((texture :initform NIL :accessor texture)
   (morph-data :initform NIL :accessor morph-data)))

(defmethod initialize-instance :after ((morph morph) &key (simultaneous-targets 8) targets)
  (setf (morph-data morph) (make-instance 'uniform-buffer :data-usage :dynamic-draw :binding NIL :struct (make-instance 'morph-data :size simultaneous-targets)))
  (let* ((attributes
           ;; TODO: compute reduced or expanded set of attributes from targets.
           #++
           (loop for target across targets
                 for attributes = (vertex-attributes target) then (union attributes (vertex-attributes target))
                 finally (return attributes))
           '(location normal uv))
         (vertex-count (vertex-count (aref targets 0)))
         ;; The stride is 9, 3 for every color. This wastes space for the UV, since it only needs RG.
         (stride 9)
         (data (make-array (* (length targets) stride vertex-count) :element-type 'single-float))
         (texture (make-instance 'texture :target :texture-1d-array
                                          :internal-format :rgb32f
                                          :width (length targets)
                                          :height stride
                                          :pixel-data data
                                          :pixel-type :float
                                          :pixel-format :rgb)))
    ;; Compact the targets into a slice per target
    (loop for target across targets
          for src-data = (vertex-data target)
          for src-stride = (vertex-attribute-stride target)
          for slice from 0 by (* vertex-count stride)
          do (unless (= (vertex-count target) vertex-count)
               (error "Not all morph targets have the same number of vertices!"))
             (loop for attribute in attributes
                   for src-offset = (vertex-attribute-offset attribute target)
                   for dst-offset = (vertex-attribute-offset attribute attributes)
                   do (loop for src from src-offset below (length src-data) by src-stride
                            for dst from dst-offset by stride
                            do (setf (aref data (+ slice dst 0)) (aref src-data (+ src 0)))
                               (setf (aref data (+ slice dst 1)) (aref src-data (+ src 1)))
                               (unless (eq attribute 'uv)
                                 (setf (aref data (+ dst 2)) (aref src-data (+ src 2)))))))
    (setf (texture morph) texture)))

(define-shader-entity morphed-entity (base-animated-entity listener)
  ()
  (:shader-file (trial "morph.glsl")))

(defmethod render :before ((entity morphed-entity) (program shader-program))
  ;; KLUDGE: This is Bad
  (when (morph-texture entity)
    (bind (morph-texture entity) :texture6)
    (setf (uniform program "morph_targets") 6)))

(defmethod stage :after ((entity morphed-entity) (area staging-area))
  (stage (morph-texture entity) area)
  (stage (morph-data entity) area))

(define-shader-entity skinned-entity (base-animated-entity)
  ((mesh :initarg :mesh :initform NIL :accessor mesh))
  (:shader-file (trial "skin-matrix.glsl")))

(defmethod (setf mesh-asset) :after ((asset asset) (entity skinned-enity))
  (unless (loaded-p asset)
    (setf (palette entity) #(#.(meye 4)))))

(defmethod render :before ((entity skinned-entity) (program shader-program))
  (when (palette-texture entity)
    (bind (palette-texture entity) :texture5)
    (setf (uniform program "pose") 5)))

(define-shader-entity quat2-skinned-entity (base-animated-entity)
  ()
  (:shader-file (trial "skin-dquat.glsl")))

(defmethod render :before ((entity quat2-skinned-entity) (program shader-program))
  (when (palette-texture entity)
    (bind (palette-texture entity) :texture5)
    (setf (uniform program "pose") 5)))

(define-shader-entity animated-entity (skinned-entity morphed-entity)
  ())

(define-class-shader (animated-entity :vertex-shader)
  "layout (location = 0) in vec3 in_position;
layout (location = 1) in vec3 in_normal;
layout (location = 2) in vec2 in_uv;
layout (location = 5) in vec4 in_joints;
layout (location = 6) in vec4 in_weights;

uniform mat2x4 pose[120];

out vec3 normal;
out vec4 world_pos;
out vec2 uv;

void main(){
  vec3 position = in_position;
  normal = in_normal;
  uv = in_uv;

  morph_vertex(position, normal, uv);
  skin_vertex(position, normal, in_joints, in_weights);

  world_pos = model_matrix * vec4(position, 1.0f);
  normal = vec3(model_matrix * vec4(normal, 0.0f));
  gl_Position = projection_matrix * view_matrix * world_pos;
}")
