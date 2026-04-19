# Padrões de Código

## Python

- Aderência à **PEP-8**
- Aspas **simples** em todo o código Python
- Código em **inglês** (variáveis, funções, classes, comentários)
- Interface do usuário em **pt-BR**

## Django

- Preferência por **Class-Based Views (CBVs)**
- Usar recursos nativos do Django: ORM, signals, forms, auth
- Cada domínio em seu próprio app
- Signals em `signals.py` por app, registrados em `apps.py` via método `ready()`
- Models sempre com `created_at` e `updated_at`

### Estrutura padrão de app

```
app/
├── __init__.py
├── admin.py
├── apps.py
├── forms.py       # ModelForms e Forms customizados
├── models.py
├── signals.py     # signals do app (se houver)
├── tests.py
├── urls.py        # rotas do app
└── views.py       # CBVs
```

### Segurança de dados por usuário

Toda view que liste ou altere dados deve filtrar por `user=request.user`. Nunca confiar em IDs vindos da URL sem validar o dono.

```python
def get_queryset(self):
    return super().get_queryset().filter(user=self.request.user)
```

## Templates

- Herdar sempre de um layout base (`base_public.html` ou `base_app.html`)
- Componentes reutilizáveis em `templates/partials/`
- Usar `{% block content %}` e `{% block title %}` conforme definido no layout

## Nomenclatura

| Tipo | Convenção | Exemplo |
|---|---|---|
| Classes Python | PascalCase | `AccountListView` |
| Funções/variáveis | snake_case | `get_queryset` |
| Templates | snake_case | `confirm_delete.html` |
| URLs (name) | snake_case com prefixo do app | `accounts:list` |
| Models | PascalCase singular | `Transaction` |
