# Design System Lar Finance — Casa de Valores 2.0

> Status: **direção híbrida aprovada em 20/08/2026**. Web e Flutter usam a
> mesma identidade; cada plataforma adapta composição e interação. O Flutter
> fornece os tokens já implementados e a Web fornece parte da densidade,
> indicadores e linguagem analítica que agradam ao proprietário.

## Princípios firmes

- nome público: Lar Finance;
- produto privado, doméstico, adulto e confiável;
- dados e números são protagonistas;
- nunca usar roxo, lavanda, violeta ou gradiente azul-roxo;
- não copiar marca, logo, fonte proprietária ou componentes de bancos;
- sem aparência genérica de IA, glassmorphism, neon ou decoração sem função;
- claro e escuro acompanham automaticamente o sistema, sem botão de tema;
- acessibilidade AA, foco visível e redução de movimento são requisitos;
- Web, Windows, Android e iOS devem parecer o mesmo produto, sem serem cópias
  pixel a pixel.

## Direção — Casa de Valores 2.0

- **Intenção:** painel financeiro familiar completo, privado e controlável.
- **Tom:** calma, clareza, proteção e domínio.
- **Densidade:** média no mobile e média-alta em Web/Windows.
- **Visual:** superfícies minerais foscas, marfim quente, champanhe restrito e
  verde mineral.
- **Composição:** editorial e orientada a dados, com cards apenas quando ajudam
  agrupamento ou comparação.
- **Motion:** discreto e funcional, respeitando redução de movimento.

C6 Bank continua uma referência de acabamento e sobriedade, nunca um modelo a
ser copiado. A referência interna aprovada é
[Home Casa de Valores](design-assets/casa-de-valores-home-reference.png).

## Autoridade compartilhada Web × Flutter

### Preservar da Web

- cards de métricas quando permitem comparação;
- gráficos com propósito explícito e alternativa textual;
- Saldo Livre Real, compromissos, orçamento diário e alertas relevantes;
- maior densidade no desktop;
- ações rápidas e leitura analítica.

### Preservar do Flutter

- tokens de cor e spacing implementados;
- tema automático do sistema;
- números tabulares e hierarquia financeira;
- superfícies mais planas, menos box-in-box e mais divisores;
- shell adaptativo a partir de 900 px;
- navegação inferior compacta;
- estados de sincronização, offline, privacidade e erro;
- comportamento nativo por plataforma.

### Regra de paridade

Paridade significa mesma identidade, nomenclatura, prioridade de informação,
componentes e estados. Não significa reproduzir a mesma geometria:

- Web/Windows: sidebar de 232 px, painéis simultâneos e gráficos mais largos;
- Android/iPhone: conteúdo empilhado, navegação inferior e ações próprias para
  toque;
- abaixo de 900 px: nenhuma sidebar fixa reduzindo a área útil;
- conteúdo Web adicional fica abaixo da hierarquia principal compartilhada.

## Tokens oficiais atuais

Fonte canônica enquanto não houver pacote compartilhado:
`mobile/lib/design_system/`.

### Cores

| Token | Hex | Uso |
|---|---|---|
| `surface.canvas.dark` | `#091311` | canvas escuro |
| `surface.base.dark` | `#101B18` | superfícies escuras |
| `surface.canvas.light` | `#F3EFE6` | canvas claro |
| `surface.base.light` | `#FFFCF5` | superfícies claras |
| `accent.champagne` | `#C7A35A` | seleção e destaque restrito |
| `accent.champagneSelectedDark` | `#4B4027` | fundo selecionado escuro |
| `accent.mineral` | `#2F756A` | ação e informação positiva |
| `accent.mineralOnDark` | `#72B8AC` | mineral acessível no escuro |
| `semantic.warning` | `#B9782D` | atenção |
| `semantic.danger` | `#B8534F` | erro/despesa perigosa |
| `text.primary.dark` | `#E8E3D8` | texto principal escuro |
| `text.primary.light` | `#17201D` | texto principal claro |

Cores semânticas não devem competir como acentos decorativos. Receitas e
despesas sempre combinam cor com sinal, texto ou ícone.

### Espaçamento

Escala oficial: `4, 8, 12, 16, 24, 32, 48` px. Valores novos precisam de
justificativa de layout, não conveniência local.

### Tipografia

