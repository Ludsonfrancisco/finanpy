# Setup local

> Este setup descreve apenas o backend Django atual. Flutter, PostgreSQL e a API ainda não estão presentes e serão documentados quando suas versões forem fixadas no Sprint 0.

## Pré-requisitos

- Python 3.12
- pip
- Git

Para Docker, instale também Docker Engine/Desktop e Compose.

## Instalação

```bash
python -m venv .venv
# Windows: .venv\Scripts\activate
# Linux/macOS: source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

Antes de executar Django, edite `.env`:

```dotenv
SECRET_KEY=gere-uma-chave-local-unica-e-longa
DEBUG=True
ALLOWED_HOSTS=127.0.0.1,localhost
SQLITE_PATH=/caminho/absoluto/para/db.sqlite3
SECURE_SSL_REDIRECT=False
SESSION_COOKIE_SECURE=False
CSRF_COOKIE_SECURE=False
```

No Windows, `SQLITE_PATH` pode ser, por exemplo,
`C:/Users/voce/lar-finance/db.sqlite3`. Não use esse exemplo literalmente.

```bash
python manage.py migrate
python manage.py check
python manage.py runserver
```

A aplicação ficará em `http://127.0.0.1:8000`.

## Primeiro acesso

Não existe cadastro público. Crie o usuário administrativamente:

```bash
python manage.py createsuperuser
```

O login usa e-mail. Para garantir o Lar e os responsáveis de um usuário já
existente:

```bash
python manage.py shell -c "from django.contrib.auth import get_user_model; from households.services import ensure_household_for_user; user = get_user_model().objects.get(email='SEU_EMAIL'); ensure_household_for_user(user)"
```

O serviço é idempotente. Ele cria ou reutiliza o Lar, a membership ativa e os
responsáveis “Eu”, “Esposa” e “Conjunto”.

## Dependências fixadas

| Pacote | Versão |
|---|---|
| Django | 5.2.13 |
| asgiref | 3.11.1 |
| gunicorn | 23.0.0 |
| Pillow | 12.2.0 |
| sqlparse | 0.5.5 |
| tzdata | 2026.1 |
| python-dotenv | 1.2.2 |
| Ruff | 0.15.11 |
| coverage | 7.13.5 |

## Testes e qualidade

```bash
ruff check . --config pyproject.toml
python manage.py check
python manage.py makemigrations --check
coverage run manage.py test
coverage report --fail-under=90
```

O check de produção exige variáveis seguras e não deve usar a configuração
local de desenvolvimento:

```bash
python manage.py check --deploy --fail-level WARNING
```

## Docker e servidor

O Compose monta `/app/data` e define
`SQLITE_PATH=/app/data/db.sqlite3`. Para o servidor caseiro, não copie apenas
os comandos locais: siga `docs/deploy-easypanel.md`.
