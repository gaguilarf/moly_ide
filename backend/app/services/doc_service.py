import os
import aiofiles
from typing import List, Optional
from backend.app.schemas.infra import DocItem
from backend.app.config import settings


class DocumentationService:
    def __init__(self, docs_dir: str = settings.DOCS_DIR):
        self.docs_dir = docs_dir

    async def list_documents(self) -> List[DocItem]:
        items: List[DocItem] = []
        if not os.path.exists(self.docs_dir):
            return items

        for root, _, files in os.walk(self.docs_dir):
            for file in files:
                if file.endswith((".md", ".txt")):
                    full_path = os.path.join(root, file)
                    rel_path = os.path.relpath(full_path, self.docs_dir).replace("\\", "/")
                    parts = rel_path.split("/")
                    category = parts[0] if len(parts) > 1 else "General"

                    items.append(
                        DocItem(
                            title=file.replace(".md", "").replace("_", " ").title(),
                            path=rel_path,
                            category=category,
                        )
                    )
        return sorted(items, key=lambda d: (d.category, d.title))

    async def get_document_content(self, rel_path: str) -> Optional[str]:
        # Prevenir directory traversal
        clean_path = os.path.normpath(rel_path).lstrip("/\\")
        full_path = os.path.join(self.docs_dir, clean_path)

        if not full_path.startswith(os.path.abspath(self.docs_dir)):
            return None

        if not os.path.exists(full_path):
            return None

        async with aiofiles.open(full_path, mode="r", encoding="utf-8", errors="replace") as f:
            return await f.read()


doc_service = DocumentationService()
