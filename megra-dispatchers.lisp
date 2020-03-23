;; event dispatching and related stuff ... 

;; simple time-recursive dispatching
(in-package :megra)

;; activate if debugging ...
(incudine::set-sharp-square-bracket-syntax)
(incudine::add-sharp-square-bracket-syntax)

;; helper to store sync informations, wraps around the event generator
(defclass processor-sync ()
  ((name :accessor name :initarg :name)
   (processor :accessor processor :initarg :processor)
   (synced-syncs :accessor synced-syncs :initform nil)
   (synced-progns :accessor synced-progns :initform nil)
   ;; think of anschluss-zug -> connection train ... 
   (anschluss-kette :accessor anschluss-kette :initform nil) 
   (wait-for-sync :accessor wait-for-sync :initform nil)
   (active :accessor is-active :initform nil :initarg :is-active)
   (shift :accessor sync-shift :initform 0.0 :initarg :shift)))

(defun activate (sync)  
  (setf (wait-for-sync sync) nil)
  (setf (is-active sync) t))

;; deactivate ... if it's a modifying event processor, delete it ...
(defun deactivate (sync)
  (setf (wait-for-sync sync) nil)
  (setf (is-active sync) nil))

(defmethod pull-events ((p processor-sync) &key)
  (pull-events (processor p)))

(defmethod pull-transition ((p processor-sync) &key)
  (pull-transition (processor p)))

;;;;;;;;;;;;;;;; EVENT DISPATCHING ;;;;;;;;;;;;;;;;;;;;
;; time recursions and management thereof ...

