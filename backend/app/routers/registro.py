"""Registro historico del ecosistema: funcionalidades, cambios, auditorias y hallazgos.

Se muda aqui desde el panel (ADR-004, INF-54). Los datos ya vinieron en la
migracion de PAN-35; esto es la puerta para leerlos y resolverlos.

El contrato se calca del que servia el panel a proposito: la skill
`brittany-arch` manda consultar los hallazgos abiertos antes de tocar codigo y
resolverlos al cerrar, y no tiene sentido cambiarle el vocabulario a ese paso
solo porque cambie la maquina.
"""

from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.app.database import get_db
from backend.app.models.registry import (
    RegistroAuditoria,
    RegistroCambio,
    RegistroFuncionalidad,
    RegistroHallazgo,
    RegistroProyecto,
)
from backend.app.schemas.registro import (
    AuditoriaOut,
    CambioOut,
    FuncionalidadOut,
    HallazgoOut,
    HallazgosRespuesta,
    HallazgoUpdate,
    ProyectoOut,
    ResumenProyecto,
)
from backend.app.security import Actor, require_actor

router = APIRouter(prefix="/registro", tags=["Registro historico"])

ESTADOS = ("abierto", "resuelto", "aceptado", "descartado")
SEVERIDADES = ("critica", "alta", "media", "baja")

# El registro fecha en dias, y el dia se cuenta en Lima. Con UTC, todo lo que se
# resuelva despues de las 19:00 quedaria fechado al dia siguiente.
LIMA = timezone(timedelta(hours=-5))


def hoy_en_lima():
    return datetime.now(LIMA).date()


@router.get("/proyectos", response_model=List[ProyectoOut])
async def listar_proyectos(db: AsyncSession = Depends(get_db)):
    res = await db.execute(select(RegistroProyecto).order_by(RegistroProyecto.nombre))
    return res.scalars().all()


@router.get("/funcionalidades", response_model=List[FuncionalidadOut])
async def listar_funcionalidades(
    proyecto: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
):
    q = (
        select(RegistroFuncionalidad, RegistroProyecto.nombre)
        .join(RegistroProyecto, RegistroProyecto.slug == RegistroFuncionalidad.proyecto_slug)
        .order_by(RegistroFuncionalidad.proyecto_slug, RegistroFuncionalidad.nombre)
    )
    if proyecto:
        q = q.where(RegistroFuncionalidad.proyecto_slug == proyecto)

    salida = []
    for func_, nombre_proyecto in (await db.execute(q)).all():
        salida.append(
            FuncionalidadOut(
                id=func_.id,
                proyecto=func_.proyecto_slug,
                proyecto_nombre=nombre_proyecto,
                nombre=func_.nombre,
                descripcion=func_.descripcion,
                doc_path=func_.doc_path,
                estado=func_.estado,
                creado_en=func_.creado_en,
            )
        )
    return salida


@router.get("/funcionalidades/{funcionalidad_id}/cambios", response_model=List[CambioOut])
async def listar_cambios(funcionalidad_id: int, db: AsyncSession = Depends(get_db)):
    if not await db.get(RegistroFuncionalidad, funcionalidad_id):
        raise HTTPException(status_code=404, detail=f"La funcionalidad {funcionalidad_id} no existe")
    res = await db.execute(
        select(RegistroCambio)
        .where(RegistroCambio.funcionalidad_id == funcionalidad_id)
        .order_by(RegistroCambio.fecha.desc(), RegistroCambio.id.desc())
    )
    return res.scalars().all()


@router.get("/auditorias", response_model=List[AuditoriaOut])
async def listar_auditorias(
    proyecto: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
):
    q = (
        select(RegistroAuditoria, RegistroProyecto.nombre)
        .join(RegistroProyecto, RegistroProyecto.slug == RegistroAuditoria.proyecto_slug)
        .order_by(RegistroAuditoria.fecha.desc())
    )
    if proyecto:
        q = q.where(RegistroAuditoria.proyecto_slug == proyecto)

    salida = []
    for aud, nombre_proyecto in (await db.execute(q)).all():
        salida.append(
            AuditoriaOut(
                id=aud.id,
                proyecto=aud.proyecto_slug,
                proyecto_nombre=nombre_proyecto,
                fecha=aud.fecha,
                tipo=aud.tipo,
                resumen=aud.resumen,
                doc_path=aud.doc_path,
            )
        )
    return salida


