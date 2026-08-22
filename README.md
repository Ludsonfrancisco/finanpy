# Lar Finance

Aplicação financeira privada para consolidar as finanças de um único Lar. O
nome técnico legado **Finanpy** ainda aparece nos módulos e caminhos durante a
modernização incremental.

## Estado atual

- Python 3.12, Django 5.2.13, Gunicorn 23.0.0 e WhiteNoise 6.12.0;
- contas, categorias, movimentações e dashboard web;
- um Lar compartilhado, com membros autorizados e responsáveis financeiros
  `Eu`, `Esposa` e `Conjunto`;
- API privada `/api/v1/` com sessões por dispositivo, sincronização idempotente,
  contrato OpenAPI e isolamento por Lar;
- SQLite persistido em `/app/data/db.sqlite3` no container;
- backup R2 diário ativo em produção, com agenda supervisionada, retenção
  `14/8/12`, idempotência após restart e restauração isolada comprovada;
- 581 testes Django e 374 testes Flutter passaram localmente em 21/08/2026;
  a CI do SHA candidato também está verde;
- cadastro público removido;
- piloto de importação manual OFX Nubank de conta/cartão, com prévia, confirmação
  explícita, deduplicação e sincronização;
- cliente Flutter com login, cache offline, sincronização pull, Home Casa de
  Valores e builds Windows/Android/iOS comprovados pela CI;
- importação manual de OFX Nubank pelo próprio app, com prévia paginada e
  confirmação explícita;
- cartões/faturas, contas fixas, orçamento por categoria, saldo livre e
  relatórios já implementados na Web e/ou Flutter;
- ledger principal sincronizado/offline; cartões e contas fixas usam servidor
  autoritativo e escrita online;
- Design System **Casa de Valores 2.0** comum a Web e Flutter, com paridade
  visual incremental ainda pendente.

O backend será preservado e evoluído por sprints. Não há proposta de rewrite
total.

## Documentação

- [PRD e estado do produto](PRD.md)
- [Contexto do produto e marca](PRODUCT.md)
- [Roadmap por sprints](docs/ROADMAP.md)
- [Arquitetura](docs/architecture.md)
- [Modelo de dados](docs/data-model.md)
- [Importação e sincronização](docs/imports-and-sync.md)
- [UX mobile e desktop](docs/mobile-ux.md)
- [Segurança e operação](docs/security-and-operations.md)
- [Runbook do EasyPanel](docs/deploy-easypanel.md)
- [Ensaio do deploy fail-fast](docs/audits/2026-08-21-fail-fast-deploy-rehearsal.md)
- [Backup automático no R2](docs/sprints/automatic-r2-backup.md)
- [Auditoria da ativação R2 em produção](docs/audits/automatic-r2-backup-production.md)
- [Sprint 1 — Household Ledger](docs/sprints/sprint-1-household-ledger.md)
- [Sprint 2 — API privada e sincronização](docs/sprints/sprint-2-api-sync.md)
- [Sprint 3 — Importação OFX Nubank](docs/sprints/sprint-3-ofx-import.md)
- [Sprint 4 — Fundação Flutter e Home Casa de Valores](docs/sprints/sprint-4-flutter-foundation.md)
- [Sprint 5 — Importação OFX no Flutter](docs/sprints/sprint-5-ofx-flutter-import.md)
- [Casa de Valores 2.0](docs/design-system.md)
- [Auditoria do estado e paridade em 20/08/2026](docs/audits/2026-08-20-product-state-and-design-parity.md)

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
A imagem executa `prepare_deploy` antes do Supervisor, na ordem: preflight,
backup R2 quando houver banco existente com migration pendente, `migrate`,
auditoria, `collectstatic` e, somente após sucesso, Supervisor. Não sobrescreva o
command da imagem nem execute migration manual em paralelo.

## API privada v1

O contrato OpenAPI está em [`docs/openapi-v1.yaml`](docs/openapi-v1.yaml). A API
entrega 32 rotas sob `/api/v1/`: health, autenticação, dispositivos,
household/owners, contas, categorias, transações, resumo, bootstrap, sync,
importação OFX, cartões/faturas e contas fixas. Access tokens duram 15 minutos e
refresh tokens 30 dias; os
tokens são opacos, rotacionados e persistidos somente como digest. Login aceita
5 tentativas/minuto e refresh 30/minuto.

Também há cinco rotas privadas de importação OFX Nubank: criar e consultar
prévia, vincular conta, confirmar e cancelar. O arquivo é limitado a 10 MiB,
descartado após normalização e só cria lançamentos depois da confirmação. Veja
[a documentação de importação](docs/imports-and-sync.md). A consulta da prévia
aceita `after` e `limit` e devolve os itens por página com `next_cursor`. O
cliente Flutter importa por essas rotas e nunca chama `/sync/push/`.

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

O cliente fica em `mobile/`. Flutter 3.47.0 está fixado em
`mobile/tool/flutter-version.json`:

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=LAR_FINANCE_API_BASE_URL=https://seu-host/api/v1
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

O contrato de release usa a tag GHCR versionada/controlada
`ghcr.io/ludsonfrancisco/finanpy:sha-<sha Git de 40 caracteres>` e registra o
digest OCI observado; tags de registry não são tratadas como imutáveis. O health
`GET /api/v1/health/` retorna exatamente `status`, `api_version` e `version`; em
imagem de release, `version` deve ser o mesmo SHA da tag.

As evidências têm fronteiras distintas:

- localmente, a matriz, o fail-fast em SQLite descartável e um fallback de
  restauração local passaram em 21/08/2026;
- a CI `32529705321`, no SHA
  `2584fa7db5e9ee9fa158cdfce54d3b2b24ef4a9d`, construiu a imagem e confirmou
  health com SHA e os três processos do Supervisor;
- a publicação da tag GHCR foi pulada por ser um push de branch, e a imagem
  candidata ainda não foi implantada nem validada no EasyPanel.

A produção anteriormente validada mantém backup R2 diário, uma réplica, um
worker Gunicorn e dois schedulers supervisionados: backup R2 e purge de prévias
OFX. R1.4 continua em andamento; a Task 7 precisa publicar a tag, resolver o
digest OCI, ensaiar a imagem candidata e o rollback com R2 no ambiente correto e
validar o EasyPanel antes do aceite. Consulte a
[auditoria do ensaio](docs/audits/2026-08-21-fail-fast-deploy-rehearsal.md).
