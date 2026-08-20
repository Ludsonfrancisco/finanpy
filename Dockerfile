# Stage 1: build dependencies
FROM python:3.12-slim AS builder

WORKDIR /app

RUN pip install --upgrade pip
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: runtime
FROM python:3.12-slim

WORKDIR /app

COPY --from=builder /install /usr/local
COPY . .

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

EXPOSE 8000

RUN chmod +x /app/deploy/entrypoint.sh

# Entrypoint automatically runs database migrations on container startup before supervisord
ENTRYPOINT ["/app/deploy/entrypoint.sh"]
