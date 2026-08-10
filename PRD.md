# Lar Finance — PRD do estado atual e evolução do produto

> Fonte única de verdade do produto. Atualizado em 10/08/2026 a partir do código da branch `main`, migrations, 151 testes, configuração Docker e documentação operacional.

## Status e convenções

- **Nome oficial:** Lar Finance.
- **Nome técnico legado:** Finanpy, mantido temporariamente no repositório, módulos Django e implantação até uma migração segura.
- **Estado atual:** aplicação web Django privada, com Lar compartilhado, membros, responsáveis financeiros, contas, categorias, transações e dashboard consolidado.
- **Produto alvo:** aplicativo Flutter para iOS, Android e Windows, sincronizado com o backend Django no servidor Linux/EasyPanel.
- **Estratégia de dados aprovada:** importação de arquivos primeiro; integração paga automática somente após o produto estar maduro e em uso.
- **Usuários do produto:** uma família no mesmo Lar, com um único login compartilhado nesta fase. Cada dispositivo terá sessão própria e revogável. O domínio mantém credenciais de acesso separadas dos responsáveis financeiros `Eu`, `Esposa` e `Conjunto`, permitindo dois logins no futuro sem migrar o ledger.
- **Identidade visual:** em avaliação. A preferência por uma linguagem fintech premium semelhante em espírito ao C6 Bank é uma referência candidata, não uma decisão final.
- **Regra visual irrevogável:** não usar roxo.
- **`[INVESTIGAR]`:** decisão ou comportamento sem evidência suficiente. Não deve ser implementado por suposição.
- **`As-is`:** comportamento comprovado no código atual.
- **`To-be`:** comportamento alvo aprovado para construção incremental.

## 1. Visão geral

### 1.1 Problema

As informações financeiras do casal estão fragmentadas entre Nubank, Inter, Santander e Mercado Pago. O controle precisa reunir movimentações, cartões, faturas, limites, empréstimos, investimentos, patrimônio, compromissos e objetivos sem depender de uma assinatura cara na primeira fase.

### 1.2 Proposta de valor

O Lar Finance será o painel financeiro privado da família: uma visão confiável do que entrou, saiu, está comprometido, deve ser pago, pertence a cada pessoa e compõe o patrimônio conjunto. O sistema ajuda a tomar decisões, mas não movimenta dinheiro, não guarda senhas bancárias e não substitui aconselhamento financeiro profissional.

### 1.3 Escopo funcional alvo

- Visão individual, da esposa e consolidada do lar.
- Contas, carteiras e saldos.
- Cartões, limites, faturas, vencimentos, fechamentos, parcelamentos e cartões adicionais.
- Receitas, despesas, transferências, estornos, juros, tarifas e ajustes.
- Importação OFX e CSV; PDF e planilhas por adaptadores específicos quando viável.
- Conciliação, deduplicação e trilha de auditoria de toda importação.
- Categorias, tags, favorecidos, regras de categorização e recorrências.
- Orçamentos, metas, reserva de emergência e previsão de caixa.
- Empréstimos e financiamentos, incluindo saldo, parcelas, taxa e CET quando disponíveis.
- Investimentos, bens, direitos, dívidas e patrimônio líquido.
- Relatórios e indicadores explicáveis, sem “score” opaco.
- Sincronização entre Windows, iOS e Android.
- Exportação e backup dos próprios dados.
- Adaptador futuro para Pierre ou outro provedor, sem acoplar o domínio ao fornecedor.

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
- Operações feitas offline sincronizam depois sem perda silenciosa.
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
| WSGI | Gunicorn 23.0.0, 1 worker | requirements, Docker e Compose |
| Imagens | Pillow 12.2.0 | `requirements.txt` |
| Ambiente | python-dotenv 1.2.2 | `requirements.txt` |
| Runtime indireto | asgiref 3.11.1, sqlparse 0.5.5, tzdata 2026.1 | `requirements.txt` |
| Qualidade | Ruff 0.15.11, Coverage 7.13.5 | `requirements.txt` |
| Banco | SQLite, caminho absoluto configurável; `/app/data/db.sqlite3` no container | `core/settings.py`, Docker e Compose |
| Frontend | Django Templates, HTML/CSS/JavaScript e Tailwind via CDN | templates e documentação |
| Fila/cache | inexistentes | settings e dependências |
| Container | Docker multi-stage + Docker Compose | arquivos raiz |
| Produção informada | Linux em EasyPanel, servidor doméstico | informação do proprietário; configuração externa não versionada `[INVESTIGAR]` |

