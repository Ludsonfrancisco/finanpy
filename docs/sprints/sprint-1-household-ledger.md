# Sprint 1 — Household Ledger

Data da verificação: 10 de agosto de 2026.

## Resultado

O Lar passou a ser a fronteira principal das consultas e relações financeiras. Cada Lar possui os responsáveis “Eu” (`self`), “Esposa” (`spouse`) e “Conjunto” (`shared`), enquanto o painel permanece consolidado entre os três.

O fechamento local foi verificado e está contido no commit `docs: close household ledger sprint`. O push deste commit não faz parte deste ensaio; antes da Task 6, a branch local e `origin/codex/sprint-1-household-ledger` estavam sincronizadas em `e73440f04ef4030d12d6e547e18c66905fbb0c47` (`0 0`).

## Commits por task

- Task 1:
  - `ebe4458b001dc753101c40c06e45b8b044628f20` — `feat: add household ownership core`;
  - `313583a1f9e3b77a20f6e67226c0cda93378d4a2` — `fix: serialize household initialization`;
  - `1c56cdacaeebb536c2f935f9c30f324f3c5f26d7` — `fix: handle household bootstrap lifecycle`;
  - `713c1f65b2eb754fd41791051de7c1d8fa49d475` — `fix: limit SQLite deployment workers`.
- Task 2: `c4e94dfdb8aecdc1f0da417ccd1c48a635f0b747` — `feat: add household boundaries to ledger`.
- Task 3:
  - `c129020c9b184686c65f20a0132483ef799e441e` — `feat: backfill legacy data into household`;
  - `3c42758cd0163c6e54b3e91d964be4de91444b05` — `fix: reject hybrid household backfill state`.
- Task 4: `8c149d74e5a42e81859c546c207a9f2ebc0096cf` — `feat: scope web ledger by household`.
- Task 5:
  - `4401ced4ca1228dea1d536f6e5a5941d766500d3` — `feat: require household ownership links`;
  - `e73440f04ef4030d12d6e547e18c66905fbb0c47` — `fix: guard category migration rollback`.
- Task 6: o commit que contém este documento, com a mensagem `docs: close household ledger sprint`; o hash final fica registrado no relatório local da task após a criação do commit.

## Banco e backup de ensaio

O `db.sqlite3` deste worktree tinha 0 bytes e nenhuma tabela. Ele não continha uma instalação migrada que pudesse representar os dados legados e não foi alterado.

Para evitar qualquer contato com dados reais, foi criada a base descartável e ignorada pelo Git `data/task-6-synthetic-legacy.sqlite3`. Ela foi levada ao estado anterior ao backfill (`households.0001` e migrations opcionais `0002` do ledger) e recebeu somente dados sintéticos: 1 usuário, 1 conta, 1 categoria e 1 movimentação. Os cinco novos vínculos estavam nulos, como em um banco legado.

O comando `manage.py backup_sqlite` criou `backups/sprint-1-before-migrations.sqlite3` e retornou `Backup verified`. No instante da criação, a cópia passou por `PRAGMA integrity_check` com resultado `ok`, preservou as quatro contagens e teve SHA-256 `80443B7A5002805757A24FF2626385F358FCB4FB01E2F72BA00A762C8B41D795`. `data/`, `backups/` e `db.sqlite3` permanecem ignorados pelo Git.

## Ensaio de upgrade, rollback e novo upgrade

Todo o ciclo abaixo ocorreu em `backups/sprint-1-before-migrations.sqlite3`:

| Etapa | Resultado |
| --- | --- |
| Primeiro upgrade | Aplicou `households.0002` e as migrations `0003` de contas, categorias e movimentações sem erro. Criou 1 Lar, 1 associação e 3 responsáveis. |
| Auditoria após upgrade | Preservou 1 conta, 1 categoria e 1 movimentação. Conta e movimentação ficaram com `shared` (“Conjunto”); todos os registros apontaram para o mesmo Lar e não houve órfãos. |
| Rollback para `households.0001` | Reverteu primeiro as três migrations `0003` e depois o backfill. Removeu Lar, associação e responsáveis, restaurou os cinco vínculos a `NULL` e preservou as três linhas do ledger. |
| Segundo upgrade | Reaplicou as quatro migrations sem erro. `PRAGMA integrity_check` retornou `ok`; os três tipos de responsável voltaram a existir e todas as contagens e valores sintéticos foram preservados. |

A auditoria final encontrou zero contas sem Lar, zero contas sem responsável, zero categorias sem Lar, zero movimentações sem Lar e zero movimentações sem responsável. Isso comprova, na base representativa, que os registros legados são atribuídos a “Conjunto”. Nenhum dado real do usuário foi inspecionado ou migrado neste worktree.

## Verificação final

- Ruff: `All checks passed!`.
- Django check: nenhum problema identificado.
- Drift de migrations: `No changes detected`.
- Suíte completa: 108 testes, todos aprovados em 49,427 segundos.
- Cobertura: 98% (1.846 statements, 42 não cobertos), acima do mínimo de 90%.
- `git diff --check`: sem erros de whitespace.
- `manage.py check --deploy`, com configuração equivalente à produção: nenhum problema identificado.
- Busca nas views financeiras: nenhuma query web usa `User` sozinho como fronteira; o escopo obrigatório é o Lar.

## Rollback operacional

Antes de qualquer migration em uma instalação real, criar e retirar do servidor um backup SQLite verificado. Para voltar ao estado anterior ao backfill, apontar `SQLITE_PATH` para uma cópia restaurável e executar `python manage.py migrate households 0001`. O ensaio confirmou que essa volta preserva contas, categorias e movimentações e limpa apenas os vínculos criados pela sprint. Bancos híbridos ou categorias incompatíveis com a unicidade legada abortam deliberadamente e exigem reconciliação antes de nova tentativa.

## Riscos restantes e próximo passo

- Trocar a senha antiga antes da publicação.
- Avaliar a limpeza opcional do histórico Git se ainda houver material sensível em commits antigos.
- Validar backup, migrations, variáveis seguras e operação com um worker no EasyPanel; este ensaio sintético não substitui a validação no ambiente real.
- Publicar o commit local de fechamento quando autorizado; até lá, o remoto permanece sem a documentação da Task 6.
- Em seguida, vincular UUID/versão e preparar a API. Nenhum trabalho de API ou design visual foi iniciado nesta sprint.
