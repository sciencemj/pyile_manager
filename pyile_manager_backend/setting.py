from __future__ import annotations

from pydantic import BaseModel, Field


class Settings(BaseModel):
    remove_duplicate: bool = True
    rename_by_ai: bool = True
    rename_ai: str = "gemma3:4b"
    ocr_ai: str = "deepocr"


class Move(BaseModel):
    url: dict[str, str] = Field(default_factory=dict)
    tag: dict[str, str] = Field(default_factory=dict)


class Schema(BaseModel):
    move: Move = Move()
    rename: list[str] = Field(default_factory=list)


class AppConfig(BaseModel):
    settings: Settings = Settings()
    watchlist: list[str] = Field(default_factory=list)
    schema: Schema = Schema()


class RenameResponse(BaseModel):
    name: str
