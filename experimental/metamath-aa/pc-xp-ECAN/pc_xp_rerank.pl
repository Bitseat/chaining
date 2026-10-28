%% Per-call rule ranking for pc-xp-ECAN-rerank.metta.
%%
%% Each application clause of the chainer (_obc has one per rule arity)
%% asks for the rules of its arity whose conclusion unifies with the call's
%% query.  rr_get/4 answers with the same rules, in this order:
%%   1. more premises that a hypothesis of the theorem closes outright, once
%%      the rule's conclusion is unified with the query;
%%   2. fewer new holes: premise variables that the query leaves unfixed;
%%   3. a more specific conclusion: more non-variable symbols in it;
%%   4. ties: the space's own order (the ECAN focus order in tier 1).
%% The order was chosen offline, by replaying the corpus proofs below index
%% 182 with the chainer's unification and ranking, at each rule node, the
%% rules whose conclusion unifies with the query the chainer sees there.
%%
%% The ranking depends only on the query up to variable renaming, the arity,
%% the space and the theorem's hypotheses, and none of those change during a
%% search.  So it is computed once per distinct query and cached for the
%% search: thread-local, since each search runs on a fresh worker thread.  A
%% cache hit fetches the ranked rules by label, which the space indexes, and
%% only those whose conclusion unifies; the plain lookup scans every rule.
%%
%% The chainer runs with occurs_check on, so binding a variable to a term
%% walks the term.  Hence the head patterns, and a cache of one clause per
%% ranked label rather than a list, which every hit would have to walk.

:- thread_local rr_seen/1.        % rr_seen(Key): ranking cached for Key
:- thread_local rr_item/2.        % rr_item(Key, Label), in ranked order
:- dynamic rr_tier_stats/2.       % rr_tier_stats(Tier, [Calls, Misses, Seconds, Cached])

% Cache at most this many distinct queries per search; a miss past it first
% empties the cache.  Safe mid-search: under the logical update view, any
% enumeration of rr_item/2 already under way keeps the clauses it started on.
rr_cache_cap(200000).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Hot path, called from the chainer as (rr_get $rb $env (: $f (-> ... $b))).
%% Nondeterministic: one solution per candidate rule, best first, each with
%% the rule's statement unified into the pattern -- exactly what
%% (get $rb (: $f (-> ... $b))) yields, in another order.

rr_get(Space, Env, Pat, Pat) :- rr_get_(Pat, Space, Env).

rr_get_([_, F, T], Space, Env) :-
    rr_shape(T, N, Q),
    rr_count_call,
    variant_sha1(k(Space, N, Q), Key),
    ( rr_seen(Key) -> true ; rr_rank(Space, N, Q, Env, Key) ),
    rr_item(Key, F),
    call(Space, ':', F, T).

% (-> P1 ... PN Q): N premises, conclusion Q.
rr_shape([_|Args], N, Q) :- rr_last(Args, 0, N, Q).

rr_last([Q], N, N, Q) :- !.
rr_last([_|T], N0, N, Q) :- N1 is N0 + 1, rr_last(T, N1, N, Q).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Miss path: rank the arity-N rules whose conclusion unifies with Q, then
%% cache the order.  Every feature is computed on copies, so Q is never bound.

rr_rank(Space, N, Q, Env, Key) :-
    get_time(T0),
    length(Prems, N),
    append(Prems, [C], Args),
    findall(c(F, Prems, C), call(Space, ':', F, ['->'|Args]), Cands),
    findall(k(NH, Ho, NS, I)-F,
            ( nth1(I, Cands, c(F, Ps, Co)),
              \+ \+ Co = Q,
              rr_features(Ps, Co, Q, Env, Hyp, Holes, Spec),
              NH is -Hyp, NS is -Spec, Ho = Holes ),
            Keyed),
    msort(Keyed, Sorted),
    rr_store(Key, Sorted),
    get_time(T1),
    US is round((T1 - T0) * 1000000),
    rr_count_miss(US).

rr_features(Ps, Co, Q, Env, Hyp, Holes, Spec) :-
    rr_nonvars(Co, Spec),
    copy_term(t(Ps, Co, Q), t(Ps1, Co1, Q1)),
    Co1 = Q1,
    aggregate_all(count,
                  ( member(P, Ps1), once(( member([_, _, H], Env), \+ \+ P = H )) ),
                  Hyp),
    term_variables(Ps1, PV),
    term_variables(Q1, QV),
    aggregate_all(count, ( member(V, PV), \+ ( member(W, QV), W == V ) ), Holes).

