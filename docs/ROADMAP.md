# Roadmap de fechamento do Lar Finance

> Reorganizado em 20/08/2026 a partir do código no `main`, da auditoria técnica
> e da decisão visual Casa de Valores 2.0. O objetivo é concluir uma versão
> pessoal confiável, sem expandir escopo por antecipação.

## Regras de execução

- cada task começa somente após autorização do proprietário;
- cada task de código começa com teste falhando quando aplicável;
- ao terminar uma task: verificar, revisar, fazer commit e push e informar o
  próximo passo de forma objetiva;
- ao terminar uma sprint: executar a matriz completa, atualizar documentação,
  fazer commit/push de fechamento e parar para aprovação;
- integridade financeira vale mais que velocidade;
- não misturar migration de dados, mudança de deploy e redesenho amplo;
- não retirar a Web: Web e Flutter continuarão partes do mesmo produto;
- `[INVESTIGAR]` não vira comportamento por suposição;
- roteamento de modelo segue `docs/ai-model-routing.md` e deve ser revalidado no
  ambiente ativo.

## Definition of Done global

- [ ] escopo da task permaneceu fechado;
- [ ] testes novos e existentes relevantes passam;
- [ ] lint, formato, checks e migrations estão limpos;
- [ ] dinheiro não usa ponto flutuante no domínio;
- [ ] isolamento por Lar/proprietário está coberto;
- [ ] loading, vazio, erro, offline e stale estão cobertos quando houver UI;
- [ ] logs não expõem PII, valores, arquivo bancário ou tokens;
- [ ] acessibilidade e responsividade foram verificadas;
- [ ] documentação e OpenAPI refletem o código;
- [ ] backup/rollback foram avaliados quando há dados ou infraestrutura;
- [ ] revisão técnica/visual não deixou Critical ou Important aberto;
- [ ] commit e push concluídos antes de avançar.

## Baseline real em 20/08/2026

- `main` e `origin/main`: `4810af4e67d23d36268b74e9654ead1978e8f707`;
- origem EasyPanel confirmada como GitHub `main`; health público 200;
- 20 models Django, 32 migrations e 32 rotas da API;
- 526 testes Django e 336 testes Flutter não-golden passando;
- CI vermelha por 7 achados Ruff, 17 arquivos Dart fora do formato e 10 goldens;
- Android e iOS sem assinatura compilam na CI; Windows foi bloqueado antes do
  build pelo gate de goldens;
- auditoria completa:
  `docs/audits/2026-08-20-product-state-and-design-parity.md`.

## Histórico entregue

| Marco | Estado comprovado |
|---|---|
| Sprint 0 — operação e backup | acesso privado, volume SQLite, secret scan, R2 diário e restauração |
| Sprint 1 — Lar e ledger | Household, memberships, owners e integridade |
| Sprint 2 — API e sync | autenticação por dispositivo, bootstrap, push/pull, cursors e tombstones |
| Sprint 3 — OFX backend | prévia, deduplicação, confirmação e purge |
| Sprint 4 — Flutter | Windows/Android/iOS, Drift, sessão, Home e sync |
| Sprint 5 — OFX Flutter | seleção, prévia, vínculo e confirmação no cliente |
| Incrementos posteriores | contas/transações Flutter, cartões/faturas, contas fixas, orçamento, relatórios e redesign Web |

Os documentos específicos dessas entregas permanecem como evidência histórica em
`docs/sprints/`. Checkboxes antigos não governam mais o trabalho atual.

## R1 — Verdade e estabilização

Objetivo: congelar expansão e recuperar uma base liberável antes do redesenho.

### R1.1 — Fonte única de verdade

- [x] auditar código, produção, CI e interfaces;
- [x] corrigir inventário de funcionalidades e riscos no PRD;
- [x] substituir o roadmap antigo por ciclos de fechamento;
- [x] oficializar Casa de Valores 2.0;
- [x] alinhar README e instruções de agentes.

### R1.2 — Gates de qualidade

- [x] corrigir os 7 achados Ruff sem mudança funcional não relacionada;
- [x] formatar os 17 arquivos Dart;
- [x] classificar as diferenças dos 10 goldens como regressão ou mudança
  intencional;
- [x] manter ou atualizar goldens somente após aprovação visual;
- [x] provar CI completa verde.

### R1.3 — Dinheiro exato em cartões e contas fixas

