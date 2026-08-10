# Household Ledger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduzir o Lar como fronteira financeira principal, criar os responsáveis “Eu”, “Esposa” e “Conjunto” e migrar os dados existentes para “Conjunto” sem interromper o sistema web atual.

**Architecture:** Manter o monólito Django e adicionar um app `households` responsável por associação, responsáveis e resolução do Lar ativo. Contas, categorias e movimentações recebem os novos vínculos em três fases — opcionais, preenchidos e obrigatórios — enquanto os vínculos legados com `User` permanecem temporariamente para compatibilidade.

**Tech Stack:** Python 3.12 no CI, Django 5.2.13, SQLite, Django TestCase/TransactionTestCase, Ruff e Coverage.

## Global Constraints

- O Lar é a unidade principal de autorização e consolidação.
- “Eu”, “Esposa” e “Conjunto” são classificações financeiras, não ledgers independentes.
- A visão principal soma os três responsáveis.
- Categorias são compartilhadas pelo Lar e não possuem responsável individual.
- Dados existentes são migrados para “Conjunto”.
- O vínculo legado com `User` permanece nesta entrega.
- Nenhum segundo login, API, Flutter, Open Finance ou design system entra neste plano.
- Toda mudança de comportamento começa por um teste que falha.
- Cada task termina com verificação, commit e push para `codex/sprint-1-household-ledger`.
- Nenhuma migration é ensaiada sobre o banco real sem backup verificado.

---

## Estrutura de arquivos

- `households/models.py`: entidades `Household`, `HouseholdMembership` e `FinancialOwner`.
- `households/services.py`: criação idempotente e resolução explícita do Lar do usuário.
- `households/mixins.py`: resolução do Lar em views autenticadas.
- `households/admin.py`: administração técnica do Lar e responsáveis.
- `households/tests/test_models.py`: invariantes dos três modelos.
- `households/tests/test_boundaries.py`: validações entre Lar, conta, categoria e movimentação.
- `households/tests/test_migrations.py`: prova do backfill e da preservação de dados.
- `accounts/models.py`, `categories/models.py`, `transactions/models.py`: vínculos e validações do domínio existente.
- `accounts/views.py`, `categories/views.py`, `transactions/views.py`, `core/views.py`: escopo obrigatório por Lar.
- `transactions/forms.py`: querysets limitados ao Lar.
- migrations `0002`/`0003` nos apps afetados: adição opcional, backfill e obrigatoriedade.
- `docs/sprints/sprint-1-household-ledger.md`: evidências do fechamento da sprint.

---

### Task 1: Criar o núcleo do Lar e os três responsáveis

**Files:**

- Create: `households/__init__.py`
- Create: `households/apps.py`
- Create: `households/models.py`
- Create: `households/services.py`
- Create: `households/admin.py`
- Create: `households/tests/__init__.py`
- Create: `households/tests/test_models.py`
- Create: `households/migrations/__init__.py`
- Create: `households/migrations/0001_initial.py`
- Modify: `core/settings.py`

**Interfaces:**

- Produces: `ensure_household_for_user(user) -> Household`.
- Produces: `get_household_for_user(user) -> Household`.
- Produces: `get_financial_owner(household, owner_type=FinancialOwner.SHARED) -> FinancialOwner`.
- Later tasks consume `Household`, `FinancialOwner` and these three functions.

- [x] **Step 1: Criar os testes que descrevem as invariantes**

Criar `households/tests/test_models.py`:

```python
from django.contrib.auth import get_user_model
from django.db import IntegrityError
from django.test import TestCase

from households.models import FinancialOwner, Household, HouseholdMembership
from households.services import ensure_household_for_user

User = get_user_model()


class HouseholdModelTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='household-owner@example.com',
            password='test-password-123',
        )

    def test_bootstrap_creates_household_membership_and_three_owners(self):
        household = ensure_household_for_user(self.user)

        self.assertEqual(household.name, 'Lar Finance')
        self.assertTrue(
            HouseholdMembership.objects.filter(
                household=household,
                user=self.user,
                role=HouseholdMembership.ADMIN,
            ).exists()
        )
        self.assertEqual(
            set(household.financial_owners.values_list('type', flat=True)),
            {FinancialOwner.SELF, FinancialOwner.SPOUSE, FinancialOwner.SHARED},
        )

    def test_bootstrap_is_idempotent(self):
        first = ensure_household_for_user(self.user)
        second = ensure_household_for_user(self.user)

        self.assertEqual(first, second)
        self.assertEqual(Household.objects.count(), 1)
        self.assertEqual(FinancialOwner.objects.count(), 3)

    def test_owner_type_is_unique_inside_household(self):
        household = ensure_household_for_user(self.user)

        with self.assertRaises(IntegrityError):
            FinancialOwner.objects.create(
                household=household,
                type=FinancialOwner.SHARED,
                name='Outro conjunto',
            )
```

