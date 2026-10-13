;; WILLIAM / infcontrol model01, written natively in MeTTa.
;;
;;   (model_001 $theory $theorem)
;;
;;   $theory  : candidate premises, ((P LABEL STATEMENT) ...)
;;   $theorem : the goal statement
;;   returns  : ((P LABEL PROBABILITY) ...), most probable first
;;
;; Statements use the corpus spelling: variables are symbols whose first
;; character is Greek (𝜑, 𝜓, ...), as in &pc-orig of the experiment files.
;;
;; model01 is a logistic regression over 21 binary features that WILLIAM
;; found by searching over operator graphs:
;;
;;   P = sigmoid(initial + sum_i coefficient_i * feature_i)
;;
;; Each feature compares six measures of a goal/candidate pair (after
;; renaming variables to v0, v1, ... in first-occurrence order):
;;
;;   s  shared operators      number of term heads both formulas use
;;   y  shared symbols        number of symbols (heads and leaves) both use
;;   v  shared variables      min of the two variable counts
;;   m  max shared subtree    size of the largest subterm both contain
;;   l  operator L1 distance  sum over heads of |count_goal - count_cand|
;;   c  operator cosine       cosine of the two head-count vectors
;;
;; Three features compare a candidate with the MEAN of a measure over the
;; whole candidate set, which is why the model takes the theory as a batch.
;;
;; WILLIAM rounds the outputs of sqrt and mean to a precision it infers from
;; the whole batch (william.library.precision); that is reproduced here, so
;; this file returns the same features as infcontrol's model01 and the same
;; probabilities to floating-point accuracy.
;;
;; Validated against infcontrol on all 176 theorems of the experiment, see
;; m001_reference.py and m001_check.py.

;;;;;;;;;;;;;;;;;;;;;;;
;; Model parameters  ;;
;;;;;;;;;;;;;;;;;;;;;;;

(= (m001-initial) -5.120817500033296)
(= (m001-coefficients)
   (-100.00942231130142 -1.0972024971188976 0.817379124870164
    -1.3126622270128772 -2.1789287765926524 0.12422063934687991
    0.12422081777777666 -1.4040741399950813 -0.47972187403877165
    0.38568288967316267 0.882316145771316 -0.003073503109700702
    4.758278101237579 1.5953586276481944 0.10555713396285674
    0.5537096710517606 1.9186273811089378 -3.148654587404932
    1.2965889528682535 -100.01075905736741 -0.00009607583148174136))

;; infcontrol.canonicalize.GREEK_CHARS
(= (m001-greek)
   (α β γ δ ε ζ η θ ι κ λ μ ν ξ ο π ρ σ τ υ φ χ ψ ω
    𝛼 𝛽 𝛾 𝛿 𝜀 𝜁 𝜂 𝜃 𝜄 𝜅 𝜆 𝜇 𝜈 𝜉 𝜊 𝜋 𝜌 𝜎 𝜏 𝜐 𝜑 𝜒 𝜓 𝜔
    𝛢 𝛣 𝛤 𝛥 𝛦 𝛧 𝛨 𝛩 𝛪 𝛫 𝛬 𝛭 𝛮 𝛯 𝛰 𝛱 𝛲 𝛴 𝛵 𝛶 𝛷 𝛸 𝛹 𝛺))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Formula trees and stats    ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Numeric zero test: (== 0.0 0) is False in PeTTa.
(= (m001-zero? $x) (and (<= $x 0) (>= $x 0)))

(= (m001-expr? $t) (== (get-metatype $t) Expression))

(= (m001-member? $x $list) (not (== () (intersection-atom ($x) $list))))

;; A variable is a symbol whose first character is Greek.
(= (m001-var? $a)
   (if (== (get-metatype $a) Symbol)
       (m001-member? (car-atom (atom_chars $a)) (m001-greek))
       False))

