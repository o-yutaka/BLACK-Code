import urllib.request
from urllib.error import URLError

def safe_url_request(url, method="GET", data=None, headers=None):
    if not url or not url.startswith("http"):
        return False, "Invalid URL"

    try:
        req = urllib.request.Request(url=url, method=method, data=data, headers=headers or {})
        with urllib.request.urlopen(req) as response:
            return True, response.read().decode()
    except (ValueError, URLError, Exception) as e:
        return False, str(e)
