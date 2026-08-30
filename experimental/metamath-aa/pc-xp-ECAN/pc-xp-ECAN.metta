;; Experiment to verify or rediscover proofs of the propositional
;; calculus fragment of set theory of Metamath.

;; NEXT: automate the discovery process of reduction rules.  It is
;; especially relevant here because new lemmas are constantly added.
;; Thus hand written reduction rules will not suffice.

;; Note that all type definitions over functions have been commented
;; out because it results in a significant speed up.

;; This variant use the stock metta-attention agents.  
;; Attention values live in the real bank (setAv / getSti / getLti /
;; stimulate) and &af is populated, so getAfAtoms yields a live bounded focus
;; and the diffusion and rent agents have targets to select.  What is still
;; local: Hebbian link maintenance and the &pc-rb-af rule focus.

;;;;;;;;;;;;;;;;;;;;;;
;; ;;;;;;;;;;;;;;;; ;;
;; ;; Parameters ;; ;;
;; ;;;;;;;;;;;;;;;; ;;
;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Experiment Parameters ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Process assertions up to the provided index (excluded).  The
;; maximum value is 1526 because the full corpus contains 1525
;; assertions.
;;
;; When using proof depth as search boundary, it is set to 95 because
;; the 95 theorem is very slow to proof.
;;
;; When using proof size as search boundary, it is set to 182 because
;; the 182 theorem is very slow to proof.
(= (up-to-idx) 182)

;;;;;;;;;;;;;;;;;;;;;;;
;; Search Parameters ;;
;;;;;;;;;;;;;;;;;;;;;;;

;; Whether to reverse the order of arguments.  For instance
;;
;; (: ax-mp (-> $𝜑 (→ $𝜑 $𝜓) $𝜓))
;;
;; becomes
;;
;; (: ax-mp (-> (→ $𝜑 $𝜓) $𝜑 $𝜓))
;;
;; This can speed up the proof search because in the reversed order,
;; the first arguments tend to be more constrained than the lastest
;; ones, which can have the effect of pruning earlier the search.
;;
;; Indeed, early results confirm that.  Reversing the arguments allows
;; to rediscover the first proofs (up to index 50 excluded) in 9.144s,
;; instead of 6m47.418s if not reversed.
(= (reverse-arguments) True)

;; Re-discover proofs.  If it is True then the proofs are attempted to
;; be re-discovered instead of merely being checked.
(= (search-proof) True)

;; For each theorem, search for all possible proofs.  Otherwise, stop
;; at the first one.
(= (search-all-proofs) False)

;; Bound search by proof size instead of proof depth.
(= (bound-search-by-proof-size) True)

;; Use proof reduction as pruning mechanism during search
(= (prune-reduct) False)

;;;;;;;;;;;;;;;;;;;;;
;; ECAN Parameters ;;
;;;;;;;;;;;;;;;;;;;;;

;; Initial short-term importance (STI) assigned to an axiom label when
;; it is first inserted into the knowledge base.
(= (ecan-axiom-sti) 100.0)

;; Initial STI assigned to a (rule/arrow) lemma label on insertion.
;; Used as a FLOOR only -- see ecan-seed-sti below.
(= (ecan-rule-sti) 100.0)

;; Extra STI given to a freshly proved lemma on top of the current
;; maximum, so it enters the attentional focus at the very top.
(= (ecan-seed-bonus) 1.0)

;; STI increment applied to every label used in a discovered proof.
(= (ecan-proof-stimulus) 1.0)

;; Run diffusion/rent agents between theorem iterations.
(= (ecan-use-agents) True)

;; Run the ECAN agents CONTINUOUSLY, on a background thread, for the whole
;; run -- instead of once between theorems.
(= (ecan-background) True)

;; Seconds the daemon sleeps between sweeps.  MUST be >= 1/AFRentFrequency
;; (0.2 s at the stock value of 5.0) or every sweep falls under
;; collectAFRent's elapsed-time threshold and rent never collects at all.
(= (ecan-daemon-interval) 0.25)

;; Whether the daemon also rebuilds &pc-rb-af.  With this False the running
;; search keeps the focus it started with and only the NEXT theorem sees the
;; daemon's work.  With it True the rule base is mutated underneath an
;; in-flight search: each node's match sees a consistent snapshot, but
;; different nodes can see different ones, so tier-1 completeness is no longer
;; guaranteed.  That is survivable here only because a tier-1 miss falls
;; through to the full rule base -- it costs time, never correctness.
(= (ecan-daemon-steers-search) False)

;; Size of the attention-focused rule base (&pc-rb-af) as a FRACTION of
;; the rules currently in &pc-rb.
(= (ecan-focus-fraction) 0.3)

;; Lower bound on the focus. 
(= (ecan-focus-min) 25)

;; Number of highest-STI inference rules kept in the focus.
(= (ecan-focus-size)
   (let $n (size-atom (collapse (match &pc-rb (: $l $t) $l)))
     (max (ecan-focus-min)
          (trunc-math (* (ecan-focus-fraction) $n)))))

;; Log per-iteration tier diagnostics (focused size / full size / whether
;; the focused search hit) so the value of ECAN guidance can be measured.
(= (ecan-log-tier) True)

;; Weight of (normalised) LTI relative to STI when ranking rules for the
;; focus.
(= (ecan-lti-weight) 1.0)

;; Blend rate pulling a Hebbian link's strength toward fresh co-use
(= (ecan-hebbian-decay) 0.1)

;; Nominal top of the STI range.  Its ONLY use is as the scale of the LTI
;; term in ecan-rule-score: the most-used rule in the corpus receives an LTI
;; bonus of exactly this many points, so the value sets how a perfect
;; long-run record trades off against raw STI (see ecan-lti-weight).
(= (ecan-sti-ceiling) 1000.0)

;;;;;;;;;;;;;;;;;;;;;;;
;; Logger Parameters ;;
;;;;;;;;;;;;;;;;;;;;;;;

;; Log level
(= (log-level) debug)

;; Log file path
(= (log-filepath) "pc-xp-ECAN.log")

;;;;;;;;;;;;;;;;;;;
;; ;;;;;;;;;;;;; ;;
;; ;; Imports ;; ;;
;; ;;;;;;;;;;;;; ;;
;;;;;;;;;;;;;;;;;;;

;; Import logger library
!(import! &self (library lib_import))
!(progn (translatePredicate (working_dir $this-dir))
        (translatePredicate (atomic_list_concat ($this-dir "/repos") $repos-dir))
        (git-import! "https://github.com/ngeiswei/petta_lib_logger" "" $repos-dir))

;; Import metta-attention
!(progn (translatePredicate (working_dir $ma-dir))
        (translatePredicate (atomic_list_concat ($ma-dir "/repos") $ma-repos))
        (git-import! "https://github.com/iCog-Labs-Dev/metta-attention" "" $ma-repos))
!(progn (translatePredicate (working_dir $bg-dir))
        (translatePredicate (atomic_list_concat ($bg-dir "/ecan_bg.pl") $bg-pl))
        (translatePredicate (ensure_loaded $bg-pl)))

!(import_prolog_functions_from_file (library petta_lib_logger lib_logger.pl)
                                    (logger-set-filepath
                                     logger-set-level
                                     logger-info
                                     logger-infof
                                     logger-debugf
                                     logger-tracef))

;; Import the propositional calculus corpus in the format
;; (MkIndexed INDEX (MkAxiom LABEL AXIOM))
;; (MkIndexed INDEX (MkTheorem LABEL PROOF THEOREM))
!(if (reverse-arguments)
     (import! &pc-idxd ../../metamath/propositional-calculus-reversed-arguments)
     (import! &pc-idxd ../../metamath/propositional-calculus))

;; Attention state and dynamics come from the metta-attention modules.
!(import! &self (library lib_spaces))

