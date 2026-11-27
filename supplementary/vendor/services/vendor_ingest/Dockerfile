FROM python:3.12-slim

WORKDIR /app

COPY services/vendor_ingest/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY common/ ./common/
COPY services/vendor_ingest/handler.py services/vendor_ingest/service.py ./

ENV HOST=0.0.0.0
ENV PORT=8080

EXPOSE 8080

CMD ["python", "service.py"]