- [x] **Step 2: Executar o teste e confirmar a falha esperada**

Run:

```powershell
$env:SECRET_KEY='local-test-only'; $env:DEBUG='True'; $env:ALLOWED_HOSTS='testserver'; $env:SECURE_SSL_REDIRECT='False'
.\.venv\Scripts\python.exe manage.py test households.tests.test_models
```

Expected: `ModuleNotFoundError: No module named 'households'`.

- [x] **Step 3: Implementar os modelos mínimos**

Criar `households/models.py`:

```python
import uuid

from django.conf import settings
from django.db import models


class Household(models.Model):
    uuid = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    name = models.CharField(max_length=120, default='Lar Finance')
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['name', 'pk']

    def __str__(self):
        return self.name


class HouseholdMembership(models.Model):
    ADMIN = 'admin'
    ROLE_CHOICES = [(ADMIN, 'Administrador')]

    household = models.ForeignKey(
        Household,
        on_delete=models.CASCADE,
        related_name='memberships',
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='household_memberships',
    )
    role = models.CharField(max_length=20, choices=ROLE_CHOICES, default=ADMIN)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=['household', 'user'],
                name='unique_household_membership',
            )
        ]


class FinancialOwner(models.Model):
    SELF = 'self'
    SPOUSE = 'spouse'
    SHARED = 'shared'
    TYPE_CHOICES = [
        (SELF, 'Eu'),
        (SPOUSE, 'Esposa'),
        (SHARED, 'Conjunto'),
    ]

    household = models.ForeignKey(
        Household,
        on_delete=models.CASCADE,
        related_name='financial_owners',
    )
    uuid = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    type = models.CharField(max_length=20, choices=TYPE_CHOICES)
    name = models.CharField(max_length=80)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['household_id', 'type']
        constraints = [
            models.UniqueConstraint(
                fields=['household', 'type'],
                name='unique_financial_owner_type_per_household',
            )
        ]

    def __str__(self):
        return self.name
```

Adicionar `'households'` a `INSTALLED_APPS` em `core/settings.py`.

Criar `households/apps.py`:

```python
from django.apps import AppConfig


class HouseholdsConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'households'
```

- [x] **Step 4: Implementar o serviço idempotente**

Criar `households/services.py`:

```python
from django.core.exceptions import ObjectDoesNotExist
from django.db import transaction

from .models import FinancialOwner, Household, HouseholdMembership

OWNER_NAMES = {
    FinancialOwner.SELF: 'Eu',
    FinancialOwner.SPOUSE: 'Esposa',
    FinancialOwner.SHARED: 'Conjunto',
}


@transaction.atomic
def ensure_household_for_user(user):
    membership = (
        HouseholdMembership.objects.select_related('household')
        .filter(user=user, is_active=True, household__is_active=True)
        .order_by('pk')
        .first()
    )
    if membership:
        household = membership.household
    else:
        household = Household.objects.create(name='Lar Finance')
        HouseholdMembership.objects.create(
            household=household,
            user=user,
            role=HouseholdMembership.ADMIN,
        )

    for owner_type, name in OWNER_NAMES.items():
        FinancialOwner.objects.get_or_create(
            household=household,
            type=owner_type,
            defaults={'name': name},
        )
    return household


def get_household_for_user(user):
    try:
        return Household.objects.get(
            memberships__user=user,
            memberships__is_active=True,
            is_active=True,
        )
    except ObjectDoesNotExist as exc:
        raise Household.DoesNotExist('Usuário sem Lar ativo.') from exc


def get_financial_owner(household, owner_type=FinancialOwner.SHARED):
    return FinancialOwner.objects.get(
        household=household,
        type=owner_type,
        is_active=True,
    )
```

- [x] **Step 5: Registrar os modelos no admin**

Criar `households/admin.py`:

