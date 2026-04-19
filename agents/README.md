# Agentes de IA — Finanpy

Time de agentes especializados na stack do projeto Finanpy (Django 5.x + DTL + TailwindCSS).

---

## Índice

| Agente | Arquivo | Quando usar |
|---|---|---|
| [Backend Django](#backend-django) | `backend-django.md` | Models, views, forms, URLs, signals, migrations, admin |
| [Frontend DTL + Tailwind](#frontend-dtl--tailwind) | `frontend-dtl-tailwind.md` | Templates HTML, componentes, design system, responsividade |
| [QA Tester](#qa-tester) | `qa-tester.md` | Testes E2E com Playwright, testes unitários Django, relatórios de bugs |

---

## Backend Django

**Arquivo:** `backend-django.md`

Engenheiro backend especializado em Django 5.x idiomático. Domina o ciclo completo de desenvolvimento server-side do Finanpy: desde a definição de models até o roteamento de URLs.

**Ferramentas:** context7 (documentação Django atualizada), ferramentas de leitura/edição de arquivos, Bash para migrations e testes.

**Use este agente quando precisar:**
- Criar ou modificar **models** Django (`Account`, `Category`, `Transaction`, `User`, `Profile`)
- Implementar **views CBV** (`ListView`, `CreateView`, `UpdateView`, `DeleteView`, `TemplateView`)
- Escrever **forms** Django com validação e filtragem de querysets por usuário
- Configurar **URLs** com namespacing (`accounts:list`, `transactions:create`)
- Criar ou ajustar **signals** (ex: criação automática de `Profile` ao salvar `User`)
- Gerar e rodar **migrations** após mudanças de modelo
- Registrar models no **admin** com `list_display`, `list_filter` e `search_fields`
- Ajustar **settings.py** (`AUTH_USER_MODEL`, `LOGIN_REDIRECT_URL`, `INSTALLED_APPS`, etc.)
- Implementar lógica de negócio no backend (cálculo de `current_balance`, filtros de transações)

**Não use para:** geração de HTML/templates, classes Tailwind, design de UI.

---

## Frontend DTL + Tailwind

**Arquivo:** `frontend-dtl-tailwind.md`

Engenheiro frontend especializado em Django Template Language e TailwindCSS. Constrói interfaces com o design system do Finanpy — paleta emerald/slate, dark mode permanente, tipografia Inter — sem build steps, sem npm, apenas classes Tailwind via CDN.

**Ferramentas:** context7 (documentação DTL e TailwindCSS atualizadas), ferramentas de leitura/edição de arquivos.

**Use este agente quando precisar:**
- Criar ou modificar **templates HTML** (layouts base, páginas, partials)
- Implementar o **design system** (cards, botões, inputs, tabelas, sidebar, topbar)
- Construir a **landing page** pública (hero, seção de features, CTAs)
- Criar **formulários** visualmente estilizados com classes Tailwind
- Implementar **listagens** com tabelas, filtros e paginação visual
- Construir o **dashboard** com cards de métrica e tabela de transações
- Criar **empty states**, mensagens de sucesso/erro e componentes reutilizáveis
- Garantir **responsividade** de 320px a 1920px
- Aplicar **acessibilidade** (aria-labels, contraste AA, navegação por teclado)
- Estilizar valores financeiros (verde para receitas, vermelho para despesas)

**Não use para:** lógica Python, models, views, migrations.

---

## QA Tester

**Arquivo:** `qa-tester.md`

Engenheiro de QA especializado em verificar o sistema Finanpy via Playwright (testes E2E no browser) e testes unitários Django. Não aceita suposições — verifica com evidências: screenshots, checklist visual, relatório de bugs padronizado.

**Ferramentas:** Playwright MCP (navegação, screenshots, interação, console), Bash para rodar suite de testes Django.

**Use este agente quando precisar:**
- **Testar uma feature recém implementada** de ponta a ponta (signup → dashboard → CRUD)
- **Verificar o design system** — se as cores, fontes e componentes estão corretos em todas as telas
- **Auditar responsividade** em mobile (375px) e desktop (1280px+)
- **Verificar isolamento de dados** entre usuários diferentes
- **Escrever ou rodar testes unitários** Django de models e views
- **Investigar um bug reportado** com reprodução passo a passo e screenshot
- **Validar um PR ou sprint inteira** antes de considerar entregue
- Verificar que `python manage.py test` passa com zero falhas
- Gerar **relatório de bugs** com severidade e passos de reprodução

**Não use para:** implementar correções de bugs (use o agente adequado após o relatório).

---

## Como usar os agentes

Para invocar um agente no Claude Code, use o comando:

```
/agents <nome-do-agente>
```

Ou referencie o arquivo `.md` correspondente ao iniciar uma tarefa. Cada agente carrega suas próprias instruções, ferramentas e contexto do projeto — você não precisa repetir as convenções de código ou o design system em cada solicitação.

### Fluxo recomendado por tipo de tarefa

```
Nova feature (ex: Sprint 4 — Contas bancárias)
  1. Backend Django   → models + views + forms + URLs + migrations
  2. Frontend DTL     → templates + design system aplicado
  3. QA Tester        → testes E2E + testes unitários + relatório

Correção de bug
  1. QA Tester        → reproduz + documenta com screenshot
  2. Backend Django   → corrige lógica (se bug de backend)
     ou Frontend DTL  → corrige UI (se bug visual)
  3. QA Tester        → verifica correção

Auditoria visual (sprint 7)
  1. Frontend DTL     → revisão e padronização
  2. QA Tester        → checklist visual em todas as telas
```
