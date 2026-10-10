from pydantic import BaseModel, EmailStr, Field
from datetime import datetime
from typing import Optional

# ============ AUTH ============

class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6)

class UserResponse(BaseModel):
    id: int
    email: str
    created_at: datetime

    class Config:
        from_attributes = True

class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"

# ============ PLACES ============

class PlaceCreate(BaseModel):
    osm_id: Optional[int] = None
    osm_type: Optional[str] = None
    name: str
    lat: float
    lng: float
    address: Optional[str] = None

class PlaceResponse(BaseModel):
    id: int
    osm_id: Optional[int]
    osm_type: Optional[str]
    name: str
    lat: float
    lng: float
    address: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True

# ============ REVIEWS ============

class ReviewCreate(BaseModel):
    rating: int = Field(ge=1, le=5)
    comment: Optional[str] = None
    photo_urls: list[str] = []

class ReviewResponse(BaseModel):
    id: int
    place_id: int
    user_id: int
    rating: int
    comment: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True

class ReviewWithUser(ReviewResponse):
    user_email: str


