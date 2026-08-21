# GEMINI.md — Lar Finance

Este arquivo complementa, mas não substitui, `CLAUDE.md`. Em caso de
divergência, use nesta ordem:

1. código e migrations;
2. `CLAUDE.md`;
3. `PRD.md` e `docs/ROADMAP.md`;
4. documentação histórica de sprint.

## Estado atual

Lar Finance é uma beta pessoal privada em Django 5.2.13 com clientes Web e
Flutter para Windows, Android e iOS. O nome técnico Finanpy permanece em alguns
caminhos. Não há cadastro público.

O domínio atual inclui Lar/owners, contas, categorias, movimentações,
importação OFX, cartões/faturas, contas fixas, orçamento e relatórios. A API usa
sessões revogáveis por dispositivo. SQLite no EasyPanel é suportado com uma
réplica e um worker; R2 fornece backup off-host.

## Fronteiras obrigatórias

- Household é a fronteira de autorização e consulta.
- FinancialOwner classifica `Eu`, `Esposa` e `Conjunto`; não autoriza acesso.
- Views financeiras usam `HouseholdContextMixin` e validam relações no mesmo
  Lar.
- Sync central cobre Account, Category e Transaction.
- Cartões e contas fixas usam API direta e não possuem a mesma garantia offline.
- Dinheiro usa Decimal no Django e minor units/tipo decimal exato no Flutter;
  não introduza novos valores monetários em `double`.

## Design

Web e Flutter seguem [Casa de Valores 2.0](docs/design-system.md): mesma
identidade, tokens, hierarquia, nomes e estados, com composição adaptada por
plataforma. Preservar cards, indicadores e gráficos úteis da Web, junto ao tema
de sistema, tokens, precisão e shell adaptativo do Flutter. Nunca usar roxo.

## Trabalho atual

O roadmap ativo é o fechamento R1–R5 em `docs/ROADMAP.md`. PostgreSQL, Open
Finance, empréstimos, investimentos e lojas públicas não bloqueiam a V1 pessoal.
Não reconstruir recursos já existentes com base em planos históricos.

Toda task exige escopo fechado, testes quando aplicável, Ruff/format/checks,
revisão, commit e push. Parar antes da próxima task/sprint até autorização do
proprietário.
