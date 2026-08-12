# Roadmap do Lar Finance

## Regras de execução

- Sprints não têm prazo fixo; qualidade e integridade financeira valem mais que velocidade.
- Cada tarefa de código começa por teste que falha.
- Uma sprint só termina com critérios de aceite, documentação e rollback/backup quando aplicável.
- `[INVESTIGAR]` precisa virar decisão registrada antes da implementação dependente.
- Não misturar grandes migrations de dados, troca de banco e nova UI na mesma entrega.
- Não remover fallback web até Flutter ter paridade validada.
- Ao compor uma sprint, registrar plano por tarefa, routing e auditoria conforme
  `docs/ai-model-routing.md`; revalidar modelos e intensidades no ambiente ativo.

## Definition of Done global

- [ ] testes novos e existentes passam;
- [ ] lint/check/migrations limpos;
- [ ] isolamento por lar/proprietário testado;
- [ ] estados loading/vazio/erro/offline cobertos quando houver UI;
- [ ] logs sem PII/valores/tokens;
- [ ] documentação e OpenAPI atualizados;
- [ ] acessibilidade verificada;
- [ ] performance medida quando afetada;
- [ ] backup/rollback validado para mudança de dados/infra;
- [ ] revisão de segurança concluída.
- [ ] auditoria de modelos concluída, sem inventar tokens ou disponibilidade.

## Sprint 0 — Contenção, baseline e decisões

Objetivo: tornar o projeto seguro e reproduzível antes de adicionar dados reais.

- [ ] rotacionar credenciais expostas e substituir scripts de QA por fixtures;
- [x] adicionar secret scanning no CI;
- [x] corrigir o caminho/volume SQLite no Compose e cobrir configuração;
- [x] desativar signup público e redirecionar `/` para login/dashboard;
- [x] executar e registrar coverage, Ruff, `check --deploy` e migrations;
- [x] documentar operação EasyPanel sem segredos;
- [x] criar backup SQLite consistente e verificar integridade;
- [ ] provar restauração em cópia externa/ambiente isolado;
- [x] auditar diffs das três branches remotas sem merge automático;
- [ ] ADR-001 API/autenticação;
- [ ] ADR-002 PostgreSQL;
- [ ] ADR-003 Flutter local DB/state;
- [ ] ADR-004 sync/conflitos;
- [ ] fixar versões Flutter/backend target em lockfiles;
- [ ] aprovar política de arquivos importados.

Aceite: nenhum segredo conhecido no HEAD, signup fechado, persistência comprovada, restauração testada e ADRs essenciais aprovados.

Riscos: rotação quebrar acesso atual; correção de volume apontar para base errada; branch remota conter mudança útil. Mitigação: backup, inventário de paths e revisão por diff.

## Sprint 1 — Lar, proprietários e integridade do ledger

Objetivo: representar corretamente “Eu”, “Esposa” e “Lar”.

- [x] testes de `Household`, membership e `FinancialOwner`;
- [x] migrations e backfill para owner padrão;
- [x] criar responsáveis “Eu”, “Esposa” e “Conjunto” de forma idempotente;
- [x] ligar account/category/transaction ao household/owner;
- [x] adicionar UUID, versão e timestamps de sync;
- [x] constraints e validações entre household/owner/entidades;
- [ ] introduzir `Institution` e aliases iniciais;
- [ ] modelar transferências com duas pontas;
- [ ] corrigir cálculos que contam transferência como receita/despesa;
- [x] criar auditoria de integridade do Lar, somente leitura e sem PII;
- [x] consolidar `Eu`, `Esposa` e `Conjunto` no dashboard web;

Entregue nesta sprint: fronteira por Lar, acesso revogável, responsáveis, backfill reversível, integridade do ledger legado, backup, CI e runbook. UUID/versão das entidades legadas, instituições, transferências, auditoria de eventos e switcher visual permanecem para planos específicos; não são considerados concluídos por associação ao nome da sprint.

Aceite: dados atuais pertencem ao owner padrão, novos dados exigem owner e consolidado não duplica transferências.

Riscos: backfill associar dados à pessoa errada; mudança de saldo. Mitigação: relatório antes/depois e migration reversível.

## Sprint 2 — API v1 e contrato de sincronização

Objetivo: expor o domínio com segurança para Flutter.

