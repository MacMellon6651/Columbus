from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from app.routers import auth, places, reviews, uploads
app = FastAPI(title="Columbus API", version="1.0.0")


app.mount("/uploads", StaticFiles(directory="/app/uploads"), name="uploads")
app.include_router(uploads.router)

# CORS — для веб-версии Flutter
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(places.router)
app.include_router(reviews.router)

@app.get("/")
async def root():
    return {"message": "Columbus API работает", "docs": "/docs"}