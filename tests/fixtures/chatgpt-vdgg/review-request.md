# Independent review of the synthetic implementation

Read plan-request.md, clamp.py and test_clamp.py using the fixture connector.
Assess correctness including inverted/equal bounds and float bound types.
Assess security: no I/O, dynamic execution, network or hidden side effects.
Use execution_output to inspect any released test output for this task if available;
otherwise explicitly distinguish code review from verified test execution.
Return severity-tagged findings. PASS only with no high/medium blocking findings.
