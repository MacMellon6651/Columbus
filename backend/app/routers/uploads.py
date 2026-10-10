import os
import uuid
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException
from app.deps import get_current_user
from app.models import User

router = APIRouter(prefix="/api/uploads", tags=["uploads"])

UPLOAD_DIR = "/app/uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}
MAX_SIZE = 10 * 1024 * 1024  # 10 MB


@router.post("")
async def upload_image(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
):
    if file.content_type not in ALLOWED_TYPES:
        raise HTTPException(400, "Разрешены только JPG, PNG, WEBP, GIF")

    contents = await file.read()
    if len(contents) > MAX_SIZE:
        raise HTTPException(400, "Файл слишком большой (макс. 10 МБ)")

    ext = file.filename.split('.')[-1] if '.' in file.filename else 'jpg'
    filename = f"{uuid.uuid4().hex}.{ext}"
    filepath = os.path.join(UPLOAD_DIR, filename)

    with open(filepath, "wb") as f:
        f.write(contents)

    return {"url": f"/uploads/{filename}"}