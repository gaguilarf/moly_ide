"""Documentacion viva: temas, secciones anidadas, historial y audiencia.

Se muda del panel al Jetson (ADR-004, INF-50). El modelo de datos y la
clasificacion por audiencia son los de ADR-003 con la correccion de PAN-33, y se
conservan enteros: lo unico que cambia es la maquina.

LA PIEZA DE SEGURIDAD, que es la razon de ser de todo esto: la audiencia va por
SECCION, no por tema, y el filtro es una clausula WHERE en CADA lectura. No se
aplica al exportar, porque una etiqueta que solo se respeta al construir el
corpus deja de proteger en cuanto alguien reindexa con el volcado completo.
"""

from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from backend.app.database import get_db
from backend.app.security import Actor, require_actor

router = APIRouter(prefix="/documentacion", tags=["Documentacion viva"])

# Ordenadas de menos a mas restrictiva. El orden ES la escala.
AUDIENCIAS = ("publico_general", "administrativo", "ti")
TIPOS = ("servicio", "regla", "mejora", "runbook", "auditoria")
ESTADOS_TEMA = ("borrador", "publicado", "archivado")

# Al Jetson solo entra el equipo tecnico, asi que todo actor autenticado lee
# hasta el nivel maximo. La etiqueta no protege de quien ya esta dentro: existe
# para el dia que un RAG sirva esto fuera del equipo.
NIVEL_MAXIMO = "ti"

LIMA = timezone(timedelta(hours=-5))


def nivel(audiencia: str) -> int:
    return AUDIENCIAS.index(audiencia)


def resolver_nivel(solicitado: Optional[str]) -> str:
    """El maximo, o uno MAS BAJO si se pide. Subirlo no se permite nunca:
    entonces el parametro seria la llave y no el candado."""
    if not solicitado:
        return NIVEL_MAXIMO
    if solicitado not in AUDIENCIAS:
        raise HTTPException(status_code=422, detail=f"audiencia debe ser: {' | '.join(AUDIENCIAS)}")
    return solicitado if nivel(solicitado) < nivel(NIVEL_MAXIMO) else NIVEL_MAXIMO


def audiencias_visibles(n: str) -> List[str]:
    return list(AUDIENCIAS[: nivel(n) + 1])


def solo_publicados(n: str) -> bool:
    """Quien pide por debajo de TI solo ve temas publicados: un borrador es
    trabajo a medias, y servirlo fuera es servir algo que todavia no es verdad."""
    return nivel(n) < nivel("ti")


def mas_restrictiva(a: str, b: str) -> str:
    return a if nivel(a) >= nivel(b) else b


@router.get("/temas")
async def listar_temas(
    tipo: Optional[str] = None,
    proyecto: Optional[str] = None,
    estado: Optional[str] = None,
    q: Optional[str] = Query(None, description="busca en titulo, resumen y CUERPO de las secciones"),
    audiencia: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
):
    n = resolver_nivel(audiencia)
    visibles = audiencias_visibles(n)

    condiciones = ["1=1"]
    params: dict = {}
    if tipo:
        if tipo not in TIPOS:
            raise HTTPException(status_code=422, detail=f"tipo debe ser: {' | '.join(TIPOS)}")
        condiciones.append("t.tipo = :tipo")
        params["tipo"] = tipo
    if proyecto:
        condiciones.append("t.proyecto = :proyecto")
        params["proyecto"] = proyecto
    if estado:
        if estado not in ESTADOS_TEMA:
            raise HTTPException(status_code=422, detail=f"estado debe ser: {' | '.join(ESTADOS_TEMA)}")
        condiciones.append("t.estado = :estado")
        params["estado"] = estado
    if solo_publicados(n):
        condiciones.append("t.estado = 'publicado'")

    if q:
        # La busqueda entra tambien en el cuerpo, pero SOLO en las secciones que
        # el nivel alcanza: si no, el buscador seria la puerta de atras del
        # filtro. Es el fallo tipico —filtrar el listado y olvidar la busqueda—.
        condiciones.append(
            "(t.titulo ILIKE :q OR COALESCE(t.resumen,'') ILIKE :q OR EXISTS ("
            " SELECT 1 FROM doc_secciones s WHERE s.tema_id = t.id"
            "   AND s.estado = 'activa' AND s.cuerpo ILIKE :q"
            "   AND s.audiencia = ANY(:visibles)))"
        )
        params["q"] = f"%{q}%"

    params["visibles"] = visibles
    sql = text(
        f"""
        SELECT t.id, t.slug, t.titulo, t.tipo::text, t.resumen, t.responsable,
               t.proyecto, t.servicio_ref, t.estado::text, t.created_at, t.updated_at,
               (SELECT COUNT(*) FROM doc_secciones s
                 WHERE s.tema_id = t.id AND s.estado = 'activa'
                   AND s.audiencia = ANY(:visibles)) AS secciones_visibles
          FROM doc_temas t
         WHERE {' AND '.join(condiciones)}
         ORDER BY t.titulo
        """
    )
    filas = (await db.execute(sql, params)).all()
    return {
        "nivel": n,
        "temas": [
            {
                "id": f[0], "slug": f[1], "titulo": f[2], "tipo": f[3], "resumen": f[4],
                "responsable": f[5], "proyecto": f[6], "servicio_ref": f[7], "estado": f[8],
                "created_at": f[9], "updated_at": f[10], "secciones_visibles": f[11],
            }
            for f in filas
        ],
    }


