# Direção visual do Lar Finance

> Status: **direção Casa de Valores aprovada em 13/08/2026**. Tokens exatos serão validados durante a Sprint 4.

## Decisões firmes

- nome público: Lar Finance;
- linguagem: fintech premium, confiável, adulta e doméstica, sem parecer planilha amadora;
- dados e números são protagonistas;
- nunca usar roxo, lavanda, violeta, magenta arroxeado ou gradiente azul-roxo;
- não copiar marca, logo, fonte proprietária, cartões ou composição de outro banco;
- não usar “AI slop”: glassmorphism gratuito, blobs, neon, cards flutuantes e gráfico sem propósito;
- claro e escuro devem ser projetados juntos;
- acessibilidade AA e redução de movimento são requisitos, não acabamento.

## Referência candidata: princípios observados no C6 Bank

O usuário citou o C6 Bank como preferência. A referência oficial descreve uma identidade inspirada em carbono, com contraste, tipografia precisa, iconografia geométrica sóbria e linguagem sofisticada. Isso pode orientar princípios, nunca reprodução.

Fontes para análise:

- [Carbon Brand Space](https://www.c6bank.com.br/carbon-brand-space/)
- [Iconografia C6](https://www.c6bank.com.br/carbon-brand-space/iconografia/)
- [Aplicativo C6 Bank na App Store](https://apps.apple.com/br/app/c6-bank-cart%C3%A3o-conta-e-mais/id1463463143)

Princípios potencialmente aproveitáveis:

- superfícies minerais e contraste controlado;
- hierarquia numérica forte;
- espaço negativo e composição calma;
- um acento quente usado com economia;
- geometria sóbria, não infantil;
- sensação de segurança e autonomia.

## Direção aprovada — Casa de Valores

- **Intenção:** painel financeiro familiar confiável, completo e privado.
- **Tom emocional:** calma, clareza, domínio e proteção.
- **Densidade:** média-alta por ser produto de dados, com respiro entre blocos.
- **Motion:** baixo a moderado, funcional.
- **Plataforma:** cross-platform premium neutral, com adaptações nativas.
- **Referência visual:** grafite esverdeado, marfim quente, champanhe restrito e verde mineral.
- **Referência aprovada:** [Home Casa de Valores](design-assets/casa-de-valores-home-reference.png), com dados sintéticos e sem autoridade literal sobre logo, ícones ou tipografia.

## Dials provisórios

- `DESIGN_VARIANCE = 5`
- `MOTION_INTENSITY = 3`
- `VISUAL_DENSITY = 6`

Esses números documentam intenção, não tokens de código.

## Gate de decisão visual

Antes de implementar componentes finais:

- [x] coletar referências de produtos financeiros reais;
- [x] registrar os princípios aproveitáveis sem copiar identidade;
- [x] criar três direções próprias, sem copiar marca;
- [x] escolher Casa de Valores e projetar claro/escuro;
- [ ] validar paleta completa em contraste e daltonismo;
- [ ] validar tipografia aberta/licenciada em iOS, Android e Windows;
- [ ] criar na implementação os conceitos de Login, Início e estados essenciais;
- [x] testar a direção com textos e valores financeiros sintéticos;
- [x] aprovar o conceito; documentar tokens exatos durante a Sprint 4;
- [ ] registrar a escolha em ADR-008.

Até a validação de contraste, licença e plataformas, os hexadecimais e famílias tipográficas continuam referências, não tokens definitivos.

## Territórios avaliados

### A. Mineral quente

Grafite, pedra clara e acento dourado/âmbar. É o território mais próximo dos princípios admirados no C6, mas precisa de personalidade própria ligada ao lar.

### B. Editorial financeiro

Off-white, carvão, tipografia editorial e acento azul petróleo ou verde profundo. Mais leve e informativo, com menos associação a banco tradicional.

### C. Arquitetura doméstica

Neutros quentes, materiais foscos e acento terracota ou verde oliva. Reforça o conceito de lar sem perder precisão financeira.

Todos excluem roxo. **Casa de Valores** escolhe o território mineral quente com uma camada editorial e identidade doméstica própria.

## Tokens que serão obrigatórios

Os valores hexadecimais ainda não estão decididos. O sistema final deve declarar:

- `surface.canvas`, `surface.base`, `surface.raised`, `surface.sunken`;
- `text.primary`, `text.secondary`, `text.muted`, `text.inverse`;
- `border.subtle`, `border.strong`, `focus`;
- `accent.primary`, `accent.onPrimary`;
- `semantic.income`, `semantic.expense`, `semantic.warning`, `semantic.info`, `semantic.success`;
- `data.series.*`, com padrões/labels além de cor;
- escalas de spacing, radius, elevation, type e motion;
- tokens equivalentes light/dark.

Regra de cor: uma cor de marca principal. Cores semânticas são reservadas a significado e não competem como acentos decorativos.

## Tipografia

Critérios:

- licença aberta ou distribuição permitida;
- números tabulares para dinheiro/tabelas;
- boa leitura de `R$`, vírgula decimal e números longos;
- pesos suficientes sem carregar muitos arquivos;
- acentos pt-BR completos;
- compatibilidade consistente nas três plataformas.

Inter não será adotada automaticamente apenas por ser comum. Candidatas serão testadas `[INVESTIGAR]`.

Escala mínima proposta, sujeita a teste: display financeiro, título de tela, título de seção, corpo, label e caption. Valores críticos não usam caption.

## Componentes estruturais

- app shell adaptativo;
- owner switcher “Lar / Eu / Esposa”;
- money value com esconder/mostrar;
- data freshness/source badge sem formato de pill excessivo;
- transaction row;
- account/card/loan/investment summary;
- statement progress e due-date status;
- import progress, mapping table e reconciliation issue;
- empty/error/offline/stale/conflict states;
- chart + table alternative;
- confirmation sheet/dialog;
- secure file picker e export receipt.

Componentes evitam box-in-box. Pills ficam restritas a status, filtro compacto e seleção, não a todo texto.

## Iconografia

- uma família coerente e licenciada;
- traço/peso consistente;
- símbolos financeiros reconhecíveis e rótulos quando houver ambiguidade;
- não misturar packs;
- não usar emoji como ícone funcional;
- categorias podem usar ícone + nome, nunca só cor.

## Motion

- 160 a 240 ms como faixa inicial `[INVESTIGAR por plataforma]`;
- movimento explica mudança de estado, hierarquia ou navegação;
- nada se move perpetuamente;
- sincronização/importação usa progresso acessível;
- `Reduce Motion` troca movimentos por fade/estado instantâneo.

## Auditoria da interface atual

Problemas observados nas screenshots:

- identidade “Finanpy” e teal dominam sem relação com “Lar Finance”;
- cadastro público contradiz o uso privado;
- dashboard replica padrão de três cards e gráfico vazio;
- cartão é uma linha genérica de conta, sem limite/fatura;
- excesso de containers e grandes áreas vazias;
- tela pensada para desktop, não para celular;
- zero é exibido onde o dado pode simplesmente não existir;
- sem estados de sincronização, origem, confiança ou proprietário.

O frontend taste skill foi aplicado como crítica e princípios para login/fallback web. Ele não define dashboards nativos; a direção mobile governa as telas Flutter.

## Critérios de aprovação

- leitura clara em 5 segundos do estado financeiro;
- visual reconhecível como Lar Finance sem logo de terceiros;
- números e ações principais acessíveis;
- nenhuma ocorrência de roxo, inclusive gráficos/ilustrações;
- sem mais de um acento de marca;
- telas variadas, mas pertencentes ao mesmo sistema;
- versões mobile e Windows parecem nativas, não páginas web esticadas;
- estados vazios/erro/offline são tão projetados quanto o happy path.
