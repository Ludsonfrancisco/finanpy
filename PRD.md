# Lar Finance — PRD do estado atual e evolução do produto

> Fonte única de verdade do produto. Revalidado em 20/08/2026 contra o código
> no `main` em `4810af4`, a CI, a produção pública e as interfaces Web/Flutter.
> Evidência detalhada:
> [auditoria de estado e paridade](docs/audits/2026-08-20-product-state-and-design-parity.md).
> O incremento R1.4 foi revalidado separadamente em 21/08/2026; a prova local e
> de CI não deve ser confundida com publicação GHCR ou deploy no EasyPanel.

## Status e convenções

- **Nome oficial:** Lar Finance.
- **Nome técnico legado:** Finanpy, mantido temporariamente no repositório, módulos Django e implantação até uma migração segura.
- **Estado atual:** beta pessoal avançada. Web Django e Flutter compartilham um
  Lar privado, owners, contas, categorias, movimentações, importação OFX,
  cartões/faturas, contas fixas, orçamento e relatórios. O ledger principal tem
  cache/sync incremental; cartões e contas fixas usam API online direta.
- **Produto alvo:** aplicativo Flutter para iOS, Android e Windows, sincronizado com o backend Django no servidor Linux/EasyPanel.
- **Estratégia de dados aprovada:** importação de arquivos primeiro; integração paga automática somente após o produto estar maduro e em uso.
- **Usuários do produto:** uma família no mesmo Lar, com um único login compartilhado nesta fase. Cada dispositivo terá sessão própria e revogável. O domínio mantém credenciais de acesso separadas dos responsáveis financeiros `Eu`, `Esposa` e `Conjunto`, permitindo dois logins no futuro sem migrar o ledger.
- **Identidade visual:** **Casa de Valores 2.0**. Web e Flutter usam o mesmo
  Design System; a Web preserva cards, indicadores, gráficos e densidade que
  agradam ao proprietário, enquanto o Flutter fornece tokens, tema de sistema,
  hierarquia financeira e comportamento adaptativo.
- **Regra visual irrevogável:** não usar roxo.
- **`[INVESTIGAR]`:** decisão ou comportamento sem evidência suficiente. Não deve ser implementado por suposição.
- **`As-is`:** comportamento comprovado no código atual.
- **`To-be`:** comportamento alvo aprovado para construção incremental.

## 1. Visão geral

### 1.1 Problema

As informações financeiras do casal estão fragmentadas entre Nubank, Inter, Santander e Mercado Pago. O controle precisa reunir movimentações, cartões, faturas, limites, empréstimos, investimentos, patrimônio, compromissos e objetivos sem depender de uma assinatura cara na primeira fase.

### 1.2 Proposta de valor

O Lar Finance será o painel financeiro privado da família: uma visão confiável do que entrou, saiu, está comprometido, deve ser pago, pertence a cada pessoa e compõe o patrimônio conjunto. O sistema ajuda a tomar decisões, mas não movimenta dinheiro, não guarda senhas bancárias e não substitui aconselhamento financeiro profissional.

### 1.3 Escopo da primeira versão pessoal

- visão `Lar`, `Eu` e `Esposa`;
- contas, categorias, receitas, despesas e saldos;
- cartões, limites, compras, faturas, vencimentos e pagamentos já modelados;
- contas fixas, compromissos, orçamento por categoria e saldo livre;
- importação OFX manual, deduplicação, prévia e confirmação;
- relatórios explicáveis sobre o ledger disponível;
- Web, Windows, Android e iOS com Casa de Valores 2.0;
- sincronização do ledger e consulta online dos módulos recentes;
- backup R2, restauração e atualização privada.

Empréstimos, investimentos, Open Finance pago, CSV/PDF genérico e automações
amplas são backlog opcional após uso real; não bloqueiam a primeira versão.

### 1.4 Fora de escopo inicial

- Iniciar pagamentos, Pix, transferências ou operações de investimento.
- Web scraping de internet banking ou armazenamento de credenciais bancárias.
- Cadastro público, landing page, marketing, múltiplas famílias ou cobrança de assinatura.
- Open Finance direto como participante regulado.
- Recomendações personalizadas tratadas como consultoria financeira.

### 1.5 Critérios de sucesso

- O casal consegue responder quanto possui, deve, gastou e terá comprometido em um único lugar.
- Toda quantia mostra origem, proprietário, data de atualização e nível de confiança.
- Reimportar o mesmo arquivo não duplica lançamentos.
- O app abre a visão inicial em menos de 2 segundos com dados locais já sincronizados.
- Operações suportadas offline sincronizam sem perda silenciosa; recursos
  online-only informam indisponibilidade em vez de simular uma mutação local.
- O usuário consegue exportar e restaurar os dados.

## 2. Personas e jornadas

### 2.1 Administrador do lar

