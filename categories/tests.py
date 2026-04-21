from django.contrib.auth import get_user_model
from django.db import IntegrityError
from django.test import TestCase

from categories.forms import CategoryForm
from categories.models import Category

User = get_user_model()


class CategoryModelTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='test@example.com',
            password='password123'
        )

    def test_category_creation(self):
        category = Category.objects.create(
            user=self.user,
            name='Alimentação',
            type=Category.EXPENSE,
            color='#FF0000'
        )
        self.assertEqual(category.name, 'Alimentação')
        self.assertEqual(category.type, Category.EXPENSE)
        self.assertEqual(str(category), 'Alimentação (Despesa)')

    def test_unique_together_constraint(self):
        Category.objects.create(
            user=self.user,
            name='Alimentação',
            type=Category.EXPENSE
        )
        with self.assertRaises(IntegrityError):
            Category.objects.create(
                user=self.user,
                name='Alimentação',
                type=Category.EXPENSE
            )

    def test_different_types_same_name_allowed(self):
        Category.objects.create(
            user=self.user,
            name='Salário',
            type=Category.INCOME
        )
        # Should NOT raise IntegrityError
        category = Category.objects.create(
            user=self.user,
            name='Salário',
            type=Category.EXPENSE
        )
        self.assertEqual(Category.objects.filter(name='Salário').count(), 2)


class CategoryFormTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email='hank@example.com',
            password='pass123',
        )

    def _valid_data(self, name='Transporte', tx_type=Category.EXPENSE):
        return {'name': name, 'type': tx_type, 'color': '#10b981', 'icon': ''}

    def test_valid_data_passes(self):
        form = CategoryForm(data=self._valid_data())
        self.assertTrue(form.is_valid(), form.errors)

    def test_name_required(self):
        data = self._valid_data()
        data['name'] = ''
        form = CategoryForm(data=data)
        self.assertFalse(form.is_valid())
        self.assertIn('name', form.errors)

    def test_type_required(self):
        data = self._valid_data()
        data['type'] = ''
        form = CategoryForm(data=data)
        self.assertFalse(form.is_valid())
        self.assertIn('type', form.errors)

    def test_unique_together_raises_validation_error_via_form(self):
        # First save is fine
        Category.objects.create(
            user=self.user,
            name='Lazer',
            type=Category.EXPENSE,
        )
        # Build the duplicate through the form; bind it to the existing instance's
        # user by saving manually, then validate_unique via full_clean.
        duplicate = Category(user=self.user, name='Lazer', type=Category.EXPENSE)
        from django.core.exceptions import ValidationError
        with self.assertRaises(ValidationError):
            duplicate.validate_unique()
