from fastapi import APIRouter, HTTPException, Query
from typing import List
from backend.app.schemas.infra import FileItem
from backend.app.services.ssh_inspector import ssh_inspector

router = APIRouter(prefix="/explorer", tags=["Read-Only Remote Explorer"])


@router.get("/tree", response_model=List[FileItem])
async def list_remote_path(path: str = Query("/root")):
    return await ssh_inspector.list_remote_directory(remote_path=path)


@router.get("/read-env")
async def read_env_file(file_path: str = Query(...)):
    try:
        content = await ssh_inspector.read_env_file_safe(file_path)
        if content is None:
            raise HTTPException(status_code=404, detail="Archivo no encontrado o no accesible.")
        return {"file_path": file_path, "content": content}
    except ValueError as ve:
        raise HTTPException(status_code=400, detail=str(ve))