;; (library lib_he) supplies `unify', which diffuseIncident uses to look up
; an atom's incident set.
!(import! &self (library lib_he))

;; No-op stub for the AF's CSV hook.
(= (write_csv_wrapper $x) ())

!(import! &self repos/metta-attention/attention/AttentionParam)
!(import! &self repos/metta-attention/attention-bank/utilities/helper-functions)
!(import! &self repos/metta-attention/attention-bank/bank/importance-index/importance-index)
!(import! &self repos/metta-attention/attention-bank/attention-value/getter-and-setter)
!(import! &self repos/metta-attention/attention-bank/bank/attention-bank)
!(import! &self repos/metta-attention/attention-bank/bank/attentional-focus/attentional-focus)
!(import! &self repos/metta-attention/attention/Neighbors)
!(import! &self repos/metta-attention/attention/baching)
!(import! &self repos/metta-attention/attention/ImportanceDiffusionAgent/ImportanceDiffusionBase/ImportanceDiffusionBase)
!(import! &self repos/metta-attention/attention/RentCollectionAgent/RentCollectionBaseAgent/RentCollectionBaseAgent)

;; Python helper used by the diffusion agent's top-k selection.
!(import! &self repos/metta-attention/attention/ImportanceDiffusionAgent/getelement.py)
!(import! &self repos/metta-attention/attention/ImportanceDiffusionAgent/AFImportanceDiffusionAgent/AFImportanceDiffusionAgent)
!(import! &self repos/metta-attention/attention/RentCollectionAgent/AFRentCollectionAgent/AFRentCollectionAgent)

;; import! cannot report a failure, so check for one.  getSti answers 0.0 for
;; an atom with no attention value once the bank is loaded, and stays the
;; unevaluated expression (getSti ...) when it is not.  Stop here rather than
;; let an unevaluated expression reach `is/2' mid-run.
!(if (== (getSti ecan-import-probe) 0.0)
     ()
     (progn
      (println! "FATAL: metta-attention did not load -- getSti/setAv/stimulate are undefined.")
      (println! "Expected the bank under <this file's dir>/repos/metta-attention; see the git-import! above.")
      (translatePredicate (halt 1))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Attention economy (AttentionParam) ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

!(updateAttentionParam HEBBIAN_MAX_ALLOCATION_PERCENTAGE 1.0)

;; Rent and wages are two sides of one homeostat, both driven by how far
;; FUNDS_STI sits from TARGET_STI, in units of STI_FUNDS_BUFFER:
;;   wage = STI_ATOM_WAGE      * (1 + clamp((FUNDS_STI - TARGET_STI)/buffer, -1, 1))
;;   rent = StartingAtomStiRent* (1 + clamp((TARGET_STI - FUNDS_STI)/buffer, -0.99, 1))
;;          ... and is EXACTLY 0.0 whenever FUNDS_STI >= TARGET_STI.
!(updateAttentionParam STARTING_FUNDS_STI 250000)
!(updateAttentionParam FUNDS_STI 250000)
!(updateAttentionParam TARGET_STI 220000)
!(updateAttentionParam STI_FUNDS_BUFFER 120000)

;;;;;;;;;;;;;;;;;;;;;;
;; Configure Logger ;;
;;;;;;;;;;;;;;;;;;;;;;

;; Control space for the background ECAN daemon: liveness flag and the
;; resolved log path (see ecan-background).  Bound here because the logger
;; block below writes into it.
!(bind! &ecan-ctl (new-space))
!(logger-set-level (log-level))
!(progn (translatePredicate (working_dir $this-dir))
        (translatePredicate (atomic_list_concat ($this-dir "/" (log-filepath)) $log-path))
        (logger-set-filepath $log-path)
        ;; Keep the resolved path: a hyperpose worker thread has to set the
        ;; logger up again for itself (see ecan-run-experiment), and cannot
        ;; recompute it -- working_dir does not resolve the same way there.
        (add-atom &ecan-ctl (logpath $log-path)))

;;;;;;;;;;;;;;;;;;;;;
;; ;;;;;;;;;;;;;;; ;;
;; ;; Functions ;; ;;
;; ;;;;;;;;;;;;;;; ;;
;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;
;; Concat ;;
;;;;;;;;;;;;

;; Concat atoms.  The implementation uses union-atom and assumes that
;; it preserves order.
(= (concat-atom $x $y) (union-atom $x $y))

;;;;;;;;;;
;; When ;;
;;;;;;;;;;

;; Binary conditional.  Only execute branch if condition is True
(: when (-> Bool Atom $a))
(= (when $c $x) (if $c $x (empty)))

;;;;;;;;;;;
;; Sized ;;
;;;;;;;;;;;

;; Associate a size to a term
(: Sized (-> $a Type))
(: MkSized (-> $n                       ; Size
               $a                       ; Object
               (Sized $a)))             ; Sized object

;; Access functions
(= (Sized.size (MkSized $s $x)) $s)
(= (Sized.object (MkSized $s $x)) $x)

;;;;;;;;;;;;;;;
;; Assertion ;;
;;;;;;;;;;;;;;;

;; Assertion, either axiom or theorem
(: Assertion Type)
(: MkAxiom (-> Symbol ; Label
               Atom   ; Axiom
               Assertion))
(: MkTheorem (-> Symbol ; Label
                 Atom   ; Proof
                 Atom   ; Theorem
                 Assertion))

;; Indexed assertion
(: Indexed Type)
(: MkIndexed (-> Number    ; Index
                 Assertion ; Axiom or Theorem
                 Indexed))

;;;;;;;;;
;; Nat ;;
;;;;;;;;;

;; Define Nat
(: Nat Type)
(: Z Nat)
(: S (-> Nat Nat))

;; Define cast functions between Nat and Number
;; (: fromNumber (-> Number Nat))
(= (fromNumber $n) (if (<= $n 0) Z (S (fromNumber (- $n 1)))))
;; (: fromNat (-> Nat Number))
(= (fromNat Z) 0)
(= (fromNat (S $k)) (+ 1 (fromNat $k)))

;;;;;;;;;;;
;; Maybe ;;
;;;;;;;;;;;

;; Define Maybe type
(: Maybe (-> $a Type))
(: Nothing (Maybe $a))
(: Just (-> $a (Maybe $a)))

;; Implement monad interface for return
;; (: Maybe.return (-> $a (Maybe $a)))
(= (Maybe.return $x) (Just $x))

;; Implement monad interface for bind
;; (: Maybe.bind (-> (Maybe $a) (-> $a (Maybe $b)) (Maybe $b)))
(= (Maybe.bind Nothing $f) Nothing)
(= (Maybe.bind (Just $x) $f) ($f $x))

;; Test Maybe
(: Maybe.test.foo (-> Number (Maybe String)))
(= (Maybe.test.foo $x) (if (== $x 42) (Just "42") Nothing))
!(test
  (Maybe.bind Nothing Maybe.test.foo)
  Nothing)
!(test
  (Maybe.bind (Just 0) Maybe.test.foo)
  Nothing)
!(test
  (Maybe.bind (Just 42) Maybe.test.foo)
  (Just "42"))

;;;;;;;;;;;;
;; Syntax ;;
;;;;;;;;;;;;

;; Return True iff the given term is an expression
;; (: is-expression (-> $a Bool))
(= (is-expression $x) (== (get-metatype $x) Expression))

;; Test is-expression
!(test
  (is-expression id)
  False)

;; Return True iff the given term is a lambda abstraction, meaning an
;; expression of the form (λ VARIABLES BODY)
;;
;; NEXT: simplify once issue
;; https://github.com/trueagi-io/PeTTa/issues/182 has been
;; solved.
;; (: is-lambda (-> $a Bool))
(= (is-lambda $x)
   (if (is-expression $x)
       (if (== () $x)
           False
           (== λ (car-atom $x)))
       False))

;; Test is-lambda
!(test
  (is-lambda A)
  False)
!(test
  (is-lambda (A B))
  False)
!(test
  (is-lambda (λ $x $y))
  True)

;; Return True iff the given term is an arrow type, meaning has the
;; following format (-> A), (-> A B), (-> A B C), etc.
;;
;; NEXT: simplify once issue
;; https://github.com/trueagi-io/PeTTa/issues/182 has been
;; solved.
;; (: is-arrow (-> Atom Bool))
(= (is-arrow $x)
   (if (is-expression $x)
       (if (== () $x)
           False
           (== -> (car-atom $x)))
       False))

;; Test is-arrow
!(test
  (is-arrow A)
  False)
!(test
  (is-arrow (F A B))
  False)
!(test
  (is-arrow (-> $a $b))
  True)

;; Return True iff the given term is a product, meaning an expression
;; of the form (, FIRST SECOND)
;;
;; NEXT: simplify once issue
;; https://github.com/trueagi-io/PeTTa/issues/182 has been
;; solved.
;; (: is-product (-> $a Bool))
(= (is-product $x)
   (if (is-expression $x)
       (if (== () $x)
           False
           (== , (car-atom $x)))
       False))

;; Test is-lambda
!(test
  (is-product A)
  False)
!(test
  (is-product (A B))
  False)
!(test
  (is-product (, A B))
  True)

;; Drop last element of a tuple
(= (drop-last $xs)
   (if (is-expression $xs)
       (if (== $xs ())
           (empty)
           (if (== (length $xs) 1)
               ()
               (let* ((($head $tail) (decons-atom $xs))
                      ($dlt (drop-last $tail)))
                 (cons-atom $head $dlt))))
       (empty)))

;; Test drop-last
!(test
  (drop-last (A))
  ())
!(test
  (drop-last (A B))
  (A))
!(test
  (drop-last (A B C))
  (A B))

;; Take last element of a tuple
(= (take-last $xs)
   (if (is-expression $xs)
       (if (== $xs ())
           (empty)
           (if (== (length $xs) 1)
               (car-atom $xs)
               (take-last (cdr-atom $xs))))
       (empty)))

;; Test take-last
!(test
  (take-last (A))
  A)
!(test
  (take-last (A B))
  B)

;; Get lambda variables.  Prune if not a lambda term.
(= (get-lambda-variables $term)
   (if (is-lambda $term)
       (let ($h $t) (decons-atom $term)
            (drop-last $t))
       (empty)))

;; Test get-lambda-variables
!(test
  (collapse (get-lambda-variables A))
  ())
!(test
  (get-lambda-variables (λ $x $y))
  ($x))
!(test
  (get-lambda-variables (λ $x1 $x2 $y))
  ($x1 $x2))

;; Get lambda body.  Prune if not a lambda term.
(= (get-lambda-body $term)
   (if (is-lambda $term)
       (take-last $term)
       (empty)))

;; Test get-lambda-body
!(test
  (collapse (get-lambda-body A))
  ())
!(test
  (get-lambda-body (λ $x A))
  A)
!(test
  (get-lambda-body (λ $x1 $x2 A))
  A)

;; Get arrow premises.  Prune if not an arrow.
(= (get-arrow-premises $term)
   (if (is-arrow $term)
       (let ($h $t) (decons-atom $term)
            (drop-last $t))
       (empty)))

;; Test get-lambda-variables
!(test
  (collapse (get-arrow-premises A))
  ())
!(test
  (get-arrow-premises (-> A B))
  (A))
!(test
  (get-arrow-premises (-> A B C))
  (A B))

;; Get lambda body.  Prune if not a lambda term.
(= (get-arrow-conclusion $term)
   (if (is-arrow $term)
       (take-last $term)
       (empty)))

;; Test get-lambda-body
!(test
  (collapse (get-arrow-conclusion A))
  ())
!(test
  (get-arrow-conclusion (-> A B))
  B)
!(test
  (get-arrow-conclusion (-> A B C))
  C)

;;;;;;;;;
;; Zip ;;
;;;;;;;;;

;; Zip two tuples with a given function.  It is assumed that both $xs
;; and $ys have the same length.
(= (zip-with $f $xs $ys)
   (if (== $xs ())
       ()
       (let* ((($xh $xt) (decons-atom $xs))
              (($yh $yt) (decons-atom $ys))
              ($zh ($f $xh $yh))
              ($zt (zip-with $f $xt $yt)))
         (cons-atom $zh $zt))))

;; Test zip-with
!(test
  (zip-with : () ())
  ())
!(test
  (zip-with : (x) (a))
  ((: x a)))
!(test
  (zip-with : (x y) (a b))
  ((: x a) (: y b)))

;;;;;;;;;;;;;;;;;;;;;;
;; Match over tuple ;;
;;;;;;;;;;;;;;;;;;;;;;

;; Match pattern over a tuple of elements
(= (match' $tuple $ptrn $tmpl) (let $ptrn (superpose $tuple) $tmpl))

;; Test match' on empty tuple
!(test
  (collapse (match' () ($x $y) ($y $x)))
  ())

;; Test match' on singleton
!(test
  (collapse (match' ((A B)) ($x $y) ($y $x)))
  ((B A)))

;; Test match' on pair
!(test
  (collapse (match' ((A B) (C D)) ($x $y) ($y $x)))
  ((B A)
   (D C)))

;;;;;;;;;
;; Get ;;
;;;;;;;;;

;; Specialized match where the pattern is equal to the template
(= (get $spc $ptrn) (match $spc $ptrn $ptrn))

;; Specialized match' where the pattern is equal to the template
(= (get' $spc $ptrn) (match' $spc $ptrn $ptrn))

;;;;;;;;;;
;; Fold ;;
;;;;;;;;;;

;; Fold a tuple from right to left
;; (: foldr (-> (-> $a $b $b) $b $c $d))  ; NEXT: re-enable when fixed
(= (foldr $f $i $xs)
   (if (== $xs ())
       $i
       (let* ((($h $t) (decons-atom $xs))
              ($ft (foldr $f $i $t)))
         ($f $h $ft))))

;; Test foldr
!(test
  (foldr + 0 (1 2 3))
  6)

;;;;;;;;;;;;;;;
;; Successor ;;
;;;;;;;;;;;;;;;

;; Increment a number by 1
;; (: succ (-> Number Number))
(= (succ $n) (+ 1 $n))

;;;;;;;;;
;; Map ;;
;;;;;;;;;

;; (: map (-> (-> $a $b) $c $d))
(= (map $f $xs) (case $xs
                  (;; Empty expression
                   (() ())
                   ;; Non-empty expression
                   ($xs (let* ((($h $t) (decons-atom $xs))
                               ($fh ($f $h))
                               ($ft (map $f $t)))
                          (cons-atom $fh $ft))))))

;; Test map
!(test
  (map succ (0 1 2))
  (1 2 3))

;;;;;;;;;;;;;;;;;
;; Max element ;;
;;;;;;;;;;;;;;;;;

;; Given a tuple of numbers, return the maximum, or 0 if empty.
;; (: max-element (-> $a Number))
(= (max-element $expr) (foldr max 0 $expr))

;; Test max-element
!(test
  (max-element (1 3 2))
  3)

;;;;;;;;;;;;;;;
;; Max index ;;
;;;;;;;;;;;;;;;

;; Extract the maximum index of a corpus in a given space
;; (: max-index (-> $a Number))
(= (max-index $spc)
   (max-element (collapse (match $spc (MkIndexed $idx $asrt) $idx))))

;;;;;;;;;;;
;; Until ;;
;;;;;;;;;;;

;; Loop-like function ported from Haskell.  Iterate applying a given
;; function till some condition is reached.  You may want to make sure
;; that the predicate and the next function are deterministic,
;; otherwise the behavior of until might be a bit unpredictable.
;; (: until (-> (-> $a Bool)               ; Predicate
;;              (-> $a $a)                 ; Next
;;              $a                         ; Initial value
;;              $a))                       ; Final value
(= (until $p $f $x)
   (if ($p $x) $x (until $p $f ($f $x))))

;; Test until
(: test.equal-to-10 (-> Number Bool))
(= (test.equal-to-10 $x) (== 10 $x))
!(test
  (until test.equal-to-10 succ 0)
  10)

;;;;;;;;;;;;;;;;
;; Term depth ;;
;;;;;;;;;;;;;;;;

;; Return the depth of a term.  If the term is a symbol then the depth
;; is 0.  Likewise the depth of (R A B) is 1, etc.
;; (: term-depth (-> $a Number))
(= (term-depth $term)
   (case (get-metatype $term)
     (;; Symbol
      (Symbol 0)
      ;; Grounded
      (Grounded 0)
      ;; Variable
      (Variable 0)
      ;; Expression
      (Expression (+ (max-element (map term-depth $term)) 1)))))

;; Test term-depth
!(test
  (term-depth A)
  0)
!(test
  (term-depth (R A (S B C)))
  2)

;;;;;;;;;;;;;;;
;; Term size ;;
;;;;;;;;;;;;;;;

;; Return the size of a term, which correspond to the number symbols,
;; variables and grounded subterms in the given term.
(= (term-size $x)
   (if (is-expression $x)
       (if (== $x ())
           0
           (let ($head $tail) (decons-atom $x)
                (+ (term-size $head) (term-size $tail))))
       1))

;; Test term-size
!(test
  (term-size A)
  1)
!(test
  (term-size ((R A) $x))
  3)
!(test
  (term-size (R A (S B C)))
  5)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Replace body of lambda by variable ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Take a term representing a proof and replace its body by a variable
;; (as to be able to rediscover it).  If it is a lambda abstraction,
;; then replace the lambda term body by a variable, other replace the
;; whole term by a variable.
;; (: replace-body-by-variable (-> $a $a))
(= (replace-body-by-variable $prf)
   (case (get-metatype $prf)
     ((Symbol $y)
      (Grounded $y)
      (Variable $y)
      (Expression
       (if (== () $prf)
           $y
           (case $prf
             (;; Unary lambda abstraction
              ((λ $x $bdy)
               (λ $x $y))
              ;; Binary lambda abstraction
              ((λ $x1 $x2 $bdy)
               (λ $x1 $x2 $y))
              ;; Ternary lambda abstraction
              ((λ $x1 $x2 $x3 $bdy)
               (λ $x1 $x2 $x3 $y))
              ;; Quaternary lambda abstraction
              ((λ $x1 $x2 $x3 $x4 $bdy)
               (λ $x1 $x2 $x3 $x4 $y))
              ;; Quintenary lambda abstraction
              ((λ $x1 $x2 $x3 $x4 $x5 $bdy)
               (λ $x1 $x2 $x3 $x4 $x5 $y))
              ;; Senary lambda abstraction
              ((λ $x1 $x2 $x3 $x4 $x5 $x6 $bdy)
               (λ $x1 $x2 $x3 $x4 $x5 $x6 $y))
              ;; Septenary lambda abstraction
              ((λ $x1 $x2 $x3 $x4 $x5 $x6 $x7 $bdy)
               (λ $x1 $x2 $x3 $x4 $x5 $x6 $x7 $y))
              ;; Octonary lambda abstraction
              ((λ $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $bdy)
               (λ $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $y))
              ;; Nonary lambda abstraction
              ((λ $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9 $bdy)
               (λ $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9 $y))
              ;; Denary lambda abstraction
              ((λ $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9 $x10 $bdy)
               (λ $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9 $x10 $y))
              ;; Otherwise
              ($else $y))))))))

;; Test replace-body-by-variable
!(test
  (replace-body-by-variable (λ mpi.2 mpi.1 (mpd mpi.2 (a1i mpi.1))))
  (λ mpi.2 mpi.1 $bdy))
!(test
  (replace-body-by-variable (mpd ax-1 ax-1))
  $bdy)

;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Variable Introduction ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Replace a given symbol by a variable in a term.
;; (: replace-symbol-by-variable (-> Symbol $a $a))
(= (replace-symbol-by-variable $sym $term) (_replace-symbol-by-variable $sym $x $term))
;; (: _replace-symbol-by-variable (-> Symbol Variable $a $a))
(= (_replace-symbol-by-variable $sym $var $term)
   (case (get-metatype $term)
     ((Symbol (if (== $sym $term) $var $term))
      (Grounded $term)
      (Variable $term)
      (Expression (if (== $term ())
                      $term
                      (let* (;; Get head and tail of term
                             (($head $tail) (decons-atom $term))
                             ;; Recurs on head
                             ($nhd (_replace-symbol-by-variable $sym $var $head))
                             ;; Recurs on tail
                             ($ntl (_replace-symbol-by-variable $sym $var $tail)))
                        ;; Cons result
                        (cons-atom $nhd $ntl)))))))

;; Test replace-symbol-by-variable
!(test
  (replace-symbol-by-variable 𝜑 𝜑)
  $𝜑)
!(test
  (replace-symbol-by-variable 𝜑 (-> (→ 𝜑 (→ 𝜓 𝜒)) 𝜓 𝜑 𝜒))
  (-> (→ $𝜑 (→ 𝜓 𝜒)) 𝜓 $𝜑 𝜒))

;; Replace all greek letters by variables
;; (: replace-greeks-by-variables (-> $a $a))
(= (replace-greeks-by-variables $term)
   (foldr replace-symbol-by-variable $term (𝜑 𝜓 𝜒 𝜃 𝜏 𝜂 𝜁 𝜎 𝜌 𝜇 𝜆 𝜅)))

;; Test replace-greeks-by-variables
!(test
  (replace-greeks-by-variables 𝜑)
  $𝜑)
!(test
  (replace-greeks-by-variables (-> (→ 𝜑 (→ 𝜓 𝜒)) 𝜓 𝜑 𝜒))
  (-> (→ $𝜑 (→ $𝜓 $𝜒)) $𝜓 $𝜑 $𝜒))

;;;;;;;;;;;;;;;
;; Reduction ;;
;;;;;;;;;;;;;;;

;; Define space mapping proof and theorem to label, with
;; representation of the form:
;;
;; (Label PROOF THEOREM LABEL)
!(bind! &labels (new-space))

;; Reduce by pruning.  That is only the candidates in reduced form are
;; kept, the others are pruned.  For now only reducing proof to its
;; label is supported.  Meaning that only a proof of a given theorem
;; not associated to an existing label is allowed.  In other words,
;; instead of rediscovering the proof, it should re-use this label.
;; Note that the theorem must match as well as the proof, to make sure
;; that the corresponding label does not correspond to an overly
;; specialized theorem, otherwise the final proof checking will fail
;; to unify.
(= (prune-reduce (: $x $a))
   (progn
    ;; (logger-tracef "Call: (prune-reduce %w)" ((: $x $a)))
    (case (once (match &labels (Label $x $a $l) $l))
      (($l (progn
            ;; (logger-tracef "%w is not in normal form, prune" ((: $x $a)))
            (empty)))
       (Empty (progn
               ;; (logger-tracef "%w is in normal form, do not prune" ((: $x $a)))
               (: $x $a)))))))

;; The code below, regular not pruning-based reduction, is only kept
;; for documentation or potential future use.

;; Reduce a proof to its label if any, or nothing otherwise.
;; (: reduce-to-label (-> $a (Maybe $a)))
(= (reduce-to-label $x)
   (case (once (match &labels (Label $x $y) $y))
     (($y (Just $y))
      (Empty Nothing))))

;; Apply any reduction rules till a fixed point is reached.  The input
;; is supposed to be closed, that is it does not contain free
;; variables.  Also, in applications such as (f a), f can be assumed
;; not to be reducible due to the lack of higher order rules in
;; propositional calculus.
;; (: reduce-proof (-> $a $a))
(= (reduce-proof $x)
   (if (is-expression $x)
       ;; Recursive steps
       (case $x
         (;; Nullary tuple
          (() ())
          ;; Unary application
          (($f $x1)
           (let $nx1 (reduce-proof $x1)
             (if (== $nx1 $x1)
                 ;; $x1 already reduced, attempt to reduce $x to label
                 (case (reduce-to-label $x)
                   (;; Reduced, return $y
                    ((Just $y) $y)
                    ;; Not reduced, return $x
                    (Nothing $x)))
                 ;; $x1 is reducible, reapply reduction
                 (reduce-proof ($f $nx1)))))
          ;; Binary application
          (($f $x1 $x2)
           (let* (($nx1 (reduce-proof $x1))
                  ($nx2 (reduce-proof $x2)))
             (if (and (== $nx1 $x1)
                      (== $nx2 $x2))
                 ;; $x1 and $x2 are already reduced, attempt to reduce
                 ;; $x to label
                 (case (reduce-to-label $x)
                   (;; Reduced, return $y
                    ((Just $y) $y)
                    ;; Not reduced, return $x
                    (Nothing $x)))
                 ;; $x1 and $x2 are reducible, reapply reduction
                 (reduce-proof ($f $nx1 $nx2)))))
          ;; Ternary application
          (($f $x1 $x2 $x3)
           (let* (($nx1 (reduce-proof $x1))
                  ($nx2 (reduce-proof $x2))
                  ($nx3 (reduce-proof $x3)))
             (if (and (== $nx1 $x1)
                      (and (== $nx2 $x2)
                           (== $nx3 $x3)))
                 ;; All arguments are already reduced, attempt to
                 ;; reduce $x to label
                 (case (reduce-to-label $x)
                   (;; Reduced, return $y
                    ((Just $y) $y)
                    ;; Not reduced, return $x
                    (Nothing $x)))
                 ;; Arguments are reducible, reapply reduction
                 (reduce-proof ($f $nx1 $nx2 $nx3)))))))
       ;; Base case
       (case (reduce-to-label $x)
         (;; Reduced, return $y
          ((Just $y) $y)
          ;; Not reduced, return $x
          (Nothing $x)))))

;; ;; Test reduce
;; !(add-atom &labels (Label (a1i id_) idd))
;; !(add-atom &labels (Label (mpd ax-1 ax-1) id_))
;; !(add-atom &labels (Label (3bitr2i bicom
;;                                    (bibi2i notnotb)
;;                                    notbi)
;;                           con2bi))
;; !(test
;;   (reduce-to-label ax-1)
;;   Nothing)
;; !(test
;;   (reduce-to-label (mpd ax-1 ax-1))
;;   (Just id_))
;; !(test
;;   (reduce-proof ax-1)
;;   ax-1)
;; !(test
;;   (reduce-proof id_)
;;   id_)
;; !(test
;;   (reduce-proof (a1i id_))
;;   idd)
;; !(test
;;   (reduce-proof (mpd ax-1 ax-1))
;;   id_)
;; !(test
;;   (reduce-proof (3bitr2i bicom (bibi2i notnotb) notbi))
;;   con2bi)

;;;;;;;;;;;;;;
;; Callback ;;
;;;;;;;;;;;;;;

; ;; Callback to be passed to the backward chainer.  It is called over
; ;; every result, intermediary included, that the backward chainer
; ;; finds.  For now it used as a reduction pruner, meaning that if the
; ;; result is recognized as reducible, then it is pruned.
; ;; (: callback (-> $a $a))
; (= (callback (: $x $a)) ; (: $x $a))
;    (progn
;     ;; (logger-tracef "Call: (callback %w)" ((: $x $a)))
;     (if (prune-reduct)
;         (prune-reduce (: $x $a))
;         (: $x $a))))

;; It can store results, or filter by returning (empty).
;; It is the IDENTITY here, deliberately.  callback runs on the chainer's
;; hot path -- every intermediary result, millions of times in a long
;; search -- so anything done here is paid per search step; the bank's
;; setAv alone costs ~5.9x a plain space write.  Attention is credited
;; once per SUCCESSFUL proof instead (ecan-stimulate-proof), which is also
;; the better signal: "appeared in a proof that worked" rather than "was
;; touched while exploring a branch that failed".
;; (: callback (-> $a $a))
(= (callback (: $x $a)) (: $x $a))

;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ECAN Helper Functions ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Thin wrappers over the bank's getSti/getLti/getVlti/setAv/stimulate.

;; atom_concat is a PeTTa builtin, so this costs one Prolog atom_concat per
;; bank access.  Keep the "L-" prefix out of every OTHER space: &pc-rb,
;; &pc-ab, &pc-rb-af and &labels are all keyed by the raw label.
(= (ecan-key $l) (atom_concat "L-" $l))

;; Current STI of a label (0.0 when it has none).
(= (ecan-get-sti $l) (getSti (ecan-key $l)))

;; Set the STI of a label, replacing any previous value.
(= (ecan-set-sti $l $v)
   (with_mutex ecan_bank
     (let $k (ecan-key $l)
       (setAv $k ($v (getLti $k) (getVlti $k))))))

;; Current LTI of a label (0.0 when it has none).
(= (ecan-get-lti $l) (getLti (ecan-key $l)))

;; Labels of all inference rules currently in the knowledge base.
(= (ecan-kb-rule-labels)
   (collapse (match &pc-rb (: $l $t) $l)))

;; Highest LTI currently recorded (0.0 if none), used to normalise the
;; LTI term when ranking rules for the focus.
(= (ecan-max-lti)
   (let $vs (collapse (let $ls (ecan-kb-rule-labels) (let $l (superpose $ls) (ecan-get-lti $l))))
     (if (== $vs ()) 0.0 (max-atom $vs))))

;; Stimulation for a label that appeared in a SUCCESSFUL proof.
(= (ecan-stimulate-lasting $l $stimulus)
   (with_mutex ecan_bank (stimulate (ecan-key $l) $stimulus)))

;; Recursively stimulate all rule/axiom labels in a proof tree.
(= (ecan-stimulate-proof $prf)
   (if (== (get-metatype $prf) Symbol)
       (ecan-stimulate-lasting $prf (ecan-proof-stimulus))
       (if (and (== (get-metatype $prf) Expression)
                (not (== () $prf)))
           (ecan-stimulate-proof-elems $prf)
           ())))

;; Walk a tuple of proof sub-terms, stimulating each.
(= (ecan-stimulate-proof-elems $elems)
   (if (== $elems ())
       ()
       (progn
        (ecan-stimulate-proof (car-atom $elems))
        (ecan-stimulate-proof-elems (cdr-atom $elems)))))

;; Take the first $n elements of a tuple.  Guard with <= 0 rather than
;; == 0: a fractional or negative bound would step straight past an
;; equality test and recurse until the tuple ran out (or forever).
(= (take-n $n $tuple)
   (if (or (<= $n 0) (== $tuple ()))
       ()
       (cons-atom (car-atom $tuple)
                  (take-n (- $n 1) (cdr-atom $tuple)))))

;; Focus ranking score: short-term importance (what is hot now, driven by
;; recency seeding and stimulation) plus normalised long-term importance
;; (what has repeatedly proved useful).  Negated so a plain ascending
;; sort-atom puts the best rules first.
(= (ecan-rule-score $lbl $max-lti)
   (* -1.0
      (+ (ecan-get-sti $lbl)
         (if (<= $max-lti 0.0)
             0.0
             (* (ecan-lti-weight)
                (* (ecan-sti-ceiling)
                   (/ (ecan-get-lti $lbl) $max-lti)))))))

;; R-tagged intermediate: an untagged ($lbl $typ) 2-tuple reduces when
;; the label collides with a builtin (e.g. the corpus label `id`).
(= (ecan-scored-rules)
   (let $max-lti (ecan-max-lti)
     (collapse
      (let (R $lbl $typ) (match &pc-rb (: $lbl $typ) (R $lbl $typ))
        ((ecan-rule-score $lbl $max-lti) $lbl $typ)))))

;; Rebuild the attention-focused rule base as the top (ecan-focus-size)
;; inference rules by STI.  Axioms live in &pc-ab and are always
;; available; only the *rules* the search may apply are restricted here.
(= (ecan-rebuild-focused-rb)
   (with_mutex ecan_bank
   (progn
    ;; Clear old AF rule-base entries
    (let $old (collapse (match &pc-rb-af $e $e))
      (collapse (let $e (superpose $old) (remove-atom &pc-rb-af $e))))
    ;; Keep the stock attentional focus (&af) sized to our focus, so
    ;; getAfAtoms and this rule focus stay in step.  updateAf evicts the
    ;; lowest-STI atom once &af reaches MAX_AF_SIZE.
    (updateAttentionParam MAX_AF_SIZE (ecan-focus-size))
    ;; Select the top-N rules and populate &pc-rb-af
    (let* (($scored (ecan-scored-rules))
           ($sorted (sort-atom $scored))
           ($top-n (take-n (ecan-focus-size) $sorted)))
      (collapse
       (let ($neg-sti $lbl $typ) (superpose $top-n)
         (add-atom &pc-rb-af (: $lbl $typ))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ECAN Pipeline: Hebbian links (lean port)   ;;
;; plus the STOCK diffusion and rent agents   ;;
;;                                            ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Hebbian link creation/update stays local because
;; HebbianCreationAgent-Run draws its sources from the AF rather than from
;; the labels co-used in a proof, which is the signal we actually have;
;; &pc-rb-af, the RULE focus the two-tier search uses, which is a different
;; population from the bank's &af (that holds every atom with an attention
;; value).

;; All symbols occurring in a proof tree, as a flat tuple (explicit
;; car/cdr walk.
(= (ecan-proof-symbols $prf)
   (if (== (get-metatype $prf) Symbol)
       ($prf)
       (if (and (== (get-metatype $prf) Expression)
                (not (== () $prf)))
           (ecan-proof-symbols-elems $prf)
           ())))

(= (ecan-proof-symbols-elems $elems)
   (if (== $elems ())
       ()
       (concat-atom (ecan-proof-symbols (car-atom $elems))
                    (ecan-proof-symbols-elems (cdr-atom $elems)))))

;; True iff the label is a rule or axiom in the knowledge bases (filters
;; out λ, premise variables like mp2.1, etc.).
(= (ecan-is-kb-label $l)
   (if (== () (collapse (match &pc-rb (: $l $t) True)))
       (not (== () (collapse (match &pc-ab (: $l $t) True))))
       True))

;; Unique KB labels used in a proof.
(= (ecan-proof-kb-labels $prf)
   (let $syms (unique-atom (ecan-proof-symbols $prf))
     (collapse
      (let $s (superpose $syms)
        (if (ecan-is-kb-label $s) $s (empty))))))

;; Create or strengthen the Hebbian link SRC->TGT (HebbianCreationAgent's
;; addHebbian initialises at (0.5 0.1); HebbianUpdatingAgent blends the
;; strength toward fresh evidence with TC_DECAY_RATE — here the direct
;; co-use of both labels in one proof counts as evidence 1.0).
;; Hebbian links are kept in the exact shape diffuseHebbian matches:
;;   ((ASYMMETRIC_HEBBIAN_LINK SRC TGT) (STV MEAN CONF))
(= (ecan-update-hebbian-pair $a $b)
   (case (once (match &hebbian-stock ((ASYMMETRIC_HEBBIAN_LINK $a $b) (STV $m $c))
                      ($m $c)))
     ((($m $c)
       (let* (($decay (ecan-hebbian-decay))
              ($new-m (+ (* $decay 1.0) (* (- 1.0 $decay) $m)))
              ($new-c (min-atom ((+ $c 0.05) 0.95))))
         (progn
          (remove-atom &hebbian-stock
                       ((ASYMMETRIC_HEBBIAN_LINK $a $b) (STV $m $c)))
          (add-atom &hebbian-stock
                    ((ASYMMETRIC_HEBBIAN_LINK $a $b) (STV $new-m $new-c))))))
      (Empty (add-atom &hebbian-stock
                       ((ASYMMETRIC_HEBBIAN_LINK $a $b) (STV 0.5 0.1)))))))

;; Create/strengthen links between every ordered pair of distinct labels
;; co-used in a proof (HebbianCreationAgent semantics over the co-focused
;; set — here the co-used set, the direct evidence available to us).
;; Takes RAW labels and converts to bank keys here, so callers keep working
;; in the label vocabulary every other space uses.
(= (ecan-update-hebbian-links $labels)
   (collapse
    (let* (($a (superpose $labels))
           ($b (superpose $labels)))
      (if (== $a $b)
          ()
          (let* (($ka (ecan-key $a))
                 ($kb (ecan-key $b)))
            (ecan-update-hebbian-pair $ka $kb))))))

;; Labels currently in the attentional focus (&pc-rb-af).
(= (ecan-focus-labels)
   (collapse (match &pc-rb-af (: $l $t) $l)))

;; One background sweep.  Kept separate from ecan-run-agents so the daemon
;; does not emit the per-iteration diagnostic line on every tick.
;; The WHOLE sweep is serialised against the main thread's bank access.
(= (ecan-sweep)
   (with_mutex ecan_bank
   (progn
    (add-atom &ecan-ctl (tick))
    (catch (collapse (AFImportanceDiffusionAgent-Run &incident &hebbian-stock)))
    (catch (collapse (AFRentCollectionAgent-run)))
    (if (ecan-daemon-steers-search) (catch (ecan-rebuild-focused-rb)) ()))))

;; The background loop.  Exits when the foreground clears the running flag.
(= (ecan-daemon)
   (if (== () (collapse (match &ecan-ctl (running True) 1)))
       (progn (add-atom &ecan-ctl (stopped)) done)
       (progn
        (catch (ecan-sweep))
        (catch (translatePredicate (sleep (ecan-daemon-interval))))
        (ecan-daemon))))

;; Wait (bounded) for the daemon thread to observe the cleared flag and exit.
(= (ecan-await-daemon $tries)
   (if (<= $tries 0)
       timeout
       (if (== () (collapse (match &ecan-ctl (stopped) 1)))
           (progn (catch (translatePredicate (sleep 0.05)))
                  (ecan-await-daemon (- $tries 1)))
           stopped)))

(= (ecan-daemon-stop)
   (progn
    (collapse (match &ecan-ctl (running True) (remove-atom &ecan-ctl (running True))))
    (ecan-await-daemon 200)))

;; Foreground branch: the experiment, then stop the daemon so hyperpose can join.
(= (ecan-run-agents)
   (if (ecan-use-agents)
       (progn
        (catch (collapse (AFImportanceDiffusionAgent-Run &incident &hebbian-stock)))
        (catch (collapse (AFRentCollectionAgent-run)))
        ;; Diagnostic only -- but a single empty result anywhere in the
        ;; argument tuple makes the whole logger-debugf fail, which
        ;; propagates out of this progn and silently ends the until loop.
        ;; So every bank lookup here is collapsed: a diagnostic must never
        ;; be able to abort the experiment.
        (if (ecan-log-tier)
            (let $focus (ecan-focus-labels)
              (let* (($sample (if (== $focus ()) none (car-atom $focus)))
                     ($af (collapse (getAfAtoms)))
                     ($sti (if (== $sample none)
                               (0.0)
                               (collapse (ecan-get-sti $sample)))))
                (logger-debugf "  [ecan] af-size=%w sample=%w sti=%w funds=%w rent=%w wage=%w"
                               ((if (== $af ()) 0 (size-atom (car-atom $af)))
                                $sample
                                (if (== $sti ()) 0.0 (car-atom $sti))
                                (getAttentionParam FUNDS_STI)
                                (calculateStiRent (getAttentionParam StartingAtomStiRent))
                                (calculateSTIWage)))))
            ()))
       (empty)))

;;;;;;;;;;;;;;;;;;;;;;
;; Backward chainer ;;
;;;;;;;;;;;;;;;;;;;;;;

;; Backward Chainer with support for lambda abstraction at the entry
;; point (no recursive search on lambda terms).  The knowledge is
;; decomposed into a rule base and an axiom base because we know we
;; never need to search both at the same time, only one or the other.
;;
;; The arguments of the backward chainer are:
;;
;; * Rule base: reference to a space containing rules in the format
;;
;; (: NAME (-> PREMISE1 ... CONCLUSION))
;;
;; * Axiom base: reference to a space containing axioms in the format
;;
;; (: NAME AXIOM)
;;
;; * Callback: function to be called everytime a result, final or
;;   intermediary is produced.  This function can be used to for
;;   instance store final and intermediary results, or acts as a
;;   filter (by returning (empty) when a condition is met, or any
;;   combinations thereof.
;;
;; * Maximum depth: maximum depth of the generated proof tree.
;;
;; * Query: a metta term of the form (: <PROOF> <THEOREM>) where
;;   <PROOF> and <THEOREM> may contain free variables that may be
;;   filled by the backward chainer.
;;
;; A result is the query with its variables grounded, fully or
;; partially.  If multiple results are possible, they are returned as
;; a superposition.

;; Entry point
;; (: bc (-> $a                            ; Rule base space
;;           $b                            ; Axiom base space
;;           (-> $c $c)                    ; Callback
;;           Nat                           ; Maximum depth
;;           $c                            ; Query
;;           $c))                          ; Result
(= (bc $rb $ab $cb $depth (: $prf $thrm))
   (progn
    (logger-tracef "Call (lambda): (bc %w %w %w %w (: %w %w))"
                   ($rb $ab $cb $depth $prf $thrm))
    (case $depth
      (;; Depth 0
       (Z (_bc $rb $ab $cb () Z (: $prf $thrm)))
       ;; Depth greater than 0 (consider lambda abstraction)
       ((S $k)
        (if (is-expression $prf)
            ;; Proof is an expression, check whether it is a lambda term
            (if (== () $prf)
                ;; Proof is empty and already fully defined
                (: $prf $thrm)
                ;; Proof is not empty
                (if (is-lambda $prf)
                    ;; Proof is a lambda term
                    (let* (;; Get variables, body, premises and conclusion
                           ($xs (get-lambda-variables $prf))
                           ($as (get-arrow-premises $thrm))
                           ($y (get-lambda-body $prf))
                           ($b (get-arrow-conclusion $thrm))
                           ;; Build environment
                           ($env (zip-with : $xs $as))
                           ;; Call _bc to proof conclusion given environment
                           ((: $y $b) (_bc $rb $ab $cb $env $k (: $y $b)))
                           ;; Reconstruct lambda term
                           ($prf (cons-atom λ (concat-atom $xs ($y))))
                           ;; Reconstruct arrow
                           ($thrm (cons-atom -> (concat-atom $as ($b)))))
                      ;; Output
                      (: $prf $thrm))
                    ;; Not a lambda term, merely call _bc
                    (_bc $rb $ab $cb () (S $k) (: $prf $thrm))))
            ;; Proof is not an expression, merely call _bc
            (_bc $rb $ab $cb () (S $k) (: $prf $thrm))))))))

;; Recursive search.  No support for lambda abstraction, but support
;; for environment, which is a tuple of typing relationships such as
;;
;;   ((: x 𝐁𝐨𝐨𝐥) (: y 𝐁𝐨𝐨𝐥))
;;
;; Also, the proof abstraction is only searched shallowly, at depth 0,
;; because they are no higher order inference rules anyway.
;; NEXT: re-enable when fixed
;; (: _bc (-> $a                            ; Rule base space
;;            $b                            ; Axiom base space
;;            (-> $d $d)                    ; Callback
;;            $c                            ; Environment
;;            Nat                           ; Maximum depth
;;            $d                            ; Query
;;            $d))                          ; Result

;; Base cases

;; Match the axiom base
(= (_bc $rb $ab $cb $env $k (: $x $a))
   (progn
    ;; (logger-tracef "Call (ab): (_bc %w %w %w %w %w (: %w %w))"
    ;;                ($rb $ab $cb $env $k $x $a))
    ($cb (get $ab (: $x $a)))))

;; Match the environment
(= (_bc $rb $ab $cb $env $k (: $x $a))
   (progn
    ;; (logger-tracef "Call (env): (_bc %w %w %w %w %w (: %w %w))"
    ;;                ($rb $ab $cb $env $k $x $a))
    ($cb (get' $env (: $x $a)))))

;; Recursive steps

;; Product.  It is used internally by proof application to iterate
;; over premises.  Due to being only used internally, we do not
;; account for its depth.  The product is associative but is assumed
;; here to only take right associative forms like (, x (, y z)).
;;
;; WARNING: decomposing multi-premise recursion using product makes a
;; more elegant code but it is also significantly, like 10x, slower.
(= (_bc_prod $rb $ab $cb $env $k (: (, $x $y) (, $a $b)))
   (progn
    ;; (logger-tracef "Call (prod): (_bc_prod %w %w %w %w %w %w)"
    ;;                ($rb $ab $cb $env $k (: (, $x $y) (, $a $b))))
    (let* (;; Recurse on first component
           ((: $x $a) (_bc $rb $ab $cb $env $k (: $x $a)))
           ;; Recurse on second component
           ((: $y $b) (if (is-product $y)
                          (_bc_prod $rb $ab $cb $env $k (: $y $b))
                          (_bc $rb $ab $cb $env $k (: $y $b)))))
      (: (, $x $y) (, $a $b)))))

;; The following functions enumerates proof application patterns by
;; arity.  The duplication up to arity is necessary to obtain search
;; branches from the non-determinism.  Maybe it can be simplified
;; further but this would require to implement a macro that would
;; generate them.

;; Unary proof application
(= (_bc $rb $ab $cb $env (S $k) (: ($f $x) $b))
   (progn
    ;; (logger-tracef "Call (app-1): (_bc %w %w %w %w %w %w)"
    ;;                ($rb $ab $cb $env (S $k) (: ($f $x) $b)))
    (let* (;; Query unary rule
           ((: $f (-> $a $b)) (get $rb (: $f (-> $a $b))))
           ;; Recurse on premise
           ((: $x $a) (_bc $rb $ab $cb $env $k (: $x $a))))
      ($cb (: ($f $x) $b)))))

;; Binary proof application
(= (_bc $rb $ab $cb $env (S $k) (: ($f $x1 $x2) $b))
   (progn
    ;; (logger-tracef "Call (app-2): (_bc %w %w %w %w %w %w)"
    ;;                ($rb $ab $cb $env (S $k) (: ($f $x1 $x2) $b)))
    (let* (;; Query binary rule
           ((: $f (-> $a1 $a2 $b))
            (get $rb (: $f (-> $a1 $a2 $b))))
           ;; Recurse on premises
           ((: (, $x1 $x2) (, $a1 $a2))
            (_bc_prod $rb $ab $cb $env $k (: (, $x1 $x2) (, $a1 $a2)))))
      ($cb (: ($f $x1 $x2) $b)))))

;; Ternary proof application
(= (_bc $rb $ab $cb $env (S $k) (: ($f $x1 $x2 $x3) $b))
   (progn
    ;; (logger-tracef "Call (app-3): (_bc %w %w %w %w %w %w)"
    ;;                ($rb $ab $cb $env (S $k) (: ($f $x1 $x2 $x3) $b)))
    (let* (;; Query ternary rule
           ((: $f (-> $a1 $a2 $a3 $b))
            (get $rb (: $f (-> $a1 $a2 $a3 $b))))
           ;; Recurse on premises
           ((: (, $x1 (, $x2 $x3)) (, $a1 (, $a2 $a3)))
            (_bc_prod $rb $ab $cb $env $k
                      (: (, $x1 (, $x2 $x3)) (, $a1 (, $a2 $a3))))))
      ($cb (: ($f $x1 $x2 $x3) $b)))))

;; Quaternary proof application
(= (_bc $rb $ab $cb $env (S $k) (: ($f $x1 $x2 $x3 $x4) $b))
   (progn
    ;; (logger-tracef "Call (app-4): (_bc %w %w %w %w %w %w)"
    ;;                ($rb $ab $cb $env (S $k) (: ($f $x1 $x2 $x3 $x4) $b)))
    (let* (;; Query quaternary rule
           ((: $f (-> $a1 $a2 $a3 $a4 $b))
            (get $rb (: $f (-> $a1 $a2 $a3 $a4 $b))))
           ;; Recurse on premises
           ((: (, $x1 (, $x2 (, $x3 $x4)))
               (, $a1 (, $a2 (, $a3 $a4))))
            (_bc_prod $rb $ab $cb $env $k
                      (: (, $x1 (, $x2 (, $x3 $x4)))
                         (, $a1 (, $a2 (, $a3 $a4)))))))
      ($cb (: ($f $x1 $x2 $x3 $x4) $b)))))

;; Quintenary proof application
(= (_bc $rb $ab $cb $env (S $k) (: ($f $x1 $x2 $x3 $x4 $x5) $b))
   (progn
    ;; (logger-tracef "Call (app-5): (_bc %w %w %w %w %w %w)"
    ;;                ($rb $ab $cb $env (S $k) (: ($f $x1 $x2 $x3 $x4 $x5) $b)))
    (let* (;; Query quintenary rule
           ((: $f (-> $a1 $a2 $a3 $a4 $a5 $b))
            (get $rb (: $f (-> $a1 $a2 $a3 $a4 $a5 $b))))
           ;; Recurse on premises
           ((: (, $x1 (, $x2 (, $x3 (, $x4 $x5))))
               (, $a1 (, $a2 (, $a3 (, $a4 $a5)))))
            (_bc_prod $rb $ab $cb $env $k
                      (: (, $x1 (, $x2 (, $x3 (, $x4 $x5))))
                         (, $a1 (, $a2 (, $a3 (, $a4 $a5))))))))
      ($cb (: ($f $x1 $x2 $x3 $x4 $x5) $b)))))

;; Senary proof application
(= (_bc $rb $ab $cb $env (S $k) (: ($f $x1 $x2 $x3 $x4 $x5 $x6) $b))
   (progn
    ;; (logger-tracef "Call (app-6): (_bc %w %w %w %w %w %w)"
    ;;                ($rb $ab $cb $env (S $k) (: ($f $x1 $x2 $x3 $x4 $x5 $x6) $b)))
    (let* (;; Query senary rule
           ((: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $b))
            (get $rb (: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $b))))
           ;; Recurse on premises
           ((: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 $x6)))))
               (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 $a6))))))
            (_bc_prod $rb $ab $cb $env $k
                      (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 $x6)))))
                         (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 $a6)))))))))
      ($cb (: ($f $x1 $x2 $x3 $x4 $x5 $x6) $b)))))

