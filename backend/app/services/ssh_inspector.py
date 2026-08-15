import asyncssh
import asyncio
import logging
import posixpath
import shlex
from typing import List, Dict, Optional, Any
from datetime import datetime, timezone
from backend.app.schemas.infra import PortInfo, ServerInfrastructureStatus, BackupFileInfo, DatabaseBackupStatus, BackupsOverview, FileItem
from backend.app.config import settings

logger = logging.getLogger("ssh_inspector")

# Catálogo conocido de servicios
CATALOGO_PUERTOS = {
    3000: {"name": "SGA API (Prod)", "env": "prod", "category": "aplicacion"},
    3001: {"name": "SGA API (Dev)", "env": "dev", "category": "aplicacion"},
    3002: {"name": "Panel Brittany Group", "env": "prod", "category": "aplicacion"},
    3003: {"name": "Portal Académico API (Prod)", "env": "prod", "category": "aplicacion"},
    3004: {"name": "Portal Académico API (Dev)", "env": "dev", "category": "aplicacion"},
    8000: {"name": "Greenter Facturación (Prod)", "env": "prod", "category": "aplicacion"},
    8001: {"name": "Greenter Facturación (Dev)", "env": "dev", "category": "aplicacion"},
    8080: {"name": "tIAcher API (Prod)", "env": "prod", "category": "aplicacion"},
    8081: {"name": "tIAcher API (Dev)", "env": "dev", "category": "aplicacion"},
    3306: {"name": "MySQL 8.0", "env": "compartido", "category": "datos"},
    5432: {"name": "PostgreSQL (Jetson)", "env": "compartido", "category": "datos"},
    6379: {"name": "Redis — SGA Prod", "env": "prod", "category": "datos"},
    6380: {"name": "Redis — tIAcher Prod", "env": "prod", "category": "datos"},
    6381: {"name": "Redis — SGA Dev", "env": "dev", "category": "datos"},
    6382: {"name": "Redis — tIAcher Dev", "env": "dev", "category": "datos"},
    3300: {"name": "Grafana", "env": "compartido", "category": "observabilidad"},
    3100: {"name": "Loki", "env": "compartido", "category": "observabilidad"},
    3200: {"name": "Tempo", "env": "compartido", "category": "observabilidad"},
    9090: {"name": "Prometheus", "env": "compartido", "category": "observabilidad"},
    8090: {"name": "CrowdSec API", "env": "compartido", "category": "seguridad"},
    22: {"name": "SSH", "env": "compartido", "category": "sistema"},
    80: {"name": "Nginx HTTP", "env": "compartido", "category": "sistema"},
    443: {"name": "Nginx HTTPS", "env": "compartido", "category": "sistema"},
}


