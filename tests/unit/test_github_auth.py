"""Unit tests for GitHubAuthProvider."""

from unittest.mock import patch

import pytest


class TestDomainMatching:
    """Tests for _is_allowed_host and host allowlist logic."""

    def test_github_com_is_allowed(self):
        """Public github.com is allowed by default."""
        from registry.services.github_auth import GitHubAuthProvider

        provider = GitHubAuthProvider()
        assert provider._is_allowed_host("https://github.com/owner/repo") is True

    def test_raw_githubusercontent_is_allowed(self):
        """raw.githubusercontent.com is allowed by default."""
        from registry.services.github_auth import GitHubAuthProvider

        provider = GitHubAuthProvider()
        assert provider._is_allowed_host(
            "https://raw.githubusercontent.com/owner/repo/main/SKILL.md"
        ) is True

    def test_non_github_host_is_not_allowed(self):
        """Non-GitHub hosts are rejected."""
        from registry.services.github_auth import GitHubAuthProvider

        provider = GitHubAuthProvider()
        assert provider._is_allowed_host("https://gitlab.com/owner/repo") is False

    def test_case_insensitive_matching(self):
        """Host matching is case-insensitive."""
        from registry.services.github_auth import GitHubAuthProvider

        provider = GitHubAuthProvider()
        assert provider._is_allowed_host("https://GitHub.COM/owner/repo") is True

    @patch("registry.services.github_auth.settings")
    def test_extra_hosts_from_config(self, mock_settings):
        """Extra hosts from config are included in allowlist."""
        mock_settings.github_pat = ""
        mock_settings.github_app_id = ""
        mock_settings.github_app_installation_id = ""
        mock_settings.github_app_private_key = ""
        mock_settings.github_extra_hosts = "github.mycompany.com,raw.github.mycompany.com"

        from registry.services.github_auth import GitHubAuthProvider

        provider = GitHubAuthProvider()
        assert provider._is_allowed_host("https://github.mycompany.com/org/repo") is True
        assert provider._is_allowed_host(
            "https://raw.github.mycompany.com/org/repo/main/f"
        ) is True

    @patch("registry.services.github_auth.settings")
    def test_empty_extra_hosts(self, mock_settings):
        """Empty extra hosts config doesn't break anything."""
        mock_settings.github_pat = ""
        mock_settings.github_app_id = ""
        mock_settings.github_app_installation_id = ""
        mock_settings.github_app_private_key = ""
        mock_settings.github_extra_hosts = ""

        from registry.services.github_auth import GitHubAuthProvider

        provider = GitHubAuthProvider()
        assert provider._is_allowed_host("https://github.com/owner/repo") is True
        assert provider._is_allowed_host("https://example.com/foo") is False
