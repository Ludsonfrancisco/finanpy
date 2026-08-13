# Lar Finance

Aplicação financeira privada para consolidar as finanças de um único Lar. O
nome técnico legado **Finanpy** ainda aparece nos módulos e caminhos durante a
modernização incremental.

## Estado atual

- Python 3.12, Django 5.2.13 e Gunicorn 23.0.0;
- contas, categorias, movimentações e dashboard web;
- um Lar compartilhado, com membros autorizados e responsáveis financeiros
  `Eu`, `Esposa` e `Conjunto`;
- API privada `/api/v1/` com sessões por dispositivo, sincronização idempotente,
  contrato OpenAPI e isolamento por Lar;
- SQLite persistido em `/app/data/db.sqlite3` no container;
- backup R2 diário codificado com agenda supervisionada e retenção `14/8/12`,
  ainda não ativado em produção;
- 381 testes e 98% de cobertura; gate mínimo de 90%;
- cadastro público removido;
- importação bancária e aplicativo Flutter ainda não implementados.

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
- [Backup automático no R2](docs/sprints/automatic-r2-backup.md)
- [Sprint 1 — Household Ledger](docs/sprints/sprint-1-household-ledger.md)
- [Sprint 2 — API privada e sincronização](docs/sprints/sprint-2-api-sync.md)

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

## API privada v1

O contrato OpenAPI está em [`docs/openapi-v1.yaml`](docs/openapi-v1.yaml). A API
entrega 16 rotas sob `/api/v1/`: health, login/refresh/logout, dispositivos,
household/owners, contas, categorias, transações, resumo, bootstrap e push/pull
de sincronização. Access tokens duram 15 minutos e refresh tokens 30 dias; os
tokens são opacos, rotacionados e persistidos somente como digest. Login aceita
5 tentativas/minuto e refresh 30/minuto.

Não existe cliente Flutter nem interface/pipeline de importação nesta Sprint.

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
python manage.py backup_to_r2
python manage.py audit_household_integrity
```

O backup usa a API do SQLite e só conclui após a verificação de integridade. A
auditoria é somente leitura, não imprime dados financeiros e retorna erro quando
encontra inconsistências. `backup_to_r2` exige as sete variáveis documentadas no
[runbook do backup automático](docs/sprints/automatic-r2-backup.md), cria uma cópia
consistente e só aplica retenção após confirmar o objeto remoto.

## Qualidade

```bash
ruff check . --config pyproject.toml
python manage.py check
python manage.py check --deploy --fail-level WARNING
python manage.py makemigrations --check
python -Wd -W error::DeprecationWarning manage.py test
coverage run manage.py test
coverage report --fail-under=90
```

## Situação de produção

O código e o runbook não autorizam implantação automática. A credencial histórica
foi rotacionada no EasyPanel real em 2026-08-12 e as sessões Django anteriores
foram revogadas. Um backup real foi armazenado em bucket R2 privado e restaurado
com sucesso em ambiente descartável em 2026-08-12. A produção continua bloqueada
até a validação restante do runbook no EasyPanel: imagem atual, migrations,
persistência após restart, proxy, rate limit e smoke checks. Enquanto o banco for
SQLite, a operação permanece limitada a uma réplica e um worker. A automação
diária para o R2 está codificada e testada, mas suas variáveis, execução real,
restart e restauração ainda não foram ativados nem comprovados no EasyPanel.
