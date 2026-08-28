from fastapi import APIRouter, Depends

from app.auth import get_current_user
from app.models import User
from app.schemas import UserResponse

router = APIRouter(prefix="/v1", tags=["users"])


@router.post("/auth/session", response_model=UserResponse)
def create_session(user: User = Depends(get_current_user)) -> UserResponse:
    """Exchange an Apple identity token for the backend user record.

    Called right after Sign in with Apple so the account exists before any upload.
    """
    return UserResponse(id=user.id, email=user.email, timezone=user.timezone)


@router.get("/me", response_model=UserResponse)
def get_me(user: User = Depends(get_current_user)) -> UserResponse:
    return UserResponse(id=user.id, email=user.email, timezone=user.timezone)