Pessoa que instala, configura fontes, importa arquivos, resolve conflitos, acompanha o consolidado e mantém backup. No primeiro uso será o titular do login.

### 2.2 Proprietário financeiro

Pessoa a quem pertencem contas, cartões, dívidas, investimentos e transações. Inicialmente existem “Eu” e “Esposa”. Proprietário financeiro não é uma credencial separada.

### 2.3 Jornada principal

```mermaid
flowchart LR
    A["Entrar no Lar Finance"] --> B["Ver resumo sincronizado"]
    B --> C["Importar arquivo do banco"]
    C --> D["Identificar instituição, conta e proprietário"]
    D --> E["Revisar duplicatas e pendências"]
    E --> F["Confirmar importação"]
    F --> G["Categorizar e conciliar"]
    G --> H["Acompanhar caixa, faturas, dívidas e patrimônio"]
    H --> I["Planejar orçamento e metas"]
```

## 3. Stack atual com versões exatas

### 3.1 As-is comprovado

| Camada | Tecnologia e versão | Evidência |
|---|---|---|
| Linguagem | Python 3.12, imagem `python:3.12-slim` | `Dockerfile` |
| Framework | Django 5.2.13 | `requirements.txt` |
| API | Django REST Framework 3.17.1; OpenAPI 3.1.0, contrato 1.0.0 | `requirements.txt`, `docs/openapi-v1.yaml` |
| WSGI | Gunicorn 23.0.0, 1 worker | requirements, Docker e Compose |
| Imagens | Pillow 12.2.0 | `requirements.txt` |
| Ambiente | python-dotenv 1.2.2 | `requirements.txt` |
| Runtime indireto | asgiref 3.11.1, sqlparse 0.5.5, tzdata 2026.1 | `requirements.txt` |
| Qualidade | Ruff 0.15.11, Coverage 7.13.5 | `requirements.txt` |
| Backup remoto | boto3 1.43.53, filelock 3.32.0, Supervisor 4.3.0 e R2 S3 API | `requirements.txt`, `deploy/supervisord.conf`, `core/remote_backup.py` |
| Banco | SQLite, caminho absoluto configurável; `/app/data/db.sqlite3` no container | `core/settings.py`, Docker e Compose |
| Frontend Web | Django Templates, Tailwind CDN, Alpine CDN, Chart.js CDN e Inter remoto | funcional, mas assets/tokens precisam convergir no ciclo R2 |
| Fila/cache | inexistentes | settings e dependências |
| Container | Docker multi-stage + Docker Compose | arquivos raiz |
| Produção informada | Linux em EasyPanel, servidor doméstico | informação do proprietário; configuração externa não versionada `[INVESTIGAR]` |

Flutter está instalado no workspace `mobile/`; PostgreSQL, fila e provedor
financeiro continuam ausentes e não bloqueiam a V1 pessoal. A API REST privada
usa Django REST Framework. Há parser OFX interno e estruturalmente compatível
com o piloto Nubank; CSV e demais fontes não foram implementados.

### 3.2 Stack cliente e direções ainda pendentes

| Camada | Direção | Estado |
|---|---|---|
| Cliente | Flutter 3.47.0 stable e Dart 3.13.0, um código-base para iOS, Android e Windows | workspace e lockfile entregues na Sprint 4; Windows/Android/iOS comprovados pela CI multiplataforma |
| Backend | Django preservado e transformado em API versionada | API v1 entregue na Sprint 2 |
| API | Django REST Framework 3.17.1 | entregue na Sprint 2 |
| Banco servidor | SQLite em volume persistente | aprovado para uma família, uma réplica e um worker; PostgreSQL não bloqueia V1 |
| Banco local | SQLite com Drift 2.34.3/drift_flutter 0.3.1 e pull atômico | ledger principal entregue; cartões/contas fixas ainda não possuem cache Drift |
| Autenticação | login familiar único; token opaco e renovação rotativa por dispositivo | backend e cliente entregues; tokens no secure storage nativo, dados financeiros no Drift |
| Importação | OFX estruturalmente compatível com conta/cartão Nubank | entregue na Web e Flutter; outros formatos são opcionais |
| Automação futura | adaptador de provedor, inicialmente candidato Pierre | contratação e suporte a dois CPFs `[INVESTIGAR]` |

Versões do cliente são fixadas em `mobile/tool/flutter-version.json`,
`mobile/pubspec.yaml` e `mobile/pubspec.lock`. Tecnologias opcionais ausentes
continuam sem versão inventada.

## 4. Arquitetura

### 4.1 As-is

Monólito Django que preserva a interface server-rendered e expõe API privada
DRF. A API autentica sessões por dispositivo e aplica a fronteira do Lar. O
serviço append-only sincroniza Account, Category e Transaction; cartões e contas
fixas usam endpoints REST diretos.

