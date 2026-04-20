from django.contrib.auth import get_user_model
from django.db import IntegrityError
from django.test import TestCase

from .models import Category

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
