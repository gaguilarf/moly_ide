import asyncio

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter(prefix="/system", tags=["System Resources"])

# El mismo comando que la app sabe interpretar: ver SystemStats.command en
# lib/features/monitor/data/models/system_stats.dart. Las secciones van
# separadas por '@@@' y el parser depende de ese orden, asi que los dos lados
# tienen que moverse a la vez.
#
# Se ejecuta AQUI en vez de por SSH porque este backend ya corre en el Jetson,
# que es justo la maquina que se quiere medir: asi no hacen falta ni credenciales
# ni sesion abierta, y no hay forma de que acabe midiendo otro servidor.
COMANDO_METRICAS = (
    "cat /proc/stat; echo '@@@'; "
    "cat /proc/meminfo; echo '@@@'; "
    "cat /proc/loadavg; echo '@@@'; "
    "cat /proc/uptime; echo '@@@'; "
    "df -kP /; echo '@@@'; "
    "ps -eo pid,comm,pcpu,pmem --sort=-pcpu 2>/dev/null | head -n 7"
)

TIEMPO_LIMITE_SEGUNDOS = 10


class SystemStatsResponse(BaseModel):
    host: str
    raw: str


@router.get("/stats", response_model=SystemStatsResponse)
async def get_system_stats() -> SystemStatsResponse:
    """Recursos de la maquina donde corre este backend, es decir el Jetson."""
    proceso = await asyncio.create_subprocess_shell(
        COMANDO_METRICAS,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )

    try:
        salida, error = await asyncio.wait_for(
            proceso.communicate(), timeout=TIEMPO_LIMITE_SEGUNDOS
        )
    except asyncio.TimeoutError:
        # Sin esto el proceso se queda huerfano: la app pregunta cada 3 s, asi
        # que uno colgado por peticion se acumula rapido.
        proceso.kill()
        await proceso.wait()
        raise HTTPException(
            status_code=504,
            detail="El Jetson tardo demasiado en leer sus propias metricas.",
        )

    if proceso.returncode != 0:
        raise HTTPException(
            status_code=500,
            detail=(
                "No se pudieron leer las metricas del Jetson: "
                f"{error.decode(errors='replace').strip()}"
            ),
        )

    return SystemStatsResponse(
        host="jetson", raw=salida.decode(errors="replace")
    )
