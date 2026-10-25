# Serveur MCP des outils web_search et fetch_page de l'interface web (voir server.py, sans SDK MCP).
# Lance par llama-server avec "docker exec -i setup-llm-web python /app/server.py" (start.sh).
FROM python:3.12-slim
RUN pip install --no-cache-dir httpx trafilatura
COPY server.py /app/server.py
RUN useradd -m -u 1000 agent
USER agent
