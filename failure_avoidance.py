def should_avoid(memory_results):
    # Codex: improve pattern detection
    for m in memory_results:
        if not m["meta"].get("success", True):
            return True, m
    return False, None