;; this one is used for mac, because time handling is a bit different
;; there with port
(defun perform-dispatch-sep-times (sync osc-time incudine-time)
  ;; regular case ... 
  (when (and sync (is-active sync))
    ;; here, the events are produced and handled ...
    (when (synced-syncs sync)
      (loop for synced-sync in (synced-syncs sync)	     
	    ;; don't check if it's active, as only deactivated procs
	    ;; are added to sync list
	    do (let ((sync-shift (sync-shift synced-sync)))	        
	         (activate synced-sync)	      
	         (setf (sync-shift synced-sync) 0)
	         ;; secure this to ensure smooth operation in case of
	         ;; forgotten graphs ... 	        
	         (handler-case		    
		     (incudine:aat (+ incudine-time #[sync-shift ms])
				   #'perform-dispatch-sep-times
				   synced-sync
				   (+ osc-time (* sync-shift 0.001))
				   it)		  		
		   (simple-error (e) (incudine::msg error "~D" e)))))
      ;; reset all synced processors
      (setf (synced-syncs sync) nil))
    (handler-case
	(when (synced-progns sync)
	  (mapc #'funcall (synced-progns sync))
	  (setf (synced-progns sync) nil))
      (simple-error (e)
	(incudine::msg error "cannot handle sync-progns: ~D" e)
	(setf (synced-progns sync) nil)))
    ;; handle events from current graph
    ;; again, secure this, so that the sync can be restarted
    ;; without having to clear everything ...
    (handler-case (handle-events (pull-events sync) osc-time)
      (simple-error (e)
	(incudine::msg error "cannot pull and handle events: ~D" e)
	;;(setf (is-active sync) nil)
	))   
    ;; here, the transition time between events is determinend,
    ;; and the next evaluation is scheduled ...
    ;; this method works only with SC,
    ;; with INCUDINE itself it'll be imprecise ... 
    (let* ((trans-time (* (if (typep *global-tempo-mod* 'param-mod-object) (evaluate *global-tempo-mod*) *global-tempo-mod*)
                          (transition-duration (car (pull-transition sync)))))
	   (next-osc-time (+ osc-time (* trans-time 0.001)))
	   (next-incu-time (+ incudine-time
			      #[(- next-osc-time (incudine::timestamp)) s])))
      (incudine:aat next-incu-time
		    #'perform-dispatch-sep-times sync next-osc-time it))))

(defun perform-dispatch (sync incudine-time) 
  (when (and sync (is-active sync))
    ;; here, the events are produced and handled ...
    (when (synced-syncs sync)
      (loop for synced-sync in (synced-syncs sync)	     
	    ;; don't check if it's active, as only deactivated procs
	    ;; are added to sync list
	    do (let ((sync-shift (sync-shift synced-sync)))	        
	         (activate synced-sync)
	         (setf (wait-for-sync synced-sync) nil)
	         (setf (sync-shift synced-sync) 0)
	         ;; secure this to ensure smooth operation in case of
	         ;; forgotten graphs ... 	        
	         (handler-case		    
		     (incudine:aat (+ incudine-time #[sync-shift ms])
				   #'perform-dispatch
			           synced-sync
				   it)		  		
		   (simple-error (e) (incudine::msg error "~D" e)))))
      ;; reset all synced processors
      (setf (synced-syncs sync) nil))
    (handler-case
	(when (synced-progns sync)
	  (mapc #'funcall (synced-progns sync))
	  (setf (synced-progns sync) nil))
      (simple-error (e)
	(incudine::msg error "cannot handle sync-progns: ~D" e)
	(setf (synced-progns sync) nil)))
    ;; handle events from current graph
    ;; again, secure this, so that the sync can be restarted
    ;; without having to clear everything ...
    (handler-case (handle-events (pull-events sync) (incudine::rt-time-offset))
      (simple-error (e)
	(incudine::msg error "cannot pull and handle events: ~D" e)))
    ;; here, the transition time between events is determinend,
    ;; and the next evaluation is scheduled ...    
    (let* ((trans-time (* (if (typep *global-tempo-mod* 'param-mod-object) (evaluate *global-tempo-mod*) *global-tempo-mod*)
                          (transition-duration (car (pull-transition sync)))))
	   (next-incu-time (+ incudine-time #[trans-time ms])))      
      (incudine:aat next-incu-time #'perform-dispatch sync it))))

(defun handle-events (events osc-timestamp)
  (mapc #'(lambda (event) (handle-event event (+ osc-timestamp *global-osc-delay*))) events))

(defun inner-dispatch (sync sync-to)
  (let ((sync-to-sync-to (gethash sync-to *global-syncs*)))
    ;; now, if we want to sync the current sync to :sync-to,
    ;; and :sync-to denotes a sync that is actually present,    
    (cond      
      ((and sync-to-sync-to (is-active sync-to-sync-to))
       ;; when the current sync is NOT yet synced to sync-to-sync-to ...		      
       (unless (wait-for-sync sync)
	 (deactivate sync)
	 (setf (wait-for-sync sync) t)
	 ;;(incudine::msg info "syncing ~D to ~D, ~D will start at next dispatch of ~D" name sync-to name sync-to)
	 (setf (synced-syncs sync-to-sync-to)
	       (nconc (synced-syncs sync-to-sync-to)
		      (list sync)))))		      
      (t (unless (or (is-active sync) (wait-for-sync sync))
	   (incudine::msg error "start sync ~D" (name sync))
	   (activate sync)
           ;; different methods work, unfortunately, better on different operating systems ...
           #-linux (incudine:at (+ (incudine:now) #[(sync-shift sync) ms])
	   	                #'perform-dispatch-sep-times
	   	                sync
	   	                (+ (incudine:timestamp) (* (sync-shift sync) 0.001))
	   	                (+ (incudine:now) #[(sync-shift sync) ms]))
           #+linux (incudine:aat (+ (incudine:now) #[(sync-shift sync) ms])
			         #'perform-dispatch
			         sync				     
			         it))))))

(defun dispatch (name proc &key (sync nil) (shift 0.0) (intro nil))  
  (let ((sync-to (cond ((gethash sync *global-syncs*) sync)
                       ((gethash sync *multichain-directory*) (car (last (gethash sync *multichain-directory*))))
                       (t sync)))
        (old-sync (gethash name *global-syncs*)))
    ;; first, construct the sync ...
    (cond ((and old-sync (wait-for-sync old-sync))) ;; don't do anything, as there's a sync for this already ...  
	  (old-sync	   	   
           (setf (sync-shift old-sync) (max 0 (- shift (sync-shift old-sync))))
           (setf (processor old-sync) (if (functionp proc) (funcall proc) proc))) 	  
	  (t (let ((new-sync (make-instance 'processor-sync :name name :shift shift :processor (if (functionp proc) (funcall proc) proc) :is-active nil)))
               ;; store sync flag 
               (setf (gethash name *global-syncs*) new-sync)
               (if intro
                   (progn (handle-event intro 0)
                          (incudine:at (+ (incudine:now) #[(event-duration intro) ms])
			               #'(lambda ()     
                                           (inner-dispatch
                                            new-sync
                                            sync-to))))
                   (inner-dispatch new-sync sync-to)))))))

(defun once (event)
  (handle-event event 0))

(defun sx-inner (fprocs names sync)
  (loop for n from (- (length fprocs) 1) downto 0
        do (let ((sync-to (if sync
                              sync
                              (if (gethash (nth n names) *global-syncs*)                                               
                                  nil
                                  (if (< n (- (length fprocs) 1) )
                                      (car (last names))
                                      nil)))))
             ;;(incudine::msg error " >>>>>> PROC ~D ----- SYNC ~D" (nth n fprocs) sync-to)                              
             (dispatch (nth n names) (nth n fprocs) :sync sync-to))))

(defun sx (basename act sync intro &rest procs)
  (if (not act)
      (loop for name in (gethash basename *multichain-directory*)
            do (clear name))
      (let* ((fprocs (mapcar #'(lambda (p) (if (functionp p) (funcall p) p)) (alexandria::flatten procs)))
             (names (loop for n from 0 to (- (length fprocs) 1)
                          collect (intern (format nil "~D-~D" basename (name (nth n fprocs)))))))
        ;;(incudine::msg error "~D" names)
        ;; check if anything else is running under this name ... 
        (if (gethash basename *multichain-directory*)
            (loop for name in (gethash basename *multichain-directory*)
                  do (unless (member name names) (clear name))))
        (setf (gethash basename *multichain-directory*) names)
        (if intro
            (progn (handle-event intro 0)
                   (incudine:at (+ (incudine:now) #[(event-duration intro) ms])
			        #'(lambda () (sx-inner fprocs names sync))))
            (sx-inner fprocs names sync)))))

(defun xdup (&rest funs-and-proc)
  (let* ((funs (butlast funs-and-proc))
         (proc (car (last funs-and-proc)))
         (duplicates (loop for p from 0 to (- (length funs) 1)
                           collect (let ((proc-dup (funcall (nth p funs) (deepcopy proc))))
                                     (setf (name proc-dup)
                                           (intern (format nil "~D-~D" (name proc-dup) p)))
                                     proc-dup))))
    (nconc duplicates (list proc))))
