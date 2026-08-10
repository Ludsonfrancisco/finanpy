# Lar Finance

Aplicação web privada para consolidar as finanças de um único Lar. O nome técnico
legado Finanpy ainda aparece em módulos e caminhos durante a modernização
incremental.

Não existe cadastro público. Usuários são criados por administração, e o Lar é a
fronteira de segurança dos dados. Contas, categorias e movimentações pertencem ao
Lar; “Eu”, “Esposa” e “Conjunto” classificam a responsabilidade financeira. O
painel soma os três responsáveis.

## Stack

- Python 3.12 e Django 5.2.13
- SQLite em arquivo persistente
- Django Templates e TailwindCSS via CDN
- Gunicorn 23.0.0 com um worker

As versões completas estão fixadas em `requirements.txt`.

## Acesso privado e criação do Lar

Crie o primeiro usuário administrativamente:

```bash
python manage.py createsuperuser
```

Depois, garanta de forma idempotente o Lar, a associação ativa e os três
responsáveis. Substitua `SEU_EMAIL` pelo login privado:

```bash
python manage.py shell -c "from django.contrib.auth import get_user_model; from households.services import ensure_household_for_user; user = get_user_model().objects.get(email='SEU_EMAIL'); household = ensure_household_for_user(user); print(household.uuid)"
```

## Configuração

Copie `.env.example` para `.env` e substitua todos os valores de exemplo. A
`SECRET_KEY` é obrigatória e nunca deve ser reutilizada ou commitada.

Em Docker e no EasyPanel, o banco deve usar caminho absoluto:

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

O projeto usa uma réplica e um worker porque SQLite não é adequado para múltiplos
workers escrevendo no mesmo arquivo. Para produção no servidor caseiro, siga o
[runbook do EasyPanel](docs/deploy-easypanel.md).

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

Crie o backup em um destino persistente e depois retire uma cópia criptografada
do servidor:

```bash
python manage.py backup_sqlite --output /app/data/backups/lar-finance.sqlite3
python manage.py audit_household_integrity
```

O backup usa a API do SQLite e só conclui após `PRAGMA integrity_check`. O
comando de auditoria é somente leitura, imprime apenas contagens e retorna erro
quando encontra inconsistências.

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
bloqueada até:

- a credencial histórica ser rotacionada pelo proprietário;
- o runbook ser validado em uma cópia/ensaio no EasyPanel real;
- existir backup externo restaurável antes das migrations.

Não foi executada nenhuma alteração no servidor ou na base real durante esta
sprint.
