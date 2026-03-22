from sentence_transformers import SentenceTransformer
import faiss, numpy as np, json, os

class MemoryEngine:
    def __init__(self, path="data/memory.index"):
        self.model = SentenceTransformer("all-MiniLM-L6-v2")
        self.dim = 384
        self.path = path

        if os.path.exists(path):
            self.index = faiss.read_index(path)
        else:
            self.index = faiss.IndexFlatL2(self.dim)

        self.data = []
        if os.path.exists("data/memory.json"):
            with open("data/memory.json") as f:
                self.data = json.load(f)

    def save(self, text, metadata):
        emb = self.model.encode([text])
        self.index.add(np.array(emb).astype("float32"))
        self.data.append({"text": text, "meta": metadata})

        os.makedirs("data", exist_ok=True)
        faiss.write_index(self.index, self.path)

        with open("data/memory.json", "w") as f:
            json.dump(self.data, f)

    def search(self, query, k=5):
        if len(self.data) == 0:
            return []
        emb = self.model.encode([query])
        D, I = self.index.search(np.array(emb).astype("float32"), k)
        return [self.data[i] for i in I[0] if i < len(self.data)]
