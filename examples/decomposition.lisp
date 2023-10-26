(in-package #:org.shirakumo.fraf.trial.examples)

(defclass decomposition-panel (trial-alloy:panel)
  ((container :initarg :container :accessor container)
   (model :initform NIL :accessor model)
   (mesh :initform NIL :accessor mesh)))

(alloy:define-observable (setf model) (value alloy:observable))
(alloy:define-observable (setf mesh) (value alloy:observable))

(defmethod initialize-instance :after ((panel decomposition-panel) &key)
  (let ((layout (make-instance 'alloy:grid-layout :col-sizes '(120 140 T) :row-sizes '(30)))
        (focus (make-instance 'alloy:vertical-focus-list)))
    (alloy:enter "Load Model" layout :row 0 :col 0)
    (let ((button (alloy:represent "..." 'alloy:button :layout-parent layout :focus-parent focus)))
      (alloy:on alloy:activate (button)
        (let ((file (org.shirakumo.file-select:existing :title "Load Model File..."
                                                        :filter '(("Wavefront OBJ" "obj")
                                                                  ("glTF File" "gltf")
                                                                  ("glTF Binary" "glb")))))
          (when file
            (setf (model panel) (generate-resources 'model-loader file))))))
    (alloy:enter "Mesh" layout :row 1 :col 0)
    (let* ((mesh NIL)
           (selector (alloy:represent mesh 'alloy:combo-set :value-set () :layout-parent layout :focus-parent focus)))
      (alloy:on model (model panel)
        (let ((meshes (if (typep model 'model) (list-meshes model) ())))
          (setf (alloy:value-set selector) meshes)
          (when meshes (setf (mesh panel) (find-mesh (first meshes) model)))))
      (alloy:on alloy:value (mesh selector)
        (setf (mesh panel) (find-mesh mesh (model selector)))))
    (alloy:enter "Show Original" layout :row 2 :col 0)
    (let* ((mode NIL)
           (switch (alloy:represent mode 'alloy:switch)))
      (alloy:on alloy:value (mode switch)
        ))
    (alloy:enter "Wireframe" layout :row 3 :col 0)
    (let* ((mode NIL)
           (switch (alloy:represent mode 'alloy:switch)))
      (alloy:on alloy:value (mode switch)
        ))
    (alloy:finish-structure panel layout focus)
    (generate-resources (assets:asset :woman) T)
    (setf (model panel) (assets:asset :woman))))

(defmethod (setf mesh) :before ((mesh mesh-data) (panel decomposition-panel))
  (clear (container panel))
  (loop for hull across (org.shirakumo.fraf.convex-covering:decompose
                         (reordered-vertex-data mesh '(location))
                         (trial::simplify (index-data mesh) '(unsigned-byte 32)))
        for (name . color) in (apply #'alexandria:circular-list (colored:list-colors))
        do (debug-draw (make-convex-mesh :vertices (org.shirakumo.fraf.convex-covering:vertices hull)
                                         :faces (org.shirakumo.fraf.convex-covering:faces hull))
                       :color (vec (colored:r color) (colored:g color) (colored:b color)))))

(define-example decomposition
  :title "Convex Hull Decomposition"
  (let ((game (make-instance 'render-pass))
        (ui (make-instance 'ui))
        (combine (make-instance 'blend-pass)))
    (connect (port game 'color) (port combine 'a-pass) scene)
    (connect (port ui 'color) (port combine 'b-pass) scene))
  (enter (make-instance 'editor-camera) scene)
  (let ((container (make-instance 'array-container)))
    (enter container scene)
    (trial-alloy:show-panel 'decomposition-panel :container container)))