async def _hallazgo_completo(db: AsyncSession, hallazgo_id: int) -> HallazgoOut:
    fila = (
        await db.execute(
            select(
                RegistroHallazgo,
                RegistroAuditoria.tipo,
                RegistroAuditoria.fecha,
                RegistroAuditoria.proyecto_slug,
                RegistroProyecto.nombre,
                RegistroFuncionalidad.nombre,
            )
            .join(RegistroAuditoria, RegistroAuditoria.id == RegistroHallazgo.auditoria_id)
            .join(RegistroProyecto, RegistroProyecto.slug == RegistroAuditoria.proyecto_slug)
            .outerjoin(
                RegistroFuncionalidad,
                RegistroFuncionalidad.id == RegistroHallazgo.funcionalidad_id,
            )
            .where(RegistroHallazgo.id == hallazgo_id)
        )
    ).first()
    if not fila:
        raise HTTPException(status_code=404, detail=f"El hallazgo {hallazgo_id} no existe")

    hallazgo, aud_tipo, aud_fecha, proyecto, proyecto_nombre, func_nombre = fila
    item = HallazgoOut.model_validate(hallazgo)
    item.auditoria_tipo = aud_tipo
    item.auditoria_fecha = aud_fecha
    item.proyecto = proyecto
    item.proyecto_nombre = proyecto_nombre
    item.funcionalidad_nombre = func_nombre
    return item


@router.get("/hallazgos", response_model=HallazgosRespuesta)
async def listar_hallazgos(
    estado: Optional[str] = Query(None, description="abierto | resuelto | aceptado | descartado"),
    proyecto: Optional[str] = None,
    severidad: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
):
    if estado and estado not in ESTADOS:
        raise HTTPException(status_code=422, detail=f"estado invalido; use uno de {', '.join(ESTADOS)}")
    if severidad and severidad not in SEVERIDADES:
        raise HTTPException(status_code=422, detail=f"severidad invalida; use una de {', '.join(SEVERIDADES)}")

    q = (
        select(
            RegistroHallazgo,
            RegistroAuditoria.tipo,
            RegistroAuditoria.fecha,
            RegistroAuditoria.proyecto_slug,
            RegistroProyecto.nombre,
            RegistroFuncionalidad.nombre,
        )
        .join(RegistroAuditoria, RegistroAuditoria.id == RegistroHallazgo.auditoria_id)
        .join(RegistroProyecto, RegistroProyecto.slug == RegistroAuditoria.proyecto_slug)
        .outerjoin(
            RegistroFuncionalidad,
            RegistroFuncionalidad.id == RegistroHallazgo.funcionalidad_id,
        )
    )
    if estado:
        q = q.where(RegistroHallazgo.estado == estado)
    if proyecto:
        q = q.where(RegistroAuditoria.proyecto_slug == proyecto)
    if severidad:
        q = q.where(RegistroHallazgo.severidad == severidad)

    # Critica primero: el orden por severidad importa mas que el alfabetico
    # cuando lo que se mira es que atender antes.
    orden = {"critica": 0, "alta": 1, "media": 2, "baja": 3}

    hallazgos = []
    for hallazgo, aud_tipo, aud_fecha, proy, proy_nombre, func_nombre in (await db.execute(q)).all():
        item = HallazgoOut.model_validate(hallazgo)
        item.auditoria_tipo = aud_tipo
        item.auditoria_fecha = aud_fecha
        item.proyecto = proy
        item.proyecto_nombre = proy_nombre
        item.funcionalidad_nombre = func_nombre
        hallazgos.append(item)
    hallazgos.sort(key=lambda h: (orden.get(h.severidad, 9), h.id))

    # El resumen mira SIEMPRE los abiertos, filtre lo que filtre la lista: es la
    # foto de lo que queda pendiente, no de lo que se esta mirando ahora.
    resumen_q = (
        select(
            RegistroAuditoria.proyecto_slug,
            RegistroProyecto.nombre,
            func.count(RegistroHallazgo.id),
            func.count(RegistroHallazgo.id).filter(RegistroHallazgo.severidad == "critica"),
            func.count(RegistroHallazgo.id).filter(RegistroHallazgo.severidad == "alta"),
        )
        .join(RegistroAuditoria, RegistroAuditoria.id == RegistroHallazgo.auditoria_id)
        .join(RegistroProyecto, RegistroProyecto.slug == RegistroAuditoria.proyecto_slug)
        .where(RegistroHallazgo.estado == "abierto")
        .group_by(RegistroAuditoria.proyecto_slug, RegistroProyecto.nombre)
        .order_by(func.count(RegistroHallazgo.id).desc())
    )
    resumen = [
        ResumenProyecto(proyecto=p, proyecto_nombre=n, abiertos=a, criticas=c, altas=al)
        for p, n, a, c, al in (await db.execute(resumen_q)).all()
    ]

    return HallazgosRespuesta(hallazgos=hallazgos, resumen=resumen)