;; Septenary proof application
(= (_bc $rb $ab $cb $env (S $k) (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7) $b))
   (progn
    ;; (logger-tracef "Call (app-7): (_bc %w %w %w %w %w %w)"
    ;;                ($rb $ab $cb $env (S $k) (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7) $b)))
    (let* (;; Query septenary rule
           ((: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $b))
            (get $rb (: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $b))))
           ;; Recurse on premises
           ((: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 $x7))))))
               (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 $a7)))))))
            (_bc_prod $rb $ab $cb $env $k
                      (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 $x7))))))
                         (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 $a7))))))))))
      ($cb (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7) $b)))))

;; Octonary proof application
(= (_bc $rb $ab $cb $env (S $k) (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8) $b))
   (progn
    ;; (logger-tracef "Call (app-8): (_bc %w %w %w %w %w %w)"
    ;;                ($rb $ab $cb $env (S $k) (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8) $b)))
    (let* (;; Query octonary rule
           ((: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $b))
            (get $rb (: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $b))))
           ;; Recurse on premises
           ((: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 (, $x7 $x8)))))))
               (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 (, $a7 $a8))))))))
            (_bc_prod $rb $ab $cb $env $k
                      (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 (, $x7 $x8)))))))
                         (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 (, $a7 $a8)))))))))))
      ($cb (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8) $b)))))

