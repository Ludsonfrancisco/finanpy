# Deploy via EasyTunnel

Este projeto não depende mais do Render. O modo recomendado é subir o Django localmente/VPS com Docker e expor a porta `8000` pelo EasyTunnel.

## 1. Variáveis de ambiente

Crie `.env` a partir do exemplo:

```bash
cp .env.example .env
```

Configure no mínimo:

```env
SECRET_KEY=gere-uma-chave-forte
DEBUG=False
ALLOWED_HOSTS=localhost,127.0.0.1,seu-dominio-ou-host-do-tunel
CSRF_TRUSTED_ORIGINS=https://seu-dominio-ou-host-do-tunel
NPM_BIN_PATH=/usr/bin/npm
```

Opcional, se for usar Postgres/MySQL:

```env
DATABASE_URL=postgres://usuario:senha@host:5432/finanpy
```

Sem `DATABASE_URL`, o projeto usa SQLite.

## 2. Subir com Docker

```bash
docker compose up -d --build
```

O container executa migrations antes de iniciar o Gunicorn.

## 3. Expor via EasyTunnel

Aponte o EasyTunnel para a porta local `8000`.

Exemplo genérico:

```bash
# ajuste para o comando real do EasyTunnel usado no servidor
# origem: http://127.0.0.1:8000
```

Depois coloque o host público recebido pelo túnel em `ALLOWED_HOSTS` e, se for HTTPS, em `CSRF_TRUSTED_ORIGINS`.

## 4. Checks de produção

```bash
docker compose exec web python manage.py check --deploy
```

## 5. Comandos úteis

```bash
docker compose logs -f web
docker compose exec web python manage.py createsuperuser
docker compose exec web python manage.py collectstatic --noinput
docker compose down
```
