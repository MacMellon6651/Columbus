from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models import Review, Place, User
from app.schemas import ReviewCreate, ReviewWithUser
from app.deps import get_current_user

router = APIRouter(prefix="/api", tags=["reviews"])


@router.post("/places/{place_id}/reviews", response_model=ReviewWithUser)
async def create_review(
    place_id: int,
    data: ReviewCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Проверяем, существует ли место
    result = await db.execute(select(Place).where(Place.id == place_id))
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Место не найдено")

    # Создаём отзыв
    review = Review(
        place_id=place_id,
        user_id=current_user.id,
        rating=data.rating,
        comment=data.comment,
        photo_urls=data.photo_urls,
    )
    db.add(review)
    await db.commit()
    await db.refresh(review)

    return ReviewWithUser(
        id=review.id,
        place_id=review.place_id,
        user_id=review.user_id,
        rating=review.rating,
        comment=review.comment,
        photo_urls=review.photo_urls or [],
        created_at=review.created_at,
        user_email=current_user.email,
    )


@router.get("/places/{place_id}/reviews", response_model=list[ReviewWithUser])
async def list_reviews(place_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Review, User.email)
        .join(User, Review.user_id == User.id)
        .where(Review.place_id == place_id)
        .order_by(Review.created_at.desc())
    )
    rows = result.all()

    return [
        ReviewWithUser(
            id=r.Review.id,
            place_id=r.Review.place_id,
            user_id=r.Review.user_id,
            rating=r.Review.rating,
            comment=r.Review.comment,
            photo_urls=r.Review.photo_urls or [],
            created_at=r.Review.created_at,
            user_email=r.email,
        )
        for r in rows
    ]


@router.delete("/reviews/{review_id}")
async def delete_review(
    review_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(select(Review).where(Review.id == review_id))
    review = result.scalar_one_or_none()

    if not review:
        raise HTTPException(status_code=404, detail="Отзыв не найден")

    if review.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Можно удалять только свои отзывы")

    await db.delete(review)
    await db.commit()

    return {"message": "Отзыв удалён"}