@router.get("/temas/{slug}")
async def ver_tema(slug: str, audiencia: Optional[str] = None, db: AsyncSession = Depends(get_db)):
    n = resolver_nivel(audiencia)
    visibles = audiencias_visibles(n)

    tema = (
        await db.execute(
            text(
                """SELECT id, slug, titulo, tipo::text, resumen, responsable, proyecto,
                          servicio_ref, estado::text, created_at, updated_at
                     FROM doc_temas WHERE slug = :slug"""
            ),
            {"slug": slug},
        )
    ).first()
    if not tema or (solo_publicados(n) and tema[8] != "publicado"):
        raise HTTPException(status_code=404, detail=f"El tema {slug} no existe")

    filas = (
        await db.execute(
            text(
                """SELECT id, tema_id, padre_id, orden, titulo, cuerpo, audiencia::text,
                          indexable_ia, origen::text, estado::text, verificado_en,
                          verificado_por, vigencia_dias
                     FROM doc_secciones
                    WHERE tema_id = :id AND estado = 'activa'
                      AND audiencia = ANY(:visibles)
                    ORDER BY orden, id"""
            ),
            {"id": tema[0], "visibles": visibles},
        )
    ).all()

    hoy = datetime.now(LIMA).date()
    secciones = []
    for f in filas:
        verificado_en, vigencia = f[10], f[12]
        caducada = bool(verificado_en) and (hoy - verificado_en).days > vigencia
        secciones.append({
            "id": f[0], "tema_id": f[1], "padre_id": f[2], "orden": f[3], "titulo": f[4],
            "cuerpo": f[5], "audiencia": f[6], "indexable_ia": f[7], "origen": f[8],
            "estado": f[9], "verificado_en": verificado_en, "verificado_por": f[11],
            "vigencia_dias": vigencia,
            # La frescura que un .md no tiene: sin verificar, o caducada.
            "frescura": "sin_verificar" if not verificado_en else ("caducada" if caducada else "vigente"),
        })

    enlaces = (
        await db.execute(
            text(
                """SELECT e.id, e.tipo::text, e.destino_tema_id, d.slug, e.destino_ref, e.nota
                     FROM doc_enlaces e
                     LEFT JOIN doc_temas d ON d.id = e.destino_tema_id
                    WHERE e.tema_id = :id ORDER BY e.id"""
            ),
            {"id": tema[0]},
        )
    ).all()

    etiquetas = [
        r[0] for r in (await db.execute(
            text("SELECT etiqueta FROM doc_etiquetas WHERE tema_id = :id ORDER BY etiqueta"),
            {"id": tema[0]},
        )).all()
    ]

    return {
        "nivel": n,
        "tema": {
            "id": tema[0], "slug": tema[1], "titulo": tema[2], "tipo": tema[3], "resumen": tema[4],
            "responsable": tema[5], "proyecto": tema[6], "servicio_ref": tema[7], "estado": tema[8],
            "created_at": tema[9], "updated_at": tema[10],
        },
        "secciones": secciones,
        "enlaces": [
            {"id": e[0], "tipo": e[1], "destino_tema_id": e[2], "destino_slug": e[3],
             "destino_ref": e[4], "nota": e[5]}
            for e in enlaces
        ],
        "etiquetas": etiquetas,
    }