@router.get("/hallazgos/{hallazgo_id}", response_model=HallazgoOut)
async def ver_hallazgo(hallazgo_id: int, db: AsyncSession = Depends(get_db)):
    return await _hallazgo_completo(db, hallazgo_id)


@router.patch("/hallazgos/{hallazgo_id}", response_model=HallazgoOut)
async def actualizar_hallazgo(
    hallazgo_id: int,
    payload: HallazgoUpdate,
    db: AsyncSession = Depends(get_db),
    actor: Actor = Depends(require_actor),
):
    if payload.estado not in ESTADOS:
        raise HTTPException(status_code=422, detail=f"estado invalido; use uno de {', '.join(ESTADOS)}")

    hallazgo = await db.get(RegistroHallazgo, hallazgo_id)
    if not hallazgo:
        raise HTTPException(status_code=404, detail=f"El hallazgo {hallazgo_id} no existe")

    cerrado = payload.estado != "abierto"
    if cerrado and not (payload.resolucion or "").strip():
        raise HTTPException(
            status_code=422,
            detail="Cerrar un hallazgo exige explicar la resolucion: un hallazgo cerrado sin motivo no se puede auditar.",
        )

    hallazgo.estado = payload.estado
    # Reabrir limpia la resolucion y la fecha: dejarlas puestas describiria un
    # cierre que ya no es cierto.
    hallazgo.resolucion = (payload.resolucion or "").strip() or None if cerrado else None
    hallazgo.resuelto_en = hoy_en_lima() if cerrado else None
    if payload.ticket_ref:
        hallazgo.ticket_ref = payload.ticket_ref

    await db.commit()
    return await _hallazgo_completo(db, hallazgo_id)


# ── Escritura ────────────────────────────────────────────────────────────────
# El flujo de desarrollo obliga a registrar el cambio al cerrar un ticket, asi
# que sin estas rutas la mudanza dejaria el registro en solo lectura y ese paso
# no se podria cumplir.


@router.post("/proyectos", status_code=201, response_model=ProyectoOut)
async def crear_proyecto(payload: ProyectoOut, db: AsyncSession = Depends(get_db), actor: Actor = Depends(require_actor)):
    if await db.get(RegistroProyecto, payload.slug):
        raise HTTPException(status_code=409, detail=f"El proyecto {payload.slug} ya existe")
    proyecto = RegistroProyecto(
        slug=payload.slug, nombre=payload.nombre,
        ticket_key=payload.ticket_key, repo_path=payload.repo_path,
    )
    db.add(proyecto)
    await db.commit()
    return payload


@router.post("/funcionalidades", status_code=201, response_model=FuncionalidadOut)
async def crear_funcionalidad(payload: dict, db: AsyncSession = Depends(get_db), actor: Actor = Depends(require_actor)):
    proyecto = (payload.get("proyecto") or "").strip()
    nombre = (payload.get("nombre") or "").strip()
    if not proyecto or not nombre:
        raise HTTPException(status_code=422, detail="proyecto y nombre son obligatorios")
    if not await db.get(RegistroProyecto, proyecto):
        raise HTTPException(status_code=404, detail=f"El proyecto {proyecto} no existe")

    func_ = RegistroFuncionalidad(
        proyecto_slug=proyecto,
        nombre=nombre,
        descripcion=payload.get("descripcion"),
        doc_path=payload.get("doc_path"),
        estado=payload.get("estado", "activa"),
        creado_en=hoy_en_lima(),
    )
    db.add(func_)
    await db.commit()
    await db.refresh(func_)
    return FuncionalidadOut(
        id=func_.id, proyecto=func_.proyecto_slug, nombre=func_.nombre,
        descripcion=func_.descripcion, doc_path=func_.doc_path,
        estado=func_.estado, creado_en=func_.creado_en,
    )


