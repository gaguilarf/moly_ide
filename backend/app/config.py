import os
import sys
from pydantic_settings import BaseSettings
from pydantic import ValidationError
from typing import List


class Settings(BaseSettings):
    APP_NAME: str = "Ragnar Group API"
    APP_VERSION: str = "1.0.0"
    API_V1_STR: str = "/api/v1"

    # Sin valor por defecto a propósito: los tres son credenciales. Si falta
    # alguna, el servicio no arranca. Un valor por defecto en el repositorio es
    # el que acaba corriendo en producción sin que nadie se entere.
    DATABASE_URL: str
    API_AUTH_TOKEN: str  # clave con la que se firman los JWT de la app móvil
    AGENT_API_TOKEN: str  # token de servicio de los agentes (+ cabecera X-Agent-Name)

    # Orígenes permitidos por CORS, separados por comas. Vacío = ninguno, que es
    # lo correcto aquí: la app de Flutter es nativa y no pasa por CORS. Solo
    # hace falta rellenarlo si algún día se sirve una web contra esta API.
    CORS_ORIGINS: str = ""

    # SSH Configurations for remote servers
    VPS_BRITTANY_HOST: str = os.getenv("VPS_BRITTANY_HOST", "144.91.113.27")
    VPS_BRITTANY_USER: str = os.getenv("VPS_BRITTANY_USER", "root")
    VPS_BRITTANY_KEY_PATH: str = os.getenv(
        "VPS_BRITTANY_KEY_PATH", "/home/jetson/.ssh/id_ed25519_claude_deploy"
    )

    VPS_PERSONAL_HOST: str = os.getenv("VPS_PERSONAL_HOST", "62.169.29.115")
    VPS_PERSONAL_USER: str = os.getenv("VPS_PERSONAL_USER", "root")
    VPS_PERSONAL_KEY_PATH: str = os.getenv(
        "VPS_PERSONAL_KEY_PATH", "/home/jetson/.ssh/id_ed25519_claude_deploy"
    )

    # Documentation Workspace directory on Jetson
    DOCS_DIR: str = os.getenv("DOCS_DIR", "/home/jetson/docs_brittanygroup")
    REPOS_BASE_DIR: str = os.getenv("REPOS_BASE_DIR", "/home/jetson/workspace")

    # Directorios del VPS que el explorador puede leer, separados por comas.
    # Es una lista CERRADA porque el comando corre como root en produccion:
    # comprobar solo la extension del fichero dejaba servir el .env del SGA, el
    # del panel, la config de MySQL o la de Redis a cualquiera autenticado.
    EXPLORADOR_RAICES: str = os.getenv(
        "EXPLORADOR_RAICES",
        "/root/sga_brittany_back,/root/tiacherback,/root/academico_brittanygroup_back,/panel_brittanygroup",
    )

    # Claude CLI paths
    CLAUDE_CLI_PATH: str = os.getenv("CLAUDE_CLI_PATH", "claude")

    # Fichero de huellas para verificar al servidor SSH. Con None se aceptaba
    # cualquiera que respondiera en esa IP, y por esa conexion va una sesion
    # root del VPS de produccion.
    SSH_KNOWN_HOSTS: str = os.getenv("SSH_KNOWN_HOSTS", "/home/jetson/.ssh/known_hosts")

    @property
    def cors_origins(self) -> List[str]:
        return [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]

    @property
    def explorador_raices(self) -> List[str]:
        return [r.strip() for r in self.EXPLORADOR_RAICES.split(",") if r.strip()]

    class Config:
        env_file = ".env"
        case_sensitive = True
        extra = "ignore"


try:
    settings = Settings()
except ValidationError as e:
    faltan = ", ".join(str(error["loc"][0]) for error in e.errors())
    print(
        f"[moly] No arranco: faltan variables obligatorias en el entorno o en .env -> {faltan}",
        file=sys.stderr,
    )
    raise SystemExit(1)
