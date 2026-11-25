%% Pattern rewards, pattern links and the mid-search focus update for
%% pc-xp-ECAN-steer-pattern.metta.
%%
%% REWARD.  Every chainer call of the focused search whose size budget
%% leaves room for a rule application (2 or more) hands its subgoal to
%% sp_call/3.  The first time a subgoal comes up in a search, up to variable
%% renaming, it rewards the rules whose conclusion matches it ONE-WAY, the
%% subgoal's own variables kept fixed, as applying the rule requires
%% (subsumes_term/2).  Every rule of the knowledge base is matched, not only
%% the focus, so a rule the focus lacks can earn its way in.  The subgoal's
%% Stimulus is split by specificity, the non-variable symbols of the
%% conclusion, so a bare-variable conclusion such as ax-mp's, which matches
%% everything, gets nothing.  A rule's n-th match in a search is worth 1/n
%% of its share, so a rule that matches hundreds of subgoals gains about the
%% log of that.  The credit waits in the global sp_pending until the MeTTa
%% side takes it (sp_take/1), right after sp_call/3, and writes it to the
%% bank.  This is nosteer-unify's matching (pc_xp_nosteer_unify.pl), given
%% out during the search instead of after it.
%%
%% PATTERN LINKS.  When a rule enters the knowledge base, sp_add_rule/3
%% links it to the rules whose whole statement unifies with its own: same
%% number of premises, premises and conclusion all unifiable, the Greek
%% letters being variables.  It is the relation nosteer-unify's nu_link/2
%% holds.  The links are kept here only so that the MeTTa side can write
%% each rule's entry, (KEY (KEY1 KEY2 ...)), into the space it hands ECAN's
%% diffusion agent as its incident space (sp_entry/2).  Nothing in this file
%% spreads attention: ECAN's diffusion does, along those entries.
%%
%% All of the reward runs only during the focused search, between
%% sp_begin/2 and sp_stop/1: the fallback searches the whole rule base,
%% which nothing can steer, so there sp_call/3 records nothing and sp_take/1
%% finds nothing.  The daemon updates the focus (sp_set_focus/3) in the same
%% window only.
%%
%% The search and the reward predicates run in the main thread; only
%% sp_set_focus/3 runs in the daemon's, and it shares nothing with them but
%% flags.  Nothing is retracted during a search: a retract there makes the
%% clause garbage collector scan the search's deep stack (see
%% pc_xp_nosteer_unify.pl), so counts live in flags and pending credit in a
%% global variable, and sp_begin/2 clears the facts of the last search.
%% The chainer runs with occurs_check on; nothing here binds a variable of a
%% subgoal.

:- dynamic sp_link/2.     % sp_link(A, B): statements of A and B unify (stored both ways)
:- dynamic sp_concl/3.    % sp_concl(Label, Conclusion, Specificity), non-variable conclusions
:- dynamic sp_key/1.      % sp_key(Key): flag Key counts the calls on a subgoal of this search
:- dynamic sp_rule/1.     % sp_rule(Label): a rule matched in this search; flags sp_n_<Label>
                          % and sp_c_<Label> hold its matches and its credit

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Pattern links.  When a rule enters the knowledge base (it is already in
%% Space): link it to the rules whose statement unifies with its own, and
%% keep its conclusion for matching.  Returns the labels it is now linked
%% to.

sp_add_rule(Space, Label, Linked) :-
    (   once(call(Space, ':', Label, T0))
    ->  findall(L,
                ( call(Space, ':', L, T1), L \== Label,
                  copy_term(T0, T), unify_with_occurs_check(T, T1) ),
                Ls),
        sort(Ls, Linked),
        forall(member(L, Linked),
               ( assertz(sp_link(Label, L)), assertz(sp_link(L, Label)) )),
        T0 = [_|Args], last(Args, C),
        (   nonvar(C)
        ->  sp_nonvars(C, S), assertz(sp_concl(Label, C, S))
        ;   true )
    ;   Linked = [] ).

sp_nonvars(V, 0) :- var(V), !.
sp_nonvars(A, 1) :- atomic(A), !.
sp_nonvars([H|T], N) :- sp_nonvars(H, A), sp_nonvars(T, B), N is A + B.

% A rule's pattern-link entry as the diffusion agent reads it, (KEY
% (KEY1 ...)) with the bank keys of the rule and of the rules it is linked
% to, or () when it has none.
sp_entry(Label, Entry) :-
    findall(B, sp_link(Label, B), Bs0),
    sort(Bs0, Bs),
    (   Bs == []
    ->  Entry = []
    ;   sp_bank_key(Label, K),
        maplist(sp_bank_key, Bs, Ks),
        Entry = [K, Ks] ).

