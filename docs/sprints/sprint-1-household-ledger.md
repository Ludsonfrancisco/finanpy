# Sprint 1 — Household Ledger

Data de fechamento: 10 de agosto de 2026.

## Resultado

O Lar passou a ser a fronteira de autorização, consulta e consolidação. Cada Lar
possui os responsáveis “Eu”, “Esposa” e “Conjunto”. O dashboard permanece
consolidado, enquanto contas e movimentações guardam o responsável financeiro.

A sprint também endureceu o legado:

- acesso revogado falha fechado;
- histórico de memberships é preservado;
- schemas SQLite divergentes são reconciliados por migration;
- FKs legadas de usuário usam `PROTECT`;
- uma auditoria somente leitura detecta inconsistências sem imprimir PII;
- erros legados aparecem no formulário sem HTTP 500;
- CI e operação são tratados como gates de segurança.

## Commits por etapa

### Construção inicial

- Task 1: `ebe4458`, `313583a`, `1c56cda`, `713c1f6`.
- Task 2: `c4e94df`.
- Task 3: `c129020`, `3c42758`.
- Task 4: `8c149d7`.
- Task 5: `4401ced`, `e73440f`.
- Task 6: `12f240b`.

### Hardening

- Task 7: `8c13fdb` — revogação e filtros por Lar.
- Task 8: `f0a95e9` — histórico e reconciliação de memberships.
- Task 9: `12a5fe3`, `0d2b132`, `b033c8d` — integridade, auditoria e
  regressões legadas.
- Task 10: segurança operacional, privacidade dos artefatos e runbook EasyPanel
  neste fechamento.

O histórico Git é a fonte exata dos hashes completos.

## Migrações e compatibilidade

`households.0003_reconcile_membership_uniqueness` reconhece os schemas físicos
legados suportados e converge para:

- unicidade do par `(household, user)`;
- histórico inativo permitido;
- no máximo uma membership ativa por usuário.

As migrations `0004_protect_legacy_user` de contas, categorias e transações
preservam o livro financeiro quando a exclusão de um usuário é tentada. No
SQLite, a alteração de `on_delete` é um no-op de DDL esperado, pois a regra é
aplicada pelo ORM.

Preflights abortam antes de alteração quando encontram dados incompatíveis.
Nenhuma migration deve ser executada na base real sem backup verificado, cópia
externa e ensaio em restauração descartável.

## Auditoria

```bash
python manage.py audit_household_integrity
```

O comando é somente leitura e informa apenas contagens. Ele verifica:

- memberships duplicadas e múltiplas memberships ativas;
- ausência/inatividade de `self`, `spouse` e `shared`;
- usuários legados sem membership ativa no mesmo Lar;
- conta, categoria ou responsável divergente do Lar da movimentação.

Qualquer contagem inconsistente encerra com erro.

## Verificação final

- Suíte: 151 testes aprovados.
- Cobertura: 98% (2.664 statements, 41 não cobertos), acima do mínimo de 90%.
- Ruff: aprovado com a configuração do projeto.
- Django check e drift de migrations: aprovados, sem alterações pendentes.
- Check de deploy estrito: aprovado com `--fail-level WARNING` e ambiente CI.
- Revisão independente: aprovada sem achados críticos, importantes ou menores.
- Sincronização remota: confirmar `0 0` após o push desta task.

## Rollback operacional

O ensaio sintético antigo de downgrade não representa sozinho o grafo completo
atual. Em produção, o rollback prioritário é:

1. interromper escrita;
2. reimplantar uma imagem compatível;
3. restaurar o backup SQLite verificado;
4. executar a auditoria;
5. liberar tráfego somente após smoke checks.

Downgrade de migrations só pode ser usado depois de ensaio do mesmo grafo e da
mesma cópia de banco. Consulte `docs/deploy-easypanel.md`.

## Bloqueios de produção

Mesmo com a branch aprovada, o deploy permanece bloqueado até:

- o proprietário rotacionar a credencial histórica;
- o runbook ser validado no EasyPanel real;
- um backup externo ser restaurado com sucesso em ensaio;
- volume `/app/data`, uma réplica/worker, TLS e rate limit de login serem
  confirmados.

Nenhum dado real ou servidor EasyPanel foi alterado nesta sprint.

## Próximo passo

Após integração segura da branch, planejar a API versionada que atenderá o
Flutter para Windows, iOS e Android. O design system será decidido com o
proprietário antes de qualquer redesenho visual.
