# Lar Finance — Plano de estabilização pós-auditoria

Data: 10 de agosto de 2026.

## Objetivo

Resolver os bloqueadores encontrados na revisão transversal da branch antes de qualquer integração com `main` ou implantação no EasyPanel. O trabalho permanece incremental: nenhuma reescrita total, nenhuma alteração visual e nenhuma API Flutter nesta etapa.

## Regras de execução

- Cada task começa por testes que reproduzem o risco.
- Cada task recebe revisão independente antes do push.
- Cada task termina com commit, push e confirmação `0 0` entre local e GitHub.
- Nenhum banco real será migrado nesta etapa; migrations serão ensaiadas em cópias sintéticas representativas.
- Migrations registradas nunca terão linhas de `django_migrations` apagadas ou falsificadas.
- O histórico Git não será reescrito sem autorização explícita.

## Task 7 — Revogação de acesso e filtros do Lar

- [ ] Trocar o contexto de requisição para `get_household_for_user()` e negar com HTTP 403 quando Lar ou associação estiver inativo.
- [ ] Provar que uma requisição não reativa Lar, associação ou responsável.
- [ ] Reservar `ensure_household_for_user()` ao bootstrap administrativo explícito e restaurar os três responsáveis ativos nesse bootstrap.
- [ ] Preencher filtros de conta e categoria da tela de movimentações pela view, sempre pelo Lar.
- [ ] Testar inclusão de dados do mesmo Lar e exclusão de outro Lar nos filtros.
- [ ] Fortalecer testes de fronteira com `error_dict` e caminhos válidos de `full_clean()`.
- [ ] Rodar suíte completa, Ruff, checks, review, commit e push.

## Task 8 — Backfill e histórico de associações

- [ ] Restaurar `households/0001_initial.py` ao conteúdo canônico publicado em `ebe4458` (`UNIQUE(household, user)`).
- [ ] Adicionar ao backfill preflight de inconsistências legadas entre movimentação, conta e categoria, sempre antes de qualquer escrita e somente com contagens técnicas.
- [ ] Criar `households.0003_reconcile_membership_uniqueness`, sem manipular `django_migrations`.
- [ ] Garantir `UNIQUE(household, user)` e `UNIQUE(user) WHERE is_active`, preservando associações inativas.
- [ ] Cobrir banco novo, schema físico original e schema físico reescrito; preservar PKs, FKs, papéis e timestamps.
- [ ] Provar aborto atômico em duplicidade ativa e em cada inconsistência legada.
- [ ] Ajustar bootstrap: usar associação ativa; não escolher silenciosamente entre várias inativas.
- [ ] Rodar round-trip, integridade SQLite, suíte completa, review, commit e push.

## Task 9 — Consistência dos vínculos legados

- [ ] Validar que o `user` legado de conta, categoria e movimentação possui associação ativa no Lar selecionado.
- [ ] Manter compartilhamento entre membros do mesmo Lar sem exigir que conta, categoria e movimentação tenham o mesmo `user`.
- [ ] Trocar `on_delete=CASCADE` dos três vínculos legados de usuário por `PROTECT` e gerar migrations forward-only.
- [ ] Criar comando somente leitura para auditar associações, responsáveis e relações financeiras entre Lares.
- [ ] Testar exclusão protegida, combinações válidas entre membros e todas as inconsistências reportadas.
- [ ] Documentar a semântica de edição do responsável financeiro.
- [ ] Rodar suíte completa, review, commit e push.

## Task 10 — Segurança operacional e documentação

- [ ] Tornar `check --deploy` bloqueante no CI com chave de teste adequada e `--fail-level WARNING`.
- [ ] Remover capturas de QA rastreadas e ignorar novas capturas; não reescrever histórico.
- [ ] Atualizar `CLAUDE.md`, arquitetura, setup, README e documentação da sprint para acesso privado, fronteira por Lar e `SQLITE_PATH` absoluto.
- [ ] Criar runbook EasyPanel: volume persistente, `/app/data/db.sqlite3`, uma réplica/worker, backup externo, auditoria, migrate e rollback.
- [ ] Registrar como bloqueio de produção a rotação da credencial histórica e a validação real no EasyPanel.
- [ ] Adicionar recomendação de rate limit do login no proxy/EasyPanel.
- [ ] Rodar verificação completa, cobertura mínima de 90%, review, commit e push.

## Critério final

A branch só estará pronta para integração quando não houver achado Critical ou Important na revisão transversal repetida, todos os testes passarem, a cobertura permanecer acima de 90% e o remoto estiver sincronizado em `0 0`. A implantação continuará bloqueada até rotação da credencial histórica e validação do runbook no EasyPanel.