Decisão aprovada: um login familiar compartilhado, sessões independentes e revogáveis por dispositivo, responsável padrão `Eu`/`Esposa` por instalação e sincronização automática com outbox offline. Especificação: [login único e sincronização por dispositivo](superpowers/specs/2026-08-10-single-login-device-sync-design.md).

- [x] OpenAPI para login, refresh, logout, dispositivos, recursos e sincronização;
- [x] testes de autorização por household nos endpoints privados entregues;
- [x] endpoints de leitura de owners, contas, categorias e transações;
- [ ] endpoint de instituições depois da introdução do model `Institution`;
- [ ] paginação por cursor e filtros nas listagens de recursos;
- [x] idempotency key nas mutações de sincronização;
- [x] versionamento otimista e resposta de conflito por operação;
- [x] endpoint delta/tombstones;
- [x] revogação de dispositivo e refresh token;
- [x] rate limiting de login/refresh e logs JSON com request ID;
- [x] teste de contrato e compatibilidade v1 para as 16 rotas atuais;
- [x] documentação de erros no contrato OpenAPI.

Entregue no backend: API privada `/api/v1`, sessões revogáveis por dispositivo,
tokens opacos rotativos, bootstrap, leitura dos recursos do Lar, push idempotente,
pull por cursor, envelope de erro estável, request IDs e contrato
`docs/openapi-v1.yaml`. Instituições, filtros/paginação das listas de recursos e o
cliente Flutter permanecem pendentes; nenhum deploy EasyPanel foi comprovado por
esta entrega.

Aceite: cliente de teste cria/edita/sincroniza dados sem acessar outro household e sem duplicar requisição repetida.

Riscos: auth escolhida inadequada para desktop; conflito complexo. Mitigação: spike/ADR e versão explícita.

## Sprint 3 — Importação OFX/CSV e conciliação

Objetivo: reduzir trabalho manual com import idempotente.

- [ ] coletar fixtures anonimizadas das instituições `[INVESTIGAR]`;
- [ ] models `ImportBatch`, `ImportRecord`, `SourceReference`, `ReconciliationIssue`;
- [ ] upload seguro, hash e limites;
- [ ] parser OFX genérico com testes de encoding/valor/data;
- [ ] framework de perfis CSV versionados;
- [ ] preview sem alterar ledger;
- [ ] mapeamento de owner/institution/account/category;
- [ ] fingerprint/deduplicação e teste de reimportação;
- [ ] conciliação de transferências e estornos;
- [ ] commit atômico e recibo;
- [ ] endpoints de job/status/cancelamento;
- [ ] métricas e logs seguros;
- [ ] matriz real de cobertura por banco.

Aceite: importar duas vezes o mesmo arquivo não duplica; linha inválida é explicada; cancelamento não altera o ledger.

Riscos: formatos divergentes e encoding; falso positivo de duplicata. Mitigação: profiles/fixtures e sugestão humana em baixa confiança.

## Sprint 4 — Cartões, faturas, limites e parcelas

Objetivo: representar crédito sem corromper caixa.

- [ ] models e testes de `CreditCard`, `CardStatement`, `CardTransaction` e payment;
- [ ] migrar contas `credit` com relatório de exceções;
- [ ] fechamento/vencimento e competência;
- [ ] total calculado versus informado;
- [ ] limite total/usado/disponível com estado “não informado”;
- [ ] parcelas atuais e futuras sem dupla contagem;
- [ ] pagamento da fatura conciliado com conta;
- [ ] estornos, tarifas, juros e pagamento parcial;
- [ ] importador CSV inicial de cartão com fixture real `[INVESTIGAR instituição]`;
- [ ] API e fallback web mínimo.

Aceite: compra afeta fatura/limite, pagamento afeta caixa, consolidado não conta ambos como duas despesas.

Riscos: formatos de fatura e parcelamento variam; migration ambígua. Mitigação: exceções manuais e dados originais preservados.

## Sprint 5 — Fundação Flutter, login e offline

Objetivo: instalar app em ambientes de desenvolvimento e provar sync offline.

- [ ] criar workspace Flutter com targets iOS/Android/Windows;
- [ ] fixar SDK/pacotes e configurar flavors;
- [ ] implementar arquitetura por features e repositories;
- [ ] SQLite local, migrations e criptografia/risco decidido;
- [ ] API client, refresh, timeout e retry controlado;
- [ ] secure storage por plataforma;
- [ ] login, logout, biometria opt-in e fallback;
- [ ] outbox, delta e conflito demonstrável;
- [ ] app shell adaptativo e tema provisório de engenharia;
- [ ] estados offline/stale/sync;
- [ ] telemetria sem PII;
- [ ] testes unitários, widget e integração;
- [ ] benchmark de abertura <2s com cache.

