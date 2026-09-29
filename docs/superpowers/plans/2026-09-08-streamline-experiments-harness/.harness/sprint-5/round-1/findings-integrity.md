# Findings — integrity lens — sprint 5 round 1

No findings under this lens.

Notes (not findings): all four criteria (C1-C4) are filesystem-state checks
(absence of `run_experiment.sh`, absence of `experiments/scapy/`, presence of
the two moved sweep files, exactly-one grep hit for `log()` and the report
writer's title string in `experiments/lib/`, and the nodes/ layout). Each can
fail on a plausible bad implementation (leaving a stray runner, forgetting
the move, or leaving a duplicate/no definition would flip the exit code), so
test 1 holds. The oracle for each is the filesystem state itself, not a
separate fixture file authored this round — `git show --stat` for
184a2eb shows only the eight deleted files, the two git-mv'd sweep scripts
(new, substantive content, not stubs — confirmed by reading think.sh and
stress.sh), and two comment-only line changes in core.sh/measure.sh that
don't touch `log()` or the report-writer string. No oracle file was
authored or modified by the same round it grades, so test 3 holds. No
`## Contract repairs` section exists in build-notes.md to audit.
