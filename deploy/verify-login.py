"""Verify the first administrator over HTTP without writing passwords or tokens to disk."""
import getpass
import json
import sys
import urllib.error
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        raise urllib.error.HTTPError(request.full_url, code, "Redirect refused", headers, fp)


def main():
    base = input("Service URL [http://127.0.0.1:8080]: ").strip().rstrip("/") or "http://127.0.0.1:8080"
    username = input("Administrator username: ").strip()
    password = getpass.getpass("Administrator password (hidden): ")
    body = json.dumps({"userName": username, "password": password}).encode("utf-8")
    opener = urllib.request.build_opener(NoRedirect)
    try:
        request = urllib.request.Request(base + "/adminLogin", data=body,
                                         headers={"Content-Type": "application/json"})
        with opener.open(request, timeout=20) as response:
            login = json.load(response)
        if login.get("code") != 0 or not login.get("token"):
            raise ValueError("Login rejected; verify credentials and server logs")
        request = urllib.request.Request(base + "/admin/me/permissions",
                                         headers={"Authorization": "Bearer " + login["token"]})
        with opener.open(request, timeout=20) as response:
            me = json.load(response)
        if me.get("code") != 0 or me.get("scope") != "HQ" or not me.get("isSuperAdmin"):
            raise ValueError("Expected initial administrator HQ scope")
        if not me.get("permissions") or not me.get("shops"):
            raise ValueError("Expected seeded permissions and first shop")
        print("PASS: login code=0; authenticated HQ administrator; permissions and shop are present.")
        print("No password or token was printed or saved. Verify menu/devices and ordering state in the client next.")
        return 0
    except (urllib.error.URLError, ValueError, KeyError):
        print("FAIL: login or authenticated startup check failed; inspect server logs and configuration.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
