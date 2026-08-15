from fastapi import APIRouter, HTTPException, Query
from typing import List
from backend.app.schemas.infra import DocItem
from backend.app.services.doc_service import doc_service

router = APIRouter(prefix="/docs", tags=["Documentation Service"])


@router.get("", response_model=List[DocItem])
async def list_documentation():
    return await doc_service.list_documents()


@router.get("/content")
async def get_document_content(path: str = Query(..., description="Ruta relativa del archivo markdown")):
    content = await doc_service.get_document_content(path)
    if content is None:
        raise HTTPException(status_code=404, detail="Documento no encontrado")
    return {"path": path, "content": content}
