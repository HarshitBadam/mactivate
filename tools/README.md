# Tools

`tools/` contains standalone utilities that support research and repository maintenance.

- `analysis/` inspects IMU captures and scores the validated palm-tap rule.
- `hardware/` checks sensor access outside the normal interactive app context.
- `maintenance/` enforces repository structure and dependency boundaries.

Run tools from the repository root:

```bash
python3 tools/maintenance/check_repository.py
python3 tools/analysis/analyze_imu.py <capture-directory>
python3 tools/analysis/score_rule.py <capture-directory>
tools/hardware/check_daemon_context.sh
```