Nenhuma dependência Flutter, API REST, PostgreSQL, parser OFX/CSV, fila ou provedor financeiro está presente na `main`.

### 3.2 Stack alvo, ainda não instalada

| Camada | Direção | Estado |
|---|---|---|
| Cliente | Flutter, um código-base para iOS, Android e Windows | aprovado; versão exata será fixada no Sprint 0 `[INVESTIGAR]` |
| Backend | Django preservado e transformado em API versionada | aprovado |
| API | Django REST Framework ou alternativa compatível | escolha e versão `[INVESTIGAR]` por ADR |
| Banco servidor | PostgreSQL | aprovado como direção; versão/imagem EasyPanel `[INVESTIGAR]` |
| Banco local | SQLite com camada reativa e fila de sincronização | aprovado; pacote `[INVESTIGAR]` |
| Autenticação | login familiar único; token curto e renovação rotativa por dispositivo em armazenamento seguro | desenho aprovado; pacote e tempos exatos `[INVESTIGAR]` por ADR |
| Importação | OFX e CSV primeiro; PDF/XLSX por adaptadores | aprovado |
| Automação futura | adaptador de provedor, inicialmente candidato Pierre | contratação e suporte a dois CPFs `[INVESTIGAR]` |

Não há versões exatas para componentes ainda não adicionados ao repositório. Inventá-las agora violaria a política de evidência; o Sprint 0 cria o lockfile e registra as versões escolhidas.

## 4. Arquitetura

### 4.1 As-is

Monólito Django MVC/MTV server-rendered, separado por apps de domínio simples. Regras e acesso a dados estão concentrados em models, forms e class-based views. Não há camada de API nem serviço de sincronização.

```mermaid
flowchart TB
    Browser["Navegador"] --> Templates["Django Templates + CSS/JS"]
    Templates --> Views["CBVs e Forms"]
    Views --> ORM["Django ORM"]
    ORM --> SQLite[("SQLite")]
    Views --> Auth["Sessão Django"]
    Gunicorn["Gunicorn no container"] --> Views
```

Apps: `core`, `users`, `profiles`, `accounts`, `categories`, `transactions` e `ai`. O app `ai` está instalado, porém sua função produtiva precisa ser validada `[INVESTIGAR]`.

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
    Domain --> PG[("PostgreSQL")]
    API --> Import["Pipeline de importação e conciliação"]
    Import --> PG
    Provider["Adaptadores: arquivos / futuro provedor"] --> Import
    Worker["Jobs assíncronos, se necessários"] --> Import
    Ops["Logs, métricas, alertas e backup"] --> API
    Ops --> PG
