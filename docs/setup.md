# Setup

## Pré-requisitos

- Python 3.12+
- pip

## Instalação

```bash
# 1. Criar e ativar virtualenv
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# 2. Instalar dependências
pip install -r requirements.txt

# 3. Rodar migrations
python manage.py migrate

# 4. Iniciar servidor
python manage.py runserver
```

A aplicação estará disponível em `http://127.0.0.1:8000`.

## Dependências

| Pacote | Versão |
|---|---|
| Django | 5.2.13 |
| asgiref | 3.11.1 |
| sqlparse | 0.5.5 |
| tzdata | 2026.1 |

## Banco de dados

SQLite. O arquivo `db.sqlite3` é gerado automaticamente na raiz do projeto após rodar as migrations.

## Admin

```bash
python manage.py createsuperuser
```

Acesse em `http://127.0.0.1:8000/admin/`.
