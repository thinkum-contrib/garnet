;;; -*- Mode: LISP; Syntax: Common-Lisp; Package: OPAL; Base: 10 -*-
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;         The Garnet User Interface Development Environment.      ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; This code was written as part of the Garnet project at          ;;;
;;; Carnegie Mellon University, and has been placed in the public   ;;;
;;; domain.  If you are using this code or any part of Garnet,      ;;;
;;; please contact garnet@cs.cmu.edu to be put on the mailing list. ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; The Aggregadgets. A straightforward way to define hierarchical
;;; graphical objects.
;;;
;;; Philippe Marchal Feb. 1989

#|
======================================================================
Change log:
  05 Jan 94 amickish  Set-values ---> s-value
  15 Jun 93 amickish  In Get-Part-From-Function, don't set up :known-as if the
                      part-name is a number
  10 Jun 93 amickish  Moved definition of safe-functionp to garnet-utils
  20 May 93 amickish  Had to declare name slot of agget constant in Call-C-I
  19 May 93 amickish  Called add-component/interactor inside Call-Create-Inst
                      so that Create-Part and Create-Inter do not have to
                      add extra slot/value pairs to the slots list.
   7 Apr 93 amickish  Declared part-name constant in agget in Get-Part-From-Fn
  26 Mar 93 amickish  Removed EVAL from Call-Create-Instance for the last time!
  25 Mar 93 dzg  Added DECLARE-CONSTANT's in Get-Part-From-Function
  26 Feb 93 amickish  Rewrote Call-Create-Instance to use begin/end-create-
                      instance and not use copy-tree (ick).
   3 Jun 92 amickish  Wrote Get-Part-From-Function which allows a single part
                      to be generated by a function
  30 Apr 92 amickish  Bound kr::*redefine-ok* in Create-Part
  28 Apr 92 amickish  Wrapped destroy-slot calls in with-constants-disabled
   8 Apr 92 amickish  Made Call-Create-Instance non-destructive
   7 Apr 92 amickish  Wrapped calls to Call-Create-Instance in
                      with-constants-disabled.
  26 Mar 92 amickish  Get-Values--->G-Value; Get-Local-Values--->G-Local-Value
  16 Mar 92 amickish  Removed append-constant-slots -- obviated by KR.
  10 Mar 92 amickish  Fixed Call-Create-Instance to handle multiple-values
  03 Mar 92 amickish  Fixed Inherit-Values to use *inherit-formula*; broke
                      Get-Inherited-Value off from Inherit-Values
  28 Feb 92 amickish  Quoted class parameter in Call-Create-Instance
  24 Feb 92 amickish  Declared :components constant in :initialize method
  18 Feb 92 amickish  Implemented :constant slot functionality
  28 Jan 92 amickish  Rewrote create-part and create-inter to use
                  create-instance.  Changed name of first-obj-in-parts-list
                  to is-first-comp-in-parts-list.
  15 Apr 91 bam   Added the :behaviors slot to the :local-only-slots of
                  aggregadget
  16 Jul 90 rbd   Changed compilation order: aggregadgets first
   8 May 90 rbd   Major changes for new version.
   11/28/89 ecp   Fixed bug in create-part such that aggrelists were not
                  getting initialized correctly.
    9/28/89 ecp   Aggrelists can now have :interactors slots, too.
    9/18/89 ecp   Copy-parts should not have been calling itself recursively.
    9/14/89 ecp   The :initialize method for aggregadgets has optional
                  second argument to keep track of top level.
    8/2/89  prm   Optimized code after review meeting.
    7/20/89 prm   Removed aggregitems (now integrated to aggrelists).
    7/13/89 prm   Changed to work with aggrelists.
    7/6/89  prm   Changed syntax (class names must be comma-ed) to keep
                  everything consistent.
    6/28/89 prm   Changed to accept open formulas. This involved a change
                  of syntax (:parts and :interactors are now lists)
    6/28/89 prm   Changed the syntax: now :parts and :interactors are
                  lists instead of multi-value slots.
    6/28/89 prm   Fixed a bug: now sets :behaviors properly
    6/23/89 prm   Quoted the names in calls to create-instance, in order
                  to match KR 2.2
    6/8/89  prm   Added "element style" components (aggregitems)
    6/5/89  prm   Fixed a bug: now when copying a part that is an
                  aggregadget, create-prototype is called instead
                  of create-instance
    5/15/89 prm   Optimized the creation of instances of aggregadget
                  prototypes (makes copies of the prototype).
    5/11/89 prm   call-prototype-method moved to the beginning
                  of the :initialize method.
    4/18/89 prm   Changed again to match KR v2.0 (methods)
    4/07/89 prm   Changed to match KR v2.0
    3/28/89 prm   Added built-in interactors.
