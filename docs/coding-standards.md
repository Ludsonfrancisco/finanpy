# Padrões de código

## Python e Django

- PEP 8, aspas simples, nomes e código em inglês.
- Textos da interface em pt-BR.
- Preferência por Class-Based Views e recursos nativos do Django.
- Cada domínio permanece em seu app.
- Mudanças de comportamento exigem teste de regressão.
- Migrations aplicadas são imutáveis; correções usam uma nova migration.

## Segurança por Lar

`Household` é a fronteira de autorização. Toda view financeira deve usar
`HouseholdContextMixin` e filtrar por `self.household`.

```python
def get_queryset(self):
    return super().get_queryset().filter(household=self.household)
```

Nunca use apenas `request.user` como fronteira e nunca confie em IDs recebidos
sem restringir a queryset ao Lar. Relações entre transação, conta, categoria e
responsável devem pertencer ao mesmo Lar.

As FKs legadas `user` são preservadas para rastreabilidade. Elas não substituem
a autorização por Lar e não devem voltar a `CASCADE`.

## Forms

ModelForms podem omitir campos preenchidos pela view, como `user`,
`household` e `financial_owner`. Erros desses campos devem ser exibidos como
erros gerais do formulário; nunca podem resultar em HTTP 500.

Criação e edição inválidas não persistem dados. Edição de transação preserva o
responsável existente, salvo requisito explícito e testado.

## Templates

- Herdar de um layout compartilhado.
- Reutilizar parciais em `templates/partials/`.
- Escapar conteúdo pelo mecanismo padrão do Django.
- Não incluir credenciais ou dados financeiros em artefatos de QA.

## Qualidade

```bash
ruff check . --config pyproject.toml
python manage.py check
python manage.py makemigrations --check
coverage run manage.py test
coverage report --fail-under=90
```

Antes de produção, executar também:

```bash
python manage.py check --deploy --fail-level WARNING
python manage.py audit_household_integrity
```

## Nomenclatura

| Tipo | Convenção | Exemplo |
|---|---|---|
| Classes Python | PascalCase | `AccountListView` |
| Funções/variáveis | snake_case | `get_queryset` |
| Templates | snake_case | `confirm_delete.html` |
| URLs nomeadas | namespace do app | `accounts:list` |
| Models | PascalCase singular | `Transaction` |
