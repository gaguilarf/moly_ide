"""Esquemas del registro historico.

Se calca el contrato que ya servia el panel para que la mudanza no obligue a
reescribir a quien lo consume: mismos nombres de campo, incluidos los que vienen
de un join (`proyecto_nombre`, `auditoria_tipo`, `funcionalidad_nombre`).
"""

from datetime import date
from typing import List, Optional

from pydantic import BaseModel, ConfigDict


class ProyectoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    slug: str
    nombre: str
    ticket_key: Optional[str] = None
    repo_path: Optional[str] = None


class CambioOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    funcionalidad_id: int
    fecha: date
    tipo: str
    descripcion: str
    commit_ref: Optional[str] = None
    ticket_ref: Optional[str] = None


class FuncionalidadOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    proyecto: str
    proyecto_nombre: Optional[str] = None
    nombre: str
    descripcion: Optional[str] = None
    doc_path: Optional[str] = None
    estado: str
    creado_en: date


class AuditoriaOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    proyecto: str
    proyecto_nombre: Optional[str] = None
    fecha: date
    tipo: str
    resumen: Optional[str] = None
    doc_path: Optional[str] = None


class HallazgoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    auditoria_id: int
    auditoria_tipo: Optional[str] = None
    auditoria_fecha: Optional[date] = None
    proyecto: Optional[str] = None
    proyecto_nombre: Optional[str] = None
    funcionalidad_id: Optional[int] = None
    funcionalidad_nombre: Optional[str] = None
    codigo: Optional[str] = None
    severidad: str
    titulo: str
    detalle: Optional[str] = None
    estado: str
    resolucion: Optional[str] = None
    resuelto_en: Optional[date] = None
    ticket_ref: Optional[str] = None


class HallazgoUpdate(BaseModel):
    """Cambio de estado de un hallazgo. `resolucion` la exige cerrar."""

    estado: str
    resolucion: Optional[str] = None
    ticket_ref: Optional[str] = None


class ResumenProyecto(BaseModel):
    proyecto: str
    proyecto_nombre: Optional[str] = None
    abiertos: int
    criticas: int
    altas: int


class HallazgosRespuesta(BaseModel):
    hallazgos: List[HallazgoOut]
    resumen: List[ResumenProyecto]
