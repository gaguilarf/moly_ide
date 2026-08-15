from sqlalchemy import Column, Integer, String, Text, Date, ForeignKey
from sqlalchemy.orm import relationship
from backend.app.database import Base


class RegistroProyecto(Base):
    __tablename__ = "registro_proyectos"

    slug = Column(String(30), primary_key=True)
    nombre = Column(String(100), nullable=False)
    ticket_key = Column(String(6), unique=True, nullable=True)
    repo_path = Column(String(200), nullable=True)

    funcionalidades = relationship("RegistroFuncionalidad", back_populates="proyecto")
    auditorias = relationship("RegistroAuditoria", back_populates="proyecto")


class RegistroFuncionalidad(Base):
    __tablename__ = "registro_funcionalidades"

    id = Column(Integer, primary_key=True, index=True)
    proyecto_slug = Column("proyecto", String(30), ForeignKey("registro_proyectos.slug", ondelete="CASCADE"), nullable=False)
    nombre = Column(String(150), nullable=False)
    descripcion = Column(Text, nullable=True)
    doc_path = Column(String(255), nullable=True)
    estado = Column(String(30), default="activa", nullable=False)
    creado_en = Column(Date, nullable=False)

    proyecto = relationship("RegistroProyecto", back_populates="funcionalidades")
    cambios = relationship("RegistroCambio", back_populates="funcionalidad")


class RegistroCambio(Base):
    __tablename__ = "registro_cambios"

    id = Column(Integer, primary_key=True, index=True)
    funcionalidad_id = Column(Integer, ForeignKey("registro_funcionalidades.id", ondelete="CASCADE"), nullable=False)
    fecha = Column(Date, nullable=False)
    tipo = Column(String(30), nullable=False)
    descripcion = Column(Text, nullable=False)
    commit_ref = Column(String(64), nullable=True)
    ticket_ref = Column(String(16), nullable=True)

    funcionalidad = relationship("RegistroFuncionalidad", back_populates="cambios")


class RegistroAuditoria(Base):
    __tablename__ = "registro_auditorias"

    id = Column(Integer, primary_key=True, index=True)
    proyecto_slug = Column("proyecto", String(30), ForeignKey("registro_proyectos.slug", ondelete="CASCADE"), nullable=False)
    fecha = Column(Date, nullable=False)
    tipo = Column(String(80), nullable=False)
    resumen = Column(Text, nullable=True)
    doc_path = Column(String(255), nullable=True)

    proyecto = relationship("RegistroProyecto", back_populates="auditorias")
    hallazgos = relationship("RegistroHallazgo", back_populates="auditoria")


class RegistroHallazgo(Base):
    __tablename__ = "registro_hallazgos"

    id = Column(Integer, primary_key=True, index=True)
    auditoria_id = Column(Integer, ForeignKey("registro_auditorias.id", ondelete="CASCADE"), nullable=False)
    funcionalidad_id = Column(Integer, ForeignKey("registro_funcionalidades.id", ondelete="SET NULL"), nullable=True)
    codigo = Column(String(20), nullable=True)
    severidad = Column(String(20), nullable=False)
    titulo = Column(String(250), nullable=False)
    detalle = Column(Text, nullable=True)
    estado = Column(String(30), default="abierto", nullable=False)
    resolucion = Column(Text, nullable=True)
    resuelto_en = Column(Date, nullable=True)
    ticket_ref = Column(String(16), nullable=True)

    auditoria = relationship("RegistroAuditoria", back_populates="hallazgos")
