# Arquitetura

## Stack

| Camada | Tecnologia |
|---|---|
| Linguagem | Python 3.12+ |
| Framework | Django 5.2 |
| Template engine | Django Template Language (DTL) |
| Estilização | TailwindCSS via CDN |
| Banco de dados | SQLite |
| Autenticação | `django.contrib.auth` |
| Views | Class-Based Views (CBVs) |
| Forms | Django Forms / ModelForms |

## Estrutura de apps

```
finanpy/
├── core/           # settings, urls raiz, wsgi/asgi
├── users/          # modelo de usuário customizado
├── profiles/       # perfil 1:1 com User
├── accounts/       # contas bancárias
├── categories/     # categorias de transações
└── transactions/   # transações financeiras
```

### Responsabilidades

| App | Responsabilidade |
|---|---|
| `core` | Configurações globais, URL raiz, WSGI/ASGI |
| `users` | `User` customizado com e-mail como campo de login |
| `profiles` | `Profile` vinculado 1:1 ao `User` |
| `accounts` | Contas bancárias do usuário |
| `categories` | Categorias de receita e despesa |
| `transactions` | Transações financeiras |

## Modelo de dados

```
User ──────── Profile      (1:1)
User ──────── Account      (1:N)
User ──────── Category     (1:N)
User ──────── Transaction  (1:N)
Account ───── Transaction  (1:N)
Category ──── Transaction  (1:N)
```

## URLs

Atualmente apenas a rota do admin está configurada:

```
/admin/   →   django.contrib.admin
```

As demais rotas serão adicionadas em cada app conforme implementação.

## Settings relevantes

- `ROOT_URLCONF = 'core.urls'`
- `DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'`
- `USE_TZ = True`
- Banco: SQLite em `BASE_DIR / 'db.sqlite3'`
