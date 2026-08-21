# Auditoria do estado do produto e paridade visual — 20/08/2026

## Escopo e evidência

Auditoria somente leitura executada no `main` sincronizado com `origin/main`, no
commit `4810af4e67d23d36268b74e9654ead1978e8f707`. O proprietário confirmou que o
EasyPanel acompanha o `main`; o endpoint público `/api/v1/health/` respondeu
HTTP 200. A resposta de health ainda não informa o SHA em execução, portanto a
origem está confirmada operacionalmente, mas o commit efetivo não é verificável
pela própria aplicação.

Foram inspecionados backend Django, migrations, rotas web/API, cliente Flutter,
persistência Drift, sincronização, CI, documentação e capturas reais da Home Web
em 375, 768 e 1280 px, comparadas aos goldens Flutter.

## Estado real do produto

O Lar Finance é uma **beta pessoal avançada**, não um MVP inicial. Já existem:

- acesso privado, um Lar e responsáveis `Eu`, `Esposa` e `Conjunto`;
- contas, categorias, movimentações, orçamento por categoria e lançamento
  rápido;
- API privada com sessões por dispositivo, tokens opacos, bootstrap, delta,
  tombstones e idempotência;
- importação OFX de conta e cartão, prévia, deduplicação e confirmação;
- cartões, despesas, faturas, limites, pagamentos e reabertura;
- contas fixas, vencimentos, pagamentos e saldo livre;
- relatórios Flutter baseados no ledger local;
- Flutter para Windows, Android e iOS, com cache Drift, tema de sistema e Home
  Casa de Valores;
- backend no EasyPanel e backup R2 diário supervisionado.

O domínio possui 20 models Django, 32 migrations e 32 rotas de API. Desde a
entrega da Sprint 5, 227 arquivos mudaram, com 27.953 inserções e 1.183
remoções; por isso a documentação anterior deixou de representar o produto.

## Verificação técnica

| Gate | Resultado no commit auditado |
|---|---|
| Django completo | 526/526 testes passaram |
| Backend focado em recursos recentes | 92/92 testes passaram |
| Django `check` | passou |
| Drift de migrations | nenhuma migration pendente |
| Flutter analyze | passou |
| Flutter sem goldens | 336/336 testes passaram |
| Flutter goldens | 2 passaram e 10 falharam |
| Ruff oficial | 7 achados; 6 autocorrigíveis |
| Formatação Dart | 17 arquivos divergentes |
| GitHub Actions | falha em lint, formato e goldens Windows |
| Build Android na CI | passou |
| Build iOS sem assinatura na CI | passou |
| Secret scan | passou |

