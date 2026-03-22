def ingest(sources):
    results = []
    for src in sources:
        try:
            results.append({"source": src, "success": True})
        except Exception as e:
            results.append({"source": src, "success": False, "error": str(e)})
    return results
