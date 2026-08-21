# Lar Finance — Produto

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Stack

- Interfaces: Web Django e Flutter para Windows, Android e iOS. macOS não
  bloqueia a V1 pessoal.
- Backend existente: Python 3.12, Django 5.2.13 e Django REST Framework 3.17.1, preservados no servidor Linux/EasyPanel.
- Persistência canônica atual: SQLite no servidor, com uma réplica e um worker. A API privada v1 é o contrato do cliente.
- Persistência local entregue: Drift/SQLite para o ledger principal; cartões e
  contas fixas usam API online direta.

## Users

O produto é privado e usado pelo proprietário e sua esposa como um único Lar. Nesta fase existe um login familiar compartilhado, com uma sessão revogável por dispositivo. `Eu`, `Esposa` e `Conjunto` são responsáveis financeiros dentro do Lar, não credenciais independentes.

## Product Purpose

O Lar Finance reúne em um único lugar as finanças do casal, hoje fragmentadas entre bancos, cartões e carteiras. Ao abrir o aplicativo, a experiência deve responder primeiro: **“como está nossa vida financeira hoje?”**

Essa resposta prioriza patrimônio disponível, compromissos próximos, gasto do mês e alertas relevantes. O produto deve permitir acompanhar origem, destino, propriedade e atualização dos valores sem movimentar dinheiro nem armazenar credenciais bancárias.

Sucesso significa que o casal consegue entender quanto possui, deve, gastou e tem comprometido, mantendo os dados sincronizados entre os dispositivos e sob seu próprio controle.

## Positioning

Painel financeiro doméstico privado, operado pelo próprio casal e hospedado em infraestrutura própria. Combina uma visão única do Lar com separação explicável entre `Eu`, `Esposa` e `Conjunto`, importação auditável e independência de um provedor financeiro pago.

## Operating Context

- Uso cotidiano em Windows, Android e iPhone, com interface adaptada ao dispositivo.
- Backend online permanentemente no servidor doméstico via EasyPanel.
- Importação manual de arquivos bancários como primeira estratégia; o piloto atual aceita OFX estruturalmente compatível com os arquivos Nubank testados.
- Sincronização online entre dispositivos, com cache local do ledger; recursos
  online-only devem declarar indisponibilidade e freshness.
- Um único administrador familiar importa arquivos, resolve pendências e acompanha a visão consolidada.
- Automação bancária paga poderá ser avaliada somente depois que o produto manual estiver maduro e em uso.

## Capabilities and Constraints

- Estado entregue: autenticação privada, sessões por dispositivo, Lar, owners,
  contas, categorias, transações, sync, OFX, cartões/faturas, contas fixas,
  orçamento, relatórios e Flutter multiplataforma.
- Flutter já possui fundação adaptativa, login, sessão segura, Drift, Home,
  importação e módulos financeiros recentes.
- Android e iOS pertencem ao mesmo workspace; builds sem assinatura passam na CI.
- A Home inicial não deve ser dominada pela importação. Importação e detalhes permanecem acessíveis como fluxos secundários.
- A tela inicial deve carregar em menos de 2 segundos usando dados locais previamente sincronizados.
- Valores financeiros usam representação decimal; conflitos não podem ser sobrescritos silenciosamente.
- Tokens e material de renovação ficam no armazenamento seguro nativo, nunca no SQLite ou nos logs.
- O produto não inicia Pix, pagamentos, transferências ou investimentos.
- Não existe cadastro público, landing page, múltiplas famílias ou cobrança de assinatura nesta fase.
- Open Finance, empréstimos, investimentos e patrimônio ampliado são backlog
  opcional; cartões/faturas já existem e precisam de estabilização monetária.

## Brand Commitments

- Nome oficial: **Lar Finance**.
- Linguagem: português do Brasil, clara, direta, calma e sem tom de consultoria financeira.
- Deve transmitir a confiança e o acabamento de um aplicativo bancário, sem parecer um template ou interface gerada por IA.
- A preferência pelo acabamento premium percebido no C6 Bank é uma referência de qualidade e disciplina, não autorização para copiar identidade, componentes ou marca.
- Roxo é proibido em cores de marca, estados, gráficos, ilustrações e gradientes.
- A direção aprovada chama-se **Casa de Valores 2.0**: Web e Flutter usam o
  mesmo Design System. Preservar cards, indicadores e gráficos úteis da Web,
  junto aos tokens, tema de sistema, precisão e adaptação do Flutter.
- A identidade será original e fundamentada em pesquisa comparativa de produtos financeiros reais; o conceito aprovado é referência de qualidade, não especificação literal de logo, ícones ou tipografia.

## Evidence on Hand

- PRD retroativo e roadmap versionados no repositório.
- Contrato OpenAPI 3.1 da API privada em `docs/openapi-v1.yaml`.
- Backend implantado no EasyPanel e backup remoto R2 documentado.
- Piloto OFX e testes automatizados versionados; arquivos financeiros reais não devem ser incorporados à identidade, aos mockups ou à documentação pública.
- Não existem depoimentos, parcerias bancárias, certificações de mercado ou métricas públicas que possam ser alegadas no produto.

## Product Principles

1. Mostrar a situação financeira do Lar antes de oferecer ferramentas e configurações.
2. Explicar de onde cada número veio, a quem pertence e quando foi atualizado.
3. Manter o controle e a portabilidade dos dados com o casal.
4. Preferir confiança, clareza e consistência a dashboards decorativos ou complexidade aparente.
5. Evoluir de forma incremental, preservando o backend e os dados já validados.

## Accessibility & Inclusion

- Respeitar escala de texto, contraste, redução de movimento e tecnologias assistivas de cada plataforma.
- Oferecer navegação completa por teclado e foco visível no desktop.
- Não depender apenas de cor para comunicar estado, propriedade, risco ou variação financeira.
- Ocultar valores deve ser uma ação acessível e reversível, sem remover contexto essencial da tela.
