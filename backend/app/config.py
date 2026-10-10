from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # База данных
    database_url: str = "postgresql+asyncpg://columbus_user:columbus_password@postgres:5432/columbus_db"

    # JWT
    secret_key: str = "CHANGE_ME_IN_PRODUCTION_openssl_rand_hex_32"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 7  # 7 дней

    class Config:
        env_file = ".env"

settings = Settings()