A CI auditada é o run
[`32417802769`](https://github.com/Ludsonfrancisco/finanpy/actions/runs/32417802769).
O Windows/MSIX não foi produzido nesse run porque o gate de goldens falhou
antes do build.

## Achados técnicos priorizados

### Alto — precisão monetária no Flutter recente

O núcleo local usa inteiros em centavos, mas cartões e contas fixas foram
implementados com `double`, `double.tryParse` e `toStringAsFixed`. O backend usa
`Decimal`. Essa fronteira pode introduzir arredondamento de centavos e viola a
regra do domínio de nunca representar dinheiro com ponto flutuante.

Tratamento: migrar valores monetários de cartões e contas fixas para minor units
ou tipo decimal exato, mantendo `double` apenas para percentuais e animações.

### Alto — release sem gate verde

Os testes funcionais principais passam, mas a branch não está liberável enquanto
Ruff, formato e goldens deixam a CI vermelha. Corrigir os gates antes de ampliar
escopo.

### Alto — migrations fail-open no WSGI

`core/wsgi.py` executa `migrate` ao iniciar Gunicorn e apenas registra a exceção.
Assim o web pode iniciar com schema incompatível. Migrations devem ser uma etapa
única, explícita e fail-fast antes do Supervisor iniciar web e schedulers.

### Alto — maturidade desigual de sincronização

O registro central sincroniza apenas Account, Category e Transaction. Cartões e
contas fixas usam API HTTP direta, sem tabelas Drift, delta ou tombstones. Quando
online, outro dispositivo recebe os dados ao consultar novamente; offline, essas
telas não têm a mesma garantia do ledger.

Para o uso pessoal aprovado, não será criada uma segunda plataforma de sync.
Servidor permanece autoridade; escrita de cartões/contas fixas exige internet e
um cache local de última leitura pode ser adicionado para consulta offline.

### Médio — documentação contraditória

PRD e roadmap ainda tratavam cartões, contas fixas, orçamento e relatórios como
futuros; README registrava 21 rotas, 487 testes Django, 285 Flutter e um deploy
92 commits atrás. Instruções `GEMINI.md` também descreviam a arquitetura anterior
ao Lar e ao Flutter.

### Médio — frontend Web não determinístico

Tailwind, Alpine, Chart.js e Google Fonts são carregados de CDNs, alguns sem
versão exata. O próprio Tailwind avisa no console que o CDN não deve ser usado em
produção. Para o servidor pessoal, a correção proporcional é fixar versões e
servir assets estáticos locais, sem introduzir outro framework frontend.

## Auditoria UI/UX: Web e Flutter

### Decisão aprovada — Casa de Valores 2.0

Web e Flutter usarão **o mesmo Design System**, sem buscar cópia pixel a pixel.
A identidade é única; a composição respeita a plataforma.

Preservar da Web:

- cards e indicadores financeiros úteis;
- gráficos com pergunta clara;
- densidade de informação de desktop;
- Saldo Livre Real, contas fixas e orçamento diário;
- ações rápidas e leitura analítica.

Preservar do Flutter:

- tokens oficiais claros/escuros;
- tema automático do sistema, sem seletor manual;
- tipografia financeira e algarismos tabulares;
- hierarquia calma, superfícies foscas e menos box-in-box;
- breakpoint desktop em 900 px;
- sidebar/rail no desktop e navegação inferior no compacto;
- estados offline, atualização, privacidade e acessibilidade.

### Divergências atuais

- Web força modo escuro; Flutter acompanha o sistema.
- Web usa fundos diferentes dos tokens Flutter e contém 821 ocorrências de cores
  hexadecimais, 315 classes de radius e 121 classes de sombra.
- Web usa brilho, gradientes e cards aninhados em excesso; Flutter é mais plano.
- Web mantém sidebar em 768 px; Flutter muda de composição abaixo de 900 px.
- Web mobile usa menu hambúrguer; Flutter usa navegação inferior.
- A primeira dobra Web prioriza dois banners e quatro métricas; Flutter prioriza
  saldo consolidado, compromissos, gasto mensal e movimentações recentes.
- Formatação Web observada não aplicava separador de milhar em todos os valores.

O redesenho não apagará os componentes Web que agradam ao proprietário. A meta é
reduzir cerca de um quarto da ornamentação, aplicar tokens comuns e reorganizar
a hierarquia para que Web, Windows, Android e iOS pareçam o mesmo produto.

## Reorganização aprovada

### R1 — Verdade e estabilização

- corrigir Ruff, formato e goldens;
- migrar dinheiro recente para representação exata;
- retirar migrations do WSGI;
- deixar CI verde;
- expor versão/SHA no health;
- manter documentos e OpenAPI coerentes.

### R2 — Fundação Web Casa de Valores 2.0

- tokens CSS equivalentes ao Flutter;
- claro/escuro automático;
- tipografia nativa por plataforma;
- shell, sidebar, navegação compacta e formatação financeira comuns;
- assets frontend fixados/localizados.

### R3 — Paridade visual incremental

Ordem: shell, login, dashboard, contas/transações, categorias/orçamentos,
cartões/faturas, contas fixas, importação, relatórios e perfil. Conteúdo analítico
exclusivo da Web permanece abaixo da hierarquia principal.

### R4 — Consistência entre dispositivos

- manter delta/outbox atual no ledger principal;
- escrita online para cartões e contas fixas;
- cache de última leitura e freshness explícita nesses módulos;
- provar Windows → servidor → Android/iPhone e o caminho inverso.

### R5 — Release pessoal

- CI verde;
- deploy fail-fast e smoke EasyPanel;
- restauração R2;
- instaláveis privados e smoke nos dispositivos reais;
- documentação final e tag estável.

## Fora da V1 pessoal

PostgreSQL, múltiplas réplicas, cadastro público, telemetria complexa, lojas
públicas, Open Finance pago, empréstimos, investimentos completos e escrita
offline de todos os módulos não são necessários para concluir a primeira versão
pessoal. Permanecem backlog opcional, guiado por uso real.