;; Nonary proof application
(= (_bc $rb $ab $cb $env (S $k) (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9) $b))
   (progn
    ;; (logger-tracef "Call (app-9): (_bc %w %w %w %w %w %w)"
    ;;                ($rb $ab $cb $env (S $k) (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9) $b)))
    (let* (;; Query nonary rule
           ((: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $a9 $b))
            (get $rb (: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $a9 $b))))
           ;; Recurse on premises
           ((: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 (, $x7 (, $x8 $x9))))))))
               (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 (, $a7 (, $a8 $a9)))))))))
            (_bc_prod $rb $ab $cb $env $k
                      (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 (, $x7 (, $x8 $x9))))))))
                         (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 (, $a7 (, $a8 $a9))))))))))))
      ($cb (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9) $b)))))

;; Denary proof application
(= (_bc $rb $ab $cb $env (S $k) (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9 $x10) $b))
   (progn
    ;; (logger-tracef "Call (app-10): (_bc %w %w %w %w %w %w)"
    ;;                ($rb $ab $cb $env (S $k) (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9 $x10) $b)))
    (let* (;; Query denary rule
           ((: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $a9 $a10 $b))
            (get $rb (: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $a9 $a10 $b))))
           ;; Recurse on premises
           ((: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 (, $x7 (, $x8 $x9))))))))
               (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 (, $a7 (, $a8 $a9)))))))))
            (_bc_prod $rb $ab $cb $env $k
                      (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 (, $x7 (, $x8 (, $x9 $x10)))))))))
                         (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 (, $a7 (, $a8 (, $a9 $a10)))))))))))))
      ($cb (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9 $x10) $b)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Optimized Backward chainer ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Like bc but uses proof size instead of depth.  Maybe "optimized" is
