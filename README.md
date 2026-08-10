# Lar Finance

Backend Django do Lar Finance. O nome técnico legado Finanpy ainda aparece em módulos e caminhos durante a migração incremental.

O acesso é privado: não existe cadastro público. Usuários são criados pelo comando administrativo `createsuperuser` ou pelo Django Admin.

## Requisitos

- Docker e Docker Compose instalados

## Configuração

Crie um arquivo `.env` na raiz do projeto (use `.env.example` como base):

```bash
cp .env.example .env
```

Edite o `.env` com os valores desejados:

```
SECRET_KEY=sua-chave-secreta-aqui
DEBUG=False
ALLOWED_HOSTS=localhost,127.0.0.1
SQLITE_PATH=db.sqlite3
```

## Docker

### Build da imagem

```bash
docker compose build
```

### Subir a aplicação

```bash
docker compose up
```

### Subir em background

```bash
docker compose up -d
```

### Parar a aplicação

```bash
docker compose down
```

### Ver logs

```bash
docker compose logs -f web
```

### Criar superusuário

```bash
docker compose exec web python manage.py createsuperuser
```

### Rodar testes

```bash
docker compose exec web python manage.py test
```

### Criar um backup verificado do SQLite

```bash
docker compose exec web python manage.py backup_sqlite
```

O comando nunca sobrescreve um backup existente e só conclui depois de executar a verificação de integridade do SQLite. A cópia deve ser transferida de forma criptografada para fora do servidor.

## Desenvolvimento local (sem Docker)

```bash
# Criar e ativar virtualenv
python -m venv .venv
.venv\Scripts\activate  # Windows
source .venv/bin/activate  # Linux/Mac

# Instalar dependências
pip install -r requirements.txt

# Rodar migrations
python manage.py migrate

# Iniciar servidor
python manage.py runserver
```

A aplicação estará disponível em `http://localhost:8000`.

## Qualidade

```bash
ruff check . --config pyproject.toml
python manage.py check
python manage.py makemigrations --check
coverage run manage.py test
coverage report --fail-under=90
```

## Scripts de QA

Os scripts não possuem credenciais ou dados pessoais. Antes de executá-los, defina `FINANPY_QA_EMAIL` e `FINANPY_QA_PASSWORD` somente no ambiente do processo.