- stack nativa: Segoe UI no Windows, SF no ecossistema Apple, Roboto no Android
  e `system-ui` como fallback Web;
- não depender de Google Fonts para a interface principal;
- display financeiro atual: 32 px, peso 600 e números tabulares;
- dinheiro sempre usa formatação pt-BR e representação monetária exata;
- labels não substituem títulos e valores críticos não usam caption;
- textos essenciais devem funcionar em 200% de escala.

### Forma e elevação

- radius moderado e consistente;
- sombras discretas apenas para elevação real;
- bordas e divisores preferidos a glows;
- sem card dentro de card quando spacing/divisor resolver;
- pills somente para seleção compacta, filtro ou status.

### Motion

- faixa inicial de 160–240 ms;
- movimento explica navegação ou mudança de estado;
- nada se move perpetuamente;
- redução de movimento troca transição por fade curto ou estado instantâneo.

## Componentes estruturais

- shell adaptativo;
- navegação desktop e compacta;
- owner selector `Lar / Eu / Esposa`;
- `FinancialAmount` com ocultar/mostrar;
- status de atualização e origem;
- saldo consolidado e compromissos;
- metric card;
- transaction row;
- account/card/bill summary;
- progresso de fatura e vencimento;
- gráfico com tabela/legenda alternativa;
- fluxo de importação e reconciliação;
- loading, vazio útil, erro, offline, stale e conflito;
- sheet/dialog de confirmação;
- file picker e recibo de exportação.

## Hierarquia da Home

A primeira dobra compartilhada deve responder, nesta ordem:

1. qual visão está ativa: `Lar`, `Eu` ou `Esposa`;
2. quão atualizados estão os dados;
3. quanto há disponível/consolidado;
4. quanto está comprometido e gasto no período;
5. quais movimentos recentes exigem leitura.

Web/Windows podem acrescentar Saldo Livre Real, Ano da Seca, evolução mensal,
orçamento e distribuição por categoria na mesma tela, mas não antes de ocultar a
hierarquia principal.

## Responsividade e interação

- `>= 900 px`: sidebar/rail e painéis múltiplos;
- `< 900 px`: navegação inferior e conteúdo empilhado;
- 375 px e 320 px com escala 200% são matrizes obrigatórias;
- alvos mínimos seguem a plataforma: 48 dp Android e 44 pt iOS;
- Web/Windows cobrem teclado, Tab, Enter/Espaço, hover e foco;
- ações críticas exigem confirmação e feedback seguro.

## Auditoria da Web atual

Aspectos que permanecem:

- conteúdo rico do dashboard;
- cards financeiros úteis;
- gráficos, orçamento diário e contas fixas;
- skip link, headings, tabelas e foco já presentes.

Aspectos que devem convergir:

- modo escuro hoje é fixo;
- fundos atuais não correspondem aos tokens Flutter;
- 821 cores hexadecimais, 315 classes de radius e 121 classes de sombra tornam
  manutenção e consistência frágeis;
- gradientes, glows e containers aninhados excedem a direção aprovada;
- tablet mantém sidebar abaixo do breakpoint oficial;
- mobile usa menu hambúrguer em vez da navegação compacta comum;
- valores monetários não são formatados de modo uniforme;
- Tailwind, Alpine, Chart.js e Inter dependem de CDN.

A meta não é eliminar os elementos Web apreciados. É reduzir aproximadamente
25% da ornamentação, centralizar tokens e fazer a interface pertencer ao mesmo
sistema do Flutter.

## Critérios de aceite por tela

- leitura do estado financeiro principal em até 5 segundos;
- mesma nomenclatura e prioridade entre plataformas;
- claro/escuro de sistema sem flash de tema incorreto;
- nenhum roxo, inclusive em gráficos;
- valores financeiros exatos, localizados e tabulares;
- sem overflow em 320 px/200%;
- teclado/foco/semântica testados quando aplicável;
- loading, vazio, erro, offline e stale projetados;
- screenshots/goldens aprovados para breakpoints relevantes;
- nenhum gráfico decorativo ou card sem função.

## Sequência incremental

1. tokens e shell;
2. login;
3. dashboard;
4. contas e transações;
5. categorias e orçamentos;
6. cartões e faturas;
7. contas fixas;
8. importação;
9. relatórios e perfil.

Cada grupo é uma task independente, com teste, revisão, commit e push antes da
próxima autorização.
