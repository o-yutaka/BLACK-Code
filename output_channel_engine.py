from core.utils.safe_request import safe_url_request

def send(url):
    success, res = safe_url_request(url)
    return {"success": success, "response": res}