```python
from django.contrib import admin

from .models import FinancialOwner, Household, HouseholdMembership


@admin.register(Household)
class HouseholdAdmin(admin.ModelAdmin):
    list_display = ('name', 'uuid', 'is_active', 'created_at')
    list_filter = ('is_active',)
    search_fields = ('name', 'uuid')


@admin.register(HouseholdMembership)
class HouseholdMembershipAdmin(admin.ModelAdmin):
    list_display = ('household', 'role', 'is_active', 'created_at')
    list_filter = ('role', 'is_active')
    search_fields = ('household__name',)


@admin.register(FinancialOwner)
class FinancialOwnerAdmin(admin.ModelAdmin):
    list_display = ('name', 'type', 'household', 'is_active')
    list_filter = ('type', 'is_active')
    search_fields = ('name', 'uuid', 'household__name')
```

- [x] **Step 6: Gerar e inspecionar a migration inicial**

Run:

```powershell
.\.venv\Scripts\python.exe manage.py makemigrations households
.\.venv\Scripts\python.exe manage.py sqlmigrate households 0001
```

Expected: criação de três tabelas, UUIDs únicos e duas constraints de unicidade.

- [x] **Step 7: Verificar e publicar a task**

Run:

```powershell
.\.venv\Scripts\python.exe manage.py test households.tests.test_models
.\.venv\Scripts\ruff.exe check . --config pyproject.toml
.\.venv\Scripts\python.exe manage.py makemigrations --check
git diff --check
git add households core/settings.py
git commit -m "feat: add household ownership core"
git push origin codex/sprint-1-household-ledger
```

Expected: testes verdes, sem nova migration pendente e push aceito.

---

### Task 2: Adicionar vínculos opcionais e bloquear relações entre lares

**Files:**

- Modify: `accounts/models.py`
- Modify: `categories/models.py`
- Modify: `transactions/models.py`
- Create: `accounts/migrations/0002_account_household_financial_owner.py`
- Create: `categories/migrations/0002_category_household.py`
- Create: `transactions/migrations/0002_transaction_household_financial_owner.py`
- Create: `households/tests/test_boundaries.py`

**Interfaces:**

- Consumes: `Household` e `FinancialOwner` da Task 1.
- Produces: `Account.household`, `Account.financial_owner`, `Category.household`, `Transaction.household` e `Transaction.financial_owner`, inicialmente opcionais.
- Produces: `clean()` explícito em conta e movimentação para validar a fronteira do Lar.

- [x] **Step 1: Escrever testes de fronteira que falham**

Criar `households/tests/test_boundaries.py` com dois usuários, dois lares e os seguintes casos:

```python
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from django.test import TestCase

from accounts.models import Account
from categories.models import Category
from households.models import FinancialOwner
from households.services import ensure_household_for_user, get_financial_owner
from transactions.models import Transaction

User = get_user_model()


class HouseholdBoundaryTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email='one@example.com', password='test-pass')
        self.other_user = User.objects.create_user(email='two@example.com', password='test-pass')
        self.household = ensure_household_for_user(self.user)
        self.other_household = ensure_household_for_user(self.other_user)
        self.owner = get_financial_owner(self.household, FinancialOwner.SHARED)
        self.other_owner = get_financial_owner(self.other_household, FinancialOwner.SHARED)

    def test_account_rejects_owner_from_another_household(self):
        account = Account(
            user=self.user,
            household=self.household,
            financial_owner=self.other_owner,
            name='Conta inválida',
            initial_balance=Decimal('0.00'),
        )

        with self.assertRaises(ValidationError):
            account.full_clean()
```

Completar o `setUp` com conta e categoria válidas em cada Lar e adicionar os três testes abaixo:

```python
self.account = Account.objects.create(
    user=self.user,
    household=self.household,
    financial_owner=self.owner,
    name='Conta do Lar',
)
self.category = Category.objects.create(
    user=self.user,
    household=self.household,
    name='Mercado',
    type=Category.EXPENSE,
)
self.other_account = Account.objects.create(
    user=self.other_user,
    household=self.other_household,
    financial_owner=self.other_owner,
    name='Conta de outro Lar',
)
self.other_category = Category.objects.create(
    user=self.other_user,
    household=self.other_household,
    name='Outra categoria',
    type=Category.EXPENSE,
)

def _transaction(self, **overrides):
    values = {
        'user': self.user,
        'household': self.household,
        'financial_owner': self.owner,
        'account': self.account,
        'category': self.category,
        'description': 'Compra',
        'amount': Decimal('10.00'),
        'date': '2026-08-10',
        'type': Transaction.EXPENSE,
    }
    values.update(overrides)
    return Transaction(**values)

def test_transaction_rejects_account_from_another_household(self):
    with self.assertRaises(ValidationError):
        self._transaction(account=self.other_account).full_clean()

def test_transaction_rejects_category_from_another_household(self):
    with self.assertRaises(ValidationError):
        self._transaction(category=self.other_category).full_clean()

def test_transaction_rejects_owner_from_another_household(self):
    with self.assertRaises(ValidationError):
        self._transaction(financial_owner=self.other_owner).full_clean()
```

