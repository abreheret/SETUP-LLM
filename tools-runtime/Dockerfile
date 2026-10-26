# Image des outils de l'interface web (llama-server --tools-runtime, voir start.sh).
# Le modele y execute ses commandes shell ; seul /work (volume Docker setup-llm-fichiers) est partage.
# /work appartient a root en 1733 : agent y cree le dossier de chaque conversation (/work/<id>) mais ne
# peut pas lister /work, donc ne voit que les dossiers dont il connait l'id. Docker recopie ces droits
# sur le volume a sa creation.
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends pandoc ripgrep file \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir python-docx openpyxl python-pptx reportlab markdown
RUN useradd -m -u 1000 agent && mkdir -p /work && chmod 1733 /work
USER agent
WORKDIR /work
