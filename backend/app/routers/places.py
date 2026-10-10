from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models import Place, User
from app.schemas import PlaceCreate, PlaceResponse
from app.deps import get_current_user

router = APIRouter(prefix="/api/places", tags=["places"])

@router.post("", response_model=PlaceResponse)
async def create_place(
    data: PlaceCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    place = Place(**data.model_dump())
    db.add(place)
    await db.commit()
    await db.refresh(place)
    return place

@router.get("/{place_id}", response_model=PlaceResponse)
async def get_place(place_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Place).where(Place.id == place_id))
    place = result.scalar_one_or_none()
    if not place:
        raise HTTPException(status_code=404, detail="Место не найдено")
    return place

@router.get("", response_model=list[PlaceResponse])
async def list_places(
    lat: float | None = None,
    lng: float | None = None,
    radius: float = 1000,
    db: AsyncSession = Depends(get_db),
):
    # Простой поиск — без гео-радиуса (для MVP)
    result = await db.execute(select(Place).limit(50))
    return result.scalars().all()