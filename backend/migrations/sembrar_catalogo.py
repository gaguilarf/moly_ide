"""INF-51 — Siembra del catalogo de servicios.

Se ejecuta EN LA JETSON con el python del venv.

El puerto y la unit NO se escriben a mano: se contrastan contra lo que la
maquina esta sirviendo de verdad (`ss -tlnp` y `systemctl`), y las filas que no
cuadran se avisan en vez de darse por buenas. Lo escrito a mano caduca en
silencio; esto no.

El resto —proposito, stack, repo, responsable— si es conocimiento humano y va
escrito, pero con `verificado_en` en blanco: sellar como verificado lo que solo
se ha copiado convierte el mecanismo de frescura en decoracion.
"""

import asyncio
import sys

# slug, nombre, categoria, entorno, proposito, stack, repo, host, unit, puerto
SERVICIOS = [
    ("greenter-prod", "Greenter — Facturación SUNAT (prod)", "aplicacion", "produccion",
     "Microservicio que firma y envía los comprobantes electrónicos a SUNAT. Solo escucha en localhost: nadie de fuera del VPS le habla.",
     "PHP", "vive dentro de sga_brittany_back", "vps-brittany", "greenter-prod.service", 8000),
    ("greenter-dev", "Greenter — Facturación SUNAT (dev)", "aplicacion", "desarrollo",
     "El mismo microservicio contra el entorno de pruebas de SUNAT.",
     "PHP", "vive dentro de sga_brittany_back", "vps-brittany", "greenter-dev.service", 8001),
    ("sga-back-prod", "SGA — API (prod)", "aplicacion", "produccion",
     "API de gestión académica y facturación del SGA.",
     "NestJS 11 + TypeORM", "sga_brittany_back", "vps-brittany", "sga-back-prod.service", 3000),
    ("sga-back-dev", "SGA — API (dev)", "aplicacion", "desarrollo",
     "Entorno de desarrollo del SGA. Su base es copia de la real, así que el correo sale redirigido.",
     "NestJS 11 + TypeORM", "sga_brittany_back", "vps-brittany", "sga-back-dev.service", 3001),
    ("panel", "Panel de administración", "aplicacion", "produccion",
     "Panel con el que se opera el negocio: SGA, tIAcher, infraestructura, backups y logs. Desde ADR-004 ya no lleva tickets, registro ni documentación.",
     "Next.js 16 + MySQL", "panel_brittanygroup", "vps-brittany", "panel-brittanygroup.service", 3002),
    ("academico-back-prod", "Portal Académico — API (prod)", "aplicacion", "produccion",
     "API del portal de alumnos y profesores. El SGA es autoritativo y se consulta por API.",
     "NestJS", "academico_brittanygroup_back", "vps-brittany", "academico-back-prod.service", 3003),
    ("academico-back-dev", "Portal Académico — API (dev)", "aplicacion", "desarrollo",
     "Entorno de desarrollo del Portal Académico.",
     "NestJS", "academico_brittanygroup_back", "vps-brittany", "academico-back-dev.service", 3004),
    ("tiacher-back-prod", "tIAcher — API (prod)", "aplicacion", "produccion",
     "API de aprendizaje de inglés con IA.",
     "Django 5.2 LTS + DRF", "tiacherback", "vps-brittany", "tiacher-back-prod.service", 8080),
    ("tiacher-back-dev", "tIAcher — API (dev)", "aplicacion", "desarrollo",
     "Entorno de desarrollo de tIAcher.",
     "Django 5.2 LTS + DRF", "tiacherback", "vps-brittany", "tiacher-back-dev.service", 8081),
    ("mysql", "MySQL 8.0", "datos", "compartido",
     "Base de datos de todo el ecosistema en el VPS. Zona horaria fijada a America/Lima.",
     "MySQL 8.0", None, "vps-brittany", "mysql.service", 3306),
    ("redis-sga-prod", "Redis — SGA (prod)", "datos", "produccion",
     "Cola de BullMQ del SGA. maxmemory-policy en noeviction: con *-lru se perderían jobs.",
     "Redis", None, "vps-brittany", "redis-server.service", 6379),
    ("redis-tiacher-prod", "Redis — tIAcher (prod)", "datos", "produccion",
     "Broker de Celery de tIAcher. maxmemory-policy en noeviction.",
     "Redis", None, "vps-brittany", "redis-server@tiacher-prod.service", 6380),
    ("redis-sga-dev", "Redis — SGA (dev)", "datos", "desarrollo",
     "Instancia dedicada de desarrollo del SGA.",
     "Redis", None, "vps-brittany", "redis-server@sga-dev.service", 6381),
    ("redis-tiacher-dev", "Redis — tIAcher (dev)", "datos", "desarrollo",
     "Instancia dedicada de desarrollo de tIAcher.",
     "Redis", None, "vps-brittany", "redis-server@tiacher-dev.service", 6382),
    ("nginx", "Nginx", "sistema", "compartido",
     "Proxy inverso y TLS delante de todas las aplicaciones del VPS.",
     "Nginx", None, "vps-brittany", "nginx.service", 443),
    ("crowdsec", "CrowdSec", "seguridad", "compartido",
     "Único baneador del VPS desde 2026-08-11; fail2ban se quedó sin jails. Incluye el WAF delante de las APIs.",
     "CrowdSec", None, "vps-brittany", "crowdsec.service", 8090),
    ("grafana", "Grafana", "observabilidad", "compartido",
     "Tableros y alertas; las alertas salen a WhatsApp y no dependen del Jetson por diseño.",
     "Grafana", None, "vps-brittany", "grafana-server.service", 3300),
    ("prometheus", "Prometheus", "observabilidad", "compartido",
     "Métricas del VPS.", "Prometheus", None, "vps-brittany", "prometheus.service", 9090),
    ("loki", "Loki", "observabilidad", "compartido",
     "Registros centralizados.", "Loki", None, "vps-brittany", "loki.service", 3100),
    ("tempo", "Tempo", "observabilidad", "compartido",
     "Trazas.", "Tempo", None, "vps-brittany", "tempo.service", 3200),
    ("moly-orchestrator", "Moly — Orquestador (Jetson)", "aplicacion", "produccion",
     "Fuente de verdad del ciclo de desarrollo desde ADR-004: tickets, registro histórico y documentación viva, más el motor de agentes Claude.",
     "FastAPI + SQLAlchemy async", "moly_ide", "jetson", "moly-orchestrator.service", 8000),
    ("postgres-jetson", "PostgreSQL 17 (Jetson)", "datos", "produccion",
     "Base moly_orchestrator, en contenedor Docker. Volcado diario a las 04:00 y copia al PC de trabajo a las 19:00.",
     "PostgreSQL 17 (pgvector)", None, "jetson", None, 5432),
    ("caddy-jetson", "Caddy (Jetson)", "sistema", "compartido",
     "Proxy con TLS en el Jetson, hoy limitado a la LAN y a la tailnet.",
     "Caddy", None, "jetson", None, 443),
]