```mermaid
flowchart TB
    Browser["Navegador"] --> Templates["Django Templates + CSS/JS"]
    Templates --> Views["CBVs e Forms"]
    Views --> ORM["Django ORM"]
    ORM --> SQLite[("SQLite")]
    Views --> Auth["Sessão Django"]
    Gunicorn["Gunicorn no container"] --> Views
```

Apps: `core`, `users`, `profiles`, `households`, `accounts`,
`categories`, `transactions`, `imports`, `cards`, `bills`, `api`,
`sync` e `ai`. O app `ai` está instalado, porém sem fluxo financeiro ativo
comprovado `[INVESTIGAR]`.

### 4.2 To-be incremental

```mermaid
flowchart TB
    subgraph Clients["Clientes Flutter"]
        IOS["iOS"]
        Android["Android"]
        Windows["Windows"]
        Local[("SQLite local + outbox")]
        IOS --> Local
        Android --> Local
        Windows --> Local
    end
    Clients -->|"HTTPS / API v1"| API["Django API"]
    API --> Domain["Serviços de domínio financeiro"]
    Domain --> ServerDB[("SQLite persistente")]
    API --> Import["Pipeline de importação e conciliação"]
    Import --> ServerDB
    Provider["Adaptadores: arquivos / futuro provedor"] --> Import
    Worker["Jobs assíncronos, se necessários"] --> Import
    Ops["Logs, métricas, alertas e backup"] --> API
    Ops --> ServerDB
```

Princípios:

- evolução por módulos, sem rewrite total do backend;
- API e domínio não conhecem widgets Flutter;
- importadores e provedores implementam contratos substituíveis;
- SQLite no servidor é a fonte canônica na topologia pessoal suportada;
- SQLite local sustenta leitura rápida, offline e fila de mudanças;
- o ledger sincronizável recebe UUID, versão, timestamps e marcador de exclusão;
- módulos online-only declaram essa limitação até possuírem cache/contrato próprio;
- conflitos financeiros nunca são sobrescritos silenciosamente.

Detalhes: [arquitetura](docs/architecture.md) e [segurança/operação](docs/security-and-operations.md).

## 5. Modelo de dados

### 5.1 As-is extraído das migrations/models

| Entidade | Campos de domínio | Relações e restrições |
|---|---|---|
| `users.User` | email único; flags e senha do Django; timestamps | autenticação por email |
| `profiles.Profile` | nome, sobrenome, nascimento, avatar, timestamps | 1:1 com User |
| `households.Household` | nome, UUID, status e timestamps | fronteira de autorização e consolidação |
| `households.HouseholdMembership` | papel, status e timestamps | liga User ao Lar; um Lar ativo por usuário |
| `households.FinancialOwner` | nome, código `self/spouse/shared`, UUID e status | responsável financeiro dentro do Lar |
| `accounts.Account` | UUID, `sync_version`, nome, tipo, saldo inicial, moeda, timestamps | N:1 Household, User legado e FinancialOwner |
| `categories.Category` | UUID, `sync_version`, nome, tipo receita/despesa, cor, ícone | N:1 Household e User legado; único no escopo definido |
| `transactions.Transaction` | UUID, `sync_version`, descrição, valor, data, tipo, timestamps | N:1 Household, User legado, FinancialOwner, Account e Category |
| `api.DeviceSession` / `UsedRefreshToken` | UUID da sessão, plataforma, digests, expiração, revogação e refresh consumido | escopo imutável por User, Household e owner padrão |
| `sync.SyncChange` / `IdempotentOperation` | cursor, entidade/UUID/versão, operação, payload e resposta idempotente | ledger append-only por Household e operação por dispositivo |
| `imports.ImportBatch` / `ImportRecord` / `ImportAccountLink` / `SourceReference` | lote, prévia, vínculo, hash/FITID e referência deduplicada | confirmação atômica e recibo sem guardar OFX bruto |
| `cards.CreditCard` | nome, limite, fechamento, vencimento e owner | N:1 Household/FinancialOwner; cartão não é conta corrente |
| `cards.CreditCardInvoice` | competência, fechamento, vencimento, status e pagamentos | N:1 CreditCard |
| `cards.CreditCardExpense` | descrição, valor, data, categoria, parcela e status | N:1 CreditCard/Invoice |
| `bills.RecurringBill` / `BillInstance` | regra, tipo, valor, vencimento, status e pagamento | N:1 Household/owner/account/category |

Lacunas comprovadas: não há instituição normalizada, transferência com duas
pontas, dívida, investimento, moeda por cotação, anexo ou `AuditEvent` de
negócio. Cartões/faturas e recorrência de contas fixas existem, mas não integram
o registro central de sync/Drift.

### 5.2 To-be

Para a V1, o núcleo atual será consolidado em vez de ampliado. `Institution`,
`Transfer`, `AuditEvent`, `Loan`, `InvestmentPosition`, `Asset`,
`Liability` e `ProviderConnection` permanecem backlog opcional.

