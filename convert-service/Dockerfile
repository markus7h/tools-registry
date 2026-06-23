# Konvertier-Dienst (Teil B): bündelt die schweren Helfer, damit Clients nur curl brauchen.
# chromium (html→pdf, Mermaid via JS), libreoffice (docx→pdf), weasyprint+markdown (md→pdf),
# pandoc (docx-Fallback), poppler-utils (pdftotext).
FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      chromium \
      libreoffice-writer libreoffice-impress libreoffice-calc \
      poppler-utils \
      pandoc \
      fonts-dejavu fonts-liberation fonts-noto-core \
      libpango-1.0-0 libpangoft2-1.0-0 libharfbuzz0b libffi8 \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir weasyprint markdown

ENV CHROME_BIN=/usr/bin/chromium
ENV PORT=3458
ENV HOST=0.0.0.0

WORKDIR /app
COPY server.py theme.css ./

EXPOSE 3458
CMD ["python", "server.py"]
