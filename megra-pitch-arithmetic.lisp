(defun add (a b)
  (cond
    ((and (typep a 'number) (typep b 'number))
     (+ a b))
    ((and (is-note-name a) (is-note-name b))
     (cm::note (+ (cm::keynum a) (cm::keynum b))))
    ((and (is-note-name a) (typep b 'number))
     (cm::note (+ (cm::keynum a) b)))
    ((and (typep a 'number) (is-note-name b))
     (cm::note (+ b (cm::keynum b))))
    (t (+ a b))))
