# Finanpy

Aplicação Django para gestão financeira pessoal.

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