@router.patch("/funcionalidades/{funcionalidad_id}", response_model=FuncionalidadOut)
async def editar_funcionalidad(
    funcionalidad_id: int, payload: dict, db: AsyncSession = Depends(get_db), actor: Actor = Depends(require_actor)
):
    func_ = await db.get(RegistroFuncionalidad, funcionalidad_id)
    if not func_:
        raise HTTPException(status_code=404, detail=f"La funcionalidad {funcionalidad_id} no existe")
    for campo in ("descripcion", "doc_path", "estado", "nombre"):
        if campo in payload and payload[campo] is not None:
            setattr(func_, campo, payload[campo])
    await db.commit()
    await db.refresh(func_)
    return FuncionalidadOut(
        id=func_.id, proyecto=func_.proyecto_slug, nombre=func_.nombre,
        descripcion=func_.descripcion, doc_path=func_.doc_path,
        estado=func_.estado, creado_en=func_.creado_en,
    )


@router.post("/funcionalidades/{funcionalidad_id}/cambios", status_code=201, response_model=CambioOut)
async def registrar_cambio(
    funcionalidad_id: int, payload: dict, db: AsyncSession = Depends(get_db), actor: Actor = Depends(require_actor)
):
    """El paso final del flujo: que quede escrito que esa funcionalidad cambio."""
    if not await db.get(RegistroFuncionalidad, funcionalidad_id):
        raise HTTPException(status_code=404, detail=f"La funcionalidad {funcionalidad_id} no existe")
    tipo = (payload.get("tipo") or "").strip()
    descripcion = (payload.get("descripcion") or "").strip()
    if not tipo or not descripcion:
        raise HTTPException(status_code=422, detail="tipo y descripcion son obligatorios")

    cambio = RegistroCambio(
        funcionalidad_id=funcionalidad_id,
        fecha=payload.get("fecha") or hoy_en_lima(),
        tipo=tipo,
        descripcion=descripcion,
        commit_ref=payload.get("commit_ref"),
        ticket_ref=payload.get("ticket_ref"),
    )
    db.add(cambio)
    await db.commit()
    await db.refresh(cambio)
    return cambio


@router.post("/auditorias", status_code=201, response_model=AuditoriaOut)
async def crear_auditoria(payload: dict, db: AsyncSession = Depends(get_db), actor: Actor = Depends(require_actor)):
    proyecto = (payload.get("proyecto") or "").strip()
    tipo = (payload.get("tipo") or "").strip()
    if not proyecto or not tipo:
        raise HTTPException(status_code=422, detail="proyecto y tipo son obligatorios")
    if not await db.get(RegistroProyecto, proyecto):
        raise HTTPException(status_code=404, detail=f"El proyecto {proyecto} no existe")

    aud = RegistroAuditoria(
        proyecto_slug=proyecto, fecha=payload.get("fecha") or hoy_en_lima(),
        tipo=tipo, resumen=payload.get("resumen"), doc_path=payload.get("doc_path"),
    )
    db.add(aud)
    await db.commit()
    await db.refresh(aud)
    return AuditoriaOut(
        id=aud.id, proyecto=aud.proyecto_slug, fecha=aud.fecha,
        tipo=aud.tipo, resumen=aud.resumen, doc_path=aud.doc_path,
    )


@router.post("/auditorias/{auditoria_id}/hallazgos", status_code=201, response_model=HallazgoOut)
async def crear_hallazgo(
    auditoria_id: int, payload: dict, db: AsyncSession = Depends(get_db), actor: Actor = Depends(require_actor)
):
    if not await db.get(RegistroAuditoria, auditoria_id):
        raise HTTPException(status_code=404, detail=f"La auditoria {auditoria_id} no existe")
    severidad = (payload.get("severidad") or "").strip()
    titulo = (payload.get("titulo") or "").strip()
    if severidad not in SEVERIDADES:
        raise HTTPException(status_code=422, detail=f"severidad debe ser una de {', '.join(SEVERIDADES)}")
    if not titulo:
        raise HTTPException(status_code=422, detail="titulo es obligatorio")

    hallazgo = RegistroHallazgo(
        auditoria_id=auditoria_id,
        funcionalidad_id=payload.get("funcionalidad_id"),
        codigo=payload.get("codigo"),
        severidad=severidad,
        titulo=titulo,
        detalle=payload.get("detalle"),
        estado="abierto",
        ticket_ref=payload.get("ticket_ref"),
    )
    db.add(hallazgo)
    await db.commit()
    await db.refresh(hallazgo)
    return await _hallazgo_completo(db, hallazgo.id)