rr_nonvars(V, 0) :- var(V), !.
rr_nonvars(A, 1) :- atomic(A), !.
rr_nonvars([H|T], N) :- rr_nonvars(H, A), rr_nonvars(T, B), N is A + B.

rr_store(Key, Sorted) :-
    rr_cache_cap(Cap),
    ( nb_current(rr_cached, C0) -> true ; C0 = 0 ),
    (   C0 >= Cap
    ->  retractall(rr_seen(_)), retractall(rr_item(_, _)), C1 = 1
    ;   C1 is C0 + 1 ),
    assertz(rr_seen(Key)),
    forall(member(_-F, Sorted), assertz(rr_item(Key, F))),
    nb_setval(rr_cached, C1).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Per-tier counters (thread-local, tiny terms only).

rr_count_call :-
    (   nb_current(rr_stats, S)
    ->  arg(1, S, C0), C is C0 + 1, nb_setarg(1, S, C)
    ;   true ).

rr_count_miss(US) :-
    (   nb_current(rr_stats, S)
    ->  arg(2, S, M0), M is M0 + 1, nb_setarg(2, S, M),
        arg(3, S, U0), U is U0 + US, nb_setarg(3, S, U)
    ;   true ).

rr_tier_init :- nb_setval(rr_stats, s(0, 0, 0)).

rr_tier_publish(Tier) :-
    (   nb_current(rr_stats, s(C, M, US))
    ->  ( nb_current(rr_cached, K) -> true ; K = 0 ),
        Secs is US / 1000000,
        retractall(rr_tier_stats(Tier, _)),
        assertz(rr_tier_stats(Tier, [C, M, Secs, K]))
    ;   true ).

% For the [rerank] line: ((focused CALLS MISSES SECONDS CACHED) ...), for the
% tiers that ran in the last search.
rr_last_stats(Stats) :-
    findall([T|S], rr_tier_stats(T, S), Stats).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Both proof-search tiers with no deadline, plus per-tier ranking
%% counters.  On a fresh worker thread, so the thread-local ranking cache
%% starts empty for each search.  The worker always sends its result before
%% it exits, so joining it first and then reading the queue cannot hang.

rr_tiers_once(FocusedRB, FullRB, AB, CB, Bound, GoalIn, Result) :-
    retractall(rr_tier_stats(_, _)),
    message_queue_create(Q),
    get_time(Start),
    thread_create(
        rr_tiers_worker(FocusedRB, FullRB, AB, CB, Bound, GoalIn, Start, Q),
        Tid,
        []
    ),
    thread_join(Tid, _Status),
    rr_tiers_result(Q, Result),
    message_queue_destroy(Q).

rr_tiers_worker(FocusedRB, FullRB, AB, CB, Bound, GoalIn, Start, Q) :-
    (   catch(rr_tier(focused, obc(FocusedRB, AB, CB, Bound, GoalIn, Out)), _, fail)
    ->  get_time(FocusEnd),
        FocusSeconds is FocusEnd - Start,
        thread_send_message(Q, [focused, Out, FocusSeconds])
    ;   get_time(FocusEnd),
        FocusSeconds is FocusEnd - Start,
        thread_send_message(Q, focus_miss(FocusSeconds)),
        (   catch(rr_tier(fallback, obc(FullRB, AB, CB, Bound, GoalIn, Out)), _, fail)
        ->  get_time(End),
            TotalSeconds is End - Start,
            thread_send_message(Q, [fallback, Out, FocusSeconds, TotalSeconds])
        ;   get_time(End),
            TotalSeconds is End - Start,
            thread_send_message(Q, [not_found, FocusSeconds, TotalSeconds])
        )
    ).

% The cleanup also runs when the tier fails or raises, so its counters are
% still reported.
rr_tier(Tier, Goal) :-
    setup_call_cleanup(rr_tier_init, once(Goal), rr_tier_publish(Tier)).

% On a tier-1 miss the worker sends focus_miss(FocusSeconds) before it
% starts tier 2; the result is the message after it.
rr_tiers_result(Q, Result) :-
    thread_get_message(Q, Msg, [timeout(0)]),
    (   Msg = focus_miss(_)
    ->  rr_tiers_result(Q, Result)
    ;   Result = Msg
    ).
