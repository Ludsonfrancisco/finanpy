# Lar Finance

Aplicação financeira privada para consolidar as finanças de um único Lar. O
nome técnico legado **Finanpy** ainda aparece nos módulos e caminhos durante a
modernização incremental.

## Estado atual

- Python 3.12, Django 5.2.13 e Gunicorn 23.0.0;
- contas, categorias, movimentações e dashboard web;
- um Lar compartilhado, com membros autorizados e responsáveis financeiros
  `Eu`, `Esposa` e `Conjunto`;
- SQLite persistido em `/app/data/db.sqlite3` no container;
- 151 testes e cobertura mínima de 90% validados na Sprint 1;
- cadastro público removido;
- API mobile, importação bancária e aplicativo Flutter ainda não implementados.

O backend será preservado e evoluído por sprints. Não há proposta de rewrite
total.

## Documentação

- [PRD e estado do produto](PRD.md)
- [Roadmap por sprints](docs/ROADMAP.md)
- [Arquitetura](docs/architecture.md)
- [Modelo de dados](docs/data-model.md)
- [Importação e sincronização](docs/imports-and-sync.md)
- [UX mobile e desktop](docs/mobile-ux.md)
- [Segurança e operação](docs/security-and-operations.md)
- [Runbook do EasyPanel](docs/deploy-easypanel.md)
- [Sprint 1 — Household Ledger](docs/sprints/sprint-1-household-ledger.md)

## Acesso privado e criação do Lar

Não existe cadastro público. Usuários são criados administrativamente. Cada
usuário precisa de uma associação ativa ao Lar; os responsáveis financeiros
classificam os dados e não concedem acesso.

```bash
python manage.py createsuperuser
python manage.py shell -c "from django.contrib.auth import get_user_model; from households.services import ensure_household_for_user; user = get_user_model().objects.get(email='SEU_EMAIL'); household = ensure_household_for_user(user); print(household.uuid)"
```

## Configuração

Copie `.env.example` para `.env` e substitua todos os valores de exemplo. A
`SECRET_KEY` é obrigatória e nunca deve ser reutilizada ou versionada.

```dotenv
SECRET_KEY=gere-uma-chave-unica-e-longa
DEBUG=False
ALLOWED_HOSTS=finance.seudominio
SQLITE_PATH=/app/data/db.sqlite3
```

O caminho `/app/data` precisa ser um volume persistente. O Docker Compose deste
repositório já declara esse volume; no EasyPanel ele deve ser configurado
manualmente.

## Docker

```bash
docker compose build
docker compose up -d
docker compose logs -f web
```

O projeto usa uma réplica e um worker enquanto estiver em SQLite. Para produção
no servidor caseiro, siga o [runbook do EasyPanel](docs/deploy-easypanel.md).

## Desenvolvimento local

```bash
python -m venv .venv
# Windows: .venv\Scripts\activate
# Linux/macOS: source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Ajuste SQLITE_PATH para um caminho absoluto válido nesta máquina.
python manage.py migrate
python manage.py runserver
```

## Backup e auditoria

```bash
python manage.py backup_sqlite --output /app/data/backups/lar-finance.sqlite3
python manage.py audit_household_integrity
```

O backup usa a API do SQLite e só conclui após a verificação de integridade. A
auditoria é somente leitura, não imprime dados financeiros e retorna erro quando
encontra inconsistências.

## Qualidade

```bash
ruff check . --config pyproject.toml
python manage.py check
python manage.py check --deploy --fail-level WARNING
python manage.py makemigrations --check
coverage run manage.py test
coverage report --fail-under=90
```

## Situação de produção

O código e o runbook não autorizam implantação automática. A produção continua
bloqueada até a rotação da credencial histórica, a validação do runbook no
EasyPanel real e a existência de backup externo restaurável. Nenhuma alteração
foi executada no servidor ou na base real durante a Sprint 1.
