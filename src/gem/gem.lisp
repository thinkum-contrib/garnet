;;; -*- Mode: LISP; Syntax: Common-Lisp; Package: GEM; Base: 10 -*-
;;-------------------------------------------------------------------;;
;;          The Garnet User Interface Development Environment.       ;;
;;-------------------------------------------------------------------;;
;;  This code was written as part of the Garnet project at           ;;
;;  Carnegie Mellon University, and has been placed in the public    ;;
;;  domain.                                                          ;;
;;-------------------------------------------------------------------;;

;;; $Id$
;;


;;; This file defines gem-method, which is used to declare, create, and
;; export the generic Gem methods.  Methods are implemented as macros which
;; dispatch on the :methods slot of a window (or font) to find the appropriate
;; method for each device.


;;; CHANGE LOG:
;;;  9/20/14 Sean Champ - Add functional interface for *device-initializers*
;;; 12/15/93 Andrew Mickish - Moved shared macros here from x.lisp
;;; 11/11/93 Andrew Mickish - Put into CLTL2 form


(in-package "GEM")

(declaim (special *root-window*))

;;; This file defines gem-method, which is used to declare, create, and
;;; export the generic Gem methods.  Methods are implemented as macros which
;;; dispatch on the :methods slot of a window (or font) to find the appropriate
;;; method for each device.



