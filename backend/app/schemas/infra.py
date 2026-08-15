from pydantic import BaseModel
from typing import List, Optional, Dict, Any
from datetime import datetime


class PortInfo(BaseModel):
    port: int
    addresses: List[str]
    process: Optional[str] = None
    is_exposed: bool
    service_name: Optional[str] = None
    environment: Optional[str] = None
    category: Optional[str] = None


class ServerInfrastructureStatus(BaseModel):
    server_name: str
    server_host: str
    is_reachable: bool
    checked_at: datetime
    ports: List[PortInfo]
    systemd_units_summary: Optional[Dict[str, str]] = None
    resource_usage: Optional[Dict[str, Any]] = None


class BackupFileInfo(BaseModel):
    filename: str
    size_bytes: int
    modified_at: datetime


class DatabaseBackupStatus(BaseModel):
    database: str
    latest_backup: Optional[BackupFileInfo] = None
    total_dumps: int
    is_healthy: bool  # Menos de 26 horas de antigüedad


class BackupsOverview(BaseModel):
    server_name: str
    is_running: bool
    schedule: Optional[str] = None
    databases: List[DatabaseBackupStatus]
    recent_logs: List[str]


class FileItem(BaseModel):
    name: str
    path: str
    is_dir: bool
    size: Optional[int] = None
    modified_at: Optional[str] = None


class DocItem(BaseModel):
    title: str
    path: str
    category: str
    content_snippet: Optional[str] = None
