import re
import ssl

import requests

from tests.tests_deployment import constants


def get_jupyterhub_session():
    session = requests.Session()
    r = session.get(
        f"https://{constants.NEBARI_HOSTNAME}/hub/oauth_login", verify=False
    )
    auth_url = re.search('action="([^"]+)"', r.content.decode("utf8")).group(1)

    r = session.post(
        auth_url.replace("&amp;", "&"),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        data={
            "username": constants.KEYCLOAK_USERNAME,
            "password": constants.KEYCLOAK_PASSWORD,
            "credentialId": "",
        },
        verify=False,
    )
    assert r.headers.get('Set-Cookie')
    xsrf_token_found = r.headers['Set-Cookie'].split("_xsrf=")
    xsrf_token = None
    if xsrf_token_found:
        xsrf_token = xsrf_token_found[1].split(";")[0]
    else:
        print(f"_xsrf token not found in headers: {r} | {r.headers}")
    return session, xsrf_token


def get_jupyterhub_token(note="jupyterhub-tests-deployment"):
    session, xsrf_token = get_jupyterhub_session()
    keycloak_tokens_url = f"https://{constants.NEBARI_HOSTNAME}/hub/api/users/{constants.KEYCLOAK_USERNAME}/tokens"
    if xsrf_token:
        keycloak_tokens_url = f"{keycloak_tokens_url}?_xsrf={xsrf_token}"
    r = session.post(
        keycloak_tokens_url,
        headers={
            "Referer": f"https://{constants.NEBARI_HOSTNAME}/hub/token",
        },
        json={
            "note": note,
            "expires_in": None,
        },
    )
    rjson = r.json()
    if "token" not in rjson:
        print(f"get_jupyterhub_token response: {r}, {r.content}")
        raise AssertionError(f"Token not in response: {rjson}")
    return r.json()["token"]


def monkeypatch_ssl_context():
    """
    This is a workaround monkeypatch to disable ssl checking to avoid SSL
    failures.
    TODO: A better way to do this would be adding the Traefik's default certificate's
    CA public key to the trusted certificate authorities.
    """

    def create_default_context(context):
        def _inner(*args, **kwargs):
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
            return context

        return _inner

    sslcontext = ssl.create_default_context()
    ssl.create_default_context = create_default_context(sslcontext)