- [x] **Step 2: Executar o teste e confirmar a falha esperada**

Run:

```powershell
.\.venv\Scripts\python.exe manage.py test households.tests.test_boundaries
```

Expected: falha porque os novos campos ainda não existem.

- [x] **Step 3: Adicionar os campos opcionais**

Adicionar a `Account`:

```python
household = models.ForeignKey(
    'households.Household',
    on_delete=models.PROTECT,
    related_name='accounts',
    null=True,
    blank=True,
)
financial_owner = models.ForeignKey(
    'households.FinancialOwner',
    on_delete=models.PROTECT,
    related_name='accounts',
    null=True,
    blank=True,
)
```

Adicionar a `Category`:

```python
household = models.ForeignKey(
    'households.Household',
    on_delete=models.PROTECT,
    related_name='categories',
    null=True,
    blank=True,
)
```

Adicionar a `Transaction`:

```python
household = models.ForeignKey(
    'households.Household',
    on_delete=models.PROTECT,
    related_name='transactions',
    null=True,
    blank=True,
)
financial_owner = models.ForeignKey(
    'households.FinancialOwner',
    on_delete=models.PROTECT,
    related_name='transactions',
    null=True,
    blank=True,
)
```

- [x] **Step 4: Implementar validações explícitas**

Adicionar a `Account.clean()`:

```python
def clean(self):
    super().clean()
    if (
        self.household_id
        and self.financial_owner_id
        and self.financial_owner.household_id != self.household_id
    ):
        raise ValidationError({'financial_owner': 'Responsável pertence a outro Lar.'})
```

Adicionar a `Transaction.clean()`:

```python
def clean(self):
    super().clean()
    errors = {}
    if self.household_id and self.account_id and self.account.household_id != self.household_id:
        errors['account'] = 'Conta pertence a outro Lar.'
    if self.household_id and self.category_id and self.category.household_id != self.household_id:
        errors['category'] = 'Categoria pertence a outro Lar.'
    if (
        self.household_id
        and self.financial_owner_id
        and self.financial_owner.household_id != self.household_id
    ):
        errors['financial_owner'] = 'Responsável pertence a outro Lar.'
    if errors:
        raise ValidationError(errors)
```

Importar `ValidationError` de `django.core.exceptions` nos dois arquivos.

- [x] **Step 5: Gerar as migrations opcionais**

Run:

```powershell
.\.venv\Scripts\python.exe manage.py makemigrations accounts --name account_household_financial_owner
.\.venv\Scripts\python.exe manage.py makemigrations categories --name category_household
.\.venv\Scripts\python.exe manage.py makemigrations transactions --name transaction_household_financial_owner
.\.venv\Scripts\python.exe manage.py showmigrations accounts categories transactions
```

Expected: uma migration `0002` em cada app, sem pedido de valor padrão.

- [x] **Step 6: Verificar e publicar a task**

Run:

```powershell
.\.venv\Scripts\python.exe manage.py test households.tests.test_boundaries
.\.venv\Scripts\python.exe manage.py test
.\.venv\Scripts\ruff.exe check . --config pyproject.toml
.\.venv\Scripts\python.exe manage.py makemigrations --check
git diff --check
git add accounts categories transactions households/tests/test_boundaries.py
git commit -m "feat: add household boundaries to ledger"
git push origin codex/sprint-1-household-ledger
```

Expected: testes existentes continuam verdes porque os campos ainda aceitam nulo.

---

### Task 3: Migrar dados existentes para Lar/Conjunto

**Files:**

- Create: `households/migrations/0002_backfill_existing_financial_data.py`
- Create: `households/tests/test_migrations.py`

**Interfaces:**

- Consumes: campos opcionais da Task 2.
- Produces: um Lar, uma associação administrativa e três responsáveis para cada usuário legado.
- Produces: todos os registros existentes preenchidos; contas e movimentações usam `shared`.

- [x] **Step 1: Escrever o teste de migration antes do backfill**

Criar `households/tests/test_migrations.py` usando `MigrationExecutor`. Migrar inicialmente para:

```python
migrate_from = [
    ('households', '0001_initial'),
    ('accounts', '0002_account_household_financial_owner'),
    ('categories', '0002_category_household'),
    ('transactions', '0002_transaction_household_financial_owner'),
]
migrate_to = [('households', '0002_backfill_existing_financial_data')]
```

