def calculate_revenue(offers, fallback):
    if not offers:
        return fallback["price"]
    return sum(o["price"] for o in offers)
