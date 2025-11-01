# Issue #195 Sub-Tasks: Example A2A Agents - Travel Booking System

## Overview
Build two production-ready example A2A agents using Strands framework, containerized with Docker, and deployed on AgentCore runtime. Agents demonstrate registration with A2A Registry, discovery via semantic search, and real-world multi-agent collaboration for a fictional travel company.

**Use Case**: Travel booking system with two collaborating agents:
1. **Travel Assistant Agent** - Helps users plan trips and search for flights
2. **Flight Booking Agent** - Manages flight reservations and bookings

**Technology Stack**:
- **Framework**: Strands (all agents)
- **Containerization**: Docker (both agents)
- **Runtime**: AgentCore (deployment platform)
- **Registry**: MCP Gateway A2A Registry (discovery & registration)
- **Search**: Semantic search for agent discovery

## Sub-Issues to Create

### 1. Build Travel Assistant Agent (Strands)
**Objective**: Create a Strands-based agent that helps users plan trips and discover flights

**Scope**:
- User interface for trip planning
- Search and query capabilities for travel options
- Discovers and calls Flight Booking Agent via registry
- Demonstrates P2P communication with booking agent

**Architecture**:
- Built with Strands framework
- Provides skills: search_flights, check_prices, get_recommendations, create_trip_plan
- Uses semantic search to discover "flight booking", "reservation" agents
- Exposes REST API following A2A protocol

**Containerization**:
- Dockerfile with Strands runtime environment
- Environment variables for registry configuration
- Port exposure for API access

**Deployment**:
- Docker image published to container registry
- Runs on AgentCore runtime
- Registers with A2A Registry on startup
- Auto-discovers Flight Booking Agent

**Acceptance Criteria**:
- [ ] Agent built using Strands framework
- [ ] Successfully registers with A2A Registry
- [ ] Follows A2A protocol specification
- [ ] Docker image builds and runs successfully
- [ ] Exposes REST API on defined port
- [ ] Can discover Flight Booking Agent via semantic search
- [ ] Demonstrates calling Flight Booking Agent endpoints
- [ ] Includes proper error handling and logging

---

### 2. Build Flight Booking Agent (Strands)
**Objective**: Create a Strands-based agent that manages flight reservations and bookings

**Scope**:
- Flight inventory and availability management
- Booking creation and confirmation
- Reservation management (modify, cancel, refund)
- Payment processing integration
- Validates with Travel Assistant Agent for trip context

**Architecture**:
- Built with Strands framework
- Provides skills: reserve_flight, confirm_booking, manage_reservation, process_payment, check_availability
- Registers with A2A Registry with tags: "booking", "flight", "reservation", "payments"
- Exposes REST API following A2A protocol
- Can be discovered by Travel Assistant via semantic search

**Containerization**:
- Dockerfile with Strands runtime environment
- Database connection for inventory/reservations
- Environment variables for registry and payment credentials
- Port exposure for API access

**Deployment**:
- Docker image published to container registry
- Runs on AgentCore runtime
- Registers with A2A Registry on startup
- Ready to receive requests from Travel Assistant

**Acceptance Criteria**:
- [ ] Agent built using Strands framework
- [ ] Successfully registers with A2A Registry
- [ ] Follows A2A protocol specification
- [ ] Docker image builds and runs successfully
- [ ] Exposes REST API on defined port
- [ ] Manages flight inventory and reservations
- [ ] Processes booking requests from Travel Assistant
- [ ] Includes proper error handling and logging
- [ ] Handles payment integration patterns

---

### 3. Implement Agent-to-Agent Communication Workflow
**Objective**: Demonstrate complete workflow of agent discovery and collaboration

**Scope**:
- Travel Assistant discovers Flight Booking Agent via semantic search
- Travel Assistant queries Flight Booking Agent for availability
- Travel Assistant requests booking from Flight Booking Agent
- Error handling and retry logic for failed calls
- Logging of all interactions