No estado histórico inicial, criar um usuário, uma conta, uma categoria e uma movimentação com os novos campos nulos. Depois de migrar, afirmar:

```python
self.assertEqual(Household.objects.count(), 1)
self.assertEqual(HouseholdMembership.objects.count(), 1)
self.assertEqual(FinancialOwner.objects.count(), 3)
self.assertEqual(Account.objects.filter(household__isnull=True).count(), 0)
self.assertEqual(Category.objects.filter(household__isnull=True).count(), 0)
self.assertEqual(Transaction.objects.filter(household__isnull=True).count(), 0)
self.assertEqual(Account.objects.get().financial_owner.type, 'shared')
self.assertEqual(Transaction.objects.get().financial_owner.type, 'shared')
self.assertEqual(Transaction.objects.get().amount, Decimal('125.50'))
```

- [x] **Step 2: Executar o teste e confirmar a falha esperada**

Run:

```powershell
.\.venv\Scripts\python.exe manage.py test households.tests.test_migrations
```

Expected: falha porque `0002_backfill_existing_financial_data` ainda não existe.

- [x] **Step 3: Criar a migration de dados reversível**

Criar `households/migrations/0002_backfill_existing_financial_data.py`:

```python
from django.db import migrations


OWNER_NAMES = {
    'self': 'Eu',
    'spouse': 'Esposa',
    'shared': 'Conjunto',
}


def forwards(apps, schema_editor):
    User = apps.get_model('users', 'User')
    Household = apps.get_model('households', 'Household')
    Membership = apps.get_model('households', 'HouseholdMembership')
    Owner = apps.get_model('households', 'FinancialOwner')
    Account = apps.get_model('accounts', 'Account')
    Category = apps.get_model('categories', 'Category')
    Transaction = apps.get_model('transactions', 'Transaction')

    for user in User.objects.order_by('pk').iterator():
        household = Household.objects.create(name='Lar Finance')
        Membership.objects.create(household=household, user_id=user.pk, role='admin')
        owners = {
            owner_type: Owner.objects.create(
                household=household,
                type=owner_type,
                name=name,
            )
            for owner_type, name in OWNER_NAMES.items()
        }
        shared = owners['shared']
        Account.objects.filter(user_id=user.pk, household__isnull=True).update(
            household=household,
            financial_owner=shared,
        )
        Category.objects.filter(user_id=user.pk, household__isnull=True).update(
            household=household,
        )
        Transaction.objects.filter(user_id=user.pk, household__isnull=True).update(
            household=household,
            financial_owner=shared,
        )


def backwards(apps, schema_editor):
    Household = apps.get_model('households', 'Household')
    Membership = apps.get_model('households', 'HouseholdMembership')
    Account = apps.get_model('accounts', 'Account')
    Category = apps.get_model('categories', 'Category')
    Transaction = apps.get_model('transactions', 'Transaction')

    for membership in Membership.objects.filter(role='admin').order_by('pk'):
        household_id = membership.household_id
        user_id = membership.user_id
        Account.objects.filter(user_id=user_id, household_id=household_id).update(
            household=None,
            financial_owner=None,
        )
        Category.objects.filter(user_id=user_id, household_id=household_id).update(
            household=None,
        )
        Transaction.objects.filter(user_id=user_id, household_id=household_id).update(
            household=None,
            financial_owner=None,
        )
        Household.objects.filter(pk=household_id).delete()


class Migration(migrations.Migration):
    dependencies = [
        ('households', '0001_initial'),
        ('users', '0001_initial'),
        ('accounts', '0002_account_household_financial_owner'),
        ('categories', '0002_category_household'),
        ('transactions', '0002_transaction_household_financial_owner'),
    ]

    operations = [migrations.RunPython(forwards, backwards)]
```

- [x] **Step 4: Testar ida, preservação e volta**

Completar o teste com uma segunda execução do `MigrationExecutor` até o estado `migrate_from` e afirmar que conta, categoria e movimentação continuam existindo, agora com os campos novos nulos.

Run:

```powershell
.\.venv\Scripts\python.exe manage.py test households.tests.test_migrations
```

Expected: backfill verde, valores preservados e reversão sem apagar o ledger legado.

- [x] **Step 5: Verificar e publicar a task**

Run:

```powershell
.\.venv\Scripts\python.exe manage.py test households.tests
.\.venv\Scripts\python.exe manage.py test
.\.venv\Scripts\ruff.exe check . --config pyproject.toml
.\.venv\Scripts\python.exe manage.py makemigrations --check
git diff --check
git add households/migrations/0002_backfill_existing_financial_data.py households/tests/test_migrations.py
git commit -m "feat: backfill legacy data into household"
git push origin codex/sprint-1-household-ledger
```