@router.get("/secciones/{seccion_id}/revisiones")
async def listar_revisiones(
    seccion_id: int, audiencia: Optional[str] = None, db: AsyncSession = Depends(get_db)
):
    n = resolver_nivel(audiencia)

    seccion = (
        await db.execute(
            text("SELECT id, audiencia::text FROM doc_secciones WHERE id = :id"),
            {"id": seccion_id},
        )
    ).first()
    if not seccion or nivel(seccion[1]) > nivel(n):
        raise HTTPException(status_code=404, detail=f"La seccion {seccion_id} no existe")

    filas = (
        await db.execute(
            text(
                """SELECT id, seccion_id, at, actor, accion::text, cuerpo_anterior,
                          audiencia_anterior::text, motivo, ticket_ref
                     FROM doc_revisiones WHERE seccion_id = :id
                    ORDER BY at DESC, id DESC"""
            ),
            {"id": seccion_id},
        )
    ).all()

    salida = []
    for f in filas:
        # Manda la MAS restrictiva entre la audiencia de entonces y la de ahora.
        # Si solo contara la de ahora, bastaria editar una seccion tecnica y
        # bajarla despues a publica para que su version con puertos y claves
        # saliera por el historial.
        exigida = mas_restrictiva(f[6], seccion[1]) if f[6] else seccion[1]
        visible = nivel(n) >= nivel(exigida)
        salida.append({
            "id": f[0], "seccion_id": f[1], "at": f[2], "actor": f[3], "accion": f[4],
            "cuerpo_anterior": f[5] if visible else None,
            "audiencia_anterior": f[6],
            # El motivo lleva el mismo candado que el cuerpo: es texto libre y en
            # una seccion tecnica dice cosas del estilo "rotamos la clave, era
            # abc123". Taparle el cuerpo y dejarle el motivo seria tapar la
            # puerta y dejar la ventana abierta.
            "motivo": f[7] if visible else None,
            "detalle_oculto": (not visible) and (f[5] is not None or f[7] is not None),
            "ticket_ref": f[8],
        })
    return {"nivel": n, "revisiones": salida}


@router.post("/temas", status_code=201)
async def crear_tema(payload: dict, db: AsyncSession = Depends(get_db), actor: Actor = Depends(require_actor)):
    slug = (payload.get("slug") or "").strip()
    titulo = (payload.get("titulo") or "").strip()
    tipo = payload.get("tipo") or "servicio"
    estado = payload.get("estado") or "borrador"
    if not slug or not titulo:
        raise HTTPException(status_code=422, detail="slug y titulo son obligatorios")
    if tipo not in TIPOS:
        raise HTTPException(status_code=422, detail=f"tipo debe ser: {' | '.join(TIPOS)}")
    if estado not in ESTADOS_TEMA:
        raise HTTPException(status_code=422, detail=f"estado debe ser: {' | '.join(ESTADOS_TEMA)}")
    # Un tema sin responsable no se publica: la documentacion huerfana es justo
    # la que se pudre.
    if estado == "publicado" and not (payload.get("responsable") or "").strip():
        raise HTTPException(status_code=422, detail="Un tema publicado necesita responsable.")

    existe = (await db.execute(text("SELECT 1 FROM doc_temas WHERE slug = :s"), {"s": slug})).first()
    if existe:
        raise HTTPException(status_code=409, detail=f"Ya existe un tema con el slug {slug}")

    # Se comprueba aqui para poder decir CUALES valen. Dejarlo a la clave ajena
    # devolvia un 500 con un ForeignKeyViolationError en el log, que no le dice
    # a quien llama ni que campo estaba mal ni que puede poner.
    proyecto = payload.get("proyecto")
    if proyecto:
        validos = [
            r[0] for r in (await db.execute(text("SELECT slug FROM registro_proyectos ORDER BY slug"))).all()
        ]
        if proyecto not in validos:
            raise HTTPException(
                status_code=422,
                detail=f"proyecto '{proyecto}' no existe; use uno de: {', '.join(validos)}",
            )

    fila = (
        await db.execute(
            text(
                """INSERT INTO doc_temas (slug, titulo, tipo, resumen, responsable, proyecto,
                                          servicio_ref, estado)
                   VALUES (:slug, :titulo, :tipo, :resumen, :responsable, :proyecto,
                           :servicio_ref, :estado)
                   RETURNING id"""
            ),
            {"slug": slug, "titulo": titulo, "tipo": tipo, "resumen": payload.get("resumen"),
             "responsable": payload.get("responsable"), "proyecto": payload.get("proyecto"),
             "servicio_ref": payload.get("servicio_ref"), "estado": estado},
        )
    ).first()
    await db.commit()
    return {"id": fila[0], "slug": slug}


