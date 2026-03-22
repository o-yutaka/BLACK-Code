import time
from core.memory.memory_engine import MemoryEngine
from core.agents.task_generator import generate_task
from core.agents.failure_avoidance import should_avoid
from core.agents.optimizer_agent import optimize
from core.agents.reviewer_agent import review

memory = MemoryEngine()

def run_once(task, mode):
    # Codex: Replace with real execution logic
    score = 0.3 if mode == "mutate" else 0.8
    success = score > 0.4
    result = {"task": task, "mode": mode}
    return result, success, score

def main_loop():
    while True:
        past = memory.search("system state")

        task = generate_task(past)

        avoid, fail_case = should_avoid(past)
        if avoid:
            task = "avoid failure pattern"

        mode = "exploit"
        result, success, score = run_once(task, mode)

        decision = optimize(score)
        score = review(score)

        memory.save(
            text=str(result),
            metadata={
                "task": task,
                "success": success,
                "score": score,
                "decision": decision
            }
        )

        print("TASK:", task)
        print("RESULT:", result)
        print("SCORE:", score, "MODE:", decision)

        time.sleep(5)