Expected: migration test prova ida e volta sem perda.

---

### Task 4: Escopar o sistema web pelo Lar

**Files:**

- Create: `households/mixins.py`
- Modify: `accounts/views.py`
- Modify: `categories/views.py`
- Modify: `transactions/forms.py`
- Modify: `transactions/views.py`
- Modify: `core/views.py`
- Modify: `accounts/tests.py`
- Modify: `categories/tests.py`
- Modify: `transactions/tests.py`
- Modify: `core/tests.py`

**Interfaces:**

- Consumes: `ensure_household_for_user()` e `get_financial_owner()`.
- Produces: `HouseholdContextMixin.household` em views autenticadas.
- Produces: `TransactionForm(..., household=household)`.
- Mantém o painel consolidado; não adiciona filtro visual nesta task.

- [x] **Step 1: Escrever testes de escopo que falham**

Atualizar os testes de views para criar dois usuários com lares distintos por `ensure_household_for_user()`. Criar os registros com Lar/responsável explícitos e adicionar estas afirmações:

```python
def test_account_list_is_scoped_by_household(self):
    response = self.client.get('/accounts/')
    self.assertContains(response, self.account.name)
    self.assertNotContains(response, self.other_account.name)


def test_dashboard_consolidates_all_three_owners(self):
    response = self.client.get('/dashboard/')
    self.assertEqual(response.context['total_balance'], Decimal('1500.00'))
```

No teste do dashboard, criar contas no mesmo Lar para “Eu”, “Esposa” e “Conjunto”; a soma esperada deve incluir todas.

- [x] **Step 2: Executar testes focados e confirmar a falha**

Run:

```powershell
.\.venv\Scripts\python.exe manage.py test accounts.tests categories.tests transactions.tests core.tests
```

Expected: falhas nas novas verificações porque as queries ainda usam somente `user`.

- [x] **Step 3: Criar o mixin de contexto**

Criar `households/mixins.py`:

```python
from .services import ensure_household_for_user


class HouseholdContextMixin:
    household = None

    def dispatch(self, request, *args, **kwargs):
        self.household = ensure_household_for_user(request.user)
        return super().dispatch(request, *args, **kwargs)
```

Nas classes de view, manter `LoginRequiredMixin` antes de `HouseholdContextMixin` para que usuários anônimos sejam redirecionados antes da resolução do Lar.

- [x] **Step 4: Trocar queries e criação de contas/categorias**

Em `accounts/views.py`:

```python
def get_queryset(self):
    return super().get_queryset().filter(household=self.household)

def form_valid(self, form):
    form.instance.user = self.request.user
    form.instance.household = self.household
    form.instance.financial_owner = get_financial_owner(self.household)
    form.instance.full_clean()
    return super().form_valid(form)
```

Em `categories/views.py`, usar o mesmo escopo e preencher `user` e `household`; categoria não recebe responsável.

- [x] **Step 5: Escopar formulário e views de movimentações**

Alterar `TransactionForm.__init__`:

```python
def __init__(self, *args, household=None, **kwargs):
    super().__init__(*args, **kwargs)
    if household:
        self.fields['account'].queryset = Account.objects.filter(household=household)
        self.fields['category'].queryset = Category.objects.filter(household=household)
    else:
        self.fields['account'].queryset = Account.objects.none()
        self.fields['category'].queryset = Category.objects.none()
```

Passar `household=self.household` em `get_form_kwargs()`. Na criação, preencher:

```python
form.instance.user = self.request.user
form.instance.household = self.household
form.instance.financial_owner = form.cleaned_data['account'].financial_owner
form.instance.full_clean()
```

Listagem, edição e exclusão devem filtrar por `household=self.household`.

- [x] **Step 6: Escopar e manter o dashboard consolidado**

Em `DashboardView`, resolver o Lar e substituir todos os filtros `user=user` por `household=household`. Não aplicar filtro por responsável. Manter os cálculos existentes de saldo, receitas, despesas, categorias e movimentações recentes.

- [x] **Step 7: Atualizar testes legados com contexto explícito**

Nos `setUp`, usar:

```python
self.household = ensure_household_for_user(self.user)
self.shared_owner = get_financial_owner(self.household)
```

Criar contas e movimentações com `household=self.household` e `financial_owner=self.shared_owner`; criar categorias com `household=self.household`. Remover o teste que esperava todas as contas quando `TransactionForm` não recebia usuário e substituí-lo por um teste que espera querysets vazios sem Lar.

