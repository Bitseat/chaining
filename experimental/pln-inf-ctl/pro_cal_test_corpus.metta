;;;;;;;;;
; Types ;
;;;;;;;;;

;; Assertion, either axiom or theorem
(: Assertion Type)
(: MkAxiom (-> Symbol Atom Assertion))
(: MkTheorem (-> Symbol Atom Atom Assertion))

;; Indexed assertion
(: Index Type)
(: MkIndexed (-> Number Assertion Index))

;;;;;;;;
; Data ;
;;;;;;;;

(MkIndex 0 (MkTheorem idi (λ idi.1 idi.1) (-> $𝜑 $𝜑)))
(MkIndex 1 (MkTheorem a1ii (λ a1ii.1 a1ii.2 a1ii.1) (-> $𝜑 $𝜓 $𝜑)))
(MkIndex 2 (MkAxiom ax-mp (-> $𝜑 (→ $𝜑 $𝜓) $𝜓)))
(MkIndex 3 (MkAxiom ax-1 (→ $𝜑 (→ $𝜓 $𝜑))))
(MkIndex 4 (MkAxiom ax-2 (→ (→ $𝜑 (→ $𝜓 $𝜒)) (→ (→ $𝜑 $𝜓) (→ $𝜑 $𝜒)))))
