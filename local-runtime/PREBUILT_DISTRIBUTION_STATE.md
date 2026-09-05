# Distribution activation state

Source-build helpers are implemented.

The prebuilt distribution path is intentionally **not yet canonical-default** because the first real BLACK 7.27 GGUF has not yet produced its final measured SHA256 and published URLs.

Activation gate:

1. real source build completes;
2. 7.20-7.35 GB artifact gate passes;
3. actual SHA256 is measured;
4. canonical `model-7.27.local.json` matches the artifact and provenance checks;
5. the exact GGUF + manifest are published;
6. future setup can then pin those published URLs/SHA and prefer direct prebuilt install.

Until those conditions are met, do not invent a prebuilt SHA or URL and do not mark distribution as canonical.
