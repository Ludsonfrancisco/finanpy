# Lar Finance

Painel financeiro privado da família, atualmente em transição de uma aplicação web Django chamada tecnicamente de Finanpy para um app Flutter sincronizado em iOS, Android e Windows.

## Estado atual

- Django 5.2.13 / Python 3.12;
- contas, categorias, transações e dashboard web;
- SQLite e Docker/Gunicorn;
- backend implantado em Linux/EasyPanel pelo proprietário;
- 72 testes Django aprovados na auditoria;
- Flutter, API, importação e PostgreSQL ainda não implementados.

O plano preserva o backend e evolui por sprints. Não é um rewrite total.

## Documentação

- [PRD e fonte de verdade](PRD.md)
- [Índice técnico](docs/README.md)
- [Roadmap](docs/ROADMAP.md)
- [Arquitetura](docs/architecture.md)
- [Importação e sincronização](docs/imports-and-sync.md)
- [UX](docs/mobile-ux.md)
- [Segurança e operação](docs/security-and-operations.md)

## Requisitos do backend atual

- Docker e Docker Compose, ou Python 3.12 e pip.

## Configuração

Copie `.env.example` para `.env` e defina valores próprios. Nunca reutilize exemplos em produção.

```bash
cp .env.example .env
```

Variáveis mínimas atuais:

```dotenv
SECRET_KEY=gere-uma-chave-forte
DEBUG=False
ALLOWED_HOSTS=localhost,127.0.0.1
```

## Docker atual

```bash
docker compose build
docker compose up
docker compose exec web python manage.py test
```

> Atenção: a auditoria identificou que o volume do SQLite monta um volume no caminho de arquivo `/app/db.sqlite3`. Corrija e valide backup/restauração antes de usar o Compose atual com dados reais.

## Desenvolvimento local

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
```

No Linux/macOS, a ativação é `source .venv/bin/activate`.

## Qualidade

```bash
ruff check .
python manage.py check
python manage.py makemigrations --check
coverage run manage.py test
coverage report
```

## Segurança

- Não versionar `.env`, banco, tokens, arquivos financeiros ou dados reais.
- O cadastro público será removido no Sprint 0.
- Scripts de QA com credencial/PII identificados na auditoria precisam de rotação e substituição por fixtures.
- Consulte [segurança e operação](docs/security-and-operations.md) antes de um novo deploy.
