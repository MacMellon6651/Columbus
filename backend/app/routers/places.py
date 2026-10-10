from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models import Place, User, Review
from app.schemas import PlaceCreate, PlaceResponse
from app.deps import get_current_user
from sqlalchemy import func

router = APIRouter(prefix="/api/places", tags=["places"])



@router.get("", response_model=list[PlaceResponse])
async def list_places(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Place).limit(500))
    return result.scalars().all()

@router.get("/{place_id}/details")
async def get_place_details(place_id: int, db: AsyncSession = Depends(get_db)):
    # Место
    result = await db.execute(select(Place).where(Place.id == place_id))
    place = result.scalar_one_or_none()
    if not place:
        raise HTTPException(status_code=404, detail="Место не найдено")

    # Средний рейтинг и количество отзывов
    rating_result = await db.execute(
        select(
            func.avg(Review.rating).label('avg_rating'),
            func.count(Review.id).label('review_count'),
        ).where(Review.place_id == place_id)
    )
    row = rating_result.first()

    return {
        'id': place.id,
        'name': place.name,
        'category': place.category,
        'address': place.address,
        'description': place.description,
        'opening_hours': place.opening_hours,
        'phone': place.phone,
        'website': place.website,
        'lat': place.lat,
        'lng': place.lng,
        'avg_rating': float(row.avg_rating) if row.avg_rating else 0.0,
        'review_count': row.review_count or 0,
    }

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


@router.post("/find-or-create", response_model=PlaceResponse)
async def find_or_create_place(
    data: PlaceCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # 1. Если есть OSM ID — ищем по нему
    if data.osm_id is not None and data.osm_type is not None:
        result = await db.execute(
            select(Place).where(
                Place.osm_id == data.osm_id,
                Place.osm_type == data.osm_type,
            )
        )
        existing = result.scalar_one_or_none()
        if existing:
            return existing

    # 2. Иначе ищем по координатам (±0.0001) и имени
    result = await db.execute(
        select(Place).where(
            Place.name == data.name,
            Place.lat.between(data.lat - 0.0001, data.lat + 0.0001),
            Place.lng.between(data.lng - 0.0001, data.lng + 0.0001),
        )
    )
    existing = result.scalar_one_or_none()
    if existing:
        return existing

    # 3. Создаём новое
    place = Place(**data.model_dump())
    db.add(place)
    await db.commit()
    await db.refresh(place)
    return place