- [x] **Step 8: Verificar e publicar a task**

Run:

```powershell
.\.venv\Scripts\python.exe manage.py test accounts.tests categories.tests transactions.tests core.tests
.\.venv\Scripts\python.exe manage.py test
.\.venv\Scripts\ruff.exe check . --config pyproject.toml
.\.venv\Scripts\python.exe manage.py makemigrations --check
git diff --check
git add households/mixins.py accounts categories transactions core/views.py core/tests.py
git commit -m "feat: scope web ledger by household"
git push origin codex/sprint-1-household-ledger
```

Expected: o painel soma os três responsáveis e um usuário não consulta objetos de outro Lar.

---

### Task 5: Tornar os vínculos obrigatórios e ajustar unicidade

**Files:**

- Modify: `accounts/models.py`
- Modify: `categories/models.py`
- Modify: `transactions/models.py`
- Create: `accounts/migrations/0003_require_household_owner.py`
- Create: `categories/migrations/0003_require_household.py`
- Create: `transactions/migrations/0003_require_household_owner.py`
- Modify: tests que ainda criem registros sem Lar/responsável

**Interfaces:**

- Consumes: backfill comprovado e views já adaptadas.
- Produces: vínculos não nulos no banco.
- Produces: unicidade de categoria por `(household, name, type)`.

- [x] **Step 1: Localizar criações incompatíveis antes de alterar o schema**

Run:

```powershell
rg -n "Account\.objects\.create|Category\.objects\.create|Transaction\.objects\.create" --glob "*tests.py" --glob "!**/migrations/**"
```

Para cada ocorrência, garantir os campos definidos na Task 4. O comando deve permanecer como checklist de revisão; não alterar arquivos de migration histórica.

- [x] **Step 2: Escrever testes de obrigatoriedade e unicidade**

Adicionar em `households/tests/test_boundaries.py`:

```python
def test_account_requires_household_and_owner(self):
    account = Account(user=self.user, name='Sem Lar')
    with self.assertRaises(ValidationError):
        account.full_clean()

def test_categories_are_unique_inside_household(self):
    Category.objects.create(
        user=self.user,
        household=self.household,
        name='Mercado',
        type=Category.EXPENSE,
    )
    with self.assertRaises(IntegrityError):
        Category.objects.create(
            user=self.user,
            household=self.household,
            name='Mercado',
            type=Category.EXPENSE,
        )
```

- [x] **Step 3: Confirmar o estado vermelho**

Run:

```powershell
.\.venv\Scripts\python.exe manage.py test households.tests.test_boundaries
```

Expected: o teste de obrigatoriedade falha enquanto os campos aceitam nulo.

- [x] **Step 4: Tornar campos obrigatórios e atualizar a constraint de categoria**

Remover `null=True, blank=True` dos novos campos. Em `Category.Meta`, substituir `unique_together = ('user', 'name', 'type')` por:

```python
constraints = [
    models.UniqueConstraint(
        fields=['household', 'name', 'type'],
        name='unique_category_per_household_name_type',
    )
]
```

Manter os campos `user` existentes, sem usá-los como fronteira principal.

- [x] **Step 5: Gerar e inspecionar migrations finais**

Run:

```powershell
.\.venv\Scripts\python.exe manage.py makemigrations accounts --name require_household_owner
.\.venv\Scripts\python.exe manage.py makemigrations categories --name require_household
.\.venv\Scripts\python.exe manage.py makemigrations transactions --name require_household_owner
.\.venv\Scripts\python.exe sqlmigrate accounts 0003
.\.venv\Scripts\python.exe sqlmigrate categories 0003
.\.venv\Scripts\python.exe sqlmigrate transactions 0003
```

Expected: alterações `NOT NULL` e troca da constraint de categoria; nenhuma operação apaga dados.

- [x] **Step 6: Verificar e publicar a task**

Run:

```powershell
.\.venv\Scripts\python.exe manage.py test households.tests.test_boundaries
.\.venv\Scripts\python.exe manage.py test
.\.venv\Scripts\ruff.exe check . --config pyproject.toml
.\.venv\Scripts\python.exe manage.py makemigrations --check
git diff --check
git add accounts categories transactions households/tests/test_boundaries.py core/tests.py
git commit -m "feat: require household ownership links"
git push origin codex/sprint-1-household-ledger
```

Expected: nenhum registro novo pode ser salvo sem Lar; conta e movimentação também exigem responsável.

