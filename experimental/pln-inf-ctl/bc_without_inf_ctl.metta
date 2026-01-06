;; ============================================================
;; Backward Chainer for Metamath Propositional Calculus
;; Compatible with PeTTa and propositional-calculus.metta corpus
;; ============================================================

;;;;;;;;;;;;;;;;;
;; Type System ;;
;;;;;;;;;;;;;;;;;

;; Natural numbers for depth tracking
(: Nat Type)
(: Z Nat)
(: S (-> Nat Nat))

;; Convert between Nat and Number
(: fromNumber (-> Number Nat))
(= (fromNumber $n) (if (<= $n 0) Z (S (fromNumber (- $n 1)))))
(: fromNat (-> Nat Number))
(= (fromNat Z) 0)
(= (fromNat (S $k)) (+ 1 (fromNat $k)))

;; List type
(: List (-> $a Type))
(: Nil (List $a))
(: Cons (-> $a (List $a) (List $a)))

;; Build list from expression
(: List.fromExpression (-> Expression (List $a)))
(= (List.fromExpression $expr)
   (if (== $expr ())
       Nil
       (let $head (car-atom $expr)
       (let $tail (cdr-atom $expr)
       (Cons $head (List.fromExpression $tail))))))

;;;;;;;;;;;;;;;;;;;
;; Match on List ;;
;;;;;;;;;;;;;;;;;;;

