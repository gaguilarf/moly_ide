from fastapi import APIRouter
from backend.app.schemas.infra import BackupsOverview
from backend.app.services.ssh_inspector import ssh_inspector

router = APIRouter(prefix="/backups", tags=["Backups Multi-Project"])


@router.get("", response_model=BackupsOverview)
async def get_backups_overview():
    return await ssh_inspector.get_backups_status()
