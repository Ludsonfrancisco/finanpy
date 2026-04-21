## 13. Lista de tarefas

Formato: `- [ ]` para pendente, `- [x]` para concluído.
As sprints abaixo assumem ciclos curtos e focados. Cada sprint é incremental e entrega valor visível.

---

### Sprint 0 — Fundação do projeto

- [X] **0.1 Configurar ambiente de desenvolvimento**
  - [X] 0.1.1 Criar virtualenv `venv` na raiz do projeto
  - [X] 0.1.2 Criar `requirements.txt` com Django pinado em versão 5.x
  - [X] 0.1.3 Instalar dependências via `pip install -r requirements.txt`
  - [X] 0.1.4 Criar `.gitignore` (venv, `__pycache__`, `db.sqlite3`, `.env`, `staticfiles/`)
  - [X] 0.1.5 Inicializar repositório Git e primeiro commit

- [X] **0.2 Criar projeto Django**
  - [X] 0.2.1 Executar `django-admin startproject core .`
  - [X] 0.2.2 Validar que `manage.py` está na raiz
  - [X] 0.2.3 Executar `python manage.py runserver` e confirmar tela inicial
  - [X] 0.2.4 Configurar `LANGUAGE_CODE = 'pt-br'` em `settings.py`
  - [X] 0.2.5 Configurar `TIME_ZONE = 'America/Sao_Paulo'` em `settings.py`
  - [X] 0.2.6 Configurar `USE_TZ = True` em `settings.py`
  - [X] 0.2.7 Instalar `python-dotenv` e adicionar ao `requirements.txt`
  - [X] 0.2.8 Criar arquivo `.env` na raiz com `SECRET_KEY`, `DEBUG` e `ALLOWED_HOSTS`
  - [X] 0.2.9 Criar `.env.example` com as mesmas chaves sem valores sensíveis
  - [X] 0.2.10 Mover `SECRET_KEY` para `.env` e ler via `os.environ` em `settings.py`
  - [X] 0.2.11 Configurar `DEBUG` via variável de ambiente (padrão `False` se ausente)
  - [X] 0.2.12 Configurar `ALLOWED_HOSTS` via variável de ambiente (lista separada por vírgula)
  - [X] 0.2.13 Adicionar `ruff` ao `requirements.txt` e criar `ruff.toml` configurado para aspas simples (`quote-style = 'single'`)

- [X] **0.3 Estrutura de apps**
  - [X] 0.3.1 Criar app `users` (`python manage.py startapp users`)
  - [X] 0.3.2 Criar app `profiles`
  - [X] 0.3.3 Criar app `accounts`
  - [X] 0.3.4 Criar app `categories`
  - [X] 0.3.5 Criar app `transactions`
  - [X] 0.3.6 Registrar todos os apps em `INSTALLED_APPS`

- [X] **0.4 Configuração de arquivos estáticos e templates**
  - [X] 0.4.1 Criar diretório `templates/` na raiz
  - [X] 0.4.2 Configurar `TEMPLATES['DIRS']` apontando para `BASE_DIR / 'templates'`
  - [X] 0.4.3 Criar diretório `static/` na raiz
  - [X] 0.4.4 Configurar `STATICFILES_DIRS`
  - [X] 0.4.5 Criar `static/css/custom.css` vazio para customizações pontuais

---

### Sprint 1 — Autenticação e usuário customizado

- [X] **1.1 Modelo de usuário customizado (app `users`)**
  - [X] 1.1.1 Criar classe `UserManager` herdando de `BaseUserManager` com `create_user` e `create_superuser` baseados em e-mail
  - [X] 1.1.2 Criar `User(AbstractUser)` com `username = None` e `email = models.EmailField(unique=True)`
  - [X] 1.1.3 Definir `USERNAME_FIELD = 'email'` e `REQUIRED_FIELDS = []`
  - [X] 1.1.4 Adicionar campos `created_at` e `updated_at`
  - [X] 1.1.5 Configurar `AUTH_USER_MODEL = 'users.User'` em `settings.py`
  - [X] 1.1.6 Registrar `User` em `users/admin.py` com `UserAdmin` adaptado
  - [X] 1.1.7 Gerar e rodar migrations iniciais


- [X] **1.2 Perfil de usuário (app `profiles`)**
  - [X] 1.2.1 Criar `Profile` 1:1 com `User` (OneToOneField, related_name='profile')
  - [X] 1.2.2 Adicionar campos `first_name`, `last_name`, `birth_date`, `avatar` (ImageField opcional)
  - [X] 1.2.3 Adicionar `created_at` e `updated_at`
  - [X] 1.2.4 Criar `profiles/signals.py` com signal `post_save` de `User` criando `Profile`
  - [X] 1.2.5 Conectar signals em `profiles/apps.py` via método `ready()`
  - [X] 1.2.6 Registrar `Profile` em `profiles/admin.py`
  - [X] 1.2.7 Gerar e rodar migrations

