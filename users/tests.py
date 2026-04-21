from django.contrib.auth import get_user_model
from django.test import TestCase

User = get_user_model()


class UserManagerTest(TestCase):
    def test_create_user_sets_email(self):
        user = User.objects.create_user(email='alice@example.com', password='pass123')
        self.assertEqual(user.email, 'alice@example.com')
        self.assertTrue(user.check_password('pass123'))
        self.assertFalse(user.is_staff)
        self.assertFalse(user.is_superuser)

    def test_create_user_normalises_email(self):
        user = User.objects.create_user(email='alice@EXAMPLE.COM', password='pass123')
        self.assertEqual(user.email, 'alice@example.com')

    def test_create_user_without_email_raises_value_error(self):
        with self.assertRaises(ValueError):
            User.objects.create_user(email='', password='pass123')

    def test_create_user_with_none_email_raises_value_error(self):
        with self.assertRaises(ValueError):
            User.objects.create_user(email=None, password='pass123')

    def test_create_superuser_sets_staff_and_superuser(self):
        user = User.objects.create_superuser(email='admin@example.com', password='admin123')
        self.assertTrue(user.is_staff)
        self.assertTrue(user.is_superuser)

    def test_create_superuser_is_saved_to_db(self):
        User.objects.create_superuser(email='admin@example.com', password='admin123')
        self.assertEqual(User.objects.filter(email='admin@example.com').count(), 1)

    def test_str_returns_email(self):
        user = User.objects.create_user(email='bob@example.com', password='pass')
        self.assertEqual(str(user), 'bob@example.com')
