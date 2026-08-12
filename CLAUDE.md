# CLAUDE.md

Orientações para agentes que trabalham neste repositório.

## Comandos

```bash
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
python manage.py test
ruff check . --config pyproject.toml
python manage.py check
python manage.py makemigrations --check
```

`SECRET_KEY` é obrigatória. Configure o ambiente antes de qualquer comando
Django. Em Docker/EasyPanel, use `SQLITE_PATH=/app/data/db.sqlite3`.

## Arquitetura

Lar Finance é um monólito Django 5.2.13 de finanças domésticas. O acesso é
privado: não há cadastro público. O login usa e-mail por meio do modelo
`users.User`.

| App | Responsabilidade |
|---|---|
| `core` | settings, URLs raiz, dashboard, backup e comandos globais |
| `users` | usuário customizado, login e logout |
| `profiles` | perfil 1:1 do usuário |
| `households` | Lar, memberships, responsáveis, bootstrap e auditoria |
| `accounts` | contas financeiras do Lar |
| `categories` | categorias de receita e despesa do Lar |
| `transactions` | movimentações vinculadas a conta, categoria e responsável |
| `ai` | app instalado sem fluxo financeiro ativo documentado [INVESTIGAR] |

## Fronteira de dados

O `Household` é a fronteira obrigatória de leitura e escrita. Uma
`HouseholdMembership` ativa autoriza o acesso. `FinancialOwner` classifica
`self`, `spouse` e `shared`; ele não substitui autorização.

Todas as views financeiras autenticadas devem:

1. usar `HouseholdContextMixin`;
2. filtrar por `self.household`;
3. nunca confiar apenas em `request.user` como fronteira;
4. validar que conta, categoria e responsável pertencem ao mesmo Lar;
5. preservar `financial_owner` de uma transação durante edição, salvo uma
   mudança explícita de produto.

As FKs legadas `user` permanecem para rastreabilidade e usam `PROTECT`.

## Migrações e integridade

- Não reescreva migrations aplicadas.
- Execute `python manage.py audit_household_integrity` antes e depois de
  migrations na cópia de ensaio e no deploy controlado.
- SQLite exige uma réplica e um worker Gunicorn.
- Antes de migrations reais, crie backup verificado e retire uma cópia do host.
- Rollback operacional prioriza imagem compatível + restauração do backup.

## Convenções

- Python em inglês, interface em pt-BR, strings Python com aspas simples.
- Views baseadas em classes.
- Templates herdam layouts compartilhados.
- Erros de modelos referentes a campos omitidos do ModelForm devem aparecer
  como erros gerais, nunca provocar HTTP 500.
- Novas mudanças precisam de testes, Ruff, Django check, migrations check e
  revisão antes de commit/push.
- A composição de cada sprint e tarefa segue
  `docs/ai-model-routing.md`: inventário confirmado, routing curto antes da
  execução, escalonamento por evidência e auditoria ao concluir.
- Nunca inventar disponibilidade, preço ou tokens de modelos. Revalidar opções
  no ambiente ativo antes de montar o plano da sprint.

## Produção

- `SECRET_KEY` somente por ambiente, única e longa.
- `SQLITE_PATH` absoluto em volume persistente.
- TLS termina no proxy; configure os flags seguros documentados no runbook.
- Uma réplica, um worker e migrations controladas.
- Rate limit de `POST /login/` no proxy/EasyPanel.
- Credencial histórica rotacionada no EasyPanel em 2026-08-12; não reproduzir ou
  reutilizar o valor antigo ainda presente no histórico Git.
- Backup real off-host restaurado com sucesso em 2026-08-12; evidência sanitizada
  em `docs/audits/2026-08-12-production-backup-restore.md`.
- Implantação ainda bloqueada até validar imagem/migrations, persistência após
  restart, proxy, rate limit e smoke checks no EasyPanel real.

Consulte `docs/architecture.md`, `docs/setup.md` e
`docs/deploy-easypanel.md`.