- [X] **1.3 Formulários e views de autenticação**
  - [X] 1.3.1 Criar `users/forms.py` com `SignUpForm` (email, password1, password2)
  - [X] 1.3.2 Criar `LoginForm` baseado em `AuthenticationForm` usando e-mail
  - [X] 1.3.3 Criar `SignUpView(CreateView)` em `users/views.py`
  - [X] 1.3.4 Criar `LoginView` herdando de `django.contrib.auth.views.LoginView`
  - [X] 1.3.5 Criar `LogoutView` usando a nativa do Django
  - [X] 1.3.6 Configurar `LOGIN_URL`, `LOGIN_REDIRECT_URL` e `LOGOUT_REDIRECT_URL` em `settings.py`

- [X] **1.4 URLs de autenticação**
  - [X] 1.4.1 Criar `users/urls.py` com rotas `signup/`, `login/`, `logout/`
  - [X] 1.4.2 Incluir `users.urls` em `core/urls.py`

---

### Sprint 2 — Design system e layouts base

- [X] **2.1 Templates base**
  - [X] 2.1.1 Criar `templates/base.html` com doctype, meta viewport, CDN do Tailwind e fonte Inter
  - [X] 2.1.2 Criar `templates/layouts/base_public.html` (herda de `base.html`) com topbar pública e footer
  - [X] 2.1.3 Criar `templates/layouts/base_app.html` (herda de `base.html`) com sidebar + topbar autenticada
  - [X] 2.1.4 Criar bloco `{% block content %}` e `{% block title %}` em cada layout
  - [X] 2.1.5 Criar parcial `templates/partials/_messages.html` para `django.contrib.messages`

- [X] **2.2 Componentes reutilizáveis**
  - [X] 2.2.1 Criar parcial `templates/partials/_sidebar.html` com links para Dashboard, Contas, Categorias, Transações, Perfil, Logout
  - [X] 2.2.2 Criar parcial `templates/partials/_topbar_public.html`
  - [X] 2.2.3 Criar parcial `templates/partials/_topbar_app.html` com nome do usuário
  - [X] 2.2.4 Criar parcial `templates/partials/_form_field.html` para renderização padronizada de campos
  - [X] 2.2.5 Criar parcial `templates/partials/_empty_state.html` para listas vazias

- [X] **2.3 Landing page pública**
  - [X] 2.3.1 Criar app/pasta de views públicas no `core` ou novo app `pages` (optar por view simples em `core`)
  - [X] 2.3.2 Criar `templates/pages/home.html` com hero (gradiente emerald→teal→cyan), seção de features, CTA cadastro e login
  - [X] 2.3.3 Criar view `HomeView(TemplateView)` em `core/views.py`
  - [X] 2.3.4 Configurar rota `''` em `core/urls.py` apontando para `HomeView`

- [X] **2.4 Templates de autenticação**
  - [X] 2.4.1 Criar `templates/users/signup.html` usando `base_public.html`
  - [X] 2.4.2 Criar `templates/users/login.html` usando `base_public.html`
  - [X] 2.4.3 Aplicar classes Tailwind do design system em todos os campos
  - [X] 2.4.4 Exibir erros de validação com estilo do design system

---

### Sprint 3 — Dashboard e perfil

- [X] **3.1 Dashboard inicial**
  - [X] 3.1.1 Criar `core/views.py` com `DashboardView(LoginRequiredMixin, TemplateView)`
  - [X] 3.1.2 Em `get_context_data`, calcular saldo total, receitas e despesas do mês
  - [X] 3.1.3 Buscar últimas 10 transações do usuário
  - [X] 3.1.4 Criar template `templates/dashboard/index.html` usando `base_app.html`
  - [X] 3.1.5 Renderizar 3 cards de métrica (saldo, receitas, despesas)
  - [X] 3.1.6 Renderizar tabela de últimas transações
  - [X] 3.1.7 Adicionar rota `dashboard/` em `core/urls.py`
  - [X] 3.1.8 Ajustar `LOGIN_REDIRECT_URL` para `/dashboard/`