;; a misnomer but it has been observed to be much faster this way.

;; ;; Entry point
;; (: obc (-> $a                            ; Rule base space
;;            $b                            ; Axiom base space
;;            (-> $c $c)                    ; Callback
;;            Number                        ; Maximum proof size
;;            $c                            ; Query
;;            $c))                          ; Result
(= (obc $rb $ab $cb $mps (: $prf $thrm))
   (progn
    (logger-tracef "Call (lambda): (obc %w %w %w %w (: %w %w))"
                   ($rb $ab $cb $mps $prf $thrm))
    (if (< 0 $mps)
        (if (is-expression $prf)
            ;; Proof is an expression, check whether it is a lambda term
            (if (== () $prf)
                ;; Proof is empty and already fully defined
                (: $prf $thrm)
                ;; Proof is not empty
                (if (is-lambda $prf)
                    ;; Proof is a lambda term
                    (let* (;; Get variables, body, premises and conclusion
                           ($xs (get-lambda-variables $prf))
                           ($as (get-arrow-premises $thrm))
                           ($y (get-lambda-body $prf))
                           ($b (get-arrow-conclusion $thrm))
                           ;; Build environment
                           ($env (zip-with : $xs $as))
                           ;; Calculate maximum body size (decount λ
                           ;; and variables)
                           ($mbs (- $mps (+ (length $xs) 1)))
                           ;; Call _obc to proof conclusion given environment
                           ((MkSized $bdysize (: $y $b))
                            (_obc $rb $ab $cb $env $mbs (: $y $b)))
                           ;; Reconstruct lambda term
                           ($prf (cons-atom λ (concat-atom $xs ($y))))
                           ;; Reconstruct arrow
                           ($thrm (cons-atom -> (concat-atom $as ($b)))))
                      ;; Output
                      (: $prf $thrm))
                    ;; Not a lambda term, merely call _obc
                    (Sized.object (_obc $rb $ab $cb () $mps (: $prf $thrm)))))
            ;; Proof is not an expression, merely call _obc
            (Sized.object (_obc $rb $ab $cb () $mps (: $prf $thrm))))
        ;; If maximum proof size is 0, then no proof can possibly be found
        (empty))))

