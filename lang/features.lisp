;; -*- lisp -*-

;; This file is part of STMX.
;; Copyright (c) 2013 Massimiliano Ghilardi
;;
;; This library is free software: you can redistribute it and/or
;; modify it under the terms of the Lisp Lesser General Public License
;; (http://opensource.franz.com/preamble.html), known as the LLGPL.
;;
;; This library is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty
;; of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
;; See the Lisp Lesser General Public License for more details.


(in-package :stmx.lang)


(eval-when (:compile-toplevel)
  #-(or abcl ccl cmucl ecl sbcl)
  (warn "Untested Common Lisp implementation.
STMX is currently tested only on ABCL, CCL, CMUCL, ECL and SBCL."))




(eval-always
  
  (pushnew :stmx *features*)
 
  
  (declaim (type list *feature-list*))
  (defvar *feature-list* nil)

  (defun intern-feature (f)
    (declare (type symbol f))
    (if (keywordp f)
        f
        (the keyword (intern (symbol-name f) :keyword))))

  (defun get-feature (f &optional default)
    "Return value of F in *FEATURE-LIST*, or DEFAULT if not present."
    (declare (type symbol f))
    (let ((pair (assoc (intern-feature f) *feature-list*)))
      (if pair
          (values (rest pair) t)
          (values default   nil))))

  (defun feature? (f)
    "Return T if F is present in *FEATURE-LIST*"
    (declare (type symbol f))
    (when (assoc (intern-feature f) *feature-list*)
      t))

  (defun all-features? (&rest list)
    "Return T if all features from LIST are present in *FEATURE-LIST*"
    (declare (type list list))
    (loop for f in list
       always (feature? f)))

  (defun any-feature? (&rest list)
    "Return T if at least one feature from LIST is present in *FEATURE-LIST*"
    (declare (type list list))
    (loop for f in list
       thereis (feature? f)))

  (defun add-feature (f &optional (value t))
    (declare (type symbol f))
    (unless (feature? f)
      (push (cons (intern-feature f) value) *feature-list*)))

  (defun add-features (&rest list)
    (declare (type list list))
    (dolist (pair list)
      (let ((feature (if (consp pair) (first pair) pair))
            (value   (if (consp pair) (rest  pair) t)))
        (add-feature feature value))))
          
 #+lispworks ;; porting still in progress
 (add-features 'disable-optimize-slot-access)

 #+abcl
 (add-features '(bt.lock-owner . :abcl))

 #+ecl
 (add-features '(bt.lock-owner . mp::lock-owner))

 #+cmucl
 (add-features '(bt.lock-owner . mp::lock-process))

 #+ccl
 (add-features '(bt.lock-owner . ccl::%%lock-owner))

 #+sbcl
 (add-features #+compare-and-swap-vops '(atomic-ops . :sbcl)
               #+memory-barrier-vops   '(mem-rw-barriers . :sbcl)
               ;; usually, bt.lock-owner it not needed on SBCL:
               ;; the combo atomic-ops + mem-rw-barriers provide fast-lock,
               ;; which has mutex-owner, a faster replacement for bt.lock-owner
               '(bt.lock-owner . sb-thread::mutex-owner)))





(eval-always
  ;; on x86 and x86_64, memory read-after-read and write-after-write barriers
  ;; are NOP (well, technically except for SSE)
  ;;
  ;; Unluckily, if the underlying Lisp does know about them,
  ;; so there is no way to stop the compiler from reordering assembler instructions.
  ;;
  ;; Luckily, the compiler cannot reorder memory-accessing assembler instructions
  ;; with function calls, which is the only guarantee we need to use bt.lock-owner
  ;; as long as we keep TVAR value and version in a CONS.
  ;;
  ;; note that in this case the memory barrier functions/macros do NOT
  ;; stop the compiler from reordering...
  #+(or x86 x8664 x86-64 x86_64)
  (unless (feature? 'mem-rw-barriers)
    (add-feature 'mem-rw-barriers :trivial))


  (unless (eql (get-feature 'mem-rw-barriers) :trivial)

    (if (all-features? 'atomic-ops 'mem-rw-barriers)
        ;; fast-lock requires atomic compare-and-swap plus real memory barriers.
        ;; Also, fast-lock provides the preferred implementation of mutex-owner,
        ;;   which does not use bt.lock-owner
        ;; 
        ;; Finally, with so rich primitives we do not need to wrap
        ;; TVAR value and version in a CONS, so add feature unwrapped-tvar
        (add-features 'fast-lock 'mutex-owner 'unwrapped-tvar)))


  (when (feature? 'mem-rw-barriers)
    ;; real - or fake - memory barriers.
    ;; no need to wrap TVAR value and version in a CONS
    (add-feature 'unwrapped-tvar)))


  (unless (any-feature? 'fast-lock 'mem-rw-barriers)
    ;; no fast-lock, and no memory barriers - not even no-op fake ones.
    ;; we will need to lock at each TVAR read :(
    ;; at least, unwrap TVAR version and value...
    (add-feature 'unwrapped-tvar))



  ;; if at least fake memory read/write barriers are available, bt.lock-owner
  ;; can be used as concurrency-safe mutex-owner even without atomic-ops
  (when (all-features? 'mem-rw-barriers 'bt.lock-owner)
    (add-feature 'mutex-owner))

  ;; (1+ most-positive-fixnum) is a power of two?
  (when (zerop (logand most-positive-fixnum (1+ most-positive-fixnum)))
    (add-feature 'fixnum-is-powerof2))

  ;; fixnum is large enough to count 10 million transactions
  ;; per second for at least 100 years?
  (when (>= most-positive-fixnum #x7fffffffffffff)
    (add-feature 'fixnum-is-large))

  ;; both the above two features
  (when (all-features? 'fixnum-is-large 'fixnum-is-powerof2)
    (add-feature 'fixnum-is-large-powerof2)))