;; Every non-expression atom of a tree, depth-first, left to right, with
;; multiplicity (heads included, as in infcontrol's symbol histogram).
(= (m001-atoms $t)
   (if (m001-expr? $t)
       (let $c (superpose $t) (m001-atoms $c))
       $t))

;; Every subterm that is an expression, with multiplicity (the root included).
(= (m001-sub $t) (if (m001-expr? $t) $t (empty)))
(= (m001-sub $t)
   (if (m001-expr? $t)
       (let $c (superpose $t) (m001-sub $c))
       (empty)))

;; Variables in order of first occurrence.
(= (m001-varorder $t)
   (unique-atom (collapse (let $a (m001-atoms $t)
                            (if (m001-var? $a) $a (empty))))))

(= (m001-index $x $list $i)
   (if (== $list ())
       -1
       (if (== (car-atom $list) $x)
           $i
           (m001-index $x (cdr-atom $list) (+ $i 1)))))

;; Rename variables to v0, v1, ... (infcontrol.canonicalize.canonicalize).
(= (m001-canon $t $vars)
   (if (m001-expr? $t)
       (m001-canon-list $t $vars)
       (let $i (m001-index $t $vars 0)
         (if (== $i -1) $t (atom_concat v $i)))))
(= (m001-canon-list $l $vars)
   (if (== $l ())
       ()
       (let ($h $tl) (decons-atom $l)
         (cons-atom (m001-canon $h $vars) (m001-canon-list $tl $vars)))))

;; Tree size: 1 + sizes of all elements (the head counts as an element).
(= (m001-size-acc $acc $x) (+ $acc (m001-size $x)))
(= (m001-size $t)
   (if (m001-expr? $t) (foldl-atom $t 1 m001-size-acc) 1))

(= (m001-count $x $list)
   (if (== $list ())
       0
       (+ (if (== (car-atom $list) $x) 1 0) (m001-count $x (cdr-atom $list)))))

;; Head-count histogram as ((O op count) ...).
;; NOTE superpose does not evaluate a call written inside it, so every list
;; that comes from a function is bound with let first.
(= (m001-histogram $heads)
   (let $ops (unique-atom $heads)
     (collapse (let $o (superpose $ops)
                 (O $o (m001-count $o $heads))))))

;; Statistics of one formula:
;;   (Fm ops-histogram symbols subtrees variable-count sum-of-squared-counts)
;; with subtrees as unique ((S size tree) ...).
(= (m001-stats $raw)
   (let* (($vars (m001-varorder $raw))
          ($t (m001-canon $raw $vars))
          ($heads (collapse (let $s (m001-sub $t)
                              (let $h (car-atom $s)
                                (if (m001-expr? $h) (empty) $h)))))
          ($hist (m001-histogram $heads))
          ($syms (unique-atom (collapse (m001-atoms $t))))
          ($subs (unique-atom (collapse (let $s (m001-sub $t) (S (m001-size $s) $s)))))
          ($sq (m001-sumsq $hist)))
     (Fm $hist $syms $subs (size-atom $vars) $sq)))

(= (m001-sumsq $hist)
   (if (== $hist ())
       0
       (let (O $o $n) (car-atom $hist)
         (+ (* $n $n) (m001-sumsq (cdr-atom $hist))))))

(= (m001-lookup $o $hist)
   (if (== $hist ())
       0
       (let (O $k $n) (car-atom $hist)
         (if (== $k $o) $n (m001-lookup $o (cdr-atom $hist))))))

(= (m001-op-names $hist)
   (collapse (let (O $o $n) (superpose $hist) $o)))

;; sum over all heads of |count_goal - count_cand|, and the dot product.
(= (m001-l1 $g $c)
   (+ (m001-l1-side $g $c) (m001-l1-only $c $g)))
(= (m001-l1-side $g $c)
   (if (== $g ())
       0
       (let (O $o $n) (car-atom $g)
         (+ (abs-math (- $n (m001-lookup $o $c))) (m001-l1-side (cdr-atom $g) $c)))))
(= (m001-l1-only $c $g)
   (if (== $c ())
       0
       (let (O $o $n) (car-atom $c)
         (+ (if (== (m001-lookup $o $g) 0) $n 0) (m001-l1-only (cdr-atom $c) $g)))))
(= (m001-dot $g $c)
   (if (== $g ())
       0
       (let (O $o $n) (car-atom $g)
         (+ (* $n (m001-lookup $o $c)) (m001-dot (cdr-atom $g) $c)))))

(= (m001-max-size $subs)
   (if (== $subs ()) 0 (max-atom (collapse (let (S $n $t) (superpose $subs) $n)))))

;; The six measures of one pair: (Mz s m l c y v).
(= (m001-measures (Fm $gh $gy $gs $gn $gq) (Fm $ch $cy $cs $cn $cq))
   (let* (($s (size-atom (intersection-atom (m001-op-names $gh) (m001-op-names $ch))))
          ($m (m001-max-size (intersection-atom $gs $cs)))
          ($l (m001-l1 $gh $ch))
          ($den (* (sqrt-math $gq) (sqrt-math $cq)))
          ($c (if (m001-zero? $den) 0.0 (/ (m001-dot $gh $ch) $den)))
          ($y (size-atom (intersection-atom $gy $cy)))
          ($v (min-atom ($gn $cn))))
     (Mz $s $m $l $c $y $v)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; WILLIAM's precision-aware sqrt and mean     ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(= (m001-sign $x) (if (> $x 0) 1 (if (< $x 0) -1 0)))

;; numpy rint: round half to even.
(= (m001-rint $y)
   (let* (($f (floor-math $y)) ($d (- $y $f)))
     (if (< $d 0.5)
         $f
         (if (> $d 0.5)
             (+ $f 1)
             (if (m001-zero? (- $f (* 2 (floor-math (/ $f 2))))) $f (+ $f 1))))))

;; numpy.round(x, k)
(= (m001-npround $x $k)
   (if (>= $k 0)
       (let $p (pow-math 10.0 $k) (/ (m001-rint (* $x $p)) $p))
       (let $p (pow-math 10.0 (- 0 $k)) (* (m001-rint (/ $x $p)) $p))))

;; william.library.precision.precision_scalar
(= (m001-prec $x)
   (if (< (abs-math $x) 1e-10) 0 (m001-prec-loop $x 0 0 True)))
(= (m001-prec-loop $x $k $p $pos)
   (if (>= $k 50)
       $p
       (if (and (<= $p 0) (< (abs-math (- $x (m001-npround $x (- 0 $k)))) 1e-10))
           (m001-prec-loop $x (+ $k 1) (- 0 $k) False)
           (if (not $pos)
               $p
               (if (< (abs-math (- $x (m001-npround $x $k))) 1e-10)
                   $k
                   (m001-prec-loop $x (+ $k 1) $p $pos))))))

(= (m001-prec-array $xs) (max-atom (collapse (m001-prec (superpose $xs)))))

;; william.library.precision.first_decimal_precision
(= (m001-first-dec $x) (m001-first-dec-loop $x 0))
(= (m001-first-dec-loop $x $i)
   (if (> $i 20)
       -9
       (if (> (pow-math 10.0 (- $i 10)) $x)
           (- 11 $i)
           (m001-first-dec-loop $x (+ $i 1)))))

(= (m001-clamp $q) (* (m001-sign $q) (min-atom ((abs-math $q) 10))))

;; william.library.precision.custom_round, halves rounded up
(= (m001-wround $x $p)
   (let* (($eps (pow-math 10.0 (- 0 $p)))
          ($mod (- $x (* $eps (floor-math (/ $x $eps))))))
     (if (< (abs-math (- $mod (/ $eps 2))) 1e-13)
         (+ $x (/ $eps 2))
         (m001-npround $x $p))))

;; Sqrt over a batch: precision from the smallest output spread of
;; sqrt(x +- eps), where eps is half a unit of the inputs' precision.
(= (m001-wsqrt $xs)
   (let* (($p (m001-prec-array $xs))
          ($eps (* (pow-math 10.0 (- 0 $p)) 0.5001))
          ($spreads (collapse (let $x (superpose $xs)
                                (if (>= (- $x $eps) 0)
                                    (- (sqrt-math (+ $x $eps)) (sqrt-math (- $x $eps)))
                                    (empty)))))
          ($q (m001-clamp (if (== $spreads ()) -10 (m001-first-dec (min-atom $spreads))))))
     (collapse (let $x (superpose $xs) (m001-wround (sqrt-math $x) $q)))))

;; Mean over a batch: the output spread of a mean is exactly 2*eps, so the
;; precision is that of the inputs.
(= (m001-wmean $xs)
   (m001-wround (/ (foldl-atom $xs 0 +) (size-atom $xs))
                (m001-clamp (m001-prec-array $xs))))

;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Features and model    ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;

(= (m001-lt $a $b) (if (< $a $b) 1 0))
(= (m001-ratio $a $b) (if (m001-zero? $b) 0.0 (/ $a $b)))

(= (m001-column $rows $i)
   (collapse (let $r (superpose $rows) (index-atom $r $i))))

;; Feature vectors of all candidates, in input order.  Each row is
;; (s m l c y v sqrt-s sqrt-m sqrt-l sqrt-y sqrt-v sqrt-sqrt-v).
(= (m001-features $theory $theorem)
   (let* (($g (m001-stats $theorem))
          ($rows (collapse (let (P $lbl $st) (superpose $theory)
                             (let (Mz $s $m $l $c $y $v) (m001-measures $g (m001-stats $st))
                               ($s $m $l $c $y $v)))))
          ($S (m001-column $rows 0)) ($M (m001-column $rows 1)) ($L (m001-column $rows 2))
          ($C (m001-column $rows 3)) ($Y (m001-column $rows 4)) ($V (m001-column $rows 5))
          ($sV (m001-wsqrt $V))
          ($cols (m001-zip7 $rows (m001-wsqrt $S) (m001-wsqrt $M) (m001-wsqrt $L)
                            (m001-wsqrt $Y) $sV (m001-wsqrt $sV)))
          ($mV (m001-wmean $V)) ($mL (m001-wmean $L)) ($mC (m001-wmean $C)))
     (collapse (let $r (superpose $cols) (m001-feature-row $r $mV $mL $mC)))))

(= (m001-zip7 $r $a $b $c $d $e $f)
   (if (== $r ())
       ()
       (cons-atom (R (car-atom $r) (car-atom $a) (car-atom $b) (car-atom $c)
                     (car-atom $d) (car-atom $e) (car-atom $f))
                  (m001-zip7 (cdr-atom $r) (cdr-atom $a) (cdr-atom $b) (cdr-atom $c)
                             (cdr-atom $d) (cdr-atom $e) (cdr-atom $f)))))

;; The 21 features, in model01's order (feature_0000 .. feature_0020).
(= (m001-feature-row (R ($s $m $l $c $y $v) $sS $sM $sL $sY $sV $ssV) $mV $mL $mC)
   ((m001-lt $s 1)
    (m001-lt $m 1)
    (m001-lt $l 1)
    (m001-lt $l 1)
    (m001-lt $c 1)
    (m001-lt $sM 1)
    (m001-lt $sM 1)
    (m001-lt $sL 1)
    (m001-lt (abs-math (- $sS $s)) 1)
    (m001-lt (abs-math (- $sS $s)) 1)
    (m001-lt (m001-ratio $sS $s) 1)
    (m001-lt (m001-ratio $sS $s) 1)
    (m001-lt (abs-math (- $y $sY)) 1)
    (m001-lt (abs-math (- $sY $y)) 1)
    (m001-lt (abs-math (- $m $sM)) 1)
    (m001-lt (abs-math (- $v $sV)) 1)
    (m001-lt (abs-math (- $sL $l)) 1)
    (m001-lt $v (abs-math (- $mV 1)))
    (m001-lt $l (abs-math (- $mL 1)))
    (m001-lt $c (m001-ratio $mC (m001-ratio 1.0 $mC)))
    (m001-lt (abs-math (- $v $ssV)) 1)))

(= (m001-dot-list $fs $ws)
   (if (== $fs ())
       0.0
       (+ (* (car-atom $fs) (car-atom $ws)) (m001-dot-list (cdr-atom $fs) (cdr-atom $ws)))))

(= (m001-e) 2.718281828459045)
(= (m001-sigmoid $z)
   (if (>= $z 0)
       (/ 1.0 (+ 1.0 (pow-math (m001-e) (- 0 $z))))
       (let $ez (pow-math (m001-e) $z) (/ $ez (+ 1.0 $ez)))))

;; Probabilities in input order.
(= (m001-scores $theory $theorem)
   (let* (($fs (m001-features $theory $theorem))
          ($ws (m001-coefficients)))
     (collapse (let $f (superpose $fs)
                 (m001-sigmoid (+ (m001-initial) (m001-dot-list $f $ws)))))))

(= (m001-pair-up $theory $ps)
   (if (== $theory ())
       ()
       (let (P $lbl $st) (car-atom $theory)
         (cons-atom (W (- 0 (car-atom $ps)) $lbl)
                    (m001-pair-up (cdr-atom $theory) (cdr-atom $ps))))))

;; The model: ranked ((P label probability) ...), most probable first.
(= (model_001 $theory $theorem)
   (let $sorted (sort-atom (m001-pair-up $theory (m001-scores $theory $theorem)))
     (collapse (let (W $neg $lbl) (superpose $sorted) (P $lbl (- 0 $neg))))))