class SSHInspectorService:
    async def _execute_remote_command(self, host: str, user: str, key_path: str, command: str) -> Optional[str]:
        try:
            # known_hosts=None aceptaba CUALQUIER servidor que respondiera en esa
            # IP: quien se metiera en medio recibia una sesion root del VPS de
            # produccion y, de paso, el contenido de los .env que se pidan. Se
            # verifica contra el known_hosts del usuario, que es donde quedo la
            # huella al copiar la clave.
            async with asyncssh.connect(
                host,
                username=user,
                client_keys=[key_path],
                known_hosts=settings.SSH_KNOWN_HOSTS,
            ) as conn:
                result = await conn.run(command, check=False)
                return result.stdout
        except Exception as e:
            logger.error(f"Error SSH en {user}@{host}: {e}")
            return None

    def _parse_ss_output(self, stdout: str) -> List[PortInfo]:
        ports: Dict[int, PortInfo] = {}
        for line in stdout.splitlines():
            if not line.startswith("LISTEN"):
                continue
            parts = line.split()
            if len(parts) < 4:
                continue
            local_addr = parts[3]
            corte = local_addr.rfind(":")
            if corte < 0:
                continue
            try:
                port_num = int(local_addr[corte + 1 :])
                ip_addr = local_addr[:corte]
            except ValueError:
                continue

            is_exposed = ip_addr in ["0.0.0.0", "*", "[::]", "::"]
            cat_info = CATALOGO_PUERTOS.get(port_num, {})

            if port_num in ports:
                ports[port_num].addresses.append(ip_addr)
                ports[port_num].is_exposed = ports[port_num].is_exposed or is_exposed
            else:
                ports[port_num] = PortInfo(
                    port=port_num,
                    addresses=[ip_addr],
                    is_exposed=is_exposed,
                    service_name=cat_info.get("name"),
                    environment=cat_info.get("env"),
                    category=cat_info.get("category"),
                )

        return sorted(list(ports.values()), key=lambda p: p.port)

    async def get_server_status(self, target: str = "vps-brittany") -> ServerInfrastructureStatus:
        if target == "vps-brittany":
            host = settings.VPS_BRITTANY_HOST
            user = settings.VPS_BRITTANY_USER
            key = settings.VPS_BRITTANY_KEY_PATH
            name = "VPS Brittany Group (Producción)"
        elif target == "vps-personal":
            host = settings.VPS_PERSONAL_HOST
            user = settings.VPS_PERSONAL_USER
            key = settings.VPS_PERSONAL_KEY_PATH
            name = "VPS Personal (Bots & Servicios)"
        else:
            host = "localhost"
            name = "Jetson Orin Nano (Orquestador)"
            # Ejecución local en el Jetson
            proc = await asyncio.create_subprocess_exec("ss", "-tlnp", stdout=asyncio.subprocess.PIPE)
            stdout, _ = await proc.communicate()
            ports = self._parse_ss_output(stdout.decode())
            return ServerInfrastructureStatus(
                server_name=name,
                server_host="192.168.0.109",
                is_reachable=True,
                checked_at=datetime.now(timezone.utc),
                ports=ports,
            )

        stdout = await self._execute_remote_command(host, user, key, "ss -tlnp")
        if stdout is None:
            return ServerInfrastructureStatus(
                server_name=name,
                server_host=host,
                is_reachable=False,
                checked_at=datetime.now(timezone.utc),
                ports=[],
            )

        ports = self._parse_ss_output(stdout)
        return ServerInfrastructureStatus(
            server_name=name,
            server_host=host,
            is_reachable=True,
            checked_at=datetime.now(timezone.utc),
            ports=ports,
        )

    async def get_backups_status(self) -> BackupsOverview:
        """Obtiene el estado de backups de MySQL en el VPS Brittany."""
        cmd = """
        find /opt/backups/mysql/daily -type f -name '*.sql.gz' -printf '%P\t%s\t%T@\n' 2>/dev/null | sort -k3 -nr
        """
        stdout = await self._execute_remote_command(
            settings.VPS_BRITTANY_HOST,
            settings.VPS_BRITTANY_USER,
            settings.VPS_BRITTANY_KEY_PATH,
            cmd,
        )
        databases: Dict[str, DatabaseBackupStatus] = {}

        if stdout:
            now_ts = datetime.now(timezone.utc).timestamp()
            for line in stdout.strip().splitlines():
                parts = line.split("\t")
                if len(parts) != 3:
                    continue
                rel_path, size_str, mtime_str = parts[0], parts[1], parts[2]
                db_name = rel_path.split("/")[0] if "/" in rel_path else "general"
                mtime_float = float(mtime_str)
                mtime_dt = datetime.fromtimestamp(mtime_float, timezone.utc)
                size_bytes = int(size_str)

                is_fresh = (now_ts - mtime_float) < (26 * 3600)

                if db_name not in databases:
                    databases[db_name] = DatabaseBackupStatus(
                        database=db_name,
                        latest_backup=BackupFileInfo(
                            filename=rel_path,
                            size_bytes=size_bytes,
                            modified_at=mtime_dt,
                        ),
                        total_dumps=1,
                        is_healthy=is_fresh,
                    )
                else:
                    databases[db_name].total_dumps += 1

        return BackupsOverview(
            server_name="VPS Brittany Group",
            is_running=False,
            databases=list(databases.values()),
            recent_logs=["Verificación de retención GFS completada."],
        )

    async def list_remote_directory(self, remote_path: str = "/root") -> List[FileItem]:
        """Explorador de directorios en modo solo lectura."""
        # shlex.quote y no comillas a mano: una comilla dentro de la ruta
        # cerraba la cadena y el resto corria como root en el VPS.
        cmd = f"ls -la --time-style=+'%Y-%m-%d %H:%M:%S' {shlex.quote(remote_path)}"
        stdout = await self._execute_remote_command(
            settings.VPS_BRITTANY_HOST,
            settings.VPS_BRITTANY_USER,
            settings.VPS_BRITTANY_KEY_PATH,
            cmd,
        )
        files = []
        if not stdout:
            return files

        for line in stdout.splitlines()[1:]:
            parts = line.split(maxsplit=7)
            if len(parts) < 8:
                continue
            perms, size_str, date_str, time_str, name = (
                parts[0],
                parts[4],
                parts[5],
                parts[6],
                parts[7],
            )
            if name in [".", ".."]:
                continue
            is_dir = perms.startswith("d")
            files.append(
                FileItem(
                    name=name,
                    path=f"{remote_path.rstrip('/')}/{name}",
                    is_dir=is_dir,
                    size=int(size_str) if not is_dir else None,
                    modified_at=f"{date_str} {time_str}",
                )
            )
        return files

    async def read_env_file_safe(self, file_path: str) -> Optional[str]:
        """Lee un fichero de configuración del VPS, en solo lectura.

        Comprobar la EXTENSION no protege de nada: el comando corre como root en
        el VPS de produccion, asi que cualquier ruta acabada en .env o .conf
        servia las credenciales del SGA, de tIAcher, del panel, de MySQL o de
        Redis a cualquiera que estuviera autenticado. Lo que decide es el
        DIRECTORIO, y por eso hay una lista cerrada.
        """
        if not file_path.endswith((".env", ".env.local", ".env.example", ".env.production", ".cnf", ".conf", ".yaml", ".yml", ".json")):
            raise ValueError("Solo se permite la lectura de archivos de configuración y entorno.")

        # normpath resuelve los .. ANTES de comparar; si se comparara la ruta
        # cruda, "/root/sga_brittany_back/../../etc/shadow.conf" pasaria.
        ruta = posixpath.normpath(file_path)
        if not any(ruta == raiz or ruta.startswith(raiz.rstrip("/") + "/")
                   for raiz in settings.explorador_raices):
            raise ValueError(
                "Ruta fuera de los directorios permitidos para el explorador."
            )

        cmd = f"cat {shlex.quote(file_path)}"
        return await self._execute_remote_command(
            settings.VPS_BRITTANY_HOST,
            settings.VPS_BRITTANY_USER,
            settings.VPS_BRITTANY_KEY_PATH,
            cmd,
        )


ssh_inspector = SSHInspectorService()
