# ~7.27 GB Uncensored Candidate Gate

This file records the future candidate contract only. It does not claim that the target GGUF already exists.

Promotion from the current verified IQ2_M baseline requires one concrete artifact with a recorded source parent, quantization recipe, exact byte size and SHA-256, followed by reproducible comparison on the canonical RTX 3060 12 GB runtime.

Required gates:

1. GGUF opens and serves successfully with the current llama.cpp runtime.
2. Uncensored behavior does not materially regress versus the selected uncensored parent/baseline suite.
3. Tool-use and code-generation validity remain inside the accepted regression budget.
4. First-pass verified task rate and invalid API/import rate are measured.
5. End-to-end verified task latency is compared against the 10.6 GB IQ2_M baseline.
6. Peak VRAM, CPU/RAM spill and context tiers are measured.
7. MTP draft width is re-benchmarked; max2 is not inherited without evidence.
8. The artifact SHA-256 is pinned before setup/doctor/model aliases are changed.

Only after all gates pass may this candidate replace the IQ2_M baseline in the installer.