;; Like _bc but uses proof size instead of depth, and outputs a sized
;; (: PROOF THEOREM) result.
;;
;; NEXT: re-enable when fixed
;; (: _obc (-> $a                            ; Rule base space
;;             $b                            ; Axiom base space
;;             (-> $c $c)                    ; Callback
;;             (List $b)                     ; Environment
;;             Number                        ; Maximum proof size
;;             $c                            ; Query
;;             (Sized $c)))                  ; Result

;; Base cases

;; Match the axiom base
(= (_obc $rb $ab $cb $env $mps (: $x $a))
   (if (< 0 $mps)
       (progn
        ;; (logger-tracef "Call (ab): (_obc %w %w %w %w %w (: %w %w))"
        ;;                ($rb $ab $cb $env $mps $x $a))
        (MkSized 1 ($cb (get $ab (: $x $a)))))
       (empty)))

;; Match the environment
(= (_obc $rb $ab $cb $env $mps (: $x $a))
   (if (< 0 $mps)
       (progn
        ;; (logger-tracef "Call (env): (_obc %w %w %w %w %w (: %w %w))"
        ;;                ($rb $ab $cb $env $mps $x $a))
        (MkSized 1 ($cb (get' $env (: $x $a)))))
       (empty)))

;; Recursive steps

;; Product.  It is used internally by proof application to iterate
;; over premises.  Due to being only used internally, we do not
;; account for the size of the product itself `,`.  The product is
;; associative but is assumed here to only take right associative
;; forms like (, x (, y z)).
(= (_obc_prod $rb $ab $cb $env $mps (: (, $x $y) (, $a $b)))
   (progn
    ;; (logger-tracef "Call (prod): (_obc_prod %w %w %w %w %w %w)"
    ;;                ($rb $ab $cb $env $mps (: (, $x $y) (, $a $b))))
    (let* (;; Recurse on first component
           ((MkSized $xps (: $x $a)) (_obc $rb $ab $cb $env $mps (: $x $a)))
           ;; Calculate remaining maximum size
           ($rms (- $mps $xps))
           ;; Recurse on second component
           ((MkSized $yps (: $y $b))
            (if (is-product $y)
                (_obc_prod $rb $ab $cb $env $rms (: $y $b))
                (_obc $rb $ab $cb $env $rms (: $y $b)))))
      ;; Output sized proof (sum up sizes of all subproofs)
      (MkSized (+ $xps $yps) (: (, $x $y) (, $a $b))))))

;; Unary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x) $b))
   (if (< 1 $mps)
       (progn
        ;; (logger-tracef "Call (app-1): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x) $b)))
        (let* (;; Query unary rule
               ((: $f (-> $a $b)) (get $rb (: $f (-> $a $b))))
               ;; Recurse on premise
               ((MkSized $xps (: $x $a))
                (_obc $rb $ab $cb $env (- $mps 1) (: $x $a))))
          ;; Output sized proof (size of proof of premise + rule)
          (MkSized (+ $xps 1) ($cb (: ($f $x) $b)))))
       (empty)))

;; Binary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x1 $x2) $b))
   (if (< 2 $mps)
       (progn
        ;; (logger-tracef "Call (app-2): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x1 $x2) $b)))
        (let* (;; Query binary rule
               ((: $f (-> $a1 $a2 $b)) (get $rb (: $f (-> $a1 $a2 $b))))
               ;; Recurse on premises
               ((MkSized $pps (: (, $x1 $x2) (, $a1 $a2)))
                (_obc_prod $rb $ab $cb $env (- $mps 1) (: (, $x1 $x2) (, $a1 $a2)))))
          ;; Output sized proof (size of proof of premises + rule)
          (MkSized (+ $pps 1) ($cb (: ($f $x1 $x2) $b)))))
       (empty)))

