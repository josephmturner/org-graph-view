;;; org-graph-view.el --- View an Org file as a graph (like a mind map)  -*- lexical-binding: t; -*-

;; Copyright (C) 2020  Adam Porter

;; Author: Adam Porter <adam@alphapapa.net>
;; Keywords: outlines
;; Package-Requires: ((emacs "25.2") (org "9.0") (dash "2.13.0") (s "1.0"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; An early proof-of-concept.

;; Uses <https://github.com/storax/graph.el>, which is included in
;; this repo since it's not in MELPA.

;;; Code:

;;;; Requirements

(require 'cl-lib)
(require 'org)
(require 'subr-x)
(require 'svg)

(require 'dash)

;;;; Variables

(defvar org-graph-view-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] #'org-graph-view-jump)
    (define-key map [mouse-2] #'org-graph-view-zoom-in)
    (define-key map [mouse-3] #'org-graph-view-zoom-out)
    map)
  "Keymap.")

(defvar org-graph-view-graph-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] #'org-graph-view-jump-from-graph)
    (define-key map [mouse-2] #'org-graph-view-zoom-in-from-graph)
    (define-key map [mouse-3] #'org-graph-view-zoom-out-from-graph)
    map)
  "Keymap.")

;;;; Customization


;;;; Commands

;;;###autoload
(define-minor-mode org-graph-view-mode
  ;; FIXME: Not quite working.
  "Drag mouse buttons to manipulate `org-graph-view'."
  :keymap 'org-graph-view-mode-map)

;;;###autoload
(cl-defun org-graph-view (layout)
  (interactive (pcase current-prefix-arg
                 ('nil '("twopi"))
                 (_ (list (completing-read "Layout: " '("twopi" "circo" "dot"))))))
  (cl-labels ((window-dimensions-in (&optional (window (selected-window)))
                                    ;; Return WINDOW (width-in height-in) in inches.
                                    (with-selected-window window
                                      (-let* (((&alist 'geometry (_ _ monitor-width-px monitor-height-px)
                                                       'mm-size (monitor-width-mm monitor-height-mm))
                                               ;; TODO: Ensure we get the monitor the frame is on.
                                               (car (display-monitor-attributes-list)))
                                              (monitor-width-in (mm-in monitor-width-mm))
                                              (monitor-height-in (mm-in monitor-height-mm))
                                              (monitor-width-res (/ monitor-width-px monitor-width-in))
                                              (monitor-height-res (/ monitor-height-px monitor-height-in))
                                              (window-width-in (/ (window-text-width nil t) monitor-width-res))
                                              (window-height-in (/ (window-text-height nil t) monitor-height-res)))
                                        (list window-width-in window-height-in))))
              (mm-in (mm) (* mm 0.04)))
    (-let* ((graph-buffer (org-graph-view-buffer))
            ((width-in height-in) (save-window-excursion
                                    (pop-to-buffer graph-buffer)
                                    (window-dimensions-in)))
            (root-node-pos (save-excursion
                             (when (org-before-first-heading-p)
                               (outline-next-heading))
                             (org-back-to-heading)
                             (point)))
            ((graph nodes) (org-graph-view--buffer-graph (current-buffer)))
            (graphviz (org-graph-view--format-graph graph nodes root-node-pos
                                                    :layout layout :width-in width-in :height-in height-in))
            (image-map (org-graph-view--graph-map graphviz))
            (svg-image (org-graph-view--svg graphviz :map image-map :source-buffer (current-buffer)))
            (inhibit-read-only t))
      (with-current-buffer graph-buffer
        (erase-buffer)
        (insert-image svg-image)
        (pop-to-buffer graph-buffer)))))

(defun org-graph-view-jump (event)
  (interactive "e")
  (-let* (((_type position _count) event)
          ((window pos-or-area (_x . _y) _timestamp
                   _object _text-pos . _)
           position))
    (with-selected-window window
      (goto-char pos-or-area)
      (org-reveal)
      (org-show-entry)
      (org-show-children)
      (goto-char pos-or-area)
      (call-interactively #'org-graph-view))))

(defun org-graph-view-zoom-in (event)
  (interactive "e")
  (-let* (((_type position _count) event)
          ((window pos-or-area (_x . _y) _timestamp
                   _object _text-pos . _)
           position))
    (with-selected-window window
      (goto-char pos-or-area)
      (org-reveal)
      (org-show-entry)
      (goto-char pos-or-area)
      (org-narrow-to-subtree)
      (call-interactively #'org-graph-view))))

(defun org-graph-view-zoom-out (event)
  (interactive "e")
  (-let* (((_type position _count) event)
          ((window pos-or-area (_x . _y) _timestamp
                   _object _text-pos . _)
           position))
    (with-selected-window window
      (widen)
      (goto-char pos-or-area)
      (when (org-up-heading-safe)
	(org-narrow-to-subtree))
      (call-interactively #'org-graph-view))))

(defun org-graph-view-jump-from-graph (event)
  (interactive "e")
  (-let* (((_type position _count) event)
          ((_window pos-or-area (_x . _y) _timestamp
                    _object _text-pos . (_ (_image . (&plist :source-buffer))))
           position)
          (begin (cl-typecase pos-or-area
                   (string (string-to-number pos-or-area))
                   (number pos-or-area))))
    (when source-buffer
      (pop-to-buffer source-buffer)
      (goto-char begin)
      (org-reveal)
      (org-show-entry)
      (org-show-children)
      (goto-char begin)
      (call-interactively #'org-graph-view))))

(defun org-graph-view-zoom-in-from-graph (event)
  (interactive "e")
  (-let* (((_type position _count) event)
          ((_window pos-or-area (_x . _y) _timestamp
                    _object _text-pos . (_ (_image . (&plist :source-buffer))))
           position)
          (begin (cl-typecase pos-or-area
                   (string (string-to-number pos-or-area))
                   (number pos-or-area))))
    (when source-buffer
      (pop-to-buffer source-buffer)
      (widen)
      (goto-char begin)
      (org-narrow-to-subtree)
      (call-interactively #'org-graph-view))))

(defun org-graph-view-zoom-out-from-graph (event)
  (interactive "e")
  (-let* (((_type position _count) event)
          ((_window pos-or-area (_x . _y) _timestamp
                    _object _text-pos . (_ (_image . (&plist :source-buffer))))
           position)
          (begin (cl-typecase pos-or-area
                   (string (string-to-number pos-or-area))
                   (number pos-or-area))))
    (when source-buffer
      (pop-to-buffer source-buffer)
      (widen)
      (goto-char begin)
      (cond ((org-up-heading-safe)
             (org-narrow-to-subtree))
            (t (goto-char (point-min))))
      (call-interactively #'org-graph-view))))








;;;; Functions

(cl-defun org-graph-view--buffer-graph (buffer)
  "Return (graph nodes) for BUFFER."
  (let ((nodes (make-hash-table :test #'equal)))
    (cl-labels ((format-tree (tree &optional path)
                             (--map (format-node it path)
                                    (cddr tree)))
                (format-node (node &optional path)
                             (-let* (((_element _properties . children) node)
                                     (path (append path (list node))))
                               (list (--map (concat (node-id node) " -> " (node-id it) ";\n")
                                            children)
                                     (--map (format-node it path)
                                            children))))
                (node-id (node)
                         (-let* (((_element (properties &as &plist :begin) . _children) node))
                           (or (car (gethash begin nodes))
                               (let* ((node-id (format "node%s" begin))
                                      (value (cons node-id node)))
                                 (puthash begin value nodes)
                                 node-id)))))
      (with-current-buffer buffer
        (list (format-tree (org-element-parse-buffer 'headline)) nodes)))))

(cl-defun org-graph-view--format-graph (graph nodes root-node-pos
                                              &key layout width-in height-in)
  "Return Graphviz string for GRAPH and NODES viewed from ROOT-NODE-POS."
  (cl-labels ((node-properties (node)
                               (cl-loop with (_element properties . children) = node
                                        for (name property) in
                                        (list '(label :raw-value)
                                              '(style "filled")
                                              (list 'color (lambda (&rest _)
                                                             (face-attribute 'default :foreground)))
                                              (list 'fillcolor #'node-color)
                                              (list 'href #'node-href))
                                        collect (cl-typecase property
                                                  (keyword (cons name (plist-get properties property)))
                                                  (function (cons name (funcall property node)))
                                                  (string (cons name property))
                                                  (symbol (cons name (symbol-value property))))))
              (node-href (node)
                         (-let* (((_element (properties &as &plist :begin) . _children) node))
                           (format "%s" begin)))
              (node-color (node)
                          (-let* (((_element (&plist :level) . _children) node))
                            (--> (face-attribute (nth (1- level) org-level-faces) :foreground nil 'default)
                                 (color-name-to-rgb it)
                                 (-let (((r g b) it))
                                   (color-rgb-to-hex r g b 2)))))
              (insert-vals (&rest pairs)
                           (cl-loop for (key value) on pairs by #'cddr
                                    do (insert (format "%s=\"%s\"" key value) "\n")))
              (format-val-list (&rest pairs)
                               (s-wrap (s-join "," (cl-loop for (key value) on pairs by #'cddr
                                                            collect (format "%s=\"%s\"" key value)))
                                       "[" "]")))
    (let ((root-node-name (car (gethash root-node-pos nodes))))
      (with-temp-buffer
        (save-excursion
          (insert "digraph orggraphview {\n")
          (insert "edge" (format-val-list "color" (face-attribute 'default :foreground)) ";\n")
          (insert "node" (format-val-list "fontname" (face-attribute 'default :family)) ";\n")
          (insert-vals "layout" layout
                       "bgcolor" (face-attribute 'default :background)
                       "size" (format "%.1d,%.1d" width-in height-in)
                       "margin" "0"
                       "ratio" "fill"
                       "nodesep" "0"
                       "mindist" "0")
          (mapc #'insert (-flatten graph))
          (maphash (lambda (_key value)
                     (insert (format "%s [%s];\n" (car value)
                                     (s-join ","
                                             (--map (format "%s=\"%s\"" (car it) (cdr it))
                                                    (node-properties (cdr value)))))))
                   nodes)
          (insert (format "root=\"%s\"" root-node-name))
          (insert "}"))
        (buffer-string)))))

(defun org-graph-view-buffer ()
  "Return initialized \"*org-graph-view*\" buffer."
  (or (get-buffer "*org-graph-view*")
      (with-current-buffer (get-buffer-create "*org-graph-view*")
        (buffer-disable-undo)
        (setq cursor-type nil)
        (toggle-truncate-lines 1)
        (read-only-mode 1)
        (use-local-map org-graph-view-graph-map)
        (current-buffer))))

;;;; Graphviz

(defmacro org-graph-view--graphviz (type &rest body)
  "Run Graphviz for TYPE on current buffer, then run BODY in it.
Current buffer should contain a Graphviz graph.  Graphviz is
called and replaces the buffer content with the rendered output."
  (declare (indent defun) (debug (stringp body)))
  `(if (zerop (call-process-region (point-min) (point-max) "circo" 'delete t nil
                                   (concat "-T" ,type)))
       (progn
         ,@body)
     (error "Oops: %s" (buffer-string))))

(cl-defun org-graph-view--svg (graph &key map source-buffer)
  "Return SVG image for Graphviz GRAPH.
MAP is an Emacs-ready image map to apply to the image's
properties.  SOURCE-BUFFER is the Org buffer the graph displays,
which is applied as a property to the image so map-clicking
commands can find the buffer."
  (with-temp-buffer
    (insert graph)
    (org-graph-view--graphviz "svg"
      (let* ((image (svg-image (libxml-parse-xml-region (point-min) (point-max)))))
        (setf (image-property image :map) map)
        (setf (image-property image :source-buffer) source-buffer)
        image))))

(defun org-graph-view--graph-map (graph)
  "Return image map for Graphviz GRAPH."
  (with-temp-buffer
    (insert graph)
    (org-graph-view--graphviz "cmapx"
      (cl-labels ((convert-map (map)
                               (-let (((_map _props . areas) map))
                                 (mapcar #'convert-area areas)))
                  (convert-area (area)
                                (-let (((_area (&alist 'shape 'title 'href 'coords)) area))
                                  (pcase-exhaustive shape
                                    ("poly" (list (cons 'poly (convert-coords coords)) href (list :help-echo title))))))
                  (convert-coords (coords)
                                  (->> coords (s-split ",") (-map #'string-to-number) (apply #'vector))))
        (let* ((cmapx (libxml-parse-xml-region (point-min) (point-max))))
          (convert-map cmapx))))))

;;;; Footer

(provide 'org-graph-view)

;;; org-graph-view.el ends here
