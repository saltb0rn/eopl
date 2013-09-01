(let ((time-stamp "Time-stamp: <2001-05-11 13:13:24 dfried>"))
  (eopl:printf "7-4.scm: continuation-passing interpreter with exceptions ~a~%"
    (substring time-stamp 13 29)))

;;;;;;;;;;;;;;;; top level ;;;;;;;;;;;;;;;;

(define run
  (lambda (string)
    (eval-program (scan&parse string))))

(define run-all
  (lambda ()
    (run-experiment run use-execution-outcome
      '(lang3-5 lang3-6 lang3-7 lang7-4) all-tests)))

(define run-one
  (lambda (test-name)
    (run-test run test-name)))

;; needed for testing
(define equal-external-reps? equal?)


;;;;;;;;;;;;;;;; grammatical specification ;;;;;;;;;;;;;;;;

(define the-lexical-spec
  '((whitespace (whitespace) skip)
    (comment ("%" (arbno (not #\newline))) skip)
    (identifier
      (letter (arbno (or letter digit "_" "-" "?")))
      symbol)
    (number (digit (arbno digit)) number)))

(define the-grammar
  '((program (expression) a-program)
    (expression (number) lit-exp)
    (expression (identifier) var-exp)   
    (expression
      (primitive "(" (separated-list expression ",") ")")
      primapp-exp)
    (expression
      ("if" expression "then" expression "else" expression)
      if-exp)
   (expression
      ("let" (arbno  identifier "=" expression) "in" expression)
      let-exp)
    (expression
      ("proc" "(" (separated-list identifier ",") ")" expression)
      proc-exp)
    (expression
      ("(" expression (arbno expression) ")")
      app-exp)
    (expression ("set" identifier "=" expression) varassign-exp)
;     (expression
;       ("begin" expression (arbno ";" expression) "end")
;       begin-exp)
    (expression                         
      ("letrec"
        (arbno identifier "(" (separated-list identifier ",") ")"
          "=" expression)
        "in" expression)
      letrec-exp)

    (expression
      ("try" expression "handle" expression)
      try-exp)
    (expression
      ("raise" expression)
      raise-exp)

    (primitive ("+")     add-prim)
    (primitive ("-")     subtract-prim)
    (primitive ("*")     mult-prim)
    (primitive ("add1")  incr-prim)
    (primitive ("sub1")  decr-prim)
    (primitive ("zero?") zero-test-prim)
    (primitive ("equal?") equal-prim)

    (primitive ("list") list-prim)
    (primitive ("cons") cons-prim)
    (primitive ("nil")  nil-prim)
    (primitive ("car")  car-prim)
    (primitive ("cdr")  cdr-prim)
    (primitive ("null?") null?-prim)

    ))

(sllgen:make-define-datatypes the-lexical-spec the-grammar)

(define list-the-datatypes
  (lambda () (sllgen:list-define-datatypes the-lexical-spec the-grammar)))

(define scan&parse
  (sllgen:make-string-parser the-lexical-spec the-grammar))

(define just-scan
  (sllgen:make-string-scanner the-lexical-spec the-grammar))

;;;;;;;;;;;;;;;; values ;;;;;;;;;;;;;;;;

(define expval?                         
  (lambda (x)
    (or (number? x) (procval? x) ((list-of expval?) x))))

;;;;;;;;;;;;;;;; the interpreter ;;;;;;;;;;;;;;;;

(define eval-program 
  (lambda (pgm)
    (cases program pgm
      (a-program (body)
        (eval-expression body (init-env) (halt-cont))))))

(define eval-expression                 ; exp * env * cont -> expval
  (lambda (exp env cont)
    (cases expression exp
      (lit-exp (datum) (apply-cont cont datum))
      (var-exp (id) (apply-cont cont (apply-env env id)))
      (proc-exp (ids body)
        (apply-cont cont (closure ids body env)))
      (letrec-exp (proc-names idss bodies letrec-body)
        (eval-expression letrec-body
          (extend-env-recursively proc-names idss bodies env)
          cont))
      ;; an easy non-simple guy
      (if-exp (test-exp true-exp false-exp)
        (eval-expression test-exp env
          (test-cont true-exp false-exp env cont)))
      (primapp-exp (prim rands)
        (eval-rands rands env (prim-args-cont prim cont)))
      (let-exp (ids rands body)
        (eval-rands rands env
          (let-exp-cont ids env body cont)))
      (app-exp (rator rands)
        (eval-expression rator env
          (eval-rator-cont rands env cont)))
      (varassign-exp (id rhs-exp)
        (eval-expression rhs-exp env
          (varassign-cont env id cont)))
      (try-exp (body-exp handler-exp)
        (eval-expression handler-exp env
          (handler-cont body-exp env cont)))
      (raise-exp (exp)
        (eval-expression exp env (raise-cont cont)))
;;       (begin-exp (exp1 exps)
;;         (eopl:error 'eval-expression
;;           "Begin not implemented in 7-4.scm"))
      )))

(define eval-rands
  (lambda (rands env cont)
    (if (null? rands) (apply-cont cont '())
      (eval-expression (car rands) env
        (eval-first-cont rands env cont)))))

(define apply-primitive
  (lambda (prim args)
    (cases primitive prim
      (add-prim  () (+ (car args) (cadr args)))
      (subtract-prim () (- (car args) (cadr args)))
      (mult-prim  () (* (car args) (cadr args)))
      (incr-prim  () (+ (car args) 1))
      (decr-prim  () (- (car args) 1))
      (zero-test-prim () (if (zero? (car args)) 1 0))
      (equal-prim () (if (equal? (car args) (cadr args)) 1 0))
      (list-prim () args)               ;already a list
      (nil-prim () '())
      (car-prim () (car (car args)))
      (cdr-prim () (cdr (car args)))
      (cons-prim () (cons (car args) (cadr args)))
      (null?-prim () (if (null? (car args)) 1 0))
      )))

(define init-env 
  (lambda ()
    (extend-env
      '(i v x)
      '(1 5 10)
      (empty-env))))

;;;;;;;;;;;;;;;; booleans ;;;;;;;;;;;;;;;;

(define true-value?
  (lambda (x)
    (not (zero? x))))

;;;;;;;;;;;;;;;; procedures ;;;;;;;;;;;;;;;;

(define-datatype procval procval?
  (closure 
    (ids (list-of symbol?)) 
    (body expression?)
    (env environment?)))

(define apply-procval
  (lambda (proc args cont)
    (cases procval proc
      (closure (ids body env)
        (eval-expression body
          (extend-env ids args env)
          cont)))))
               
;;;;;;;;;;;;;;;; continuations ;;;;;;;;;;;;;;;;

(define-datatype continuation continuation?
  (halt-cont)
  (test-cont
    (true-exp expression?)
    (false-exp expression?)
    (env environment?)
    (cont continuation?))
  (prim-args-cont (prim primitive?)
    (cont continuation?))
  (let-exp-cont
    (ids (list-of symbol?))
    (env environment?)
    (body expression?)
    (cont continuation?))
  (eval-rator-cont
    (rands (list-of expression?))
    (env environment?)
    (cont continuation?))
  (eval-rands-cont
    (proc expval?)
    (cont continuation?))
  (eval-first-cont 
    (exps (list-of expression?))
    (env environment?)
    (cont continuation?))
  (eval-rest-cont 
    (first-value expval?)
    (cont continuation?))
  (varassign-cont
    (env environment?)
    (id symbol?)
    (cont continuation?))
  (handler-cont
    (body expression?)
    (env environment?)
    (cont continuation?))
  (try-cont
    (handler expval?)
    (cont continuation?))
  (raise-cont
    (cont continuation?))
  )

(define apply-cont
  (lambda (cont val)
    (cases continuation cont
      (halt-cont ()
        (begin
          (eopl:printf "The answer is: ~s~%" val)
          val))
      (test-cont (true-exp false-exp env cont)
        (if (true-value? val)
          (eval-expression true-exp env cont)
          (eval-expression false-exp env cont)))
      (prim-args-cont (prim cont)
        (let ((args val))
          (apply-cont cont (apply-primitive prim args))))
      (let-exp-cont (ids env body cont)
        (let ((new-env (extend-env ids val env)))
          (eval-expression body new-env cont)))
      (eval-rator-cont (rands env cont) 
        (let ((proc val))
          (eval-rands rands env (eval-rands-cont proc cont))))
      (eval-rands-cont (proc cont)
        (let ((args val))
          (if (procval? proc)
            (apply-procval proc args cont)
            (eopl:error 'eval-expression 
              "Attempt to apply non-procedure ~s" proc))))
      (eval-first-cont (exps env cont)
        (eval-rands (cdr exps) env
          (eval-rest-cont val cont)))
      (eval-rest-cont (first cont)
        (let ((rest val))
          (apply-cont cont (cons first rest))))
      (varassign-cont (env id cont)
        (begin
          (setref! (apply-env-ref env id) val)
          (apply-cont cont 1)))
      (handler-cont (body-exp env cont)
        (if (procval? val)
          (eval-expression body-exp env (try-cont val cont))
          (eopl:error 'eval-expression
            "Exception handler not a procedure: ~s" handler-val)))
      (try-cont (handler cont)
        (apply-cont cont val))
      (raise-cont (cont)
        (find-handler val cont))
      )))

(define find-handler
  (lambda (val cont)
    (cases continuation cont
      (try-cont (handler cont)
        (apply-procval handler (list val) cont))
      (halt-cont ()
        (eopl:error 'find-handler
          "Uncaught exception ~s" val))
      (test-cont (true-exp false-exp env cont) 
        (find-handler val cont))
      (prim-args-cont (prim cont)
        (find-handler val cont))
      (let-exp-cont (ids env body cont)
        (find-handler val cont))
      (eval-rator-cont (rands env cont) 
        (find-handler val cont))
      (eval-rands-cont (proc cont)
        (find-handler val cont))
      (eval-first-cont (exps env cont)
        (find-handler val cont))
      (eval-rest-cont (first cont)
        (find-handler val cont))
      (varassign-cont (env id cont)
        (find-handler val cont))
      (handler-cont (body-exp env cont)
        (find-handler val cont))
      (raise-cont (cont)
        (find-handler val cont))
      )))

;;;;;;;;;;;;;;;; references ;;;;;;;;;;;;;;;;

(define-datatype reference reference?
  (a-ref
    (position integer?)
    (vec vector?)))

(define deref 
  (lambda (ref)
    (cases reference ref
      (a-ref (pos vec)
             (vector-ref vec pos)))))

(define setref! 
  (lambda (ref val)
    (cases reference ref
      (a-ref (pos vec)
             (vector-set! vec pos val)))
    1))

;;;;;;;;;;;;;;;; environments ;;;;;;;;;;;;;;;;

(define-datatype environment environment?
  (empty-env-record)
  (extended-env-record
    (syms (list-of symbol?))
    (vec vector?)              ; can use this for anything.
    (env environment?))
  )

(define empty-env
  (lambda ()
    (empty-env-record)))

(define extend-env
  (lambda (syms vals env)
    (extended-env-record syms (list->vector vals) env)))

(define apply-env-ref
  (lambda (env sym)
    (cases environment env
      (empty-env-record ()
        (eopl:error 'apply-env-ref "No binding for ~s" sym))
      (extended-env-record (syms vals env)
        (let ((position (rib-find-position sym syms)))
          (if (number? position)
              (a-ref position vals)
              (apply-env-ref env sym)))))))

(define apply-env
  (lambda (env sym)
    (deref (apply-env-ref env sym))))

(define extend-env-recursively
  (lambda (proc-names idss bodies old-env)
    (let ((len (length proc-names)))
      (let ((vec (make-vector len)))
        (let ((env (extended-env-record proc-names vec old-env)))
          (for-each
            (lambda (pos ids body)
              (vector-set! vec pos (closure ids body env)))
            (iota len) idss bodies)
          env)))))

(define rib-find-position 
  (lambda (sym los)
    (list-find-position sym los)))

(define list-find-position
  (lambda (sym los)
    (list-index (lambda (sym1) (eqv? sym1 sym)) los)))

(define list-index
  (lambda (pred ls)
    (cond
      ((null? ls) #f)
      ((pred (car ls)) 0)
      (else (let ((list-index-r (list-index pred (cdr ls))))
              (if (number? list-index-r)
                (+ list-index-r 1)
                #f))))))

(define iota
  (lambda (end)
    (let loop ((next 0))
      (if (>= next end) '()
        (cons next (loop (+ 1 next)))))))

(define difference
  (lambda (set1 set2)
    (cond
      ((null? set1) '())
      ((memv (car set1) set2)
       (difference (cdr set1) set2))
      (else (cons (car set1) (difference (cdr set1) set2))))))