---

### Task 6: Ensaiar migrations, registrar evidências e fechar a sprint

**Files:**

- Modify: `README.md`
- Create: `docs/sprints/sprint-1-household-ledger.md`
- Modify: `docs/superpowers/plans/2026-08-10-household-ledger-implementation.md` para marcar checkboxes comprovados

**Interfaces:**

- Consumes: schema e código concluídos nas Tasks 1–5.
- Produces: prova de backup, migração, rollback, cobertura e sincronização remota.
- Não altera comportamento financeiro.

- [x] **Step 1: Criar backup verificado do banco local de ensaio**

Run:

```powershell
$env:SECRET_KEY='local-test-only'; $env:DEBUG='True'; $env:ALLOWED_HOSTS='localhost,testserver'; $env:SECURE_SSL_REDIRECT='False'
.\.venv\Scripts\python.exe manage.py backup_sqlite --output backups/sprint-1-before-migrations.sqlite3
```

Expected: `Backup verified` e arquivo ignorado pelo Git.

- [x] **Step 2: Ensaiar upgrade, rollback e novo upgrade somente na cópia**

Run:

```powershell
$env:SQLITE_PATH='backups/sprint-1-before-migrations.sqlite3'
.\.venv\Scripts\python.exe manage.py migrate
.\.venv\Scripts\python.exe manage.py migrate households 0001
.\.venv\Scripts\python.exe manage.py migrate
.\.venv\Scripts\python.exe manage.py check
```

Expected: os três comandos de migration terminam sem erro. Confirmar, com shell Django na cópia, que não há contas, categorias ou movimentações órfãs após o segundo upgrade.

- [x] **Step 3: Executar a verificação completa com cobertura**

Run:

```powershell
$env:SQLITE_PATH='data/sprint-1-verification.sqlite3'; $env:SECURE_SSL_REDIRECT='False'
.\.venv\Scripts\ruff.exe check . --config pyproject.toml
.\.venv\Scripts\python.exe manage.py check
.\.venv\Scripts\python.exe manage.py makemigrations --check
.\.venv\Scripts\coverage.exe erase
.\.venv\Scripts\coverage.exe run manage.py test
.\.venv\Scripts\coverage.exe report --fail-under=90
git diff --check
```

Expected: todos os testes verdes, coverage mínimo de 90%, Ruff e migrations limpos.

- [x] **Step 4: Verificar configuração equivalente à produção**

Run:

```powershell
$env:SECRET_KEY='production-check-only-0123456789-abcdefghijklmnopqrstuvwxyz-XYZ'; $env:DEBUG='False'; $env:ALLOWED_HOSTS='finance.example.test'; $env:SECURE_SSL_REDIRECT='True'; $env:SESSION_COOKIE_SECURE='True'; $env:CSRF_COOKIE_SECURE='True'; $env:SECURE_HSTS_SECONDS='3600'; $env:SECURE_HSTS_INCLUDE_SUBDOMAINS='True'; $env:SECURE_HSTS_PRELOAD='True'
.\.venv\Scripts\python.exe manage.py check --deploy
```

Expected: `System check identified no issues`.

- [x] **Step 5: Documentar resultado e rollback**

Atualizar `README.md` com o conceito de Lar e o comando administrativo utilizado para garantir o Lar do usuário. Criar `docs/sprints/sprint-1-household-ledger.md` contendo:

- commits de cada task;
- contagem final de testes e cobertura;
- resultado do ensaio de upgrade/rollback;
- confirmação de que dados legados foram atribuídos a “Conjunto”;
- riscos restantes: troca da senha antiga, limpeza opcional do histórico e validação no EasyPanel;
- próximo passo: vincular UUID/versão e preparar a API, sem iniciar design visual.

- [x] **Step 6: Commit e push de encerramento da sprint**

Run:

```powershell
git add README.md docs/sprints/sprint-1-household-ledger.md docs/superpowers/plans/2026-08-10-household-ledger-implementation.md
git diff --cached --check
git commit -m "docs: close household ledger sprint"
git push origin codex/sprint-1-household-ledger
git fetch origin
git rev-list --left-right --count HEAD...origin/codex/sprint-1-household-ledger
```

Expected: resultado final `0 0`, comprovando sincronização entre local e GitHub.

---

## Critério de encerramento

A sprint termina somente quando Tasks 1–6 estiverem verificadas e publicadas, migrations tiverem sido ensaiadas sobre uma cópia, o consolidado incluir os três responsáveis e nenhuma query financeira web depender apenas de `User` como fronteira de segurança.