@router.patch("/temas/{slug}")
async def actualizar_tema(
    slug: str, payload: dict, db: AsyncSession = Depends(get_db), actor: Actor = Depends(require_actor)
):
    """Edita metadata del tema (titulo/tipo/estado/resumen/responsable/proyecto/
    servicio_ref) y deja rastro en doc_revisiones vía tema_id — antes de la
    migración 0001 este endpoint no existía y esos cambios no dejaban historial."""
    actual = (
        await db.execute(
            text(
                """SELECT id, titulo, tipo::text, estado::text, resumen, responsable,
                          proyecto, servicio_ref
                     FROM doc_temas WHERE slug = :slug"""
            ),
            {"slug": slug},
        )
    ).first()
    if not actual:
        raise HTTPException(status_code=404, detail=f"El tema {slug} no existe")

    nuevo_tipo = payload.get("tipo", actual[2])
    if nuevo_tipo not in TIPOS:
        raise HTTPException(status_code=422, detail=f"tipo debe ser: {' | '.join(TIPOS)}")
    nuevo_estado = payload.get("estado", actual[3])
    if nuevo_estado not in ESTADOS_TEMA:
        raise HTTPException(status_code=422, detail=f"estado debe ser: {' | '.join(ESTADOS_TEMA)}")
    nuevo_responsable = payload.get("responsable", actual[5])
    if nuevo_estado == "publicado" and not (nuevo_responsable or "").strip():
        raise HTTPException(status_code=422, detail="Un tema publicado necesita responsable.")

    nuevo_proyecto = payload.get("proyecto", actual[6])
    if nuevo_proyecto and nuevo_proyecto != actual[6]:
        validos = [
            r[0] for r in (await db.execute(text("SELECT slug FROM registro_proyectos ORDER BY slug"))).all()
        ]
        if nuevo_proyecto not in validos:
            raise HTTPException(
                status_code=422,
                detail=f"proyecto '{nuevo_proyecto}' no existe; use uno de: {', '.join(validos)}",
            )

    await db.execute(
        text(
            """UPDATE doc_temas
                  SET titulo = :titulo, tipo = :tipo, estado = :estado, resumen = :resumen,
                      responsable = :responsable, proyecto = :proyecto,
                      servicio_ref = :servicio_ref, updated_at = CURRENT_TIMESTAMP
                WHERE id = :id"""
        ),
        {
            "titulo": payload.get("titulo", actual[1]), "tipo": nuevo_tipo, "estado": nuevo_estado,
            "resumen": payload.get("resumen", actual[4]), "responsable": nuevo_responsable,
            "proyecto": nuevo_proyecto, "servicio_ref": payload.get("servicio_ref", actual[7]),
            "id": actual[0],
        },
    )
    accion = "reclasificada" if nuevo_tipo != actual[2] or nuevo_estado != actual[3] else "editada"
    await db.execute(
        text(
            """INSERT INTO doc_revisiones (tema_id, actor, accion, motivo, ticket_ref)
               VALUES (:tema, :actor, :accion, :motivo, :ticket)"""
        ),
        {"tema": actual[0], "actor": actor.nombre, "accion": accion,
         "motivo": payload.get("motivo"), "ticket": payload.get("ticket_ref")},
    )
    await db.commit()
    return {"id": actual[0], "slug": slug, "accion": accion}