- [X] **3.2 Gestão de perfil**
  - [X] 3.2.1 Criar `profiles/forms.py` com `ProfileForm(ModelForm)`
  - [X] 3.2.2 Criar `ProfileUpdateView(LoginRequiredMixin, UpdateView)` que atualiza o profile do usuário logado
  - [X] 3.2.3 Criar template `templates/profiles/edit.html`
  - [X] 3.2.4 Criar `profiles/urls.py` e incluir em `core/urls.py`
  - [X] 3.2.5 Adicionar link do perfil na sidebar e topbar

---

### Sprint 4 — Contas bancárias

- [X] **4.1 Model Account**
  - [X] 4.1.1 Criar `Account` em `accounts/models.py` com `user` (FK para `User`), `name`, `type` (choices), `initial_balance` (DecimalField), `currency` (default `'BRL'`)
  - [X] 4.1.2 Adicionar `created_at` e `updated_at`
  - [X] 4.1.3 Definir `__str__` retornando `self.name`
  - [X] 4.1.4 Criar método `current_balance` que soma `initial_balance` + transações
  - [X] 4.1.5 Registrar no admin
  - [X] 4.1.6 Gerar e rodar migrations

- [X] **4.2 CRUD de contas**
  - [X] 4.2.1 Criar `accounts/forms.py` com `AccountForm(ModelForm)`
  - [X] 4.2.2 Criar `AccountListView(LoginRequiredMixin, ListView)` filtrando por `user=self.request.user`
  - [X] 4.2.3 Criar `AccountCreateView(LoginRequiredMixin, CreateView)` atribuindo `user` em `form_valid`
  - [X] 4.2.4 Criar `AccountUpdateView(LoginRequiredMixin, UpdateView)` com `get_queryset` restrito ao usuário
  - [X] 4.2.5 Criar `AccountDeleteView(LoginRequiredMixin, DeleteView)` com confirmação
  - [X] 4.2.6 Criar `accounts/urls.py` com rotas CRUD
  - [X] 4.2.7 Incluir em `core/urls.py`

- [X] **4.3 Templates de contas**
  - [X] 4.3.1 Criar `templates/accounts/list.html` com tabela e botão "Nova conta"
  - [X] 4.3.2 Criar `templates/accounts/form.html` reutilizado por create/update
  - [X] 4.3.3 Criar `templates/accounts/confirm_delete.html`
  - [X] 4.3.4 Adicionar link "Contas" na sidebar

---

### Sprint 5 — Categorias [X]

- [X] **5.1 Model Category**
  - [X] 5.1.1 Criar `Category` em `categories/models.py` com `user`, `name`, `type` (choices: `income`/`expense`), `color` (default `'#10b981'`), `icon` (CharField opcional)
  - [X] 5.1.2 Adicionar `created_at` e `updated_at`
  - [X] 5.1.3 Definir `unique_together = ('user', 'name', 'type')`
  - [X] 5.1.4 Registrar no admin
  - [X] 5.1.5 Gerar e rodar migrations

- [X] **5.2 CRUD de categorias**
  - [X] 5.2.1 Criar `categories/forms.py` com `CategoryForm(ModelForm)`
  - [X] 5.2.2 Criar CBVs `CategoryListView`, `CategoryCreateView`, `CategoryUpdateView`, `CategoryDeleteView`
  - [X] 5.2.3 Aplicar filtro por `user` em todas as views
  - [X] 5.2.4 Criar `categories/urls.py` e incluir em `core/urls.py`

- [X] **5.3 Templates de categorias**
  - [X] 5.3.1 Criar `templates/categories/list.html` com grid de cards exibindo cor/ícone
  - [X] 5.3.2 Criar `templates/categories/form.html`
  - [X] 5.3.3 Criar `templates/categories/confirm_delete.html`
  - [X] 5.3.4 Adicionar link "Categorias" na sidebar

---

### Sprint 6 — Transações [X]

- [X] **6.1 Model Transaction**
  - [X] 6.1.1 Criar `Transaction` em `transactions/models.py` com `user`, `account` (FK), `category` (FK), `description`, `amount` (DecimalField), `date` (DateField), `type` (choices `income`/`expense`)
  - [X] 6.1.2 Adicionar `created_at` e `updated_at`
  - [X] 6.1.3 Definir ordenação default por `-date, -created_at`
  - [X] 6.1.4 Registrar no admin com `list_filter` e `search_fields`
  - [X] 6.1.5 Gerar e rodar migrations