Regras essenciais:

- valores monetários usam decimal e moeda explícita, nunca ponto flutuante;
- cartão não é tratado como conta corrente;
- compra no cartão afeta fatura/limite, não o caixa imediatamente;
- pagamento da fatura liga saída da conta à quitação da fatura;
- transferência liga débito e crédito, sem contar como receita/despesa do lar;
- toda entidade financeira pertence a um `FinancialOwner` e a um `Household`;
- campos ausentes no arquivo ficam “não informado”, jamais zero presumido;
- saldo calculado e saldo informado pela fonte são distintos;
- importações preservam arquivo hash, linha original normalizada e decisões de conciliação.

Diagrama e campos: [modelo de dados](docs/data-model.md).

## 6. Endpoints, rotas e comandos expostos

### 6.1 Rotas web atuais

| Método | Rota | Acesso | Função |
|---|---|---|---|
| GET | `/` | público/autenticado | redireciona para login ou dashboard |
| — | `/signup/` | indisponível | cadastro público removido |
| GET/POST | `/login/` | público | login |
| POST/GET `[INVESTIGAR]` | `/logout/` | autenticado | logout |
| GET | `/dashboard/` | autenticado | resumo financeiro |
| GET/POST | `/profile/edit/` | autenticado | edição do perfil |
| GET/POST | `/accounts/`, `/accounts/new/` | autenticado | listar/criar contas |
| GET/POST | `/accounts/<id>/edit/`, `/delete/` | autenticado | editar/excluir conta |
| GET/POST | `/categories/`, `/categories/novo/` | autenticado | listar/criar categorias |
| GET/POST | `/categories/<id>/editar/`, `/excluir/` | autenticado | editar/excluir categoria |
| GET/POST | `/transacoes/`, `/transacoes/nova/` | autenticado | listar/criar transações |
| GET/POST | `/transacoes/<id>/editar/`, `/excluir/` | autenticado | editar/excluir transação |
| GET/POST | `/transacoes/importar/`, `/exportar-ofx/` | autenticado | importar/exportar OFX |
| vários | `/contas-fixas/` | autenticado | regras, instâncias, pagamento e reabertura |
| vários | `/cartoes/` | autenticado | cartões, despesas, faturas, importação, pagamento e reabertura |
| vários | `/admin/` | staff | Django Admin |
| GET | `/media/*` | conforme settings | mídia servida pelo Django na configuração atual |

### 6.2 API privada atual

O prefixo entregue é `/api/v1/`, com 32 rotas para health,
login/refresh/logout, dispositivos, household/owners, contas, categorias,
transações, resumo, bootstrap, sincronização push/pull, importação OFX, cartões,
faturas e contas fixas. O contrato normativo OpenAPI está em
[`docs/openapi-v1.yaml`](docs/openapi-v1.yaml) e precisa permanecer alinhado a
esse inventário.

Access tokens duram 15 minutos e refresh tokens 30 dias; ambos são opacos, rotacionados e persistidos somente como digest. Login usa throttle de 5/minuto e refresh 30/minuto. Push aceita de 1 a 100 operações idempotentes com versão otimista e retorna resultados/estado/versão sem cursor. O cliente preserva o cursor anterior e só o avança com o cursor de um pull bem-sucedido, após aplicar atomicamente a página; cada pull retorna até 100 mudanças e tombstones após cursor assinado vinculado ao Lar.

Instituições, transferências com duas pontas, tags, metas, empréstimos,
investimentos/patrimônio, CSV/outros bancos e conciliação completa continuam
fora da API atual. O cliente Flutter usa sync no ledger principal e endpoints
diretos para cartões e contas fixas.

### 6.3 Comandos atuais

`manage.py prepare_deploy`, `migrate`, `collectstatic`, `runserver`, `test`, `check`,
`makemigrations --check`, `createsuperuser`, `backup_sqlite`, `backup_to_r2`,
`run_backup_scheduler`, `purge_import_previews`,
`run_import_preview_purge_scheduler`, `audit_household_integrity`, `coverage`
e `ruff`. Os
scripts de QA foram neutralizados no HEAD; a credencial histórica foi rotacionada
pelo proprietário no EasyPanel em 2026-08-12.

## 7. Integrações backend e externas

### 7.1 Comprovadas hoje

- SMTP, Open Finance, webhooks, filas e analytics: ausentes.
- Docker/EasyPanel: implantação informada; manifesto real do EasyPanel não está versionado `[INVESTIGAR]`.
- Tailwind e fontes por CDN: dependência de rede no frontend web atual.

### 7.2 Importação aprovada