**Architecture**:
- REST-based P2P communication between agents
- Each agent maintains registry client connection
- Semantic search queries for agent discovery
- Service discovery pattern implementation

**Documentation**:
- Workflow diagram showing agent interactions
- Example API calls and responses
- Error scenarios and handling
- Logging and monitoring patterns

**Acceptance Criteria**:
- [ ] Agents can discover each other via semantic search
- [ ] Travel Assistant successfully calls Flight Booking Agent
- [ ] Proper request/response handling implemented
- [ ] Error handling and retry logic working
- [ ] Workflow tested end-to-end
- [ ] All interactions logged properly
- [ ] Performance metrics captured

---

### 4. Create Docker & AgentCore Deployment Guide
**Objective**: Document how to build, containerize, and deploy Strands agents on AgentCore

**Scope**:
- Dockerfile best practices for Strands agents
- AgentCore runtime configuration
- A2A Registry registration configuration
- Environment variables and secrets management
- Health checks and monitoring setup
- Multi-agent orchestration on AgentCore

**Documentation Includes**:
- Step-by-step Dockerfile creation guide
- Docker Compose configuration for local testing
- AgentCore deployment manifest examples
- Registry integration configuration
- Debugging and troubleshooting guide

**Acceptance Criteria**:
- [ ] Comprehensive deployment guide (markdown)
- [ ] Example Dockerfile with best practices
- [ ] Docker Compose example with both agents
- [ ] AgentCore manifest examples
- [ ] Registry configuration documentation
- [ ] Health check setup documented
- [ ] Troubleshooting guide included

---

### 5. Create Integration Tests & Demo Workflow
**Objective**: Automated tests and interactive demo showing agent collaboration

**Scope**:
- Unit tests for each agent's skills
- Integration tests for agent-to-agent communication
- End-to-end workflow tests (trip planning to booking)
- Demo script orchestrating complete user journey
- Performance and load testing patterns

**Test Coverage**:
- Agent registration and health checks
- Semantic search discovery accuracy
- Agent communication and API calls
- Error scenarios and edge cases
- Concurrent requests handling

**Demo Script**:
- Simulates user trip planning request
- Shows Travel Assistant discovering Flight Booking Agent
- Demonstrates booking workflow
- Displays all API interactions and responses

**Acceptance Criteria**:
- [ ] Integration tests passing (>80% coverage)
- [ ] Tests cover agent communication workflows
- [ ] Demo script runs end-to-end successfully
- [ ] Clear output showing each step
- [ ] Error handling tested and working
- [ ] Performance metrics captured
- [ ] Documentation for running tests

---

### 6. Implement A2A Agent Metrics & Analytics
**Objective**: Track agent interactions, discovery patterns, and usage metrics

**Scope**:
- Metrics for agent discovery queries
- Agent-to-agent communication metrics
- Booking success rates and latency
- Agent health and availability tracking
- Integration with existing Prometheus + SQLite

**Metrics Tracked**:
- Agent discovery: queries performed, success rate, response time
- Agent calls: frequency, latency, success rate, error rate
- Business metrics: bookings created, bookings completed, revenue
- System metrics: agent uptime, resource usage, queue depths

**Storage & Retrieval**:
- Time-series data in Prometheus
- Historical data in SQLite
- API endpoints to query metrics

**Acceptance Criteria**:
- [ ] Metrics collection implemented in both agents
- [ ] Prometheus scrape configuration updated
- [ ] SQLite schema for metrics storage
- [ ] API endpoints for metrics queries
- [ ] Real-time metrics dashboard ready
- [ ] Historical trend analysis possible

---

### 7. Visualize Agent Metrics in Dashboard
**Objective**: Display travel agents system health and performance in dashboard

**Scope**:
- Agent availability and health status
- Discovery and communication metrics
- Business metrics (bookings, success rates)
- Agent collaboration patterns
- System performance and resource usage

