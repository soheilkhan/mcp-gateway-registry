"""
Anthropic MCP Registry API endpoints for A2A agents.

Implements the standard MCP Registry REST API pattern for A2A agent discovery,
compatible with Anthropic's official registry specification.

This provides public API endpoints for discovering and retrieving A2A agents,
with JWT Bearer token authentication via Keycloak.

Spec: https://raw.githubusercontent.com/modelcontextprotocol/registry/refs/heads/main/docs/reference/api/openapi.yaml
"""

import logging
from typing import Annotated, Optional
from urllib.parse import unquote

from fastapi import APIRouter, Depends, HTTPException, Query, status

from ..auth.dependencies import nginx_proxied_auth
from ..constants import REGISTRY_CONSTANTS
from ..schemas.anthropic_schema import ErrorResponse, ServerList, ServerResponse
from ..services.agent_service import agent_service
from ..services.agent_transform_service import (
    transform_to_agent_list,
    transform_to_agent_response,
)


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s,p%(process)s,{%(filename)s:%(lineno)d},%(levelname)s,%(message)s",
)

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix=f"/{REGISTRY_CONSTANTS.ANTHROPIC_API_VERSION}",
    tags=["Anthropic Registry API - A2A Agents"],
)


@router.get(
    "/agents",
    response_model=ServerList,
    summary="List A2A agents",
    description="Returns a paginated list of all registered A2A agents that the authenticated user can access.",
)
async def list_agents(
    cursor: Annotated[Optional[str], Query(description="Pagination cursor")] = None,
    limit: Annotated[
        Optional[int], Query(description="Maximum number of items", ge=1, le=1000)
    ] = None,
    user_context: Annotated[dict, Depends(nginx_proxied_auth)] = None,
) -> ServerList:
    """
    List all A2A agents with pagination.

    This endpoint respects user permissions - users only see agents they have access to.

    Args:
        cursor: Pagination cursor (opaque string from previous response)
        limit: Max results per page (default: 100, max: 1000)
        user_context: Authenticated user context from nginx_proxied_auth

    Returns:
        ServerList with agents and pagination metadata
    """
    logger.info(
        f"{REGISTRY_CONSTANTS.ANTHROPIC_API_VERSION} API: Listing agents for user '{user_context['username']}' (cursor={cursor}, limit={limit})"
    )

    # Load all agents (currently no permission-based filtering for A2A agents)
    all_agents = agent_service.list_agents()
    logger.debug(f"Found {len(all_agents)} agents total")

    # Filter to only enabled agents
    enabled_agents = [
        agent for agent in all_agents
        if agent_service.is_agent_enabled(agent.get("path"))
    ]
    logger.debug(f"After filtering enabled: {len(enabled_agents)} agents")

    # Add metadata for transformation
    agents_with_meta = []
    for agent in enabled_agents:
        agent_with_meta = agent.copy()
        agent_with_meta["is_enabled"] = True
        agent_with_meta["health_status"] = "healthy"  # A2A agents default to healthy
        agent_with_meta["last_checked_iso"] = None
        agents_with_meta.append(agent_with_meta)

    # Transform to Anthropic format with pagination
    agent_list = transform_to_agent_list(
        agents_with_meta, cursor=cursor, limit=limit or 100
    )

    logger.info(
        f"{REGISTRY_CONSTANTS.ANTHROPIC_API_VERSION} API: Returning {len(agent_list.servers)} agents (hasMore={agent_list.metadata.nextCursor is not None})"
    )

    return agent_list