# origen -> destino, tipo, nota
DEPENDENCIAS = [
    ("sga-back-prod", "greenter-prod", "dura", "Sin Greenter no se emiten comprobantes a SUNAT."),
    ("sga-back-dev", "greenter-dev", "dura", None),
    ("sga-back-prod", "redis-sga-prod", "dura", "Colas de BullMQ."),
    ("sga-back-dev", "redis-sga-dev", "dura", None),
    ("sga-back-prod", "mysql", "dura", None),
    ("sga-back-dev", "mysql", "dura", None),
    ("tiacher-back-prod", "redis-tiacher-prod", "dura", "Broker de Celery."),
    ("tiacher-back-dev", "redis-tiacher-dev", "dura", None),
    ("tiacher-back-prod", "mysql", "dura", None),
    ("academico-back-prod", "mysql", "dura", None),
    ("academico-back-prod", "sga-back-prod", "dura", "El SGA es autoritativo; el portal lo consulta por API."),
    ("panel", "mysql", "dura", None),
    ("panel", "sga-back-prod", "blanda", "Solo para las pantallas de negocio; si no responde, esa sección avisa."),
    ("panel", "tiacher-back-prod", "blanda", None),
    ("moly-orchestrator", "postgres-jetson", "dura", None),
    ("grafana", "prometheus", "dura", None),
    ("grafana", "loki", "blanda", None),
    ("grafana", "tempo", "blanda", None),
    ("nginx", "sga-back-prod", "blanda", "Nginx es la puerta; el backend caído da 502."),
]


async def main():
    import asyncpg

    conn = await asyncpg.connect(sys.argv[1])
    try:
        async with conn.transaction():
            for (slug, nombre, cat, ent, prop, stack, repo, host, unit, puerto) in SERVICIOS:
                await conn.execute(
                    """
                    INSERT INTO servicios (slug, nombre, categoria, entorno, proposito,
                                           stack, repo, host, unit, puerto, origen)
                    VALUES ($1,$2,$3::servicio_categoria,$4::servicio_entorno,$5,$6,$7,$8,$9,$10,'manual')
                    ON CONFLICT (slug) DO UPDATE SET
                        nombre = EXCLUDED.nombre, categoria = EXCLUDED.categoria,
                        entorno = EXCLUDED.entorno, proposito = EXCLUDED.proposito,
                        stack = EXCLUDED.stack, repo = EXCLUDED.repo, host = EXCLUDED.host,
                        unit = EXCLUDED.unit, puerto = EXCLUDED.puerto,
                        updated_at = CURRENT_TIMESTAMP
                    """,
                    slug, nombre, cat, ent, prop, stack, repo, host, unit, puerto,
                )
            print(f"servicios: {len(SERVICIOS)}")

            for origen, destino, tipo, nota in DEPENDENCIAS:
                await conn.execute(
                    """
                    INSERT INTO servicio_dependencias (servicio_id, depende_de_id, tipo, nota)
                    SELECT a.id, b.id, $3, $4 FROM servicios a, servicios b
                     WHERE a.slug = $1 AND b.slug = $2
                    ON CONFLICT (servicio_id, depende_de_id) DO UPDATE
                        SET tipo = EXCLUDED.tipo, nota = EXCLUDED.nota
                    """,
                    origen, destino, tipo, nota,
                )
            print(f"dependencias: {len(DEPENDENCIAS)}")
    finally:
        await conn.close()


asyncio.run(main())