- [X] **6.2 CRUD de transações**
  - [X] 6.2.1 Criar `transactions/forms.py` com `TransactionForm(ModelForm)` que filtra `account` e `category` pelo usuário logado
  - [X] 6.2.2 Criar `TransactionListView(LoginRequiredMixin, ListView)` com paginação (`paginate_by = 20`)
  - [X] 6.2.3 Implementar filtros por querystring (período, conta, categoria, tipo) em `get_queryset`
  - [X] 6.2.4 Criar `TransactionCreateView`, `TransactionUpdateView`, `TransactionDeleteView`
  - [X] 6.2.5 Criar `transactions/urls.py` e incluir em `core/urls.py`

- [X] **6.3 Templates de transações**
  - [X] 6.3.1 Criar `templates/transactions/list.html` com filtros no topo e tabela
  - [X] 6.3.2 Estilizar valores: verde (`emerald-400`) para receitas, vermelho (`rose-400`) para despesas
  - [X] 6.3.3 Criar `templates/transactions/form.html`
  - [X] 6.3.4 Criar `templates/transactions/confirm_delete.html`
  - [X] 6.3.5 Adicionar paginação visual no rodapé da lista
  - [X] 6.3.6 Adicionar link "Transações" na sidebar

- [X] **6.4 Integração com dashboard**
  - [X] 6.4.1 Refinar cálculo de saldo total usando `Sum` agregado do ORM
  - [X] 6.4.2 Refinar cálculo de receitas e despesas do mês
  - [X] 6.4.3 Adicionar seção de "Despesas por categoria" (lista simples) no dashboard

---

### Sprint 7 — Polimento visual e UX

- [X] **7.1 Consistência visual**
  - [X] 7.1.1 Revisar todas as telas garantindo uso dos mesmos tokens de cor
  - [X] 7.1.2 Padronizar espaçamento interno (`p-6`) e externo (`gap-6`) em cards
  - [X] 7.1.3 Padronizar botões primários e secundários em todas as telas
  - [X] 7.1.4 Validar responsividade em 320px, 768px e 1280px

- [X] **7.2 Microinterações**
  - [X] 7.2.1 Adicionar `transition` em botões e links
  - [X] 7.2.2 Adicionar `focus:ring` em todos os inputs
  - [X] 7.2.3 Aplicar hover states em linhas de tabela e itens de menu

- [X] **7.3 Mensagens e empty states**
  - [X] 7.3.1 Exibir `messages.success` após ações CRUD
  - [X] 7.3.2 Exibir `messages.error` em falhas
  - [X] 7.3.3 Renderizar empty states com ilustração SVG simples e CTA

- [x] **7.4 Acessibilidade**
  - [x] 7.4.1 Garantir `aria-label` em ícones isolados
  - [x] 7.4.2 Validar contraste AA em texto sobre fundo escuro
  - [x] 7.4.3 Testar navegação via Tab em todos os formulários

---

### Sprint 8 — Testes (sprint final)

- [X] **8.1 Testes unitários**
  - [X] 8.1.1 Testar criação de `User` com e-mail via manager customizado
  - [X] 8.1.2 Testar criação automática de `Profile` via signal
  - [X] 8.1.3 Testar método `current_balance` de `Account`
  - [X] 8.1.4 Testar validações dos forms

- [X] **8.2 Testes de views**
  - [X] 8.2.1 Testar redirecionamento de rotas protegidas sem login
  - [X] 8.2.2 Testar filtragem por usuário em todas as listagens
  - [X] 8.2.3 Testar CRUD de contas, categorias e transações
  - [X] 8.2.4 Testar filtros de transações

- [X] **8.3 Cobertura**
  - [X] 8.3.1 Instalar `coverage`
  - [X] 8.3.2 Rodar suite e gerar relatório
  - [X] 8.3.3 Garantir cobertura > 70%

---

playwright### Sprint 9 — Docker (sprint final)

- [X] **9.1 Containerização**
  - [X] 9.1.1 Criar `Dockerfile` multi-stage baseado em `python:3.12-slim`
  - [X] 9.1.2 Criar `docker-compose.yml` com serviço `web` e volume para SQLite
  - [X] 9.1.3 Criar `.dockerignore`
  - [X] 9.1.4 Documentar comandos de build e up no `README.md`

- [X] **9.2 Variáveis de ambiente**
  - [X] 9.2.1 Extrair `SECRET_KEY`, `DEBUG` e `ALLOWED_HOSTS` para variáveis de ambiente
  - [X] 9.2.2 Criar `.env.example`
  - [X] 9.2.3 Adicionar leitura via `os.environ` em `settings.py`

- [X] **9.3 Deploy-ready**
  - [X] 9.3.1 Configurar `collectstatic`
  - [X] 9.3.2 Configurar servidor WSGI (gunicorn) no container
  - [X] 9.3.3 Validar execução via `docker compose up`

---
