# Task 7 — Revogação de acesso e filtros do Lar

## Escopo e hashes

- Worktree: `C:\Users\ludso\Documents\projects\finanpy-sprint0`.
- Branch: `codex/sprint-1-household-ledger`.
- Base: `0147abf169104c630094b316a28b1fff155cd62b`.
- Commit único planejado: `fix: enforce revoked household access`.
- O SHA final do commit é registrado no handoff externo: este relatório integra o próprio
  commit e não pode conter o seu SHA sem alterar esse SHA.
- Nenhum push foi realizado.

## Vermelho

A primeira tentativa de execução não chegou aos testes porque `SECRET_KEY` não estava
definida. Ela foi repetida com ambiente local de teste (`DEBUG=True` e
`SECURE_SSL_REDIRECT=False`) e então reproduziu o risco esperado:

```text
Found 27 test(s).
FAILED (failures=4, errors=1)
```

Falhas observadas antes da implementação:

- Lar e associação inativos eram reativados pelo request e o GET retornava 200;
- nenhum aviso técnico era emitido na negação;
- owners existentes permaneciam inativos e com nomes não canônicos no bootstrap;
- a view não fornecia `filter_accounts`/`filter_categories` e o template excluía dados de
  outro membro ativo do mesmo Lar.

## Verde

- O request path usa somente `get_household_for_user()` e converte a ausência de Lar ou
  associação ativa em `PermissionDenied` (HTTP 403).
- O aviso técnico é genérico e os testes confirmam ausência de e-mail e nome do Lar.
- Nenhuma requisição reativa Lar, associação ou responsável.
- `LoginRequiredMixin` continua antes de `HouseholdContextMixin`; acesso anônimo redireciona
  para login sem bootstrap.
- O bootstrap administrativo explícito cria owners ausentes e restaura atividade e nomes
  canônicos (`Eu`, `Esposa`, `Conjunto`).
- A lista de movimentações fornece filtros de conta e categoria limitados ao Lar; o template
  usa apenas essas listas, sem mudança visual.
- Os testes usam uma movimentação externa real e requisições independentes para IDs de
  conta e categoria estrangeiros, provando que nenhum deles amplia ou revela resultados.
- Os testes de fronteira verificam `ValidationError.error_dict` por campo e executam
  `full_clean()` válido diretamente para Account e Transaction no mesmo Lar.

O ciclo verde inicial retornou:

```text
Found 27 test(s).
Ran 27 tests in 14.633s
OK
```

Depois do reforço solicitado pela revisão independente:

```text
Found 28 test(s).
Ran 28 tests in 15.350s
OK
```

## Arquivos

- `households/mixins.py`: resolução fail-closed e aviso sem dados pessoais/financeiros.
- `households/services.py`: restauração canônica dos três owners no bootstrap explícito.
- `transactions/views.py`: listas de filtro por Lar.
- `templates/transactions/list.html`: consumo exclusivo das listas da view, sem alteração
  visual.
- `households/tests/test_access.py`: revogação, 403, não reativação, log seguro e login.
- `households/tests/test_models.py`: reparo explícito de owners inativos/ausentes.
- `households/tests/test_boundaries.py`: erros por campo e caminhos válidos de `full_clean()`.
- `transactions/tests.py`: filtros multi-membro e isolamento de IDs estrangeiros.
- `core/tests.py`: fixture do contrato privado atualizada com bootstrap explícito.

## Testes e verificações

| Verificação | Resultado |
| --- | --- |
| `manage.py test households transactions accounts core` | 93 testes, OK |
| `manage.py test` | 117 testes, OK |
| `ruff check . --config pyproject.toml` | `All checks passed!` |
| `manage.py check` | nenhum problema |
| `manage.py makemigrations --check` | nenhuma mudança detectada |
| `git diff --check` | nenhum erro de whitespace |

## Revisão independente

A primeira revisão encontrou zero Critical e um Important: os IDs estrangeiros de conta e
categoria estavam combinados na mesma requisição de teste. A prova foi separada e passou a
criar uma movimentação externa real. A nova revisão retornou zero Critical e zero Important.
O Minor de arquivo de teste ainda não rastreado é resolvido pela inclusão no commit único.