- **OFX:** primeira opção para extrato de conta e movimentações quando o banco oferece.
- **CSV:** adaptador futuro; não implementado.
- **PDF:** útil para faturas/extratos, mas exige parser específico; não entra no primeiro importador genérico.
- **XLS/XLSX:** útil para exportações e planilhas existentes; esquema varia por origem.
- **Manual:** obrigatório para limite, CET, bens ou posições que a fonte não exportar.

Arquivos transacionais normalmente não garantem limite de cartão, empréstimos,
investimentos ou patrimônio. OFX de cartão pode alimentar compras/fatura quando
a estrutura contém os eventos, mas não autoriza inferir parcelas ou limites
ausentes. Inter, Santander e Mercado Pago permanecem `[INVESTIGAR]`.

### 7.3 Automação futura

Pierre é candidato por caber aproximadamente no teto informado de R$40/mês para uma conta, mas a cobertura de sete conexões e dois CPFs/consentimentos precisa de confirmação contratual `[INVESTIGAR]`. O domínio deve aceitar qualquer provedor que implemente o contrato interno e nunca depender do formato proprietário.

Detalhes: [importação e sincronização](docs/imports-and-sync.md).

## 8. Débitos técnicos

| Severidade | Evidência | Impacto | Tratamento |
|---|---|---|---|
| Mitigado no código; validação operacional aberta | o entrypoint executa `prepare_deploy` antes do Supervisor | falha de configuração, backup, migration, auditoria ou static não inicia processos | publicar a tag versionada, registrar o digest OCI e validar no EasyPanel na Task 7 |
| Alto | sync central cobre só Account/Category/Transaction | cartões/contas fixas não têm a mesma garantia offline | servidor canônico, escrita online e cache de leitura vinculado à sessão |
| Alto | o health e a tag GHCR têm contrato por SHA, mas a tag não foi publicada nem seu digest resolvido/selecionado no EasyPanel | produção/rollback ainda não foram validados para o candidato | publicar `sha-<40-char-sha>`, registrar o digest OCI e ensaiar rollback manual na Task 7 |
| Médio | PRD, roadmap, README e instruções descreviam estado anterior | decisões e novas tasks podem duplicar trabalho pronto | auditoria datada e atualização documental |
| Médio | Web hardcoded dark e 821 cores hex espalhadas | paridade/tema/manutenção frágeis | tokens Casa de Valores 2.0 e migração incremental |
| Médio | Tailwind, Alpine, Chart.js e fonte vêm de CDN | supply chain, CSP e indisponibilidade | fixar e servir assets locais, sem trocar framework |
| Médio | cálculos do dashboard podem causar consultas repetidas | degradação com volume | agregação e testes de performance na tela afetada |
| Mitigado | credencial histórica e backup fora do host | reutilização/perda ainda exigem disciplina operacional | valor rotacionado, R2 privado e restauração ensaiada |
| Adequado ao escopo | SQLite em uma réplica/um worker | não escala horizontalmente | manter topologia pessoal; PostgreSQL somente por dor real |

## 9. Riscos de segurança e privacidade

- Dados financeiros do casal são dados pessoais sensíveis no contexto do produto, mesmo quando a classificação legal exata deve ser confirmada `[INVESTIGAR LGPD]`.
- O app não deve armazenar senha bancária, cookie de internet banking ou token bruto em logs.
- Tokens móveis ficam em Keychain/Keystore/Credential Locker com fallback seguro documentado.
- Biometria apenas desbloqueia credencial local já autorizada; senha do Lar Finance permanece fallback.
- Arquivos importados são criptografados em repouso ou descartados depois de normalizados conforme política escolhida `[INVESTIGAR]`.
- Backup deve ser criptografado, testado por restauração e mantido fora do mesmo disco do servidor doméstico.
- Acesso externo exige HTTPS, proxy confiável, rate limit e allowlist administrativa quando possível.
- Cadastro público e landing foram removidos; criação de usuário é administrativa.
- Exclusões financeiras usam retenção/auditoria e confirmação; nada relevante some sem trilha.

## 10. Cobertura de testes atual

Na branch candidata em 21/08/2026, 581 testes Django e 374 testes Flutter
passaram localmente; Ruff, formato após resolução de dependências, análise,
checks, migrations e cobertura de 95% também passaram. Os builds Windows e APK
release foram produzidos. A CI `32529705321` ficou verde no SHA
`2584fa7db5e9ee9fa158cdfce54d3b2b24ef4a9d`, inclusive nos jobs Windows/MSIX,
Android e iOS. Há testes de isolamento
por Lar, tokens/dispositivos, reutilização de
refresh, idempotência, conflitos, tombstones, cursors, contrato OpenAPI,
observabilidade, migrations fresh/legadas/rollback/replay, backup consistente,
gateway R2, retenção, scheduler, concorrência e logs sanitizados.

Sem cobertura comprovada:

- tag GHCR publicada, associação tag→digest registrada e rollback por digest no EasyPanel real;
- concorrência além da topologia suportada de uma réplica/um worker;
- CSV/outros bancos e escrita offline de cartões/contas fixas;
- instalação em iPhone físico, assinatura e distribuição iOS;
- testes end-to-end autenticados no EasyPanel; a prova atual cobre health e login
  público, processos, integridade e backup, sem navegar nos dados financeiros;
- rate limit persistente de `POST /login/` e alertas externos de backup.

Novos recursos seguirão TDD: teste falha, implementação mínima, refatoração e suíte completa.

## 11. Observabilidade atual

As-is: a API emite log JSON seguro por request, propaga/gera `X-Request-ID`
UUID e expõe `/api/v1/health/`. O payload contém exatamente `status`,
`api_version` e `version`; na release, `version` é o SHA Git de 40 caracteres.
Backup SQLite e auditoria de integridade continuam disponíveis sem PII. Não há
métricas, tracing, alertas, rastreamento de erros ou auditoria de eventos
financeiros.

To-be mínimo:

- logs JSON com `request_id`, sem valores financeiros completos nem PII;
- health, readiness e métrica de última sincronização/backup;
- auditoria separada de eventos financeiros;
- alertas para falha repetida de importação, backup, banco, login suspeito e indisponibilidade;
- painel local ou solução gratuita/self-hosted antes de serviço pago `[INVESTIGAR]`.

## 12. Mapa de telas

```mermaid
flowchart TB
    Login["Login"] --> Home["Visão geral"]
    Home --> Activity["Movimentações"]
    Home --> Cards["Cartões e faturas"]
    Home --> Bills["Contas fixas"]
    Home --> Reports["Relatórios"]
    Activity --> Import["Importar e conciliar"]
    Activity --> Detail["Detalhe do lançamento"]
    Cards --> Statement["Detalhe da fatura"]
    Bills --> BillDetail["Vencimento e pagamento"]
    Activity --> Budgets["Categorias e orçamentos"]
    Home --> More["Mais"]
    More --> Sources["Contas, fontes e proprietários"]
    More --> Export["Exportação"]
    More --> Settings["Segurança, dispositivos e backup"]
```

Navegação compacta usa destinos essenciais e `Mais`; Web/Windows usam
sidebar/rail a partir de 900 px. A nomenclatura e prioridade são comuns, mas a
geometria respeita a plataforma.

## 13. Especificação resumida das telas e estados

- **Login:** email, senha, estado carregando/erro/offline e biometria depois do primeiro acesso. Sem cadastro público.
- **Visão geral:** patrimônio, caixa disponível, compromissos próximos, faturas, evolução e origem/atualização dos dados.
- **Movimentações:** busca, filtros por proprietário/conta/período/tipo, agrupamento por data, pendências de categorização.
- **Importar:** seleção do arquivo, prévia, mapeamento, duplicatas, erros por linha, confirmação e recibo.
- **Cartões:** limite informado, utilizado, disponível, fatura atual, melhor data, fechamento, vencimento e parcelas. Campo desconhecido aparece como “não informado”.
- **Contas fixas:** regras, ocorrências, vencimentos, pagamento, reabertura e saldo livre.
- **Relatórios:** fluxo mensal, categorias, owners e indicadores explicáveis disponíveis.
- **Configurações:** proprietários, instituições, dispositivos, segurança,
  backups e fonte futura; aparência acompanha o sistema sem seletor manual.

Toda tela deve ter loading, vazio útil, erro recuperável, offline, dado desatualizado, acesso negado e sucesso. Gráficos só entram quando respondem uma pergunta clara.

## 14. Integrações nativas, offline e storage

| Capacidade | Uso | Permissão/fallback |
|---|---|---|
| Arquivos | importar OFX; outros formatos são backlog | seletor nativo; digitação manual como fallback |
| Câmera | fotografar documento/fatura em fase posterior | só ao acionar; seleção de arquivo como fallback |
| Biometria | desbloqueio rápido do token local | opt-in; senha como fallback |
| Push | avisos de sincronização, vencimento e backup | opt-in; central interna como fallback |
| Share | receber/compartilhar arquivo financeiro/exportação | seletor de arquivo como fallback |
| Geolocalização | sem necessidade comprovada | não solicitar |

Offline por capacidade:

- leitura vem do SQLite local;
- Account, Category e Transaction usam o ledger local/sync disponível;
- cartões e contas fixas são servidor-autoritativos e exigem internet para
  escrita; cache de última leitura é evolução aprovada;
- sincronização ocorre ao abrir, por ação manual e em segundo plano quando permitido;
- iOS/Android podem limitar execução em background, portanto “sincronização imediata” não é garantida `[INVESTIGAR]`;
- importação OFX envia o arquivo para prévia e confirmação explícita;
- conflitos são apresentados ao usuário quando não houver regra determinística segura.

## 15. Autenticação, i18n, acessibilidade e telemetria

