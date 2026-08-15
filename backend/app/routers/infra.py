from fastapi import APIRouter, Query
from typing import List
from backend.app.schemas.infra import ServerInfrastructureStatus
from backend.app.services.ssh_inspector import ssh_inspector

router = APIRouter(prefix="/infra", tags=["Infrastructure & Ports Monitor"])


@router.get("/status", response_model=ServerInfrastructureStatus)
async def get_node_status(node: str = Query("vps-brittany", enum=["vps-brittany", "vps-personal", "jetson"])):
    """Obtiene el estado de puertos e infraestructura del nodo seleccionado."""
    return await ssh_inspector.get_server_status(target=node)
