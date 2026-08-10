# Lar Finance — documentação

O projeto público chama-se **Lar Finance**. O repositório e módulos ainda usam o nome técnico legado **Finanpy** durante a migração incremental.

## Fonte de verdade

- [PRD](../PRD.md): estado atual, produto alvo, riscos e decisões.
- [Roadmap](ROADMAP.md): sprints, tarefas, critérios de aceite e riscos.

## Produto e engenharia

- [Arquitetura](architecture.md): as-is, to-be, limites e migração.
- [Modelo de dados](data-model.md): entidades atuais e alvo.
- [Importação e sincronização](imports-and-sync.md): arquivos, deduplicação, conciliação, offline e provedor futuro.
- [UX mobile/desktop](mobile-ux.md): jornadas, telas, estados, permissões e acessibilidade.
- [Direção visual](design-system.md): critérios firmes e design system ainda em investigação.
- [Segurança e operação](security-and-operations.md): ameaças, backup, EasyPanel, observabilidade e privacidade.
- [Setup atual](setup.md): execução do backend Django existente.
- [Padrões de código](coding-standards.md): convenções de implementação.

## Planos executáveis

- [Fundação Lar Finance](superpowers/plans/2026-08-09-lar-finance-foundation.md): segurança, household/owners, API e sync base.
- [Importação e cartões](superpowers/plans/2026-08-09-lar-finance-imports-cards.md): OFX/CSV, deduplicação, faturas e parcelas.
- [Cliente Flutter](superpowers/plans/2026-08-09-lar-finance-flutter-client.md): offline, sync, telas diárias e plataformas.
- [Planejamento e patrimônio](superpowers/plans/2026-08-09-lar-finance-planning-wealth.md): orçamento, dívidas, investimentos e relatórios.
- [Operação e distribuição](superpowers/plans/2026-08-09-lar-finance-operations-release.md): PostgreSQL, EasyPanel, backup e releases.

O provedor automático é um gate opcional dentro do plano de operação e só começa depois da validação de custo, dois CPFs e cobertura.

## Regras documentais

- `[INVESTIGAR]` significa que o código/dado disponível não sustenta uma conclusão.
- Versões só são declaradas como exatas quando estão pinadas ou comprovadas.
- Mudança de arquitetura exige ADR.
- Decisão de design exige atualização do gate em `design-system.md`.
- Segredos, valores reais, CPF, email privado e payload bancário não entram na documentação.