- Interface inicial em `pt-BR`, moeda BRL e datas locais; arquitetura preparada para outros idiomas/moedas sem prometer lançamento.
- VoiceOver, TalkBack e Narrator; alvos de toque, foco visível, contraste WCAG AA, escala de fonte e redução de movimento.
- Valores não dependem apenas de cor; receitas/despesas têm sinal, texto e ícone.
- Analytics será privativo e opt-in quando possível, sem descrição de transação, saldo, CPF, arquivo ou token.
- Eventos úteis: tempo de abertura, importação iniciada/concluída/falha, conflito resolvido, sync concluído/falhou. Eventos não carregam valores financeiros.

## 16. CI/CD e publicação

- GitHub Actions para lint, testes Django, migrations, segurança de dependências, testes Flutter e builds por plataforma.
- Imagens do backend usam a tag versionada/controlada
  `ghcr.io/ludsonfrancisco/finanpy:sha-<sha Git de 40 caracteres>`; a identidade
  imutável é o digest OCI que a Task 7 deve resolver e registrar. O entrypoint
  faz preflight, backup opcional, migration, auditoria e `collectstatic` antes
  de iniciar o Supervisor; a publicação e o deploy reais aguardam a Task 7.
- Windows: MSIX piloto gerado com certificado de teste; distribuição ainda exige
  certificado privado compatível com `CN=Lar Finance Private`.
- Android: distribuição privada primeiro; Play Store depois se fizer sentido `[INVESTIGAR conta e política]`.
- iOS: instalação privada exige Apple Developer/TestFlight ou alternativa permitida; custo e método serão confirmados antes do Sprint de distribuição `[INVESTIGAR]`.
- Segredos ficam no ambiente/secret store, nunca no repositório ou no app.

## 17. Roadmap em sprints

O roteiro atual, critérios e riscos estão em [ROADMAP.md](docs/ROADMAP.md). As
Sprints 0–5 e seus incrementos posteriores entregaram operação, Lar, API/sync,
OFX, fundação Flutter, contas/transações, cartões/faturas, contas fixas,
orçamento e relatórios. O fechamento foi reorganizado em:

- [~] **R1 — Verdade e estabilização:** documentação, CI, dinheiro exato, código
  fail-fast e versão observável estão entregues; publicação GHCR, ensaio de
  rollback da imagem anterior e validação EasyPanel permanecem na Task 7.
- [ ] **R2 — Fundação Web Casa de Valores 2.0:** tokens, tema, assets e shell.
- [ ] **R3 — Paridade visual incremental:** uma tela por task.
- [ ] **R4 — Consistência entre dispositivos:** contrato de maturidade, cache de
  leitura e provas reais.
- [ ] **R5 — Release pessoal estável:** EasyPanel, R2 e instaláveis privados.

PostgreSQL, Open Finance, empréstimos, investimentos e lojas públicas passaram
para backlog opcional e não bloqueiam a V1 pessoal.

## 18. Quick wins

Concluídos: remoção de PII do HEAD, secret scanning, correção do volume
SQLite, remoção de signup/landing, criação do Lar e responsáveis, backup
consistente, auditoria de integridade, rotação externa da credencial histórica,
restauração real off-host em R2, implementação testada do backup diário R2 com
retenção `14/8/12`, CI completa verde e dinheiro exato no Flutter para cartões e
contas fixas. Em 2026-08-13, a automação também foi ativada no EasyPanel e teve
objeto, restart, idempotência e restauração descartável comprovados.

Pendentes imediatos:

- publicar a tag GHCR versionada do SHA candidato, resolver o digest OCI e
  selecionar por digest quando suportado;
- materializar e ensaiar o rollback manual para a imagem anterior;
- validar preflight, topologia e health no EasyPanel sem sobrescrever o
  entrypoint;
- aplicar Casa de Valores 2.0 incrementalmente;
- exibir “não informado” em vez de `R$ 0,00` para dado realmente ausente.

## 19. Riscos por eixo

- **Dados:** arquivos de cada banco mudam de formato. Mitigação: fixtures anonimizadas, perfis versionados e falha explícita.
- **Sincronização:** conflitos e exclusões podem corromper o histórico. Mitigação: versões, tombstones e auditoria.
- **Cartões:** compra, fatura e pagamento podem ser contados duas vezes. Mitigação: agregados separados e conciliação de duas pontas.
- **Servidor doméstico:** energia, internet e disco são pontos únicos de falha. Mitigação: modo offline, UPS `[INVESTIGAR]`, backup externo e monitoramento.
- **Distribuição iOS:** publicação/instalação tem exigências e custo Apple. Mitigação: validar antes de comprometer o sprint.
- **Fornecedor futuro:** preço, cobertura e regra de dois CPFs podem inviabilizar Pierre. Mitigação: adapter portável e importação manual mantida.
- **Escopo:** “trazer tudo” pode virar promessa impossível. Mitigação: matriz de cobertura por fonte e estado “não informado”.
- **Design:** copiar marca de banco cria risco legal e produto sem identidade. Mitigação: inspiração por princípios, identidade própria e gate de aprovação.

