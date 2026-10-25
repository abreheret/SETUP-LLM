# Image des outils de l'interface web (llama-server --tools-runtime, voir start.sh).
# Le modele y execute ses commandes shell ; seul /work (= ~/LLM-fichiers sur le Mac) est partage.
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends pandoc ripgrep file \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir python-docx openpyxl python-pptx reportlab markdown
RUN useradd -m -u 1000 agent && mkdir -p /work && chown agent /work
USER agent
WORKDIR /work