@router.post("/temas/{slug}/secciones", status_code=201)
async def crear_seccion(
    slug: str, payload: dict, db: AsyncSession = Depends(get_db), actor: Actor = Depends(require_actor)
):
    tema = (await db.execute(text("SELECT id FROM doc_temas WHERE slug = :s"), {"s": slug})).first()
    if not tema:
        raise HTTPException(status_code=404, detail=f"El tema {slug} no existe")

    titulo = (payload.get("titulo") or "").strip()
    cuerpo = (payload.get("cuerpo") or "").strip()
    audiencia = payload.get("audiencia") or "ti"
    if not titulo or not cuerpo:
        raise HTTPException(status_code=422, detail="titulo y cuerpo son obligatorios")
    if audiencia not in AUDIENCIAS:
        raise HTTPException(status_code=422, detail=f"audiencia debe ser: {' | '.join(AUDIENCIAS)}")

    fila = (
        await db.execute(
            text(
                """INSERT INTO doc_secciones (tema_id, padre_id, orden, titulo, cuerpo,
                                              audiencia, origen, vigencia_dias)
                   VALUES (:tema, :padre, :orden, :titulo, :cuerpo, :audiencia, :origen, :vig)
                   RETURNING id"""
            ),
            {"tema": tema[0], "padre": payload.get("padre_id"), "orden": payload.get("orden", 0),
             "titulo": titulo, "cuerpo": cuerpo, "audiencia": audiencia,
             "origen": payload.get("origen", "manual"), "vig": payload.get("vigencia_dias", 180)},
        )
    ).first()
    # Toda escritura deja revision, tambien el alta: si no, la primera version de
    # una seccion no tendria autor.
    await db.execute(
        text(
            """INSERT INTO doc_revisiones (seccion_id, actor, accion, audiencia_anterior,
                                           motivo, ticket_ref)
               VALUES (:sec, :actor, 'creada', :aud, :motivo, :ticket)"""
        ),
        {"sec": fila[0], "actor": actor.nombre, "aud": audiencia,
         "motivo": payload.get("motivo"), "ticket": payload.get("ticket_ref")},
    )
    await db.commit()
    return {"id": fila[0]}


@router.patch("/secciones/{seccion_id}")
async def actualizar_seccion(
    seccion_id: int, payload: dict, db: AsyncSession = Depends(get_db), actor: Actor = Depends(require_actor)
):
    actual = (
        await db.execute(
            text("SELECT id, cuerpo, audiencia::text FROM doc_secciones WHERE id = :id"),
            {"id": seccion_id},
        )
    ).first()
    if not actual:
        raise HTTPException(status_code=404, detail=f"La seccion {seccion_id} no existe")

    nueva_audiencia = payload.get("audiencia", actual[2])
    if nueva_audiencia not in AUDIENCIAS:
        raise HTTPException(status_code=422, detail=f"audiencia debe ser: {' | '.join(AUDIENCIAS)}")
    nuevo_cuerpo = payload.get("cuerpo", actual[1])
    verificar = bool(payload.get("verificar"))

    accion = "verificada" if verificar else ("reclasificada" if nueva_audiencia != actual[2] else "editada")

    await db.execute(
        text(
            """UPDATE doc_secciones
                  SET cuerpo = :cuerpo, audiencia = :aud,
                      titulo = COALESCE(:titulo, titulo),
                      verificado_en = CASE WHEN :verificar THEN CURRENT_DATE ELSE verificado_en END,
                      verificado_por = CASE WHEN :verificar THEN :actor ELSE verificado_por END,
                      updated_at = CURRENT_TIMESTAMP
                WHERE id = :id"""
        ),
        {"cuerpo": nuevo_cuerpo, "aud": nueva_audiencia, "titulo": payload.get("titulo"),
         "verificar": verificar, "actor": actor.nombre, "id": seccion_id},
    )
    await db.execute(
        text(
            """INSERT INTO doc_revisiones (seccion_id, actor, accion, cuerpo_anterior,
                                           audiencia_anterior, motivo, ticket_ref)
               VALUES (:sec, :actor, :accion, :cuerpo, :aud, :motivo, :ticket)"""
        ),
        # Se guarda la audiencia de ANTES en toda edicion, no solo al
        # reclasificar: es lo que permite servir el historial con el candado
        # correcto.
        {"sec": seccion_id, "actor": actor.nombre, "accion": accion,
         "cuerpo": actual[1], "aud": actual[2],
         "motivo": payload.get("motivo"), "ticket": payload.get("ticket_ref")},
    )
    await db.commit()
    return {"id": seccion_id, "accion": accion}
