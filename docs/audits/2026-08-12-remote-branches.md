# Auditoria das branches remotas legadas

Data: 2026-08-12

Escopo somente leitura:

- `origin/final-sprints`;
- `origin/finapy-pwa`;
- `origin/fix/easytunnel-deploy`.

Nenhuma branch foi mesclada, alterada ou removida. Servidor, EasyPanel e banco
real não foram acessados.

## Routing da tarefa

**Modelo recomendado:** `gpt-5.6-sol`

**Intensidade recomendada:** `high`

**Motivo:** comparação de três linhas antigas com mudanças de autenticação,
privacidade, dados financeiros, deploy e cache offline. Um erro de triagem poderia
contaminar várias sprints posteriores.

**Consumo esperado:** Alto

**Ferramentas necessárias:** Git e leitura estática de código/documentação

## Base e divergência

As três branches divergem de `main` no commit
`f029c14e2ba6ac55567bc1a33fb7ce32080be1aa`, anterior às Sprints 1 e 2. No
momento da auditoria, `main` tinha 53 commits exclusivos em relação a cada uma.

| Branch | Commits exclusivos da branch | Arquivos no diff | Relação |
|---|---:|---:|---|
| `final-sprints` | 4 | 51 | base da antiga IA/settings |
| `finapy-pwa` | 15 | 77 | contém integralmente `final-sprints` e mais 11 commits |
| `fix/easytunnel-deploy` | 2 | 6 | linha separada de deploy |

Conclusão comum: merge em bloco não é seguro. As branches usam o modelo antigo
por usuário e não conhecem `Household`, `FinancialOwner`, API v1, sessões de
dispositivo ou contrato de sincronização entregues depois.

## `origin/final-sprints`

### Conteúdo

- separação antiga de settings development/production;
- integração LangChain/OpenAI para gerar análise financeira;
- persistência de `AIAnalysis` e comando para todos os usuários;
- alteração extensa do dashboard;
- remoção de capturas QA já removidas da linha atual.

### Achados

**Crítico — privacidade e fronteira de autorização.**
`ai/services/analysis_service.py` filtra por `user`, não por Lar, converte saldos
e totais em `float` e monta contexto com nome/email, contas, saldos, receitas,
despesas e categorias. `ai/agents/finance_insight_agent.py` envia o dicionário
como texto para provedor externo. Isso viola as fronteiras atuais de Lar, a regra
de dinheiro com `Decimal` e a política de não enviar dados financeiros/PII sem
decisão explícita.

**Alto — PII em saída operacional.**
`run_finance_analysis.py` imprime email e mensagem bruta de exceção. Falta
sanitização e correlação segura.

**Alto — dependências e contrato não reproduzíveis.**
`langchain`, `langchain-openai`, `langchain-core` e `openai` não possuem versões
fixadas. Modelo é literal no código. Custo, disponibilidade, consentimento,
retenção e exclusão pelo provedor não foram decididos.

**Alto — ausência de testes novos.**
O diff não adiciona suíte para isolamento, falha do provedor, privacidade,
arredondamento, idempotência ou persistência.

**Médio — qualidade mecânica.**
`git diff --check` falha por espaços finais em vários arquivos.

### Decisão

**Não mesclar e não fazer cherry-pick.** Conceitos que podem voltar em sprint
futura: snapshot imutável, porta de provedor e análise explicável. Devem ser
redesenhados por Lar, opt-in, minimização de dados, `Decimal`, testes e política
de provedor. Código atual da branch não é base segura.

## `origin/finapy-pwa`

### Conteúdo

- inclui todos os quatro commits de `final-sprints`;
- manifest, service worker, página offline e instalação PWA;
- configurações Render/Fly.io e PostgreSQL;
- importador direto de planilha Excel;
- imagens/planilha de referência e estáticos gerados versionados.

### Achados

**Crítico — cache de dados financeiros autenticados.**
`templates/serviceworker.js` armazena respostas GET/HTML com status 200 sem
allowlist de rotas públicas, `Cache-Control`, separação por sessão ou limpeza no
logout. Assim, dashboard e outras páginas privadas podem permanecer no cache do
dispositivo após logout ou troca de sessão.