Aceite: usuário entra, consulta cache offline, cria alteração offline, reconecta e sincroniza sem perda.

Riscos: pacote não suportar Windows ou background; migração local falhar. Mitigação: proof-of-concept e tabela de suporte antes de fechar ADR.

## Sprint 6 — Início, movimentações e proprietários

Objetivo: tornar o Flutter útil para acompanhamento diário.

- [ ] owner switcher Lar/Eu/Esposa;
- [ ] Início com caixa, patrimônio e compromissos;
- [ ] origem e freshness de cada bloco;
- [ ] lista paginada, busca e filtros;
- [ ] detalhe/edição/categorização;
- [ ] fluxo de importação e conciliação mobile;
- [ ] visualização adaptativa Windows;
- [ ] ocultar valores e proteção no app switcher `[INVESTIGAR]`;
- [ ] loading/vazio/erro/offline/conflito;
- [ ] acessibilidade e teclado;
- [ ] teste com volume realista.

Aceite: rotina diária completa pode ser feita no app sem recorrer ao web, exceto administração avançada documentada.

Riscos: dashboard ficar denso ou enganoso. Mitigação: hierarquia validada com dados reais e sem zeros presumidos.

## Sprint 7 — Planejamento, recorrências e metas

Objetivo: sair do histórico e apoiar decisões futuras.

- [ ] recorrências e detecção sugerida;
- [ ] calendário de entradas, despesas, faturas e parcelas;
- [ ] orçamento por categoria/owner/lar;
- [ ] realizado versus previsto;
- [ ] metas e reserva de emergência;
- [ ] alertas de vencimento e excesso opt-in;
- [ ] projeção com níveis confirmado/recorrente/estimado;
- [ ] regras de categorização explicáveis;
- [ ] relatórios e testes de virada de mês/timezone.

Aceite: usuário entende compromissos futuros e diferença entre confirmado e estimado.

Riscos: previsão parecer certeza; recorrência errada. Mitigação: confiança explícita e edição simples.

## Sprint 8 — Empréstimos, financiamentos e dívidas

Objetivo: consolidar passivos e custo de crédito.

- [ ] loan/installment models e migrations;
- [ ] cadastro manual completo com origem/data;
- [ ] principal, saldo, taxa, CET, prazo e amortização opcionais;
- [ ] cronograma e pagamentos conciliados;
- [ ] custo total quando calculável;
- [ ] cenários de antecipação apenas informativos `[INVESTIGAR fórmula/escopo]`;
- [ ] importador específico se arquivos reais permitirem;
- [ ] UI e alertas de próxima parcela;
- [ ] testes de arredondamento e pagamento parcial.

Aceite: dívida manual/importada entra no patrimônio e cronograma sem inventar taxa/CET.

Riscos: cálculo financeiro incorreto. Mitigação: biblioteca/fórmula validada, golden tests e rótulo de estimativa.

## Sprint 9 — Investimentos, bens e patrimônio

Objetivo: visão completa de ativos e passivos.

- [ ] classes de investimento e posições;
- [ ] bens, direitos e outros passivos;
- [ ] valor, custo, moeda, data e fonte;
- [ ] snapshots históricos;
- [ ] patrimônio individual/conjunto;
- [ ] importação por arquivo quando disponível;
- [ ] cotações automáticas fora do escopo ou ADR `[INVESTIGAR]`;
- [ ] UI de composição e evolução;
- [ ] testes de moeda e data de referência.

Aceite: patrimônio líquido é reproduzível e cada valor mostra data/origem.

Riscos: valores defasados e dupla contagem com contas investimento. Mitigação: freshness e vínculos explícitos.

## Sprint 10 — Relatórios e saúde financeira explicável

Objetivo: transformar dados em orientação transparente.

- [ ] fluxo de caixa e comparação mensal;
- [ ] gastos por categoria/favorecido/owner;
- [ ] comprometimento de renda e cobertura de reserva;
- [ ] evolução de dívida e patrimônio;
- [ ] indicadores com fórmula e fontes visíveis;
- [ ] insights baseados em regras, não diagnóstico opaco;
- [ ] exportação CSV/PDF `[INVESTIGAR PDF]`;
- [ ] tabelas alternativas a gráficos;
- [ ] testes de agregação e privacidade.