======================================================================
|#

(in-package "OPAL")
(eval-when (eval load compile)
  (export '(GVL-SIBLING AGGREGADGET)))

;;;---------------------------------------------------------
;;; Macros to make the pathes to other objects more readable
;;;---------------------------------------------------------

;;; To access slots in a sibling object.
;;; (gvl-sibling :brother :top) will expand into:
;;; (gvl :parent :brother :top)
(defmacro gvl-sibling (name &rest slots)
  `(gvl :parent ,name ,@slots))

;;;
;;; Macros to access to the elements of a part or interactor
;;; definition of an aggregadget.
;;;

;;; Gives the name of the part or inter,
(defmacro get-name (def)
  `(car ,def))

;;; Gives the name of class of the part or inter.
(defmacro get-class-name (def)
  `(cadr ,def))

;;; Gives the body of the part  or inter (slots definitions)
(defmacro get-body (def)
  `(cddr ,def))

;;;
;;; An Aggregadget is an aggregate that builds itself, using a slot
;;; called "parts" where the components of the aggregadget are described;
;;; and a slot called "interactors" where the interactors that operates
;;; on the aggregadget are described.
;;;

(create-instance 'opal:aggregadget opal:aggregate
  (:local-only-slots '((:behaviors nil) (:window nil) (:parent nil))))


;;;--------------------------------------------------------------------------
;;;
;;; Utility functions
;;;
;;;--------------------------------------------------------------------------

;;;
;;;  Function for generating an instance from a list of slot/value pairs
;;;
(defun call-create-instance (class slots agget &key name add-as)
  (unless (schema-p class)
    (error "~A ~A ~A ~A~%?"
	   "Is a comma missing before" class "in declaration of" agget))
  (let ((obj (kr::begin-create-instance NIL class :name-prefix name)))
    (dolist (pair slots)
      (if (consp pair)
	  (let ((val-list (cdr pair))
		(slot (car pair)))
	    (if (cdr val-list)
		;; Multiple values were supplied
		(s-value obj slot val-list)
		;; A single value was supplied.
		(s-value obj slot (car val-list))))))
    (when name (s-value obj :known-as name))
    (case add-as
      (:component (with-constants-disabled (add-local-component agget obj)))
      (:interactor (with-constants-disabled (add-local-interactor agget obj))))
    ;; The following instruction would have been done during the add, but
    ;; constants were disabled.
    (when (and add-as name) (declare-constant agget name))
    (kr::end-create-instance obj)
    obj
    ))

;;;  
;;;       Inherit-Values is used to copy down formulas from the parts of a
;;;  prototype aggregadget.  SLOTS is a list of slots to go in a part of AGG.
;;;  For example, I might want to specify that a part named :box is an
;;;  opal:circle rather than an instance of the :box part in the prototype.
;;;  Nevertheless, I might want to still inherit :left, :top, :width, and
;;;  :height from the prototype part.  
;;;       If the prototype component has a formula in the inherited slot,
;;;  then the component instance gets an instance of that formula.  Otherwise,
;;;  the component instance gets a new formula that looks at its prototype
;;;  component's slot.  This is the special *inherit-formula*, which is checked
;;;  in copy-agg and save-agg.

(defvar *inherit-formula* (o-formula (gv (car (gvl :parent :is-a))
					 (gvl :known-as) kr::*schema-slot*)))

(defun get-inherited-value (quasi-prototype inherited-slot)
  (let ((inherited-formula (get-value quasi-prototype inherited-slot)))
    (if (formula-p inherited-formula)
	(formula inherited-formula)
        (formula *inherit-formula*))))

(defun inherit-values (slots agg proto-component-name)
  (do ((slots-aux slots (cdr slots-aux)))
      ((null slots-aux))
    (let ((pair (car slots-aux)))
      (if (eq pair :inherit) ; the unusual case that :inherit was specified
	  (let ((inherited-slots (second slots-aux))
		(quasi-prototype (g-value (car (g-value agg :is-a))
					  proto-component-name)))
	    (setf slots (remove :inherit slots))
	    (setf slots (remove inherited-slots slots))
	    (dolist (inherited-slot inherited-slots)
	      (push (list inherited-slot (get-inherited-value quasi-prototype
							      inherited-slot))
		    slots))))))
  slots)

;;;
;;; Test if the first component of agg is in the parts-list.
;;; May also be used to check for behaviors in the :interactors list.
;;;
(defun is-first-comp-in-parts-list (components parts-list)
  (if components
      (let ((first-comp (g-value (first components) :known-as)))
	(member first-comp parts-list 
		:test #'(lambda (fc part)
			  (let ((name (if (listp part)
					  (get-name part)
					  part)))
			    (if (numberp name)
				(eql 0 name)
				(eq fc name))))))))


;;;--------------------------------------------------------------------------
;;;
;;;    Initialize method
;;;
;;;--------------------------------------------------------------------------


;;;--------------------------------------------------------------------------
;;;  Initialization subroutines for making parts
;;;--------------------------------------------------------------------------

;;;    For each part, an instance is created and added to the components
;;; of the aggregadget.  If the part is named, then  1) a slot named after
;;; the part is created in the aggregadget with the component as its value,
;;; and  2) a :known-as slot is created in the part, whose value is the name
;;; of the part.  This processing is recursive in order to deal with
;;; aggregadgets inside aggregadgets.
;;;    Ditto for the interactors, except that they are added to the
;;; :behaviors list of the aggregadget instead of the :components list.
;;;       name - the keyword name of the part being created
;;;       class - the object that the part is an instance of
;;;       slots - slots that we will set in the new part
;;;       agget - the aggregadget that the new part will be a component of
(defun create-part (name class slots agget)
  (unless (schema-p class)
    (error "~A ~A ~A ~A~%   ~A ~A?"
	   "Is a comma missing before" class "in declaration of part" name
	   "of aggregadget" agget))
  ;; Take out :inherit keyword and install "inherited" formulas in slot list
  (setf slots (inherit-values slots agget name))
  ;; Add a few slots to the slots list
  (let (new-comp)
    (let ((kr::*redefine-ok* T))
      (setf new-comp (call-create-instance class slots agget
					   :name name
					   :add-as :component)))
    ;; Make :parent and :known-as constant slot
    (when (g-value agget :parts)
      (declare-constant new-comp :parent)
      (declare-constant new-comp :known-as))))

;;;
;;; Make instances of the components of a prototype.
;;;
(defun make-instances-from (agget prototype)
  (dolist (component (g-local-value prototype :components))
    (let ((part-fn (g-value component :*special-creator*))
	  (known-as (g-value component :known-as)))
      ;; Check if the part should be generated by a function
      (if part-fn
	  (get-part-from-function known-as agget part-fn)
	  (create-part known-as component NIL agget)))))

;;;  Generate a single part by executing the function supplied as a part
(defun get-part-from-function (part-name agget part-function)
  (let ((part (funcall part-function agget)))
    (with-constants-disabled
      (unless (numberp part-name) (s-value part :known-as part-name))
      (s-value part :*special-creator* part-function)
      (add-local-component agget part))
    (unless (numberp part-name) (declare-constant agget part-name))
    (declare-constant part :parent)
    (declare-constant part :known-as)))
    

;;;
;;;  Generate parts by calling the function supplied in the :parts slot
;;;
(defun get-parts-from-function (agget part-function)
  (multiple-value-bind (components names)
		       (funcall part-function agget)
    (if names
	;; the function did return names for the parts
	(do ((components-list components (cdr components-list))
	     (names-list names (cdr names-list)))
	    ((or (null components-list) (null names-list)))
	  (let ((this-part (car components-list))
		(this-part-name (car names-list)))
	    (when this-part-name
	      (s-value this-part :known-as this-part-name))
	    (let ((kr::*constants-disabled* T))
	      (add-local-component agget this-part))))
	;; the function did not return names for the parts
	(dolist (new-component components)
	  (let ((kr::*constants-disabled* T))
	    (add-local-component agget new-component))))))

(defun get-name-and-protopart-from-rank (rank prototype agget
					 &optional NIL-name-OK)
  (let ((protopart (nth rank (g-local-value prototype :components))))
    (if protopart
	(values (g-value protopart :known-as) protopart)
	(unless NIL-name-OK
	  (error "Error while making parts of ~S:
Could not find component of rank ~S in prototype.~%" agget rank)))))



;;;
;;; make-parts - make components for aggregadgets and aggrelists
;;;
(defun make-parts (agget parts-list prototype)
  (dolist (part parts-list)
    (let ((name NIL) (protopart NIL) (slots NIL))
      (cond
	;; The case where you want to inherit a part -- the user has
	;; put just the name of the part in the parts list
	((keywordp part)
	 (setf name part)
	 (setf protopart :modify))
	;; The case where the rank of the part (as it appears in the
	;; :components list of the prototype) is specified
	((numberp part)
	 (multiple-value-setq (name protopart)
	   (get-name-and-protopart-from-rank part prototype agget)))
	;; The case where you generate all the parts with a function
	((garnet-utils:safe-functionp part)
	 (get-parts-from-function agget part))
	;; The case where the :modify or :use keyword appears
	((and (listp part) (>= (length part) 2))
	 (setf name (get-name part))
	 (setf protopart (get-class-name part))
	 ;; Slots can either be a list of slot/value pairs or a function to
	 ;; generate a single part.
	 (setf slots (get-body part)))
	(t (error "bad part specification: ~S" part)))
      ;; now make an instance
      (cond ((eq protopart :omit))  ;; do nothing
	    ((eq protopart :modify)
	     (let ((fn (car slots))) ;; Check if part is generated by function
	       (cond ((garnet-utils:safe-functionp fn)
		      (get-part-from-function name agget fn))
		     (t (if (numberp name)
			    (multiple-value-setq (name protopart)
			      (get-name-and-protopart-from-rank
			       name prototype agget))
			    (setf protopart (g-local-value prototype name)))
			(if protopart
			    (create-part name protopart slots agget)
			    (warn "Warning while making parts of ~S:
~S not found in prototype, ignoring this part: ~S~%" agget name part))))))
	    ((garnet-utils:safe-functionp protopart)
	     (get-part-from-function name agget protopart))
	    ((garnet-utils:safe-functionp part)) ;; instances were created already
	    (t (if (numberp name)
		   (setf name (get-name-and-protopart-from-rank
			       name prototype agget T)))
	       (create-part name protopart slots agget))))))


;;;--------------------------------------------------------------------------
;;;  Initialization subroutines for making interactors
;;;--------------------------------------------------------------------------

(defun create-inter (name class slots agget)
  (unless (schema-p class)
    (error "Comma missing before ~A in declaration of interactor ~A~%   of aggregadget ~A."
	   class name agget))
  ;; Take out :inherit keyword and install "inherited" formulas in slot list
  (setf slots (inherit-values slots agget name))
  ;; Add a few slots to the slots list
  (let (new-inter)
    (with-constants-disabled
      (setf new-inter (call-create-instance class slots agget
					    :name name
					    :add-as :interactor)))
    (when (g-value agget :interactors)
      (declare-constant new-inter :known-as))))


(defun make-inters-from (agget prototype)
  (dolist (inter (g-local-value prototype :behaviors))
    (create-inter (g-value inter :known-as) inter nil agget)))

(defun get-inters-from-function (agget inter-function)
  (multiple-value-bind (inters names)
		       (funcall inter-function agget)
    (if names
	;; the function did returned names for the inters
	(do ((inters-list inters (cdr inters-list))
	     (names-list names (cdr names-list)))
	    ((or (null inters-list) (null names-list)))
	  (let ((this-inter (car inters-list))
		(this-inter-name (car names-list)))
	    (s-value agget :behaviors 
                     (nconc (g-local-value agget :behaviors)
                            (list this-inter)))
	    (s-value this-inter :operates-on agget)
	    (when this-inter-name    ; the current inter has a name
	      (s-value agget this-inter-name this-inter)
	      (s-value this-inter :known-as this-inter-name))))
	;; the function did not return names for the inters
	(dolist (new-inter inters)
	  (s-value agget :behaviors 
                   (nconc (g-local-value agget :behaviors) (list new-inter)))
	  (s-value new-inter :operates-on agget)))))
	
;;;
;;; make-interactors -- make interactors for aggregadgets and aggrelists
;;;
(defun make-interactors (agget inter-list prototype)
  ;; now do the interactors
  (dolist (inter inter-list)
    (let (name slots protointer)
      (cond ((listp inter)
	     (setf name (get-name inter))
	     (setf protointer (get-class-name inter))
	     (setf slots (get-body inter)))
	    ((keywordp inter)
	     (setf name inter)
	     (setf protointer :modify))
	    (t (error "bad interactor specification: ~S" inter)))
      (cond ((eq protointer :omit))
	    ((eq protointer :modify)
	     (setf protointer (g-value prototype name))
	     (cond ((null protointer)
		    (format t 
		     "Warning in AGGREGADGET-INITIALIZE-METHOD: ~S not found ~
		     in prototype, ignoring this inter: ~A~%" name inter-list))
		   (t (create-inter name protointer slots agget))))
	    (t (create-inter name protointer slots agget))))))


;;;
;;; The initialize method for aggregadgets.
;;; If the aggregadget is a prototype (an instance of opal:aggregadget), its
;;; components and interactors are created according to the :parts and
;;; :interactors slots.
;;; If it is an instance of a prototype, the :parts slot is a guide to
;;; making instances of the prototype's components and interactors.
;;; The algorithm is the following: 
;;;    if there is no parts list, just make instances of prototype's components
;;;    if the first item of the prototype is not in the parts list, make
;;;        instances of all the prototype components and then add from the
;;;        parts list
;;;    for each name in the parts list, do one of the following:
;;;        (1) if prototype is :omit, omit the component, but put a link to nil
;;;        (2) if prototype is :modify,  make an instance of the
;;;        corresponding part, but use the given slot/value list to override
;;;        inherited slots
;;;        (3) if prototype is an object, then make an instance of it

(define-method :initialize aggregadget (agget)
  (call-prototype-method agget)
  (let ((prototype (car (g-local-value agget :is-a)))
	(parts-list (g-local-value agget :parts))
	(inter-list (g-local-value agget :interactors)))
    (if (or (null parts-list) 
	    (not (is-first-comp-in-parts-list 
		  (g-local-value prototype :components) parts-list)))
	;; create instances of components of a prototype aggregadget
	(make-instances-from agget prototype))
    (make-parts agget parts-list prototype)
    (if (or (null inter-list) 
	    (not (is-first-comp-in-parts-list  ; use same fn for inters
		  (g-local-value prototype :behaviors) inter-list)))
	(make-inters-from agget prototype))
    (make-interactors agget inter-list prototype)
    (if (or parts-list (g-value agget :parts))
	(declare-constant agget :components))))


;;;--------------------------------------------------------------------------
;;;
;;;   Add/Remove component methods for aggregadgets
;;;
;;;--------------------------------------------------------------------------


(define-method :add-component aggregadget (agg element &rest args)
  (let (where locator known-as)
    (cond ((eq (first args) :where)
	   (setq where (second args))
	   (setq locator (third args)))
	  ((first args)
	   (setq where (first args))
	   (setq locator (second args)))
	  (t
	   (setq where :tail)))

    ;; first add to prototype
    (add-local-component agg element where locator)

    ;; now do instances
    (setf known-as (g-local-value element :known-as))
    (dolist (agg-instance (g-local-value agg :is-a-inv))
      (let ((element-instance (create-instance nil element))
	    (my-where where)
	    my-locator)
	(s-value element-instance :known-as known-as)
	(cond ((member where '(:front :tail :back :head)))
	      ((member where '(:behind :before :in-front :after))
	       ;; see if instance of locator is in agg-instance
	       (setf my-locator (find-locator-instance locator agg-instance))
	       (cond (my-locator) ; no problem
		     (t           ; put new component at the :front
		      (setf my-where :front))))
	      ;; otherwise this must be an :at
	      (t (setf my-locator locator)))
	(add-component agg-instance element-instance my-where my-locator)))))


;;; add-local-component -- to an aggregadget
;;;
(define-method :add-local-component opal:aggregadget
  (agg gob &optional key where loc)
  (let ((name (g-local-value gob :known-as)))
    (when name
      (let ((kr::*constants-disabled* T))
	(s-value agg name gob))
      (if (g-value agg :parts)
	  (declare-constant agg name)))
    ;; this would be just a call-prototype-method, but we have to 
    ;;  invoke :add-component, not :add-local-component
    (kr-send opal:aggregate :add-component agg gob key where loc)))


;;; remove-component -- remove a component from an aggregate and 
;;;   remove instances of the component from instances of the aggregate
;;;
;;; NOTE: we could do a quick-and-dirty job by just removing all instances
;;;  of component from their :parents, but the :parent might not be an
;;;  instance of agg, and we would not get components with the same name.
;;; To get everything but not too much, we will
;;;  (1) remove all instances from parents IF the parent :is-a this agg
;;;	 but the parent does not equal the agg.
;;;  (2) remove all parts that have the same name (:known-as) from the
;;;      aggregate's instances
;;;
(define-method :remove-component aggregadget (agg component &optional destroy?)
  (let ((component-instances (g-local-value component :is-a-inv))
	(known-as (g-local-value component :known-as)))
    (dolist (instance component-instances)
      (let ((parent (g-local-value instance :parent)))
        ;;; Condition used to be (is-a-p parent agg)
	(when (and (is-a-p parent agg) (not (eq parent agg)))
	  (remove-component parent instance destroy?))))
    (when known-as
      (dolist (agg-instance (g-local-value agg :is-a-inv))
	(let ((component (g-local-value agg-instance known-as)))
	  (when component
	    (remove-component agg-instance component destroy?)))))
    (remove-local-component agg component)
    (when destroy?
      (destroy component))))


;;; remove-local-component -- from an aggregadget
;;;
(define-method :remove-local-component opal:aggregadget (agg gob)
  (let ((name (g-local-value gob :known-as)))
    (if name (with-constants-disabled (destroy-slot agg name)))
    (kr-send opal:aggregate :remove-component agg gob)))


;;; Move-component method for aggregadgets.  Just does remove and add.
(define-method :move-component opal:aggregadget (agg comp &rest args)
  (let (where locator #+comment key)
    (multiple-value-setq (where locator #+comment key) (get-wheres args))
    (remove-component agg comp)
    (add-component agg comp where locator)))


;;;--------------------------------------------------------------------------
;;;
;;;    Add/Remove interactor methods for aggregadgets
;;;
;;;--------------------------------------------------------------------------


;;; add-interactor -- add an interactor to prototype and instances
;;;
(define-method :add-interactor aggregadget (agg interactor)
  (let (known-as)
    ;; first add to prototype
    (add-local-interactor agg interactor)

    ;; now do instances
    (setf known-as (g-local-value agg :known-as))
    (dolist (agg-instance (g-local-value agg :is-a-inv))
      (let ((interactor-instance (create-instance nil interactor)))
	(s-value interactor-instance :known-as known-as)
	(add-interactor agg-instance interactor-instance)))))


;;; add-local-interactor -- to an aggregadget or aggrelist
;;;
(define-method :add-local-interactor aggregadget (agg inter)
  (let ((name (g-local-value inter :known-as)))
    (when name
      (let ((kr::*constants-disabled* T))
	(s-value agg name inter))
      (if (g-value agg :interactors)
	  (declare-constant agg name)))
    (s-value inter :operates-on agg)
    (s-value agg :behaviors 
	     (nconc (g-local-value agg :behaviors) (list inter)))))


;;; remove-interactor
;;;
(define-method :remove-interactor aggregadget (agg interactor &optional destroy?)
  (let ((interactor-instances (g-local-value interactor :is-a-inv))
	(known-as (g-local-value interactor :known-as)))
    (dolist (instance interactor-instances)
      (let ((parent (g-local-value instance :operates-on)))
	(when (is-a-p parent agg)
	  (remove-interactor parent instance destroy?))))
    (when known-as
      (dolist (agg-instance (g-local-value agg :is-a-inv))
	(let ((interactor (g-local-value agg-instance known-as)))
	  (when interactor
	    (remove-interactor agg-instance interactor destroy?)))))
    (s-value interactor :active nil)
    (remove-local-interactor agg interactor)
    (when destroy?
      (destroy interactor))))

;;; remove-local-interactor -- from an aggregadget or aggrelist
;;;
(define-method :remove-local-interactor aggregadget (agg inter)
  (let ((name (g-local-value inter :known-as)))
    (if name (with-constants-disabled (destroy-slot agg name)))
    (s-value agg :behaviors (delete inter (g-local-value agg :behaviors)))))

;;;--------------------------------------------------------------------------
;;;
;;;    Take-Default-Component method
;;;
;;;--------------------------------------------------------------------------

;;; find-locator-instance -- find a locator in agg-instance that corresponds
;;;  to locator, presumed to be a member of the prototype of agg-instance
;;;
(defun find-locator-instance (locator agg-instance)
  (let ((agg-instance-components (g-local-value agg-instance :components))
	my-locator ; the locator we are trying to find
	known-as)  ; the :known-as field of locator

    ;; first look to see if locator has an instance in agg-instance
    (dolist (locator-instance (g-local-value locator :is-a-inv))
      (when (member locator-instance agg-instance-components)
	(setf my-locator locator-instance)
	(return)))

    ;; if that fails, then look for a component with the same name as locator
    (when (null my-locator)
      (setf known-as (g-local-value locator :known-as))
      (when known-as
	(setf my-locator (g-local-value agg-instance known-as))))

    ;; if no locator was found, then print a warning
    (when (null my-locator)
      (warn "~A ~A in aggregate ~A~%~A ~A."
	    "No component corresponding to locator"
	    locator (g-value locator :parent)
	    "could be found for aggregate " agg-instance))

    my-locator))


;;; take-default-component -- remove a component and inherit default from
;;; prototype NOTICE that the argument is the NAME of the component to remove.
;;; An instance of the default prototype (if there is one) is placed :in-front
;;; of the appropriate component using add-component so that this change 
;;; propagates down to instances of agg.  If this component is not :in-front
;;; of anything, then :back is used.
;;;
(define-method :take-default-component aggregadget (agg name &optional destroy?)
  (let ((component (g-local-value agg name))
	(proto-agg (g-local-value agg :is-a))
	(where :in-front)
	locator)
    ;; if the component exists locally, remove it
    (when component
      (remove-component agg component destroy?))

    ;; find the new prototype component in the prototype aggregadget
    (setf component (g-local-value proto-agg name))

    (when component
      ;; find the element before component to serve as a locator
      (dolist (element (g-local-value proto-agg :components))
	(if (eq element component) (return))
	(setf locator element)))

    ;; map the locator into the current agg if possible, if there is no
    ;; locator, then the component is at the :back of the prototype; if
    ;; the locator has no instance in agg, then put the instance at the
    ;; :front.
    (cond (locator
	   (setf locator (find-locator-instance locator agg))
	   
	   (when (null locator)
	     (setf where :front))) ; mapping failed, move to :front
	  (t 
	   (setf where :back))) ; null locator -> :back of aggregate

    ;; install a new prototype
    (when component
      (add-component agg (create-instance nil component) where locator))))


;;;--------------------------------------------------------------------------
;;;
;;;    Destroy Method
;;;
;;;--------------------------------------------------------------------------

;;; destroy-me -- gets interactors as well as components
;;;
(define-method :destroy-me opal:aggregadget (agg &optional (top-level-p t))
  (dolist (behavior (copy-list (g-local-value agg :behaviors)))
    (destroy behavior))
  (call-prototype-method agg top-level-p))
