"""
File-based repository for virtual server configuration storage.

Stores virtual server configs as JSON files under ~/mcp-gateway/virtual_servers/.
Virtual servers are an advanced feature that aggregates tools from multiple backends.
When no virtual servers are configured, all operations return empty results.
"""

import json
import logging
from pathlib import Path
from typing import Any

from ...schemas.virtual_server_models import VirtualServerConfig
from ..interfaces import VirtualServerRepositoryBase

logger = logging.getLogger(__name__)


class FileVirtualServerRepository(VirtualServerRepositoryBase):
    """File-based implementation of virtual server repository."""

    def __init__(self):
        self._servers: dict[str, VirtualServerConfig] = {}
        self._data_dir = Path.home() / "mcp-gateway" / "virtual_servers"

    async def ensure_indexes(self) -> None:
        """No-op for file storage (no indexes needed)."""
        self._data_dir.mkdir(parents=True, exist_ok=True)
        await self._load_all()

    async def _load_all(self) -> None:
        """Load all virtual server configs from disk."""
        if not self._data_dir.exists():
            self._servers = {}
            return

        self._servers = {}
        for config_file in self._data_dir.glob("*.json"):
            try:
                with open(config_file) as f:
                    data = json.load(f)
                config = VirtualServerConfig(**data)
                self._servers[config.path] = config
            except Exception as e:
                logger.error(f"Error loading virtual server config {config_file}: {e}")

    async def get(
        self,
        path: str,
    ) -> VirtualServerConfig | None:
        return self._servers.get(path)

    async def list_all(self) -> list[VirtualServerConfig]:
        return list(self._servers.values())

    async def list_enabled(self) -> list[VirtualServerConfig]:
        return [s for s in self._servers.values() if s.enabled]

    async def create(
        self,
        config: VirtualServerConfig,
    ) -> VirtualServerConfig:
        if config.path in self._servers:
            raise ValueError(f"Virtual server already exists: {config.path}")

        self._servers[config.path] = config
        self._persist(config)
        return config

    async def update(
        self,
        path: str,
        updates: dict[str, Any],
    ) -> VirtualServerConfig | None:
        existing = self._servers.get(path)
        if not existing:
            return None

        data = existing.model_dump()
        data.update(updates)
        updated = VirtualServerConfig(**data)
        self._servers[path] = updated
        self._persist(updated)
        return updated

    async def delete(
        self,
        path: str,
    ) -> bool:
        if path not in self._servers:
            return False

        del self._servers[path]
        safe_name = path.strip("/").replace("/", "_")
        file_path = self._data_dir / f"{safe_name}.json"
        file_path.unlink(missing_ok=True)
        return True

    async def get_state(
        self,
        path: str,
    ) -> bool:
        server = self._servers.get(path)
        return server.enabled if server else False

    async def set_state(
        self,
        path: str,
        enabled: bool,
    ) -> bool:
        server = self._servers.get(path)
        if not server:
            return False

        data = server.model_dump()
        data["enabled"] = enabled
        updated = VirtualServerConfig(**data)
        self._servers[path] = updated
        self._persist(updated)
        return True

    def _persist(self, config: VirtualServerConfig) -> None:
        """Write a virtual server config to disk."""
        self._data_dir.mkdir(parents=True, exist_ok=True)
        safe_name = config.path.strip("/").replace("/", "_")
        file_path = self._data_dir / f"{safe_name}.json"
        with open(file_path, "w") as f:
            json.dump(config.model_dump(), f, indent=2, default=str)