- [x] escrever testes de parsing, serialização e arredondamento;
- [x] substituir `double` por minor units/tipo decimal exato no domínio Flutter;
- [x] preservar `double` somente em percentuais, animações e geometria;
- [x] validar contratos backend `Decimal` ↔ Flutter;
- [x] provar que os 12 goldens permanecem inalterados.

### R1.4 — Deploy fail-fast e versão observável

- [x] reproduzir o fail-fast em SQLite descartável sem alterar hash ou migrations;
- [x] retirar `migrate` de `core/wsgi.py`;
- [x] executar preflight, backup opcional, migration, auditoria e `collectstatic`
  antes de iniciar Supervisor;
- [x] abortar o entrypoint quando qualquer etapa de preparação falhar;
- [x] expor versão/SHA sem segredo no health, com os campos exatos `status`,
  `api_version` e `version`;
- [x] comprovar na CI `32529705321` a imagem, o health com SHA e os três processos;
- [x] Task 7: publicar `v1.4.0` e a tag por SHA, resolver o digest OCI, implantar
  por digest, restaurar o R2 em cópia descartável e validar no EasyPanel uma
  réplica, um worker, os dois schedulers, smoke autenticado e restart;
- [x] preservar `rollback/pre-r1.4` no SHA anterior e documentar que a primeira
  release GHCR não possui digest anterior para ensaio literal.

R1.4 está **concluída com a limitação de primeira release registrada**. A imagem
ativa é o SHA `5e62f84d` pelo digest `sha256:0d1621…5b5e3`; a próxima release
deve ensaiar o digest R1.4 como imagem anterior. Evidência:
`docs/audits/2026-08-21-fail-fast-deploy-rehearsal.md`.

Aceite R1: CI verde, dinheiro recente exato, deploy não inicia com schema inválido
e documentação corresponde ao código.

Riscos: golden esconder regressão real; alteração monetária mudar payload;
EasyPanel não suportar o hook imaginado. Mitigação: RED/GREEN, fixtures de
centavos, ensaio em cópia e rollback para imagem anterior.

## R2 — Fundação Web Casa de Valores 2.0

Objetivo: criar a mesma linguagem visual do Flutter preservando os elementos Web
aprovados.

### R2.1 — Tokens e contrato visual

- [x] criar variáveis CSS para os tokens oficiais claro/escuro;
- [x] adicionar teste de paridade token Flutter ↔ Web;
- [x] usar stack tipográfica nativa e números tabulares;
- [x] centralizar spacing, radius, bordas, elevação e motion;
- [x] remover cores estruturais hardcoded do shell.

Evidência R2.1: commits de implementação `e001fc5`, `2c436c7`, `4278b6e` e
`62f63dd`; suíte Django: 591 testes, suíte Flutter (golden excluído): 364
testes.

Correções pós-revisão R2.1: `6a53c5744a32117f73586fbe4beb744720d7389b` e
`b2dd2f84a6d0e8244e99fc747a3e0e8197e46c2f`.

### R2.2 — Tema e assets

- [ ] seguir `prefers-color-scheme` automaticamente, sem botão;
- [ ] impedir flash de tema incorreto;
- [ ] fixar versões e servir Tailwind/Alpine/Chart.js localmente;
- [ ] remover dependência de Google Fonts;
- [ ] manter CSP e funcionamento sem CDN externo.

### R2.3 — Shell adaptativo

- [ ] sidebar/rail a partir de 900 px;
- [ ] navegação inferior abaixo de 900 px;
- [ ] padronizar owner selector, status de atualização e privacidade;
- [ ] cobrir teclado, foco, 320/375/768/1280 px e escala 200%;
- [ ] preservar skip link e semântica HTML.

Aceite R2: login/shell em claro e escuro pertencem ao mesmo sistema do Flutter,
sem remover conteúdo financeiro.

Riscos: substituir CDN alterar estilos existentes; tema automático causar flash;
sidebar/navegação mudar rotas. Mitigação: tokens primeiro, screenshots e rollout
por shell compartilhado.

## R3 — Paridade visual incremental

Objetivo: convergir tela a tela, sem grande redesign único.

Cada item é uma task independente:

- [ ] R3.1 Login;
- [x] R3.2 Dashboard/Home;
- [ ] R3.3 Contas e movimentações;
- [ ] R3.4 Categorias e orçamento;
- [ ] R3.5 Cartões e faturas;
- [ ] R3.6 Contas fixas;
- [ ] R3.7 Importação OFX;
- [ ] R3.8 Relatórios e perfil.

