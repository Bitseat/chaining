% Background runner for the ECAN daemon.
%
% The daemon is defined in MeTTa as (= (ecan-daemon) ...), which PeTTa
% compiles to 'ecan-daemon'/1 (the extra argument is the return value).
% We spawn it on its own SWI thread so the agents sweep continuously while
% the proof search runs on the main thread.
%
% Why a thread and not hyperpose: hyperpose runs EVERY branch in a worker
% thread, which would put the proof search off the main thread too.  Two
% pieces of state do not survive that: occurs_check is a thread-local Prolog
% flag (without it the chainer's until loop never returns), and log4p's
% handler registration does not propagate (every log line is silently lost).
% Spawning only the daemon keeps the search, its logging and its flags where
% they already work.  The daemon itself logs nothing.

:- use_module(library(thread)).

ecan_bg_start(true) :-
    thread_create(ecan_bg_loop, _, [detached(true)]).

ecan_bg_loop :-
    catch('ecan-daemon'(_), E, ecan_bg_recover(E)).

% unwind/1 is how SWI implements halt/0,1 and thread cancellation: it is a
% control construct, NOT an error, and swallowing it wedges process shutdown.
% Symptom when this clause is missing:
%   Warning: [Thread 3] Unknown message: ecan_bg_failed(unwind(halt(0)))
% Re-throw it and only report genuine errors.
ecan_bg_recover(unwind(Term)) :- !, throw(unwind(Term)).
ecan_bg_recover(E) :- print_message(warning, ecan_bg_failed(E)).

% Give the warning a printable form, so a real failure says what happened
% instead of "Unknown message".
:- multifile prolog:message//1.
prolog:message(ecan_bg_failed(E)) -->
    ['ECAN background daemon aborted: ~p'-[E]].