**Crítico — importação não idempotente nem atômica.**
`import_financial_data.py` cria transações diretamente, sem hash, preview,
`ImportBatch`, deduplicação, transação atômica, Lar ou responsável financeiro.
Reimportar pode duplicar lançamentos. Erros parciais deixam dados já persistidos.

**Alto — branch baseada no domínio antigo.**
Queries e criações usam somente `user`; ignoram `Household`, `FinancialOwner`,
UUID e sincronização atual.

**Alto — arquivos que exigem revisão de privacidade.**
Foram adicionados `referencias/favio_fpy.png` (3.190.898 bytes) e
`referencias/modelo_financas.xlsx` (7.104 bytes). Conteúdo pessoal não foi
necessário para concluir a auditoria e permanece `[INVESTIGAR]`; não copiar para
`main` sem anonimização comprovada.

**Médio — artefatos e direção obsoletos.**
Render/Fly.io não correspondem ao EasyPanel atual. `staticfiles` está versionado.
Os ícones declarados como 192 e 512 usam o mesmo blob de 1.961.576 bytes. O alvo
de produto aprovado é Flutter para Windows/iOS/Android, não PWA como cliente
principal.

**Médio — ausência de testes novos.**
Não há testes automatizados para cache/logout, offline, importação ou isolamento.
`git diff --check` também falha.

### Decisão

**Não mesclar e não fazer cherry-pick.** Reaproveitar apenas ideias de estados
offline e instalação ao desenhar Flutter. Importador deve nascer no pipeline
seguro da Sprint 3; nenhum código deste importador deve ser reutilizado.

## `origin/fix/easytunnel-deploy`

### Conteúdo

- porta interna 8020;
- variáveis de CSRF/host e rede EasyPanel;
- volume SQLite/media;
- Gunicorn e documentação EasyTunnel.

### Achados

**Alto — topologia SQLite incompatível.**
Compose e Dockerfile iniciam dois workers Gunicorn. A topologia aprovada e
testada em `main` exige uma réplica e um worker enquanto SQLite estiver ativo.

**Alto — migration automática sem gate de backup.**
O comando de inicialização executa `migrate` em cada start antes de validar
backup/restauração. Isso contraria o runbook atual de auditoria, backup externo e
migration controlada.

**Médio — porta contraditória.**
`DEPLOY_EASYTUNNEL.md` manda expor 8000, enquanto Dockerfile/Compose usam 8020.

**Médio — configuração específica não comprovada.**
Publicação TCP e UDP em modo host e nomes de redes externas são específicos do
servidor. Necessidade real permanece `[INVESTIGAR]` no EasyPanel.

### Decisão

**Não mesclar.** `main` já contém de forma mais segura: `SQLITE_PATH` absoluto,
volume persistente, CSRF/hosts por ambiente, proxy TLS, um worker e runbook de
backup/rollback. Somente porta e redes reais devem ser conferidas durante a
validação operacional; se necessárias, implementar sobre `main` com teste.

## Resultado consolidado

| Branch | Merge em bloco | Cherry-pick atual | Ideia preservada |
|---|---|---|---|
| `final-sprints` | Não | Não | análise explicável com provider port futura |
| `finapy-pwa` | Não | Não | estados offline/instalação para o Flutter |
| `fix/easytunnel-deploy` | Não | Não | confirmar porta/redes reais no EasyPanel |

Próxima ação possível, somente após autorização: criar tags de preservação e
remover branches remotas obsoletas. Até lá, mantê-las intactas.

## Auditoria do roteamento

**Usado:** identidade exata do modelo principal não verificável no ambiente
atual; routing recomendado `gpt-5.6-sol/high`.

**Por que:** exigiu cruzar histórico Git, arquitetura atual, privacidade,
integridade financeira, deploy e direção Flutter.

**Resultado:** Suficiente

**Poderia usar nível menor:** Não para a triagem; sim para as correções mecânicas
do roadmap.

**Recomendação para tarefas semelhantes:** `gpt-5.6-sol/high`

**Escalonamentos:** Nenhum.

**Tokens reais:** não disponíveis.