;; Ternary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x1 $x2 $x3) $b))
   (if (< 3 $mps)
       (progn
        ;; (logger-tracef "Call (app-3): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x1 $x2 $x3) $b)))
        (let* (;; Query ternary rule
               ((: $f (-> $a1 $a2 $a3 $b))
                (get $rb (: $f (-> $a1 $a2 $a3 $b))))
               ;; Recurse on premises
               ((MkSized $pps (: (, $x1 (, $x2 $x3)) (, $a1 (, $a2 $a3))))
                (_obc_prod $rb $ab $cb $env (- $mps 1)
                           (: (, $x1 (, $x2 $x3)) (, $a1 (, $a2 $a3))))))
          ;; Output sized proof (size of proof of premises + rule)
          (MkSized (+ $pps 1) ($cb (: ($f $x1 $x2 $x3) $b)))))
       (empty)))

;; Quaternary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4) $b))
   (if (< 4 $mps)
       (progn
        ;; (logger-tracef "Call (app-4): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4) $b)))
        (let* (;; Query quaternary rule
               ((: $f (-> $a1 $a2 $a3 $a4 $b))
                (get $rb (: $f (-> $a1 $a2 $a3 $a4 $b))))
               ;; Recurse on premises
               ((MkSized $pps (: (, $x1 (, $x2 (, $x3 $x4)))
                                 (, $a1 (, $a2 (, $a3 $a4)))))
                (_obc_prod $rb $ab $cb $env (- $mps 1)
                           (: (, $x1 (, $x2 (, $x3 $x4)))
                              (, $a1 (, $a2 (, $a3 $a4)))))))
          ;; Output sized proof (size of proof of premises + rule)
          (MkSized (+ $pps 1) ($cb (: ($f $x1 $x2 $x3 $x4) $b)))))
       (empty)))

;; Quintenary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5) $b))
   (if (< 5 $mps)
       (progn
        ;; (logger-tracef "Call (app-5): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5) $b)))
        (let* (;; Query quintenary rule
               ((: $f (-> $a1 $a2 $a3 $a4 $a5 $b))
                (get $rb (: $f (-> $a1 $a2 $a3 $a4 $a5 $b))))
               ;; Recurse on premises
               ((MkSized $pps (: (, $x1 (, $x2 (, $x3 (, $x4 $x5))))
                                 (, $a1 (, $a2 (, $a3 (, $a4 $a5))))))
                (_obc_prod $rb $ab $cb $env (- $mps 1)
                           (: (, $x1 (, $x2 (, $x3 (, $x4 $x5))))
                              (, $a1 (, $a2 (, $a3 (, $a4 $a5))))))))
          ;; Output sized proof (size of proof of premises + rule)
          (MkSized (+ $pps 1) ($cb (: ($f $x1 $x2 $x3 $x4 $x5) $b)))))
       (empty)))

;; Senary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6) $b))
   (if (< 6 $mps)
       (progn
        ;; (logger-tracef "Call (app-6): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6) $b)))
        (let* (;; Query senary rule
               ((: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $b))
                (get $rb (: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $b))))
               ;; Recurse on premises
               ((MkSized $pps (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 $x6)))))
                                 (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 $a6)))))))
                (_obc_prod $rb $ab $cb $env (- $mps 1)
                           (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 $x6)))))
                              (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 $a6)))))))))
          ;; Output sized proof (size of proof of premises + rule)
          (MkSized (+ $pps 1) ($cb (: ($f $x1 $x2 $x3 $x4 $x5 $x6) $b)))))
       (empty)))

;; Septenary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7) $b))
   (if (< 7 $mps)
       (progn
        ;; (logger-tracef "Call (app-7): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7) $b)))
        (let* (;; Query septenary rule
               ((: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $b))
                (get $rb (: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $b))))
               ;; Recurse on premises
               ((MkSized $pps (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 $x7))))))
                                 (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 $a7))))))))
                (_obc_prod $rb $ab $cb $env (- $mps 1)
                           (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 $x7))))))
                              (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 $a7))))))))))
          ;; Output sized proof (size of proof of premises + rule)
          (MkSized (+ $pps 1) ($cb (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7) $b)))))
       (empty)))

;; Octonary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8) $b))
   (if (< 8 $mps)
       (progn
        ;; (logger-tracef "Call (app-8): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8) $b)))
        (let* (;; Query octonary rule
               ((: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $b))
                (get $rb (: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $b))))
               ;; Recurse on premises
               ((MkSized $pps (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 (, $x7 $x8)))))))
                                 (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 (, $a7 $a8)))))))))
                (_obc_prod $rb $ab $cb $env (- $mps 1)
                           (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 (, $x7 $x8)))))))
                              (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 (, $a7 $a8)))))))))))
          ;; Output sized proof (size of proof of premises + rule)
          (MkSized (+ $pps 1) ($cb (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8) $b)))))
       (empty)))

;; Nonary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9) $b))
   (if (< 9 $mps)
       (progn
        ;; (logger-tracef "Call (app-9): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9) $b)))
        (let* (;; Query nonary rule
               ((: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $a9 $b))
                (get $rb (: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $a9 $b))))
               ;; Recurse on premises
               ((MkSized $pps (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 (, $x7 (, $x8 $x9))))))))
                                 (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 (, $a7 (, $a8 $a9))))))))))
                (_obc_prod $rb $ab $cb $env (- $mps 1)
                           (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 (, $x7 (, $x8 $x9))))))))
                              (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 (, $a7 (, $a8 $a9))))))))))))
          ;; Output sized proof (size of proof of premises + rule)
          (MkSized (+ $pps 1) ($cb (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9) $b)))))
       (empty)))

;; Denary proof application
(= (_obc $rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9 $x10) $b))
   (if (< 10 $mps)
       (progn
        ;; (logger-tracef "Call (app-10): (_obc %w %w %w %w %w %w)"
        ;;                ($rb $ab $cb $env $mps (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9 $x10) $b)))
        (let* (;; Query denary rule
               ((: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $a9 $a10 $b))
                (get $rb (: $f (-> $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $a9 $a10 $b))))
               ;; Recurse on premises
               ((MkSized $pps (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 (, $x7 (, $x8 $x9))))))))
                                 (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 (, $a7 (, $a8 $a9))))))))))
                (_obc_prod $rb $ab $cb $env (- $mps 1)
                           (: (, $x1 (, $x2 (, $x3 (, $x4 (, $x5 (, $x6 (, $x7 (, $x8 (, $x9 $x10)))))))))
                              (, $a1 (, $a2 (, $a3 (, $a4 (, $a5 (, $a6 (, $a7 (, $a8 (, $a9 $a10)))))))))))))
          (MkSized (+ $pps 1) ($cb (: ($f $x1 $x2 $x3 $x4 $x5 $x6 $x7 $x8 $x9 $x10) $b)))))
       (empty)))

;;;;;;;;;;;;;;;;;
;; ;;;;;;;;;;; ;;
;; ;; Tests ;; ;;
;; ;;;;;;;;;;; ;;
;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;
;; Helpers ;;
;;;;;;;;;;;;;

;; In case the input number is something, then return True iff it is
;; equal of the maximum index of the propositional calculus indexed
;; corpus.  If the input number is nothing, then return True as well
;; because it means that a verification has failed and thus the
;; experiment should be aborted.
;; (: equal-to-upidx-or-nothing (-> (Maybe Number) Bool))
(= (equal-to-upidx-or-nothing $idxm)
   (case $idxm
     (((Just $idx) (== (up-to-idx) $idx))
      (Nothing True))))

;; Create a propositional calculus rule base, containing type
;; theoretic representation of rules like
;;
;; (: ax-mp (-> (→ $𝜑 $𝜓) $𝜑 $𝜓))
!(bind! &pc-rb (new-space))

;; Create a propositional calculus axiom base, containing type
;; theoretic representation of axioms like
;;
;; (: ax-1 (→ $𝜑 (→ $𝜓 $𝜑)))
;; (: ax-2 (→ (→ $𝜑 (→ $𝜓 $𝜒)) (→ (→ $𝜑 $𝜓) (→ $𝜑 $𝜒))))
;; (: ax-3 (→ (→ (¬ $𝜑) (¬ $𝜓)) (→ $𝜓 $𝜑)))
!(bind! &pc-ab (new-space))

;; Create the attention-focused rule base.
!(bind! &pc-rb-af (new-space))

;; Hebbian link space: (Heb SRC TGT MEAN CONF) records that labels SRC and
;; TGT were used together in a discovered proof (asymmetric, like
;; ASYMMETRIC_HEBBIAN_LINK in the HebbianCreationAgent).
!(bind! &hebbian-stock (new-space))