Aceite: cada insight pode ser explicado e auditado; nenhum gráfico existe só como decoração.

Riscos: interpretação como consultoria. Mitigação: linguagem factual, fórmula e limites explícitos.

## Sprint 11 — PostgreSQL, EasyPanel, backup e observabilidade

Objetivo: produção resiliente no servidor doméstico.

- [ ] criar PostgreSQL e usuário/rede dedicados;
- [ ] ensaiar migração SQLite → PostgreSQL com contagem/checksum;
- [ ] janela, backup e rollback;
- [ ] settings por ambiente e secrets;
- [ ] health/readiness e migrations controladas;
- [ ] logs JSON e IDs de correlação;
- [ ] métricas/alertas mínimos;
- [ ] backup 3-2-1 criptografado;
- [ ] restauração automatizada/ensaiada;
- [ ] runbooks e inventário EasyPanel;
- [ ] teste de queda/restart/indisponibilidade.

Aceite: deploy/restart preservam dados, backup restaura e falhas críticas alertam.

Riscos: downtime/perda de dados. Mitigação: ensaio com clone, freeze de escrita e rollback.

## Sprint 12 — Qualidade, performance e acessibilidade

Objetivo: preparar uso contínuo sem dívida invisível.

- [ ] coverage gates incrementais por domínio;
- [ ] E2E de jornadas críticas;
- [ ] testes de carga/sync/import grande;
- [ ] profiling de consultas e N+1;
- [ ] auditoria OWASP/dependências/secrets;
- [ ] acessibilidade iOS/Android/Windows;
- [ ] teste de fonte grande, contraste e reduced motion;
- [ ] caos básico: rede intermitente, token expirado, disco cheio;
- [ ] revisão de privacidade e retenção;
- [ ] corrigir defeitos P0/P1.

Aceite: SLOs definidos e alcançados, zero P0/P1 aberto e jornadas críticas automatizadas.

Riscos: achar problemas estruturais tarde. Mitigação: gates já existem nos sprints anteriores; esta sprint consolida.

## Sprint 13 — Distribuição Windows, Android e iOS

Objetivo: instalar de forma repetível nos dispositivos reais.

- [ ] ícone, nome e bundle IDs próprios;
- [ ] assinatura Windows `[INVESTIGAR]`;
- [ ] Android privado e estratégia Play Store `[INVESTIGAR]`;
- [ ] Apple Developer/TestFlight e custo `[INVESTIGAR]`;
- [ ] textos de permissão e política de privacidade;
- [ ] screenshots/metadata depois do design aprovado;
- [ ] CI de builds e artefatos assinados;
- [ ] canal de atualização/rollback;
- [ ] smoke test nos dispositivos do casal;
- [ ] manual de instalação não técnico.

Aceite: versão assinada e atualizável instalada em Windows, iPhone e Android reais.

Riscos: exigências de loja e certificado. Mitigação: resolver contas/custos antes do início da sprint.

## Sprint 14 — Automação opcional com provedor

Objetivo: eliminar importação frequente sem quebrar independência.

- [ ] confirmar orçamento total, dois CPFs e sete conexões;
- [ ] confirmar campos por instituição/produto;
- [ ] aprovar contrato, privacidade e retenção;
- [ ] implementar provider port;
- [ ] OAuth/consent e token vault;
- [ ] webhook/poll idempotente;
- [ ] mapear para o mesmo pipeline de importação;
- [ ] reconciliar provider versus arquivos existentes;
- [ ] botão revogar/apagar conexão;
- [ ] piloto com uma instituição antes das sete;
- [ ] medir confiabilidade por 30 dias `[INVESTIGAR]`;
- [ ] manter importação manual como fallback.

Aceite: automação não duplica histórico, pode ser revogada e falha sem bloquear o controle manual.

Riscos: fornecedor caro/incompleto, conta individual, dados inconsistentes. Mitigação: piloto pequeno, contrato adapter e saída fácil.

## Ordem de valor

O primeiro marco realmente utilizável termina no Sprint 6: dados corretos, importação, cartões e app sincronizado. Sprints 7 a 10 transformam controle em planejamento abrangente. Infra é tratada desde o Sprint 0 e consolidada no Sprint 11, não adiada integralmente.
