# R3.3.1 — Sincronização, dados e baseline visual

**Data:** 22/08/2026

**Privacidade:** o repositório é público. Nenhuma captura real, valor, conta,
token, sessão ou identificador privado é versionado.

## Causa confirmada no código para a data antiga da tela Mais

`MoreScreen` lia apenas `AuthState.lastSyncAt`, carregado durante autenticação ou
restauração de sessão. Sincronizações normais atualizavam `SyncState` e Drift,
mas não esse snapshot de autenticação. A Home já observava o estado vivo; a tela
Mais não. A Task 1 conecta a tela Mais ao mesmo `LedgerSyncCoordinator.state`.

Isso explica a data visualmente congelada, mas a validação no Windows ainda deve
provar uma sincronização real após instalar o artefato exato.

## Matriz de disponibilidade

| Indicador Web | Fonte Web | Flutter atual | Estado para R3.3 |
|---|---|---|---|
| saldo total | `DashboardView.total_balance` | `HomeSnapshot.balanceMinor` via Drift | disponível offline |
| saldo livre real | `bills_metrics.free_cash_balance` | `BillsMetricsModel.freeCashBalanceMinor` | disponível online; ainda não composto na Home |
| compromissos pendentes | `pending_bills_total` | `BillsMetricsModel.pendingExpensesTotalMinor` | disponível online; `HomeSnapshot.upcomingCommitmentMinor` não é semanticamente idêntico |
| vencidos | `overdue_bills_count` | `BillsMetricsModel.overdueCount` | disponível online |
| receitas, despesas, líquido e poupança | agregados mensais | `ReportsSummary` | disponível offline pelo ledger |
| fluxo de seis meses | `monthly_flows` | `ReportsSummary.monthlyFlows` | disponível offline pelo ledger |
| distribuição e maiores gastos | `expenses_by_category` | `categoryDistributions`, já ordenado por valor | disponível offline pelo ledger |
| transações recentes | 10 linhas | `HomeSnapshot.recentTransactions` | disponível offline; Flutter limita a 5 |
| lista de próximos vencimentos | `bills_metrics.upcoming_bills` | `BillsDataSnapshot.instances` | disponível online na área Contas Fixas |
| teto total, restante, uso e gasto diário permitido | orçamento de categorias no Django | schema Drift de categoria não possui `budget` | ausente no ledger Flutter; não exibir até contrato próprio |

## Decisão

R3.3.2 e R3.3.3 reutilizam os dados disponíveis. Saldo livre e contas fixas
continuam online até uma decisão de cache posterior. Orçamento diário não será
simulado com saldo ou gasto mensal. A quantidade de recentes pode mudar apenas
com teste de desempenho e sem alterar o significado.

## Evidência de execução

- [ ] timestamp da tela Mais mudou após sincronização real;
- [ ] cliente exibiu SHA curto correspondente ao artefato instalado;
- [ ] host exibido foi `financeiro.palmbook.online`;
- [ ] health público respondeu `status=ok`, `api_version=v1` e SHA de 40 caracteres;
- [ ] Web e Windows foram comparados no escopo `Lar` e no mesmo período;
- [ ] screenshots reais ficaram somente em `screenshots/`, ignorado pelo Git;
- [ ] seis goldens Flutter sintéticos passaram sem atualização.
