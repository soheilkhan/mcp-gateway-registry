FROM public.ecr.aws/docker/library/python:3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install dependencies
COPY pyproject.toml .
RUN pip install uv && uv pip install --system -e .

# Copy application
COPY app/ app/
COPY create_api_key.py ./

# Create data directory
RUN mkdir -p /var/lib/sqlite

# Run as non-root user
RUN groupadd --gid 1001 appuser && \
    useradd --uid 1001 --gid appuser --shell /bin/bash appuser && \
    chown -R appuser:appuser /app /var/lib/sqlite
USER appuser

# Expose port
EXPOSE 8890

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8890/health || exit 1

CMD ["python", "-m", "app.main"]