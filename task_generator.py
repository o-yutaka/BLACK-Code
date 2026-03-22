def generate_task(memory_results):
    # Codex: Replace with intelligent task generation
    if not memory_results:
        return "explore new strategy"

    failures = [m for m in memory_results if not m["meta"].get("success", True)]
    if failures:
        return "fix previous failure"

    return "optimize high score strategy"