% The bank key of a label, as ecan-key makes it.
sp_bank_key(L, K) :- atom_concat('L-', L, K).

% Pattern links in the knowledge base, each counted once.
sp_link_count(N) :-
    aggregate_all(count, sp_link(_, _), N2),
    N is N2 // 2.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Focused search start: forget the last search, set this one's stimulus,
%% and let rewards and the daemon's focus updates run.

sp_begin(Stimulus, true) :-
    forall(sp_key(K), flag(K, _, 0)),
    retractall(sp_key(_)),
    forall(sp_rule(L), ( sp_count_key(L, NK), flag(NK, _, 0),
                         sp_credit_key(L, CK), flag(CK, _, 0) )),
    retractall(sp_rule(_)),
    forall(member(F, [sp_calls, sp_subgoals, sp_matches, sp_given, sp_flushes,
                      sp_errors, sp_steer_checks, sp_steer_changes,
                      sp_steer_in, sp_steer_out]),
           flag(F, _, 0)),
    nb_setval(sp_pending, []),
    nb_setval(sp_flush_secs, 0.0),
    nb_setval(sp_stimulus, Stimulus),
    nb_setval(sp_on, true),
    flag(sp_steering, _, 1).

% Focused search end, after its last credit is given out: stop recording
% and stop the daemon's focus updates.  The fallback, if any, runs after.
sp_stop(true) :-
    nb_setval(sp_on, false),
    flag(sp_steering, _, 0).

sp_count_key(L, K) :- atom_concat(sp_n_, L, K).
sp_credit_key(L, K) :- atom_concat(sp_c_, L, K).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Every chainer call, from the first _obc clause, with the subgoal and the
%% call's size budget.  Always succeeds once and binds nothing; errors are
%% counted, never thrown -- a throw here would abort the whole tier.

sp_call(Q, MPS, true) :-
    (   nb_current(sp_on, true), number(MPS), MPS >= 2
    ->  catch(sp_call_(Q), E, sp_recover(E))
    ;   true ),
    !.
sp_call(_, _, true).

sp_recover(E) :- sp_control(E), !, throw(E).
sp_recover(_) :- flag(sp_errors, N, N + 1).

sp_control(unwind(_)).
sp_control('$aborted').

% The calls on a subgoal live in a flag named by its hash, and the first
% call rewards the rules that match it.
sp_call_(Q) :-
    flag(sp_calls, C, C + 1),
    variant_sha1(Q, H),
    atom_concat(sp_q_, H, K),
    flag(K, N0, N0 + 1),
    (   N0 =:= 0
    ->  assertz(sp_key(K)),
        flag(sp_subgoals, S, S + 1),
        sp_reward(Q)
    ;   true ).

% Queue the credit of a new subgoal Q: Stimulus split over the rules whose
% conclusion matches it, by specificity, each share divided by how many
% subgoals the rule has now matched in this search.
sp_reward(Q) :-
    findall(L-Sp, ( sp_concl(L, C, Sp), subsumes_term(C, Q) ), Ms),
    pairs_values(Ms, Sps),
    sum_list(Sps, Tot),
    (   Tot > 0
    ->  length(Ms, NM),
        flag(sp_matches, M0, M0 + NM),
        nb_getval(sp_stimulus, Stim),
        findall(L-X,
                ( member(L-Sp, Ms),
                  sp_count_key(L, NK),
                  flag(NK, N0, N0 + 1),
                  ( N0 =:= 0 -> assertz(sp_rule(L)) ; true ),
                  X is Stim * Sp / Tot / (N0 + 1),
                  sp_credit_key(L, CK),
                  flag(CK, X0, X0 + X) ),
                Credits),
        nb_getval(sp_pending, P0),
        append(Credits, P0, P1),
        nb_setval(sp_pending, P1)
    ;   true ).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Right after sp_call/3: the credit queued since the last take, summed per
%% rule, as ((credit LABEL STIMULUS) ...), and an empty queue.  () on most
%% calls, cheaply, and always outside the focused search.

sp_take(Credits) :-
    ( nb_current(sp_pending, P) -> true ; P = [] ),
    (   P == []
    ->  Credits = []
    ;   nb_setval(sp_pending, []),
        keysort(P, Sorted),
        group_pairs_by_key(Sorted, Groups),
        findall([credit, L, S], ( member(L-Ss, Groups), sum_list(Ss, S) ), Credits),
        length(Credits, N),
        flag(sp_given, G, G + N),
        flag(sp_flushes, Fl, Fl + 1) ).