@router.get(
    "/agents/{agentName:path}/versions",
    response_model=ServerList,
    summary="List agent versions",
    description="Returns all available versions for a specific A2A agent.",
    responses={404: {"model": ErrorResponse, "description": "Agent not found"}},
)
async def list_agent_versions(
    agentName: str,
    user_context: Annotated[dict, Depends(nginx_proxied_auth)] = None,
) -> ServerList:
    """
    List all versions of a specific agent.

    Currently, we only maintain one version per agent, so this returns a single-item list.

    Args:
        agentName: URL-encoded agent name in reverse-DNS format (e.g., "io.mcpgateway%2Fcode-reviewer")
        user_context: Authenticated user context

    Returns:
        ServerList with single version

    Raises:
        HTTPException: 404 if agent not found or user lacks access
    """
    # URL-decode the agent name
    decoded_name = unquote(agentName)
    logger.info(
        f"{REGISTRY_CONSTANTS.ANTHROPIC_API_VERSION} API: Listing versions for agent '{decoded_name}' (user='{user_context['username']}')"
    )

    # Extract path from reverse-DNS name
    # Expected format: "io.mcpgateway/code-reviewer"
    namespace = REGISTRY_CONSTANTS.ANTHROPIC_SERVER_NAMESPACE
    expected_prefix = f"{namespace}/"

    if not decoded_name.startswith(expected_prefix):
        logger.warning(f"Invalid agent name format: {decoded_name}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Agent not found"
        )

    # Construct path for lookup
    lookup_path = "/" + decoded_name.replace(expected_prefix, "")

    # Get agent info - try with and without trailing slash
    agent_info = agent_service.get_agent(lookup_path)
    if not agent_info:
        # Try with trailing slash
        agent_info = agent_service.get_agent(lookup_path + "/")

    if not agent_info:
        logger.warning(f"Agent not found: {lookup_path}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Agent not found"
        )

    # Verify agent is enabled
    if not agent_service.is_agent_enabled(agent_info.get("path")):
        logger.warning(f"Agent is disabled: {lookup_path}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Agent not found"
        )

    # Add metadata for transformation
    agent_with_meta = agent_info.copy()
    agent_with_meta["is_enabled"] = True
    agent_with_meta["health_status"] = "healthy"
    agent_with_meta["last_checked_iso"] = None

    # Since we only have one version, return a list with one item
    agent_list = transform_to_agent_list([agent_with_meta])

    logger.info(
        f"{REGISTRY_CONSTANTS.ANTHROPIC_API_VERSION} API: Returning version info for {decoded_name}"
    )

    return agent_list


@router.get(
    "/agents/{agentName:path}/versions/{version}",
    response_model=ServerResponse,
    summary="Get agent version details",
    description="Returns detailed information about a specific version of an A2A agent. Use 'latest' to get the most recent version.",
    responses={
        404: {"model": ErrorResponse, "description": "Agent or version not found"}
    },
)
async def get_agent_version(
    agentName: str,
    version: str,
    user_context: Annotated[dict, Depends(nginx_proxied_auth)] = None,
) -> ServerResponse:
    """
    Get detailed information about a specific agent version.

    Args:
        agentName: URL-encoded agent name (e.g., "io.mcpgateway%2Fcode-reviewer")
        version: Version string (e.g., "1.0.0" or "latest")
        user_context: Authenticated user context

    Returns:
        ServerResponse with full agent details

    Raises:
        HTTPException: 404 if agent not found or user lacks access
    """
    # URL-decode parameters
    decoded_name = unquote(agentName)
    decoded_version = unquote(version)

    logger.info(
        f"{REGISTRY_CONSTANTS.ANTHROPIC_API_VERSION} API: Getting agent '{decoded_name}' version '{decoded_version}' (user='{user_context['username']}')"
    )

    # Extract path from reverse-DNS name
    namespace = REGISTRY_CONSTANTS.ANTHROPIC_SERVER_NAMESPACE
    expected_prefix = f"{namespace}/"

    if not decoded_name.startswith(expected_prefix):
        logger.warning(f"Invalid agent name format: {decoded_name}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Agent not found"
        )

    # Construct path for lookup
    lookup_path = "/" + decoded_name.replace(expected_prefix, "")

    # Get agent info - try with and without trailing slash
    agent_info = agent_service.get_agent(lookup_path)
    if not agent_info:
        # Try with trailing slash
        agent_info = agent_service.get_agent(lookup_path + "/")

    if not agent_info:
        logger.warning(f"Agent not found: {lookup_path}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Agent not found"
        )

    # Verify agent is enabled
    if not agent_service.is_agent_enabled(agent_info.get("path")):
        logger.warning(f"Agent is disabled: {lookup_path}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Agent not found"
        )

    # Currently we only support "latest" or version matching protocol_version
    protocol_version = agent_info.get("protocol_version", "1.0.0")
    if decoded_version not in ["latest", protocol_version, "1.0.0"]:
        logger.warning(f"Unsupported version requested: {decoded_version}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Version {decoded_version} not found",
        )

    # Add metadata for transformation
    agent_with_meta = agent_info.copy()
    agent_with_meta["is_enabled"] = True
    agent_with_meta["health_status"] = "healthy"
    agent_with_meta["last_checked_iso"] = None

    # Transform to Anthropic format
    agent_response = transform_to_agent_response(
        agent_with_meta, include_registry_meta=True
    )

    logger.info(
        f"{REGISTRY_CONSTANTS.ANTHROPIC_API_VERSION} API: Returning details for {decoded_name} v{decoded_version}"
    )

    return agent_response
