%% Run focused and fallback obc searches under one wall-clock deadline.

timed_obc_tiers_once(FocusedRB, FullRB, AB, CB, Bound, GoalIn,
                     TimeLimit, Result) :-
    message_queue_create(Q),
    get_time(Start),
    Deadline is Start + TimeLimit,
    thread_create(
        timed_obc_tiers_worker(
            FocusedRB, FullRB, AB, CB, Bound, GoalIn, Start, Q
        ),
        Tid,
        []
    ),
    timed_obc_tiers_wait(Q, Tid, Start, Deadline, focused, 0.0, Result0),
    thread_join(Tid, _Status),
    message_queue_destroy(Q),
    Result = Result0.

timed_obc_tiers_wait(Q, Tid, Start, Deadline, Phase, FocusSeconds, Result) :-
    get_time(Now),
    Remaining is max(0.0, Deadline - Now),
    (   thread_get_message(Q, Msg, [timeout(Remaining)])
    ->  (   Msg = focus_miss(Elapsed)
        ->  timed_obc_tiers_wait(
                Q, Tid, Start, Deadline, fallback, Elapsed, Result
            )
        ;   Result = Msg
        )
    ;   catch(thread_signal(Tid, abort), _, true),
        get_time(End),
        TotalSeconds is End - Start,
        Result = [timeout, Phase, FocusSeconds, TotalSeconds]
    ).

timed_obc_tiers_worker(FocusedRB, FullRB, AB, CB, Bound, GoalIn, Start, Q) :-
    (   catch(once(obc(FocusedRB, AB, CB, Bound, GoalIn, Out)), _, fail)
    ->  get_time(FocusEnd),
        FocusSeconds is FocusEnd - Start,
        thread_send_message(Q, [focused, Out, FocusSeconds])
    ;   get_time(FocusEnd),
        FocusSeconds is FocusEnd - Start,
        thread_send_message(Q, focus_miss(FocusSeconds)),
        (   catch(once(obc(FullRB, AB, CB, Bound, GoalIn, Out)), _, fail)
        ->  get_time(End),
            TotalSeconds is End - Start,
            thread_send_message(Q, [fallback, Out, FocusSeconds, TotalSeconds])
        ;   get_time(End),
            TotalSeconds is End - Start,
            thread_send_message(Q, [not_found, FocusSeconds, TotalSeconds])
        )
    ).