(eval-when (:execute :compile-toplevel :load-toplevel)
  (defvar *method-names* nil
    "Holds the method names.  This is used to create the Gem interface
   macros."))


;;; Functional interface for *device-initializers*


(eval-when (:execute :compile-toplevel :load-toplevel)
  (defvar *device-initializers* nil
    "An a-list which associates device types with the function to be called
     to initialize them."))

(defun ensure-device-initializer (device fspec)
  (declare (type symbol device)
	   (type (or symbol function) fspec)
	   (values function))
  "Ensure function FSPEC will be registered as a device initializer.

This function operates on the list, GEM::*DEVICE-INITIALIZERS*

If the FDEFINITION for FSPEC denotes a function already registered in
the list, but the FDEFINITION registered in the list differs from
that denoted by FSPEC at the time of this functin's evaluation,
then this function will ensure that the function is registered with
the updated FDEFINITIONS, as unique to the DEVICE designator."
  (flet ((ensure-fn (o) (coerce o 'function)))
    (let ((fn (ensure-fn fspec))
	  (existing (assoc device *device-initializers*)))
    (cond
      ((and existing
	    (eq (ensure-fn (cdr existing))
		fn))
       (values fn))
      (existing
       (setf (cdr existing) fn)
       (values fn))
      (t
       ;; FIXME: Thread safety for *DEVICE-INITIALIZERS*
       ;; r/w locks and symbol macros?
       (setf *device-initializers* 
	     (nconc 
	      (list (cons device fn))))
       (values fn))))))

(defun find-device-initializer (device &optional (errorp t))
  (declare (type symbol device)
	   (values (or function null)))
  (let ((spec (assoc device *device-initializers* 
		     :test #'eq)))
    (cond
      (spec (cdr spec))
      (errorp
       (error "Device initializer not defined for device ~s"
	      device))
      (t nil))))

(defun delete-device-initializer (device &optional (errorp t))
  (declare (type symbol device)
	   (values (or function null)))
  (let ((spec (assoc device *device-initializers* 
		     :test #'eq)))
    (cond
      (spec (setf *device-initializers*
		  (delete spec *device-initializers*
			  :test #'eq))
	    (prog1 (cdr spec)
	      (rplacd spec nil)))
      (errorp
       (error "Device initializer not defined for device ~s"
	      device))
      (t nil))))

;; (delete-device-initializer :x)
;; (find-device-initializer :x)
;; (find-device-initializer :x nil)
;; (ensure-device-initializer :x #'X-TOP-LEVEL-INITIALIZE)
;; (ensure-device-initializer :x #'X-TOP-LEVEL-INITIALIZE)
;; (find-device-initializer :x)


;;; Methods mechanism


(defun attach-method (device method-name method)
  (let ((number (find-or-create-name method-name))
	(methods (g-value device :methods)))
    (unless methods
      (s-value device :methods
	       (setf methods (make-array (length *method-names*)))))
    (when (<= (length methods) number)
      (let ((array (make-array (1+ number))))
	(dotimes (i (length methods))
	  (setf (aref array i) (aref methods i)))
	(setf methods array)
	(s-value device :methods array)))
    (setf (aref methods number) method)))



(defun set-window-methods (window device)
  (s-value window :device device)
  (s-value window :methods (g-value device :methods)))



;;; Interface definitions


(eval-when (:execute :compile-toplevel :load-toplevel)
  (defun find-or-create-name (name)
    (let ((pos (position name *method-names*)))
      (unless pos
	(if *method-names*
	  (setf (cdr (last *method-names*)) (list name))
	  (setf *method-names* (list name)))
	(setf pos (1- (length *method-names*))))
      pos)))


;;; This macro creates a macro such as gem:clear-area.  The name is
;;  determined by the <method-name> (which should be a keyword).  The
;;  <args> are used for the macro definition.
;;  The first of the <args> must be a window, which determines the device
;;  (and hence the method).  The generated macro simply does a funcall on the
;;  appropriate method for the device, passing all the arguments verbatim.
;;
;;  Things are handled properly when <args> contains &rest, &optional, or
;;  &key parameters."

;; XXX FMG the above appears to be incorrect: the following generates a defun
;; while the commented out code below generates a defmacro (and the one below
;; that generates a defun as well).

(defmacro gem-method (method-name (&rest args))
  (let ((macro-name (intern (symbol-name method-name) (find-package "GEM")))
	(has-rest (find '&rest args)))
    `(progn

       ;; Make sure the method name is defined when we load this.
       (find-or-create-name ,method-name)

       ;; Define the interface function itself, which will dispatch on its
       ;; first argument (a window) to find the appropriate device-specific
       ;; argument.
       (defun ,macro-name (,@args)
	 (,(if has-rest 'APPLY 'FUNCALL)
	   (aref (g-value ,(car args) :METHODS)
		 ,(find-or-create-name method-name))
	   ,@(if (or has-rest (intersection '(&key &optional) args))
		 ;; We must manipulate the arguments list.
		 (do ((head args (cdr head))
		      (in-key NIL)
		      (final nil))
		     ((null head)
		      (nreverse final))
		   (case (car head)
		     ((&optional &rest))
		     (&key
		      (setf in-key T))
		     (T
		      (let ((symbol (car head)))
			(if (listp symbol)
			    (setf symbol (car symbol)))
			(if in-key
			    (push (intern (symbol-name symbol)
					  (find-package "KEYWORD"))
				  final))
			(push symbol final)))))
		 ;; Arguments list is OK as is.
		 args)))

       ;; Export the interface function from the Gem package.
       (eval-when (:execute :load-toplevel :compile-toplevel) (export ',macro-name)))))

;; Same, generates a function instead of a macro.
#-(and)
(defmacro gem-method (method-name (&rest args))
  (let ((macro-name (intern (symbol-name method-name) (find-package "GEM")))
	(has-rest (find '&rest args)))
    `(progn
      (defmacro ,macro-name (,@args)
	(,(if has-rest 'LIST* 'LIST)
	  'FUNCALL
	  (list 'aref (list 'g-value ,(car args) :METHODS)
		,(find-or-create-name method-name))
	  ,@(if (or has-rest (intersection '(&key &optional) args))
	      ;; We must manipulate the arguments list.
	      (do ((head args (cdr head))
		   (in-key NIL)
		   (final nil))
		  ((null head)
		   (nreverse final))
		(case (car head)
		  ((&optional &rest))
		  (&key
		   (setf in-key T))
		  (T
		   (let ((symbol (car head)))
		     (if (listp symbol)
		       (setf symbol (car symbol)))
		     (if in-key
		       (push (intern (symbol-name symbol)
				     (find-package "KEYWORD"))
			     final))
		     (push symbol final)))))
	      ;; Arguments list is OK as is.
	      args)))
      (export ',macro-name))))

#-(and)
(defmacro gem-method (method-name (&rest args))
  (let ((macro-name (intern (symbol-name method-name) (find-package "GEM")))
	(has-rest (find '&rest args)))
    `(eval-when (load eval compile)
      (defun ,macro-name (,@args)
	(,(if has-rest 'APPLY 'FUNCALL)
	  (aref (g-value ,(car args) :METHODS)
		,(find-or-create-name method-name))
	  ,@(if (or has-rest (find '&optional args))
		;; We must manipulate the arguments list.
		(mapcar #'(lambda (x) (if (listp x) (car x) x))
			;; Eliminate &optional, &rest from arguments
			(delete '&optional
				(delete '&rest (copy-list args))))
		;; Arguments list is OK as is.
		args)))
      (export ',macro-name))))
|#




;; This is called when a root-window device does not yet exist.  Therefore,
;; we cannot rely on the usual dispatching method.  Rather, we pass a
;; keyword that contains the type of device we want to initialize.
;; RETURNS: the object that stands for the device, i.e., a Gem root window.
;;
(defun init-device (device-type display-name)
  (let ((entry (assoc device-type *device-initializers*)))
    (if entry
      (funcall (cdr entry) display-name)
      (error "gem::init-device: the specified device ~S does not exist."
             device-type))))




;;; --------------------------------------------------


;;; This is a utility function, used only for interactive debugging.
;;;
(defmacro adjust (name)
  `(progn
    (attach-method
     x-device
     (intern ,(symbol-name name) (find-package "KEYWORD"))
     (symbol-function (intern (concatenate 'string "X-" ,(symbol-name name))
			      (find-package "GEM"))))
    (set-window-methods opal::window gem::x-device)))



;;; Another debugging function
;;;
(defun trace-gem (device)
  (let ((prefix
	 (case device
	   (:X "GEM::X-")
	   (t
	    (error "Unknown device ~S in trace-gem" device)))))
    (dolist (key *method-names*)
      (let ((name (read-from-string
		   (concatenate 'simple-string prefix (symbol-name key)))))
	(eval `(trace ,name))
	(eval `(adjust ,key))))))


(defun untrace-gem (device)
  (let ((prefix
	 (case device
	   (:X "GEM::X-")
	   (t
	    (error "Unknown device ~S in trace-gem" device)))))
    (dolist (key *method-names*)
      (let ((name (read-from-string
		   (concatenate 'simple-string prefix (symbol-name key)))))
	(eval `(untrace ,name))
	(eval `(adjust ,key))))))


;;;
;;; Macros shared by "mac.lisp" and "x.lisp"
;;;

;;; Given an Opal window, return the display structure that is attached
;;; to it.
;;;
(defmacro the-display (window)
  `(display-info-display (g-value ,window :display-info)))

;;; RETURNS: the buffer for the <window>, if this is a double-buffered
;;; window, or the main drawable otherwise.
;;;
(defmacro the-drawable (window)
  `(or (g-local-value ,window :buffer) (g-value ,window :drawable)))