## 20. Glossário

- **Household/Lar:** contêiner dos dados financeiros da família.
- **Proprietário financeiro:** pessoa a quem um ativo, passivo ou lançamento pertence; não é login.
- **Fonte:** origem do dado, como manual, OFX, CSV ou provedor.
- **ImportBatch:** lote imutável que registra uma importação.
- **Conciliação:** ligação entre registros que representam o mesmo evento ou duas pontas relacionadas.
- **Idempotência:** reexecutar uma importação sem duplicar o efeito.
- **Outbox:** fila local de alterações ainda não confirmadas pelo servidor.
- **Tombstone:** marcador de exclusão sincronizável.
- **Saldo informado:** saldo declarado pela fonte em uma data.
- **Saldo calculado:** saldo reconstruído a partir de lançamentos.
- **CET:** custo efetivo total de uma operação de crédito.
- **Fatura:** ciclo de compras e ajustes de um cartão, fechado em uma data e vencendo em outra.
- **Patrimônio líquido:** ativos menos passivos.
- **ADR:** registro de decisão arquitetural com contexto e consequências.

## 21. Decisões pendentes `[INVESTIGAR]`

- Arquivos reais exportados por cada instituição e campos disponíveis.
- Titularidade exata das sete conexões e nomes dos cartões adicionais.
- Política de retenção dos arquivos originais.
- SLA doméstico, mecanismo de rollback por digest e rate limit persistente no
  EasyPanel/Cloudflare.
- Classificação/aprovação visual das diferenças dos 10 goldens atuais.
- Política de cache de leitura de cartões e contas fixas.
- Método/custo de distribuição privada no iPhone.
- Cobertura, preço e regra familiar de Pierre no momento do piloto.
- Necessidade real de PDF/OCR após medir OFX/CSV.

## 22. Evidências de auditoria

- O estado do produto no `main` `4810af4`, a CI, a produção pública e a
  paridade Web/Flutter foram revalidados em 20/08/2026. Evidência:
  `docs/audits/2026-08-20-product-state-and-design-parity.md`.
- Nesse SHA, 526 testes Django e 336 Flutter não-golden passaram; Ruff, formato e
  10 goldens mantêm a CI vermelha. Android/iOS passaram e Windows foi bloqueado
  antes do build.
- A Sprint 1 foi mesclada em `origin/main` no commit `20a9c42bc6140fa8576f79b0687420fde283d029`.
- Branches remotas `final-sprints`, `finapy-pwa` e `fix/easytunnel-deploy` foram auditadas por diff em 2026-08-12. Nenhuma deve ser mesclada ou receber cherry-pick no estado atual; evidências e ideias preserváveis estão em `docs/audits/2026-08-12-remote-branches.md`.
- O SQLite real do EasyPanel foi enviado a bucket R2 privado e restaurado em cópia descartável em 2026-08-12; hash, migrations, auditoria e integridade passaram. Evidência: `docs/audits/2026-08-12-production-backup-restore.md`.
- A Sprint 1 registrou 151 testes; a Sprint 2 foi concluída com 277 testes e 98% de cobertura.
- O `main` em `0d85999f4e66290fa06484d802d08fbb310ad164` passou 383 testes e
  98% de cobertura. Em 2026-08-13, foi implantado no EasyPanel `v2.33.1`; a
  automação R2 criou uma única chave, permaneceu idempotente após restart e o
  objeto foi restaurado em cópia descartável com tamanho, SHA-256, migrations,
  auditoria e integridade aprovados. Evidência:
  `docs/audits/automatic-r2-backup-production.md`.
- Ruff com `pyproject.toml`, warnings, Django check, migrations check e deploy
  check passaram localmente; a CI mantém esses gates e secret scan. O Ruff sem
  `--config` ainda encontra dívida legada sob `ruff.toml`.
- Cadastro público e landing foram removidos; login e fallback web privado permanecem.
- O servidor EasyPanel foi atualizado de forma controlada em 2026-08-13. O ensaio
  de restauração nunca apontou para a base real; a base permaneceu íntegra.
- Em 21/08/2026, a CI `32529705321` comprovou no SHA
  `2584fa7db5e9ee9fa158cdfce54d3b2b24ef4a9d` o build da imagem, o health com o
  mesmo SHA e os três processos do Supervisor. O job de publicação GHCR foi
  pulado, porque o evento foi push de branch; nenhuma tag foi publicada.
- A matriz e os ensaios locais sanitizados estão em
  `docs/audits/2026-08-21-fail-fast-deploy-rehearsal.md`. Eles não comprovam
  download R2 atual, imagem anterior ou configuração do EasyPanel.
