def optimize(score):
    # Codex: evolve scoring strategy
    if score < 0.5:
        return "mutate"
    return "exploit"
