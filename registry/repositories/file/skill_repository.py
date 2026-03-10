"""File-based skill repository implementation."""

import json
import logging
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from ...core.config import settings
from ...schemas.skill_models import SkillCard
from ..interfaces import SkillRepositoryBase

logger = logging.getLogger(__name__)

SKILLS_DIR_NAME = "skills"
SKILL_STATE_FILE = "skill_state.json"


def _path_to_filename(path: str) -> str:
    """Convert skill path to safe filename."""
    normalized = path.lstrip("/").replace("/", "_")
    if not normalized.endswith(".json"):
        normalized += ".json"
    return normalized


class FileSkillRepository(SkillRepositoryBase):
    """File-based skill repository using JSON files."""

    def __init__(self):
        self.skills_dir = settings.container_registry_dir / SKILLS_DIR_NAME
        self.state_file = self.skills_dir / SKILL_STATE_FILE
        self.skills_dir.mkdir(parents=True, exist_ok=True)

    async def ensure_indexes(self) -> None:
        """No-op for file-based storage."""
        pass

    async def _load_all(self) -> dict[str, SkillCard]:
        """Load all skills from disk."""
        skills: dict[str, SkillCard] = {}
        for file in self.skills_dir.glob("*.json"):
            if file.name == SKILL_STATE_FILE:
                continue
            try:
                with open(file) as f:
                    data = json.load(f)
                if isinstance(data, dict) and "path" in data:
                    skill = SkillCard(**data)
                    skills[skill.path] = skill
            except Exception as e:
                logger.error(f"Failed to load skill from {file}: {e}")
        return skills

    async def get(self, path: str) -> SkillCard | None:
        """Get a skill by path."""
        skills = await self._load_all()
        return skills.get(path)

    async def list_all(
        self,
        skip: int = 0,
        limit: int = 100,
    ) -> list[SkillCard]:
        """List all skills with pagination."""
        skills = await self._load_all()
        all_skills = list(skills.values())
        return all_skills[skip : skip + limit]

    async def list_filtered(
        self,
        include_disabled: bool = False,
        tag: str | None = None,
        visibility: str | None = None,
        registry_name: str | None = None,
    ) -> list[SkillCard]:
        """List skills with filtering."""
        skills = await self._load_all()
        result = []

        state = await self._load_state()
        disabled_paths = set(state.get("disabled", []))

        for skill in skills.values():
            if not include_disabled and skill.path in disabled_paths:
                continue
            if tag and tag not in (skill.tags or []):
                continue
            if visibility and getattr(skill, "visibility", None) != visibility:
                continue
            if registry_name and getattr(skill, "registry_name", None) != registry_name:
                continue
            result.append(skill)

        return result

    async def create(self, skill: SkillCard) -> SkillCard:
        """Create a new skill."""
        if not skill.registered_at:
            skill.registered_at = datetime.now(UTC)
        skill.updated_at = datetime.now(UTC)

        filename = _path_to_filename(skill.path)
        file_path = self.skills_dir / filename

        with open(file_path, "w") as f:
            json.dump(skill.model_dump(mode="json"), f, indent=2)

        return skill

    async def update(
        self,
        path: str,
        updates: dict[str, Any],
    ) -> SkillCard | None:
        """Update a skill."""
        existing = await self.get(path)
        if not existing:
            return None

        data = existing.model_dump()
        data.update(updates)
        data["updated_at"] = datetime.now(UTC).isoformat()

        updated = SkillCard(**data)

        filename = _path_to_filename(path)
        file_path = self.skills_dir / filename

        with open(file_path, "w") as f:
            json.dump(updated.model_dump(mode="json"), f, indent=2)

        return updated

    async def delete(self, path: str) -> bool:
        """Delete a skill."""
        filename = _path_to_filename(path)
        file_path = self.skills_dir / filename

        if file_path.exists():
            file_path.unlink()
            return True
        return False

    async def _load_state(self) -> dict[str, list[str]]:
        """Load skill state from disk."""
        if self.state_file.exists():
            try:
                with open(self.state_file) as f:
                    state = json.load(f)
                if isinstance(state, dict):
                    return {
                        "enabled": state.get("enabled", []),
                        "disabled": state.get("disabled", []),
                    }
            except Exception as e:
                logger.error(f"Failed to load skill state: {e}")
        return {"enabled": [], "disabled": []}

    async def _save_state(self, state: dict[str, list[str]]) -> None:
        """Save skill state to disk."""
        with open(self.state_file, "w") as f:
            json.dump(state, f, indent=2)

    async def get_state(self, path: str) -> bool:
        """Get skill enabled state. Returns True if not explicitly disabled."""
        state = await self._load_state()
        return path not in state.get("disabled", [])

    async def set_state(self, path: str, enabled: bool) -> bool:
        """Set skill enabled state."""
        state = await self._load_state()

        if enabled:
            if path in state["disabled"]:
                state["disabled"].remove(path)
            if path not in state["enabled"]:
                state["enabled"].append(path)
        else:
            if path in state["enabled"]:
                state["enabled"].remove(path)
            if path not in state["disabled"]:
                state["disabled"].append(path)

        await self._save_state(state)
        return True

    async def create_many(self, skills: list[SkillCard]) -> list[SkillCard]:
        """Create multiple skills."""
        created = []
        for skill in skills:
            created.append(await self.create(skill))
        return created

    async def update_many(self, updates: dict[str, dict[str, Any]]) -> int:
        """Update multiple skills by path, return count."""
        count = 0
        for path, update_data in updates.items():
            result = await self.update(path, update_data)
            if result:
                count += 1
        return count

    async def count(self) -> int:
        """Get total count of skills."""
        skills = await self._load_all()
        return len(skills)
