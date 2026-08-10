# Lar Finance — documentação

O projeto público chama-se **Lar Finance**. O repositório e os módulos ainda
usam o nome técnico legado **Finanpy** durante a migração incremental.

## Fonte de verdade

- [PRD](../PRD.md): estado atual, produto alvo, riscos e decisões.
- [Roadmap](ROADMAP.md): sprints, tarefas, critérios de aceite e riscos.
- [Sprint 1 — Household Ledger](sprints/sprint-1-household-ledger.md): entrega
  concluída e suas evidências.
- [Sprint 2 — API privada e sincronização](sprints/sprint-2-api-sync.md):
  candidato de handoff e evidências; conclusão depende da revisão final.

## Produto e engenharia

- [Arquitetura](architecture.md): estado atual, direção alvo e limites.
- [Modelo de dados](data-model.md): entidades atuais e alvo.
- [Importação e sincronização](imports-and-sync.md): arquivos, deduplicação,
  conciliação, offline e provedor futuro.
- [UX mobile/desktop](mobile-ux.md): jornadas, telas, estados e acessibilidade.
- [Direção visual](design-system.md): critérios firmes e gate visual pendente.
- [Segurança e operação](security-and-operations.md): ameaças, backup,
  EasyPanel, observabilidade e privacidade.
- [Runbook EasyPanel](deploy-easypanel.md): implantação, backup e rollback.
- [Setup atual](setup.md): execução do backend Django.
- [Padrões de código](coding-standards.md): convenções de implementação.

## Planos por fase

- [Fundação](superpowers/plans/2026-08-09-lar-finance-foundation.md)
- [Importação e cartões](superpowers/plans/2026-08-09-lar-finance-imports-cards.md)
- [Cliente Flutter](superpowers/plans/2026-08-09-lar-finance-flutter-client.md)
- [Planejamento e patrimônio](superpowers/plans/2026-08-09-lar-finance-planning-wealth.md)
- [Operação e distribuição](superpowers/plans/2026-08-09-lar-finance-operations-release.md)

O provedor automático é opcional e só será avaliado depois da validação da
importação manual, do custo, de dois CPFs e da cobertura das instituições.

## Regras documentais

- `[INVESTIGAR]` indica ausência de evidência suficiente.
- Versões só são exatas quando pinadas ou comprovadas.
- Mudança de arquitetura exige ADR.
- O design final depende de aprovação explícita do gate visual.
- Segredos, CPF, email privado, valores e payload bancário não entram nos docs.