;; Match over a list instead of a space
(: match-list (-> (List $a) $b $c $c))
(= (match-list Nil $pattern $rewrite) (empty))
(= (match-list (Cons $head $tail) $pattern $rewrite)
   (case (match $head $pattern $rewrite)
     (($rewrite $rewrite)
      ($else (match-list $tail $pattern $rewrite)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Backward Chainer Signature ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Main backward chaining function
;; bc : Environment -> Context -> Depth -> Query -> Result
(: bc (-> (List $a)  ; Environment (known facts)
          (List $a)  ; Context (surrounding premises)
          Nat        ; Maximum depth
          $a         ; Query (what to prove)
          $a))       ; Result (proof)

;;;;;;;;;;;;;;;;
;; Base Cases ;;
;;;;;;;;;;;;;;;;

;; Match the environment - look for the query in known facts
(= (bc $env $ctx Z (: $prf $thrm))
   (match-list $env (: $prf $thrm) (: $prf $thrm)))

(= (bc $env $ctx (S $k) (: $prf $thrm))
   (match-list $env (: $prf $thrm) (: $prf $thrm)))

;; Axiom ax-1: φ → (ψ → φ)
(= (bc $env $ctx Z (: ax-1 (→ $𝜑 (→ $𝜓 $𝜑))))
   (: ax-1 (→ $𝜑 (→ $𝜓 $𝜑))))

(= (bc $env $ctx (S $k) (: ax-1 (→ $𝜑 (→ $𝜓 $𝜑))))
   (: ax-1 (→ $𝜑 (→ $𝜓 $𝜑))))

;; Axiom ax-2: (φ → (ψ → χ)) → ((φ → ψ) → (φ → χ))
(= (bc $env $ctx Z (: ax-2 (→ (→ $𝜑 (→ $𝜓 $𝜒)) (→ (→ $𝜑 $𝜓) (→ $𝜑 $𝜒)))))
   (: ax-2 (→ (→ $𝜑 (→ $𝜓 $𝜒)) (→ (→ $𝜑 $𝜓) (→ $𝜑 $𝜒)))))

(= (bc $env $ctx (S $k) (: ax-2 (→ (→ $𝜑 (→ $𝜓 $𝜒)) (→ (→ $𝜑 $𝜓) (→ $𝜑 $𝜒)))))
   (: ax-2 (→ (→ $𝜑 (→ $𝜓 $𝜒)) (→ (→ $𝜑 $𝜓) (→ $𝜑 $𝜒)))))

;; Axiom ax-3: (¬φ → ¬ψ) → (ψ → φ)
(= (bc $env $ctx Z (: ax-3 (→ (→ (¬ $𝜑) (¬ $𝜓)) (→ $𝜓 $𝜑))))
   (: ax-3 (→ (→ (¬ $𝜑) (¬ $𝜓)) (→ $𝜓 $𝜑))))

(= (bc $env $ctx (S $k) (: ax-3 (→ (→ (¬ $𝜑) (¬ $𝜓)) (→ $𝜓 $𝜑))))
   (: ax-3 (→ (→ (¬ $𝜑) (¬ $𝜓)) (→ $𝜓 $𝜑))))

;;;;;;;;;;;;;;;;;;;;
;; Recursive Step ;;
;;;;;;;;;;;;;;;;;;;;

;; Modus Ponens (ax-mp): from φ and (φ → ψ), derive ψ
(= (bc $env $ctx (S $k) (: (ax-mp $prf1 $prf2) $𝜓))
   (let (: $prf1 $𝜑) (bc $env (Cons (: $prf2 (→ $𝜑 $𝜓)) $ctx) $k (: $prf1 $𝜑))
   (let (: $prf2 (→ $𝜑 $𝜓)) (bc $env (Cons (: $prf1 $𝜑) $ctx) $k (: $prf2 (→ $𝜑 $𝜓)))
   (: (ax-mp $prf1 $prf2) $𝜓))))

;;;;;;;;;;;;;;;;;;;;;;;;;
;; Convenience Wrapper ;;
;;;;;;;;;;;;;;;;;;;;;;;;;

;; Prove a theorem with empty environment and context
(: prove (-> Nat $a $a))
(= (prove $depth $query)
   (bc Nil Nil $depth $query))

;; Prove with numeric depth
(: prove-n (-> Number $a $a))
(= (prove-n $n $query)
   (prove (fromNumber $n) $query))

;; Prove a theorem with given environment
(: prove-with-env (-> (List $a) Nat $a $a))
(= (prove-with-env $env $depth $query)
   (bc $env Nil $depth $query))

;; Prove with environment and numeric depth
(: prove-with-env-n (-> (List $a) Number $a $a))
(= (prove-with-env-n $env $n $query)
   (prove-with-env $env (fromNumber $n) $query))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Corpus Loading Support ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Extract axiom or theorem from MkIndex wrapper
(: extract-from-index (-> $a $a))
(= (extract-from-index (MkIndex $idx (MkAxiom $name $type)))
   (: $name $type))
(= (extract-from-index (MkIndex $idx (MkTheorem $name $proof $type)))
   ;; Use the actual proof term, not just the theorem name, so incorrect
   ;; proof terms do not unify.
   (: $proof $type))

;; Build environment from corpus
(: build-env-from-corpus (-> (List $a) (List $a)))
(= (build-env-from-corpus Nil) Nil)
(= (build-env-from-corpus (Cons $head $tail))
   (Cons (extract-from-index $head) (build-env-from-corpus $tail)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Display and Verification ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Display proof result
(: display-proof (-> String $a $a))
(= (display-proof $name $result)
   (let $_ (println! (concat "✓ " $name))
   (let $_ (println! $result)
   $result)))

;; Verify a theorem and display result
(: verify-and-show (-> String (List $a) Number $a $a))
(= (verify-and-show $name $env $depth $query)
   (let $result (prove-with-env-n $env $depth $query)
   (display-proof $name $result)))

;;;;;;;;;;;;;;;;;;;
;; Test Examples ;;
;;;;;;;;;;;;;;;;;;;

!(println! "========================================")
!(println! "Testing Basic Axioms")
!(println! "========================================")

;; Test axiom ax-1
!(println! "Test 1: ax-1")
!(prove-n 0 (: ax-1 (→ p (→ q p))))

;; Test axiom ax-2
!(println! "Test 2: ax-2")
!(prove-n 0 (: ax-2 (→ (→ p (→ q r)) (→ (→ p q) (→ p r)))))

;; Test axiom ax-3
!(println! "Test 3: ax-3")
!(prove-n 0 (: ax-3 (→ (→ (¬ p) (¬ q)) (→ q p))))

!(println! "")
!(println! "========================================")
!(println! "Testing Modus Ponens")
!(println! "========================================")

;; Test modus ponens with environment
!(println! "Test 4: Simple modus ponens")
!(prove-with-env-n 
   (Cons (: premise1 p) 
         (Cons (: premise2 (→ p q)) 
               Nil))
   1
   (: (ax-mp premise1 premise2) q))

!(println! "")
!(println! "========================================")
!(println! "Testing Examples from pln-inf-ctl.metta")
!(println! "========================================")

;; Test from pln-inf-ctl.metta: mp2 subgoal
!(println! "Test 5: mp2 subgoal")
!(prove-with-env-n
   (Cons (: mp2.1 𝜑)
         (Cons (: mp2.2 𝜓)
               (Cons (: mp2.3 (→ 𝜑 (→ 𝜓 𝜒)))
                     Nil)))
   1
   (: (ax-mp mp2.1 mp2.3) (→ 𝜓 𝜒)))

;; Test from pln-inf-ctl.metta: full mp2
!(println! "Test 6: mp2")
!(prove-with-env-n
   (Cons (: mp2.1 𝜑)
         (Cons (: mp2.2 𝜓)
               (Cons (: mp2.3 (→ 𝜑 (→ 𝜓 𝜒)))
                     Nil)))
   2
   (: (ax-mp mp2.2 (ax-mp mp2.1 mp2.3)) 𝜒))

;; Test from pln-inf-ctl.metta: mp2b
!(println! "Test 7: mp2b")
!(prove-with-env-n
   (Cons (: mp2b.1 𝜑)
         (Cons (: mp2b.2 (→ 𝜑 𝜓))
               (Cons (: mp2b.3 (→ 𝜓 𝜒))
                     Nil)))
   2
   (: (ax-mp (ax-mp mp2b.1 mp2b.2) mp2b.3) 𝜒))

;; Test from pln-inf-ctl.metta: a1i
!(println! "Test 8: a1i")
!(prove-with-env-n
   (Cons (: a1i.1 𝜑) Nil)
   1
   (: (ax-mp a1i.1 ax-1) (→ 𝜓 𝜑)))

!(println! "")
!(println! "========================================")
!(println! "All tests completed!")
!(println! "========================================")

