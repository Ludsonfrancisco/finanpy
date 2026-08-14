# Lar Finance — documentação

O projeto público chama-se **Lar Finance**. O repositório e os módulos ainda
usam o nome técnico legado **Finanpy** durante a migração incremental.

## Fonte de verdade

- [PRD](../PRD.md): estado atual, produto alvo, riscos e decisões.
- [Roadmap](ROADMAP.md): sprints, tarefas, critérios de aceite e riscos.
- [Sprint 1 — Household Ledger](sprints/sprint-1-household-ledger.md): entrega
  concluída e suas evidências.
- [Sprint 2 — API privada e sincronização](sprints/sprint-2-api-sync.md):
  entrega concluída, evidências e bloqueios operacionais restantes.
- [Sprint 3 — Importação OFX Nubank](sprints/sprint-3-ofx-import.md): piloto
  manual entregue, com escopo, rollback e riscos explícitos.
- [Sprint 4 — Fundação Flutter e Casa de Valores](superpowers/specs/2026-08-13-lar-finance-flutter-foundation-design.md):
  direção aprovada, escopo, arquitetura adaptativa e critérios de aceite.
- [Backup automático no R2](sprints/automatic-r2-backup.md): configuração,
  operação, interpretação de resultados, restauração e rollback.

## Produto e engenharia

- [Arquitetura](architecture.md): estado atual, direção alvo e limites.
- [Modelo de dados](data-model.md): entidades atuais e alvo.
- [Importação e sincronização](imports-and-sync.md): arquivos, deduplicação,
  conciliação, offline e provedor futuro.
- [UX mobile/desktop](mobile-ux.md): jornadas, telas, estados e acessibilidade.
- [Direção visual](design-system.md): Casa de Valores aprovada e validações de tokens pendentes.
- [Segurança e operação](security-and-operations.md): ameaças, backup,
  EasyPanel, observabilidade e privacidade.
- [Runbook EasyPanel](deploy-easypanel.md): implantação, backup e rollback.
- [Setup atual](setup.md): execução do backend Django.
- [Padrões de código](coding-standards.md): convenções de implementação.
- [Roteamento de modelos](ai-model-routing.md): escolha proporcional de modelo e
  intensidade, templates de routing e auditoria entre tarefas e sprints.
- [Auditoria das branches remotas](audits/2026-08-12-remote-branches.md): análise
  read-only, riscos e decisão de não mesclar as três linhas legadas.
- [Ensaio de backup/restauração](audits/2026-08-12-backup-restore-rehearsal.md):
  prova sintética isolada e seus limites antes do ensaio real.
- [Backup real off-host e restauração](audits/2026-08-12-production-backup-restore.md):
  evidência sanitizada do SQLite real no R2 e do ensaio descartável aprovado.
- [Rotação da credencial histórica](audits/2026-08-12-credential-rotation.md):
  evidências sanitizadas da troca no EasyPanel e da revogação de sessões.

## Planos por fase

- [Fundação](superpowers/plans/2026-08-09-lar-finance-foundation.md)
- [Importação e cartões](superpowers/plans/2026-08-09-lar-finance-imports-cards.md)
- [Cliente Flutter](superpowers/plans/2026-08-09-lar-finance-flutter-client.md)
- [Sprint 4 — Fundação Flutter Casa de Valores](superpowers/plans/2026-08-13-lar-finance-flutter-foundation-implementation.md)
- [Planejamento e patrimônio](superpowers/plans/2026-08-09-lar-finance-planning-wealth.md)
- [Operação e distribuição](superpowers/plans/2026-08-09-lar-finance-operations-release.md)

O provedor automático é opcional e só será avaliado depois da validação da
importação manual, do custo, de dois CPFs e da cobertura das instituições.

## Regras documentais

- `[INVESTIGAR]` indica ausência de evidência suficiente.
- Versões só são exatas quando pinadas ou comprovadas.
- Mudança de arquitetura exige ADR.
- Mudanças na direção Casa de Valores dependem de nova aprovação explícita.
- Segredos, CPF, email privado, valores e payload bancário não entram nos docs.