**Dashboard Widgets**:
- **Agent Status**: Travel Assistant & Flight Booking Agent health
- **Discovery Metrics**: Search queries, success rates, most sought capabilities
- **Communication Patterns**: Agent-to-agent call frequency and latency
- **Business Metrics**: Booking volume, success rate, average booking time
- **Performance**: Response times, error rates, resource utilization
- **Audit Trail**: Recent agent interactions and key events

**Features**:
- Real-time updates
- Responsive design
- Historical trend analysis
- Alert conditions for failures

**Acceptance Criteria**:
- [ ] At least 5 dashboard widgets implemented
- [ ] Real-time metrics updates
- [ ] Historical data visualization
- [ ] Responsive design matching existing UI
- [ ] Works with both travel agents
- [ ] Performance metrics displayed
- [ ] Alert thresholds configurable

---

## Implementation Order
1. **Phase 1**: Travel Assistant Agent (foundation - Strands + Docker)
2. **Phase 2**: Flight Booking Agent (capability - Strands + Docker)
3. **Phase 3**: Agent-to-Agent Communication (integration - discovery & calling)
4. **Phase 4**: Deployment Guide (enablement - Docker & AgentCore)
5. **Phase 5**: Integration Tests & Demo (validation - end-to-end workflows)
6. **Phase 6**: Metrics & Analytics (observability - tracking interactions)
7. **Phase 7**: Dashboard Visualization (insights - system visibility)

## Success Metrics
- [ ] Both agents successfully build and run in Docker
- [ ] Agents register with A2A Registry on startup
- [ ] Travel Assistant discovers Flight Booking Agent via semantic search
- [ ] Complete booking workflow works end-to-end
- [ ] All agent interactions logged and measurable
- [ ] Dashboard displays real-time agent metrics
- [ ] Integration tests passing (>80% coverage)
- [ ] Deployment guide enables users to build similar agents
- [ ] Demo shows clear business value of agent collaboration

## Architecture Diagram
```
┌─────────────────────────────────────────────────────┐
│         MCP Gateway A2A Registry                    │
│  (Agent Discovery & Registration)                   │
└────────────────────┬────────────────────────────────┘
                     │
       ┌─────────────┼─────────────┐
       │             │             │
       ▼             ▼             ▼
┌──────────────┐ ┌──────────────┐ ┌────────────────┐
│Travel        │ │Flight        │ │Metrics Service │
│Assistant     │ │Booking       │ │(Prometheus +   │
│Agent         │ │Agent         │ │SQLite)         │
│              │ │              │ │                │
│Strands+      │ │Strands+      │ │                │
│Docker        │ │Docker        │ │                │
└──────┬───────┘ └──────┬───────┘ └────────┬───────┘
       │                │                  │
       └────────────────┼──────────────────┘
                        │
                   AgentCore Runtime
```

## Technology Stack Summary
- **Agent Framework**: Strands
- **Containerization**: Docker
- **Runtime Environment**: AgentCore
- **Registry**: MCP Gateway A2A Registry
- **Search**: Semantic search (FAISS)
- **Metrics**: Prometheus + SQLite
- **Visualization**: Grafana + Custom Dashboard
- **Communication**: REST API (A2A Protocol)

## Notes
- Both agents built with Strands for consistency and best practices
- Docker containerization enables easy deployment and scaling
- AgentCore runtime provides production-grade execution environment
- A2A Registry enables true decentralized agent discovery
- Semantic search makes agents discoverable by capability, not just name
- Real-world travel booking use case demonstrates practical value
- Metrics and visualization provide operational visibility
- Example agents serve as templates for users building similar systems

## Related
- Main Issue: #195 - Add A2A Protocol Support to Registry
- Design Doc: `.scratchpad/a2a-integration-design.md`
- A2A Protocol: https://a2a-protocol.org/
- Strands Framework: [Strands Documentation]
- AgentCore: [AgentCore Documentation]
