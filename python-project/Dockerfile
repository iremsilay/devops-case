
FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY ETL.py .

RUN useradd --create-home --uid 10001 appuser

USER appuser

CMD ["python", "ETL.py"]