Evidência R3.2: Dashboard Web e Home Flutter entregues nos commits `2f340af`,
`79af9fa`, `77a5e5a` e `baee787`, com formalização documental em `87214a3`,
fechamento em `e1c0b11` e agrupamento monetário pt-BR em `b58a647`. Gates locais:
Django 607 testes; Flutter 369 testes sem golden e 6 goldens; formatter,
análise estática, tokens, Ruff, system check e migrations check sem falhas. Os
seis renders golden foram inspecionados e regenerados sem diff. A Dashboard
autenticada foi validada em 375, 900 e 1280 px, com capturas em
`.impeccable/review/web-{375,900,1280}.png`, ordem, ações, gráficos, ausência de
overflow e console sem erro. CI: workflow `CI` verificado no HEAD exato após o
push; URL e conclusão permanecem no relatório local de fechamento ignorado.

Critérios comuns:

- mesma nomenclatura, hierarquia e estado nas plataformas;
- conteúdo Web mais rico permanece abaixo da hierarquia principal;
- cerca de 25% menos ornamentação, sem apagar cards/gráficos aprovados;
- dinheiro pt-BR, exato e tabular;
- loading, vazio, erro, offline e stale;
- goldens/screenshots aprovados antes de substituir baseline.

Aceite R3: usuário reconhece imediatamente Web, Windows, Android e iOS como o
mesmo produto, com composição apropriada a cada plataforma.

Riscos: paridade virar cópia pixel a pixel; reduzir densidade útil da Web;
alterar tudo de uma vez. Mitigação: uma tela por task e aprovação visual.

## R4 — Consistência entre dispositivos

Objetivo: tornar explícito o que sincroniza e o que exige internet.

### R4.1 — Contrato de maturidade por recurso

- [ ] documentar Account/Category/Transaction como ledger offline/delta;
- [ ] documentar Card/Bill como servidor autoritativo e escrita online;
- [ ] exibir freshness e indisponibilidade sem fingir sincronização;
- [ ] atualizar OpenAPI e UX com essa distinção.

### R4.2 — Cache de leitura para cartões e contas fixas

- [ ] adicionar snapshot local da última leitura válida;
- [ ] nunca permitir mutação offline silenciosa nesses módulos;
- [ ] invalidar/refazer cache após escrita online;
- [ ] cobrir migração, logout, troca de sessão e dado stale.

### R4.3 — Prova entre dispositivos

- [ ] importar/editar no Windows e ler no Android/iPhone;
- [ ] editar online no mobile e ler na Web/Windows;
- [ ] provar offline e reconexão;
- [ ] validar que nenhum evento duplica.

Aceite R4: todo recurso informa claramente origem e atualização; os caminhos
reais entre dispositivos são reproduzíveis.

Riscos: criar segundo mecanismo de sync; cache expor sessão anterior. Mitigação:
cache somente leitura, vinculado à identidade da sessão, com servidor canônico.

## R5 — Release pessoal estável

Objetivo: instalar e usar continuamente sem depender do ambiente de
desenvolvimento.

- [ ] CI completa verde no SHA candidato;
- [ ] deploy EasyPanel fail-fast e smoke autenticado sanitizado;
- [ ] backup R2 e restauração do schema candidato;
- [ ] Windows/MSIX privado testado;
- [ ] APK Android privado testado;
- [ ] instalação iPhone por método aprovado `[INVESTIGAR conta Apple]`;
- [ ] teste das jornadas críticas nos dispositivos reais;
- [ ] manual curto de instalação/atualização/rollback;
- [ ] PRD, OpenAPI, README e runbooks finais;
- [ ] tag de versão pessoal estável.

Aceite R5: o proprietário consegue instalar, atualizar, usar e restaurar o Lar
Finance sem intervenção de desenvolvimento na rotina normal.

Riscos: assinatura iOS/Windows, diferença entre CI e dispositivo, rollback de
produção. Mitigação: distribuição privada, smoke real, tag versionada e imagem
fixada por digest OCI quando suportado.

## Backlog opcional após uso real

Não bloqueiam a V1 pessoal:

- PostgreSQL ou múltiplas réplicas;
- cadastro público, múltiplos lares e cobrança;
- Open Finance/Pierre;
- empréstimos e financiamentos completos;
- investimentos, bens e patrimônio avançado;
- PDF/OCR e novos formatos além do OFX necessário;
- escrita offline para cartões e contas fixas;
- notificações push e telemetria complexa;
- publicação em lojas públicas.

Esses itens só voltam ao roadmap quando houver dor comprovada, fonte de dados
real, custo aceito e uma especificação aprovada.