;; Incident space for the diffusion agent's non-Hebbian spreading.  Our
;; labels are opaque symbols with no incoming/outgoing structure, so this
;; stays empty; diffusion therefore flows purely along Hebbian links.
!(bind! &incident (new-space))

;; Enable occurs check to detect cycles in unification (note that it
;; returns a variable, this is normal)
!(translatePredicate (set_prolog_flag occurs_check True))

;; Add assertion to knowledge bases.  If it is an axiom then add it to
;; pc-ab.  If it is a rule then add it to pc-rb.  Additionally replace
;; greek letters by variables.
(= (add-to-kbs $label $stmt)
   (let $stmt-with-vars (replace-greeks-by-variables $stmt)
     (let $is-rule (is-arrow $stmt)
       (progn
        ;; Add to rule base or axiom base
        (if $is-rule
            (add-atom &pc-rb (: $label $stmt-with-vars))
            (add-atom &pc-ab (: $label $stmt-with-vars)))
        (ecan-set-sti $label
                      (if $is-rule (ecan-seed-sti) (ecan-axiom-sti)))))))

;; Seed STI for a newly proved lemma: just above the highest STI in the
;; system, with (ecan-rule-sti) as a floor for the very first lemmas.
(= (ecan-seed-sti)
   (let $vals (collapse (let $ls (ecan-kb-rule-labels) (let $l (superpose $ls) (ecan-get-sti $l))))
     (if (== $vals ())
         (ecan-rule-sti)
         (max (ecan-rule-sti) (+ (max-atom $vals) (ecan-seed-bonus))))))

;; Add proof and theorem to label mapping to labels space
(= (add-to-labels $proof $theorem $label)
   (progn
    ;; (logger-tracef "Call: (add-to-labels %w %w %w)" ($proof $theorem $label))
    (let $theorem-with-vars (replace-greeks-by-variables $theorem)
      (add-atom &labels (Label $proof $theorem-with-vars $label)))))

;; Process the axiom of given index, that is insert the axiom into
;; pc-ab and return the next index.
;; NEXT: re-enable when fixed
;; (: process-axiom (-> Number Assertion (Maybe Number)))
(= (process-axiom $idx (MkAxiom $label $axiom))
   (progn
    (logger-infof "Iteration %w: add axiom %w" ($idx $label))
    (add-to-kbs $label $axiom)
    (Maybe.return (+ $idx 1))))

;; Process the theorem of a given index by checking its proof, if it
;; succeeds then insert it alongside its proof into the propositional
;; knowledge bases and return the next idx, or Nothing if it fails.
;; NEXT: re-enable when fixed (: process-theorem-check (-> Number
;; Number Assertion (Maybe Number)))
(= (process-theorem-check $idx $bound (MkTheorem $label $proof $thrm))
   (progn
    (if (bound-search-by-proof-size)
        (logger-infof "Iteration %w: verify proof of %w up to size %w"
                      ($idx $label $bound))
        (logger-infof "Iteration %w: verify proof of %w up to depth %w"
                      ($idx $label $bound)))
    (let (: $proof $thrm)
      (if (bound-search-by-proof-size)
          (obc &pc-rb &pc-ab callback $bound (: $proof $thrm))
          (bc &pc-rb &pc-ab callback (fromNumber $bound) (: $proof $thrm)))
      (case (: $proof $thrm)
        (;; Verified
         ((: $proof $thrm) (progn (add-to-kbs $label $thrm)
                                  (Maybe.return (+ $idx 1))))
         ;; Not verified
         (Empty Nothing))))))

;; Rediscover proof(s) of a theorem.  The results are returned as an
;; expression, a tuple of solutions, instead of a superposition to
;; avoid nondeterminism.
(= (rediscover-proofs $bound $proof $thrm)
   (let ;; Replace proof body by variable
       $proof-wo-bdy (replace-body-by-variable $proof)
     ;; Call backward chainer to rediscover the proof
     (collapse
      (if (bound-search-by-proof-size)
          (if (search-all-proofs)
              (obc &pc-rb &pc-ab callback $bound (: $proof-wo-bdy $thrm))
              (once (obc &pc-rb &pc-ab callback $bound (: $proof-wo-bdy $thrm))))
          (let $pdepth (fromNumber $depth)
            (if (search-all-proofs)
                (bc &pc-rb &pc-ab callback $pdepth (: $proof-wo-bdy $thrm))
                (once (bc &pc-rb &pc-ab callback $pdepth (: $proof-wo-bdy $thrm)))))))))

;; ECAN-guided rediscovery of proof(s) of a theorem.  It searches the
;; attention-focused rule base (&pc-rb-af, rebuilt from the current
;; attentional focus) FIRST; on a miss it falls back to the full &pc-rb.
;; Each tier is wrapped in `collapse` so a miss yields () (a value)
;; rather than a hard Prolog failure -- and each obc call is the only
;; one inside its own collapse.
(= (rediscover-proofs-ecan $bound $proof $thrm)
   (let $proof-wo-bdy (replace-body-by-variable $proof)
     ;; Rebuild the focused rule base from the current attentional focus.
     (let $_ (catch (ecan-rebuild-focused-rb))
       ;; Tier 1: search the attention-focused rule base.
       (let $af-result-raw
           (catch
            (collapse
             (if (search-all-proofs)
                 (obc &pc-rb-af &pc-ab callback $bound (: $proof-wo-bdy $thrm))
                 (once (obc &pc-rb-af &pc-ab callback $bound (: $proof-wo-bdy $thrm))))))
         ;; Normalize a caught error to an empty result.
         (let $af-result
             (if (and (is-expression $af-result-raw)
                      (== (car-atom $af-result-raw) Error))
                 ()
                 $af-result-raw)
         ;; Tier diagnostics: focused rule count, full rule count, Tier-1 hit.
         (let $_log (if (ecan-log-tier)
                        (logger-infof "  [tier] focused=%w full=%w af-hit=%w"
                                      ((size-atom (collapse (match &pc-rb-af (: $la $ta) $la)))
                                       (size-atom (collapse (match &pc-rb (: $lb $tb) $lb)))
                                       (not (== $af-result ()))))
                        ())
         (if (not (== $af-result ()))
             $af-result
             ;; Tier 2: fall back to the full rule base.
             (collapse
              (if (search-all-proofs)
                  (obc &pc-rb &pc-ab callback $bound (: $proof-wo-bdy $thrm))
                  (once (obc &pc-rb &pc-ab callback $bound (: $proof-wo-bdy $thrm))))))))))))

;; Process the theorem of a given index by rediscovering its proof, if
;; it succeeds then insert its alongside its proof(s) into the
;; propositional calculus knowledge bases and return the next idx, or
;; Nothing if it fails.
;;
;; NEXT: re-enable when fixed
;; (: process-theorem-search (-> Number Number Assertion (Maybe Number)))
(= (process-theorem-search $idx $bound (MkTheorem $label $proof $thrm))
   (progn
    (logger-infof "Iteration %w: ECAN-guided search proof of %w up to size %w"
                  ($idx $label $bound))
    (let $prfs-thrms (rediscover-proofs-ecan $bound $proof $thrm)
      (if (== $prfs-thrms ())
          ;; No proof
          (progn (logger-info "No proof found")
                 Nothing)
          ;; One or more proofs
          (progn
           ;; For each proof: map proof to label, stimulate the labels it
           ;; uses, and create/strengthen Hebbian links between every pair
           ;; of co-used labels (so future diffusion pre-activates them
           ;; together).
           (collapse
            (let (: $p $t) (superpose $prfs-thrms)
                 (progn
                  (logger-infof "Found proof%w %w" (: $p))
                  (add-to-labels $p $t $label)
                  (ecan-stimulate-proof $p)
                  (ecan-update-hebbian-links (ecan-proof-kb-labels $p)))))
           ;; Add proved theorem as lemma in kbs
           (add-to-kbs $label $thrm)
           ;; Run ECAN agents (diffusion + rent).  Skipped when the daemon is
           ;; running them continuously on its own thread.
           (if (ecan-background) () (ecan-run-agents))
           ;; Output next index
           (Just (+ $idx 1)))))))

;; Process the theorem of a given index, that is either check or
;; rediscover its proof, if it succeeds then insert it alongside its
;; proof into the propositional calculus knowledge bases and return
;; the next idx, or Nothing if it fails.
;; NEXT: re-enable when fixed
;; (: process-theorem (-> Number Assertion (Maybe Number)))
(= (process-theorem $idx (MkTheorem $label $proof $thrm))
   (let $bound (if (bound-search-by-proof-size)
                   (term-size $proof)   ; Calculate proof size
                   (term-depth $proof)) ; Calculate proof depth
     (if (search-proof)
         (process-theorem-search $idx
                                 $bound
                                 (MkTheorem $label $proof $thrm))
         (process-theorem-check $idx
                                $bound
                                (MkTheorem $label $proof $thrm)))))

;; Process the assertion corresponding to the given index and return
;; the index of the next assertion to process.  Meaning, if the
;; assertion is an axiom, insert the axiom in the knowledge base, and
;; if the assertion is a theorem, verify or proof the theorem and then
;; insert it in the knowledge base as if it were an axiom.  If it
;; fails to verify or proof then return Nothing instead of the next
;; index.
;; (: process-assertion (-> Number (Maybe Number)))
(= (process-assertion $idx)
   (progn
    (logger-tracef "Call: (process-assertion %w)" ($idx))
    (case (match &pc-idxd (MkIndexed $idx $asrt) $asrt)
      (((MkAxiom $label $axiom) (process-axiom $idx $asrt))
       ((MkTheorem $label $proof $thrm) (process-theorem $idx $asrt))
       ($else Nothing)))))

;; Like process-assertion but wrapped in Maybe.bind to accept maybe a
;; number, which the until construct needs.
;; (: process-assertion-m (-> (Maybe Number) (Maybe Number)))
(= (process-assertion-m $midx) (Maybe.bind $midx process-assertion))

;;;;;;;;;;;;;;;;;;;;;;;
;; Process PC Corpus ;;
;;;;;;;;;;;;;;;;;;;;;;;

;; Loop over all assertions of the corpus
;; once commits to the first solution, so a failure can't unwind past it
!(if (ecan-background)
     (progn (add-atom &ecan-ctl (running True))
            (translatePredicate (ecan_bg_start $bg-ok)))
     ())
!(once (until equal-to-upidx-or-nothing process-assertion-m (Just 2)))
!(if (ecan-background)
     (progn (ecan-daemon-stop)
            (logger-infof "[bg] daemon sweeps=%w final-funds=%w"
                          ((size-atom (collapse (match &ecan-ctl (tick) 1)))
                           (getAttentionParam FUNDS_STI))))
     ())

;; Log the content of pc-rb and pc-ab
!(logger-debugf "pc-rb: %w" ((get-atoms &pc-rb)))
!(logger-debugf "pc-ab: %w" ((get-atoms &pc-ab)))
