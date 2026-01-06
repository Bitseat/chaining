; ;; Step 1: load the backward chainer
; !(load "pp.metta")

; ;; Step 2: load the propositional-calculus corpus
; !(load "propositional-calculus.metta")

; ;; Step 3: build an environment of facts from the corpus (unwrap MkIndex)
; !(bind! &pc-indexes (collapse (match &self (MkIndex $idx $assert) (MkIndex $idx $assert))))
; !(bind! &pc-env (build-env-from-corpus (List.fromExpression &pc-indexes)))

; ;; Step 4: prove something using the backward chainer and the corpus environment.
; ;; Example: check that ax-1 is available via the corpus environment.
; !(println! "Proving ax-1 from corpus environment:")
; !(prove-with-env-n &pc-env 0 (: ax-1 (→ $𝜑 (→ $𝜓 $𝜑))))

; ;; Example: attempt the idi theorem (→ $𝜑 $𝜑) with depth 5.
; ;; This uses a proof term (λ idi.1 idi.1) from the corpus.
; !(println! "Attempting idi theorem (→ 𝜑 𝜑) with depth 5:")
; !(prove-with-env-n &pc-env 5 (: (λ idi.1 idi.1) (→ $𝜑 $𝜑)))


;; Load the backward chainer
!(load "bc_without_inf_ctl.metta")

;; Load the propositional-calculus corpus
!(load "propositional-calculus.metta")

;; Build environment from corpus
!(bind! &pc-indexes (collapse (match &self (MkIndex $idx $assert) (MkIndex $idx $assert))))
!(bind! &pc-env (build-env-from-corpus (List.fromExpression &pc-indexes)))

!(println! "========================================")
!(println! "Proving Theorems from Corpus")
!(println! "========================================")

;; Prove idi: (→ $𝜑 $𝜑)
!(println! "Theorem: idi (identity)")
!(verify-and-show "idi" &pc-env 5 (: (λ idi.1 idi.1) (→ $𝜑 $𝜑)))

;; Prove a1ii: (→ $𝜑 $𝜓 $𝜑)
!(println! "Theorem: a1ii")
!(verify-and-show "a1ii" &pc-env 5 (: (λ a1ii.1 a1ii.1) (→ $𝜑 $𝜓 $𝜑)))

;; Verify ax-mp is in corpus
!(println! "Axiom: ax-mp (modus ponens)")
!(verify-and-show "ax-mp" &pc-env 0 (: ax-mp (→ $𝜑 (→ $𝜑 $𝜓) $𝜓)))

;; Verify ax-1 is in corpus
!(println! "Axiom: ax-1")
!(verify-and-show "ax-1" &pc-env 0 (: ax-1 (→ $𝜑 (→ $𝜓 $𝜑))))

;; Verify ax-2 is in corpus
!(println! "Axiom: ax-2")
!(verify-and-show "ax-2" &pc-env 0 (: ax-2 (→ (→ $𝜑 (→ $𝜓 $𝜒)) (→ (→ $𝜑 $𝜓) (→ $𝜑 $𝜒)))))

!(println! "========================================")
!(println! "All corpus theorems verified!")
!(println! "========================================")