```

Princípios:

- evolução por módulos, sem rewrite total do backend;
- API e domínio não conhecem widgets Flutter;
- importadores e provedores implementam contratos substituíveis;
- PostgreSQL no servidor é a fonte canônica;
- SQLite local sustenta leitura rápida, offline e fila de mudanças;
- todo registro sincronizável recebe UUID, versão, timestamps e marcador de exclusão;
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
| `accounts.Account` | nome, tipo, saldo inicial, moeda, timestamps | N:1 Household, User legado e FinancialOwner |
| `categories.Category` | nome, tipo receita/despesa, cor, ícone | N:1 Household e User legado; único no escopo definido |
| `transactions.Transaction` | descrição, valor, data, tipo, timestamps | N:1 Household, User legado, FinancialOwner, Account e Category |

Lacunas comprovadas: não há instituição normalizada, UUID/versão de sync nas entidades financeiras legadas, transferência com duas pontas, fatura, limite, parcela, recorrência, dívida, investimento, importação, deduplicação, moeda por cotação, anexo ou trilha de eventos financeiros. Existe auditoria de integridade do Lar, mas não `AuditEvent` de negócio.

### 5.2 To-be

Núcleo proposto: `Household`, `FinancialOwner`, `Institution`, `FinancialAccount`, `CreditCard`, `CardStatement`, `CardTransaction`, `Transaction`, `Transfer`, `Category`, `Tag`, `Counterparty`, `RecurringRule`, `Budget`, `Goal`, `Loan`, `LoanInstallment`, `InvestmentPosition`, `Asset`, `Liability`, `ImportBatch`, `ImportRecord`, `ReconciliationIssue`, `ProviderConnection`, `SyncDevice` e `AuditEvent`.

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
| vários | `/admin/` | staff | Django Admin |
| GET | `/media/*` | conforme settings | mídia servida pelo Django na configuração atual |

### 6.2 API alvo

Prefixo `/api/v1/`. Recursos previstos: autenticação, sessão/dispositivos, household/owners, instituições, contas, cartões/faturas, transações/transferências, categorias/tags, recorrências, orçamentos/metas, empréstimos, investimentos/patrimônio, importações/conciliação, dashboard/relatórios e sincronização incremental.

O contrato exato e verbos serão definidos antes do código em OpenAPI `[INVESTIGAR]`. O app Flutter não consumirá páginas HTML.

### 6.3 Comandos atuais

`manage.py migrate`, `collectstatic`, `runserver`, `test`, `check`, `makemigrations --check`, `createsuperuser`, `backup_sqlite`, `audit_household_integrity`, `coverage` e `ruff`. Os scripts de QA foram neutralizados no HEAD; a credencial histórica ainda precisa ser rotacionada pelo proprietário.

## 7. Integrações backend e externas

### 7.1 Comprovadas hoje

- SMTP, Open Finance, webhooks, filas e analytics: ausentes.
- Docker/EasyPanel: implantação informada; manifesto real do EasyPanel não está versionado `[INVESTIGAR]`.
- Tailwind e fontes por CDN: dependência de rede no frontend web atual.

### 7.2 Importação aprovada

- **OFX:** primeira opção para extrato de conta e movimentações quando o banco oferece.
- **CSV:** suportado por perfis de instituição e mapeamento revisável.
- **PDF:** útil para faturas/extratos, mas exige parser específico; não entra no primeiro importador genérico.
- **XLS/XLSX:** útil para exportações e planilhas existentes; esquema varia por origem.
- **Manual:** obrigatório para limite, CET, bens ou posições que a fonte não exportar.

Arquivos transacionais normalmente não garantem limite de cartão, empréstimos, investimentos ou patrimônio. A cobertura de Nubank, Inter, Santander e Mercado Pago será testada com arquivos reais anonimizados `[INVESTIGAR]`.

### 7.3 Automação futura

Pierre é candidato por caber aproximadamente no teto informado de R$40/mês para uma conta, mas a cobertura de sete conexões e dois CPFs/consentimentos precisa de confirmação contratual `[INVESTIGAR]`. O domínio deve aceitar qualquer provedor que implemente o contrato interno e nunca depender do formato proprietário.

Detalhes: [importação e sincronização](docs/imports-and-sync.md).

## 8. Débitos técnicos

| Severidade | Evidência | Impacto | Tratamento |
|---|---|---|---|
| Crítico | credencial existiu no histórico Git; valores foram removidos do HEAD | acesso indevido caso a credencial continue válida | proprietário deve rotacionar; avaliar reescrita do histórico separadamente |
| Resolvido | volume SQLite antes apontava para caminho de arquivo | persistência/boot não confiáveis | Sprint 1 passou a montar `/app/data`; validar no EasyPanel real |
| Alto | settings únicos para dev/prod e headers de segurança não evidenciados | exposição em produção | settings por ambiente e `check --deploy` |
| Alto | SQLite com múltiplos clientes e sincronização futura | concorrência, lock e backup frágil | PostgreSQL incremental |
| Alto | nenhuma API versionada | bloqueia Flutter | API v1 + OpenAPI |
| Alto | modelo mistura cartão e conta | saldos/faturas incorretos | separar agregados antes da importação completa |
| Alto | ausência de importação/deduplicação/auditoria | trabalho manual e dados duplicados | pipeline idempotente |
| Médio | documentação de arquitetura diz que só `/admin/` existe | onboarding e operação incorretos | documentação atualizada neste PRD |
| Médio | UI por CDN e assets remotos | indisponibilidade/CSP | bundle local no fallback web |
| Médio | cálculos no dashboard e propriedade `current_balance` podem causar consultas repetidas | degradação com volume | consultas agregadas/testes de performance |
| Resolvido | cobertura percentual não estava configurada como gate | regressões invisíveis | CI exige no mínimo 90%; resultado atual 98% |
| Resolvido | screenshots/relatórios privados estavam versionados | PII e ruído no repositório | artefatos removidos e padrões adicionados ao `.gitignore` |

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

Após a Sprint 1, 151 testes Django passaram, com 98% de cobertura (2.664 statements, 41 não cobertos). Ruff, Django check, migrations check e deploy check estrito também passaram. Há testes de isolamento por Lar, acesso revogado, integridade, migrations fresh/legadas/rollback, backup, CRUD, filtros e dashboard consolidado.

Sem cobertura comprovada:

- recuperação de acesso e ciclo mobile de tokens/dispositivos;
- dashboard e suas agregações;
- upload de avatar/mídia;
- operação real no EasyPanel e restauração de backup externo;
- concorrência real e persistência após reinício no host;
- API, importações, deduplicação, cartões, faturas, sincronização, offline e Flutter, pois não existem;
- testes end-to-end reais no EasyPanel;
- teste de restauração fora do host/volume de produção.

Novos recursos seguirão TDD: teste falha, implementação mínima, refatoração e suíte completa.

## 11. Observabilidade atual

As-is: logs padrão do Django/Gunicorn, backup SQLite verificado e comando de auditoria de integridade sem PII. Não há configuração comprovada de logs estruturados, correlação, métricas, tracing, health/readiness checks, alertas, rastreamento de erros ou auditoria de eventos financeiros.

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
    Home --> Plan["Planejamento"]
    Home --> Wealth["Patrimônio"]
    Activity --> Import["Importar e conciliar"]
    Activity --> Detail["Detalhe do lançamento"]
    Cards --> Statement["Detalhe da fatura"]
    Plan --> Budgets["Orçamentos e recorrências"]
    Plan --> Goals["Metas e reserva"]
    Wealth --> Loans["Empréstimos e dívidas"]
    Wealth --> Investments["Investimentos e bens"]
    Home --> More["Mais"]
    More --> Sources["Contas, fontes e proprietários"]
    More --> Reports["Relatórios e exportação"]
    More --> Settings["Segurança, dispositivos e backup"]
```

Navegação mobile: no máximo cinco destinos, com hierarquia a validar em protótipo. Windows usa rail/sidebar adaptativa preservando os mesmos nomes e fluxos. Especificações: [UX mobile](docs/mobile-ux.md).

## 13. Especificação resumida das telas e estados

- **Login:** email, senha, estado carregando/erro/offline e biometria depois do primeiro acesso. Sem cadastro público.
- **Visão geral:** patrimônio, caixa disponível, compromissos próximos, faturas, evolução e origem/atualização dos dados.
- **Movimentações:** busca, filtros por proprietário/conta/período/tipo, agrupamento por data, pendências de categorização.
- **Importar:** seleção do arquivo, prévia, mapeamento, duplicatas, erros por linha, confirmação e recibo.
- **Cartões:** limite informado, utilizado, disponível, fatura atual, melhor data, fechamento, vencimento e parcelas. Campo desconhecido aparece como “não informado”.
- **Planejamento:** orçamento realizado/previsto, recorrências, calendário e metas.
- **Patrimônio:** ativos, passivos, investimentos, empréstimos e evolução do patrimônio líquido.
- **Relatórios:** fluxo de caixa, categorias, favorecidos, comparação mensal, exportação.
- **Configurações:** proprietários, instituições, dispositivos, segurança, backups, fonte futura e tema.

Toda tela deve ter loading, vazio útil, erro recuperável, offline, dado desatualizado, acesso negado e sucesso. Gráficos só entram quando respondem uma pergunta clara.

## 14. Integrações nativas, offline e storage

| Capacidade | Uso | Permissão/fallback |
|---|---|---|
| Arquivos | importar OFX/CSV/PDF/XLSX | seletor nativo; digitação manual como fallback |
| Câmera | fotografar documento/fatura em fase posterior | só ao acionar; seleção de arquivo como fallback |
| Biometria | desbloqueio rápido do token local | opt-in; senha como fallback |
| Push | avisos de sincronização, vencimento e backup | opt-in; central interna como fallback |
| Share | receber/compartilhar arquivo financeiro/exportação | seletor de arquivo como fallback |
| Geolocalização | sem necessidade comprovada | não solicitar |

Offline-first:

- leitura vem do SQLite local;
- mudanças entram em outbox com UUID e versão;
- sincronização ocorre ao abrir, por ação manual e em segundo plano quando permitido;
- iOS/Android podem limitar execução em background, portanto “sincronização imediata” não é garantida `[INVESTIGAR]`;
- importação pesada deve subir o arquivo/manifesto e acompanhar o job;
- conflitos são apresentados ao usuário quando não houver regra determinística segura.

## 15. Autenticação, i18n, acessibilidade e telemetria

- Interface inicial em `pt-BR`, moeda BRL e datas locais; arquitetura preparada para outros idiomas/moedas sem prometer lançamento.
- VoiceOver, TalkBack e Narrator; alvos de toque, foco visível, contraste WCAG AA, escala de fonte e redução de movimento.
- Valores não dependem apenas de cor; receitas/despesas têm sinal, texto e ícone.
- Analytics será privativo e opt-in quando possível, sem descrição de transação, saldo, CPF, arquivo ou token.
- Eventos úteis: tempo de abertura, importação iniciada/concluída/falha, conflito resolvido, sync concluído/falhou. Eventos não carregam valores financeiros.

## 16. CI/CD e publicação

- GitHub Actions para lint, testes Django, migrations, segurança de dependências, testes Flutter e builds por plataforma.
- Imagens do backend identificadas por commit e implantadas no EasyPanel com migração controlada.
- Windows: pacote assinado/instalável `[INVESTIGAR certificado]`.
- Android: distribuição privada primeiro; Play Store depois se fizer sentido `[INVESTIGAR conta e política]`.
- iOS: instalação privada exige Apple Developer/TestFlight ou alternativa permitida; custo e método serão confirmados antes do Sprint de distribuição `[INVESTIGAR]`.
- Segredos ficam no ambiente/secret store, nunca no repositório ou no app.

## 17. Roadmap em sprints

O roteiro completo, dependências, riscos e critérios de aceite estão em [ROADMAP.md](docs/ROADMAP.md). Ordem resumida:

- [x] Sprint 1: acesso por Lar, responsáveis, backfill e integridade do ledger legado.
- [ ] Fundação operacional restante: rotação da credencial, restauração externa e validação do EasyPanel real.
- [ ] Sprint 2: API v1, autenticação e contrato de sincronização.
- [ ] Sprint 3: importação OFX/CSV, deduplicação e conciliação.
- [ ] Sprint 4: cartões, faturas, limites e parcelamentos.
- [ ] Sprint 5: shell Flutter, login, storage seguro e offline.
- [ ] Sprint 6: visão geral, movimentações e proprietários.
- [ ] Sprint 7: orçamento, recorrências, calendário e metas.
- [ ] Sprint 8: empréstimos, financiamentos e dívidas.
- [ ] Sprint 9: investimentos, bens e patrimônio líquido.
- [ ] Sprint 10: relatórios, previsões e saúde financeira explicável.
- [ ] Sprint 11: PostgreSQL, EasyPanel, backup e observabilidade.
- [ ] Sprint 12: performance, acessibilidade, segurança e testes finais.
- [ ] Sprint 13: distribuição Windows, Android e iOS.
- [ ] Sprint 14: piloto opcional do adaptador Pierre/provedor.

## 18. Quick wins

Concluídos: remoção de PII do HEAD, secret scanning, correção do volume SQLite, remoção de signup/landing, criação do Lar e responsáveis, backup consistente e auditoria de integridade.

Pendentes:

- Rotacionar a credencial histórica fora do código.
- Validar backup/restauração e o runbook no EasyPanel real.
- Adicionar hash idempotente e `ImportBatch` antes do primeiro importador.
- Separar “cartão” de “conta” antes de calcular saldos.
- Exibir “não informado” em vez de `R$ 0,00` para dados ausentes.
- Criar backup automatizado com teste de restauração.
- Corrigir documentação divergente e padronizar UTF-8.

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

- Design system final do Lar Finance, incluindo claro/escuro, paleta, tipografia, ícones e motion.
- Arquivos reais exportados por cada instituição e campos disponíveis.
- Titularidade exata das sete conexões e nomes dos cartões adicionais.
- Política de retenção dos arquivos originais.
- Forma de acesso externo ao EasyPanel, domínio, TLS e disponibilidade do servidor.
- Versões/pacotes do Flutter, API, SQLite local e PostgreSQL.
- Estratégia exata de conflitos e exclusões por entidade.
- Método/custo de distribuição privada no iPhone.
- Cobertura, preço e regra familiar de Pierre no momento do piloto.
- Necessidade real de PDF/OCR após medir OFX/CSV.

## 22. Evidências de auditoria

- A Sprint 1 foi mesclada em `origin/main` no commit `20a9c42bc6140fa8576f79b0687420fde283d029`.
- Branches remotas `final-sprints`, `finapy-pwa` e `fix/easytunnel-deploy` têm commits não incorporados; devem ser auditadas por diff, nunca mescladas em bloco.
- 151 testes Django passaram; a cobertura registrada foi 98%.
- Ruff, Django check, migrations check, deploy check e GitHub Actions passaram.
- Cadastro público e landing foram removidos; login e fallback web privado permanecem.
- O servidor EasyPanel e a base real não foram alterados durante a sprint.
