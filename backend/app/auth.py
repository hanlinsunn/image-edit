"""Sign in with Apple identity verification.

Clients send the Apple identity token as a bearer token. The token is verified
against Apple's published JWKS; in dev/test ``APP_AUTH_ALLOW_INSECURE_TOKENS``
skips signature verification so the API can be exercised without Apple.
"""

from __future__ import annotations

import time
from dataclasses import dataclass

import httpx
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.db import get_session
from app.models import User

_bearer = HTTPBearer(auto_error=True)
_jwk_client: PyJWKClient | None = None
_jwk_client_created_at: float = 0.0
_JWK_CLIENT_TTL_SECONDS = 3600


@dataclass(frozen=True)
class AppleIdentity:
    subject: str
    email: str | None
    is_private_relay: bool


class AuthError(HTTPException):
    def __init__(self, detail: str) -> None:
        super().__init__(status_code=status.HTTP_401_UNAUTHORIZED, detail=detail)


def _get_jwk_client(settings: Settings) -> PyJWKClient:
    global _jwk_client, _jwk_client_created_at
    if _jwk_client is None or time.time() - _jwk_client_created_at > _JWK_CLIENT_TTL_SECONDS:
        _jwk_client = PyJWKClient(settings.apple_keys_url)
        _jwk_client_created_at = time.time()
    return _jwk_client


def verify_apple_token(token: str, settings: Settings) -> AppleIdentity:
    if settings.auth_allow_insecure_tokens:
        claims = jwt.decode(token, options={"verify_signature": False})
    else:
        try:
            signing_key = _get_jwk_client(settings).get_signing_key_from_jwt(token)
            claims = jwt.decode(
                token,
                signing_key.key,
                algorithms=["RS256"],
                audience=settings.apple_bundle_id,
                issuer=settings.apple_issuer,
            )
        except (jwt.PyJWTError, httpx.HTTPError) as exc:
            raise AuthError(f"invalid Apple identity token: {exc}") from exc

    subject = claims.get("sub")
    if not subject:
        raise AuthError("Apple identity token is missing a subject")
    return AppleIdentity(
        subject=subject,
        email=claims.get("email"),
        is_private_relay=bool(claims.get("is_private_email", False)),
    )


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
    session: Session = Depends(get_session),
    settings: Settings = Depends(get_settings),
) -> User:
    identity = verify_apple_token(credentials.credentials, settings)
    user = session.scalar(select(User).where(User.apple_subject == identity.subject))
    if user is None:
        user = User(
            apple_subject=identity.subject,
            email=identity.email,
            is_private_relay_email=identity.is_private_relay,
        )
        session.add(user)
        session.flush()
    elif identity.email and user.email != identity.email:
        user.email = identity.email
    return user