% Seconds the MeTTa side spent writing one batch to the bank.
sp_flushed(Secs, true) :-
    nb_getval(sp_flush_secs, S0),
    S1 is S0 + Secs,
    nb_setval(sp_flush_secs, S1).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% After the search for the theorem Thm: for the [pattern] line (Calls
%% Subgoals Matches Rules Given Flushes FlushSecs SteerChecks SteerChanges
%% SteerIn SteerOut Top Errors), all of the focused search, Top being the
%% five rules credited most, as atoms such as 'syl=0.123'.  With the table
%% open, one CSV row per rule credited in it.

sp_end(Thm, [Calls, Subgoals, Matches, Rules, Given, Flushes, FlushSecs,
             Checks, Changes, In, Out, Top, Errors]) :-
    flag(sp_calls, Calls, Calls),
    flag(sp_subgoals, Subgoals, Subgoals),
    flag(sp_matches, Matches, Matches),
    flag(sp_given, Given, Given),
    flag(sp_flushes, Flushes, Flushes),
    flag(sp_errors, Errors, Errors),
    flag(sp_steer_checks, Checks, Checks),
    flag(sp_steer_changes, Changes, Changes),
    flag(sp_steer_in, In, In),
    flag(sp_steer_out, Out, Out),
    ( nb_current(sp_flush_secs, FlushSecs) -> true ; FlushSecs = 0.0 ),
    findall(X-row(L, N),
            ( sp_rule(L), sp_count_key(L, NK), flag(NK, N, N),
              sp_credit_key(L, CK), flag(CK, X, X) ),
            Rows),
    length(Rows, Rules),
    sort(1, @>=, Rows, Sorted),
    length(Sorted, Len), Kt is min(5, Len), length(Best, Kt), append(Best, _, Sorted),
    findall(At, ( member(X-row(L, _), Best), format(atom(At), '~w=~4f', [L, X]) ), Top),
    sp_write_table(Thm, Sorted).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% The credit table: one CSV row per rule credited in a focused search, most
%% credit first.  subgoals = the subgoals its conclusion matched; credit =
%% what it was given for them, in units of stimulus (the STI each unit buys
%% is the wage when it was given out).  What ECAN's diffusion then moved
%% along the pattern links is not here: it happens in the bank.

sp_open_table(Path, true) :-
    ( is_stream(sp_table) -> close(sp_table) ; true ),
    open(Path, write, _, [alias(sp_table), encoding(utf8)]),
    format(sp_table, "theorem,rule,subgoals,credit~n", []),
    flush_output(sp_table).

sp_write_table(Thm, Sorted) :-
    (   is_stream(sp_table), Sorted \== []
    ->  forall(member(X-row(L, N), Sorted),
               format(sp_table, "~w,~w,~w,~6f~n", [Thm, L, N, X])),
        flush_output(sp_table)
    ;   true ).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% The daemon's mid-search focus update, during a focused search only: make
%% Space hold the rules of TopN, a list of (SCORE LABEL TYPE), without
%% reordering it.  A rule that has left the top is erased, by reference; a
%% rule that has entered it is added at the end; the others keep their
%% place, so the order the search tries them in stays the one it started
%% with.  The entering rules are added before the leaving ones are erased,
%% so a rule lookup never sees the focus empty, and one already under way
%% keeps the clauses it started with (logical update view).

sp_set_focus(Space, TopN, true) :-
    (   flag(sp_steering, 1, 1)
    ->  flag(sp_steer_checks, C, C + 1),
        Probe =.. [Space, ':', _, _],
        (   current_predicate(_, Probe)
        ->  findall(L-Ref, ( H0 =.. [Space, ':', L, _], clause(H0, true, Ref) ), Old)
        ;   Old = [] ),
        findall(L-T, ( member([_, L, T], TopN), \+ memberchk(L-_, Old) ), Entering),
        findall(L-Ref, ( member(L-Ref, Old), \+ memberchk([_, L, _], TopN) ), Leaving),
        (   Entering == [], Leaving == []
        ->  true
        ;   forall(member(L-T, Entering), ( H =.. [Space, ':', L, T], assertz(H) )),
            forall(member(_-Ref, Leaving), erase(Ref)),
            length(Entering, NIn), length(Leaving, NOut),
            flag(sp_steer_changes, Ch, Ch + 1),
            flag(sp_steer_in, I0, I0 + NIn),
            flag(sp_steer_out, O0, O0 + NOut) )
    ;   true ).
