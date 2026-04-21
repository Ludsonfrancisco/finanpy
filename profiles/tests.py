from django.contrib.auth import get_user_model
from django.test import TestCase

from profiles.models import Profile

User = get_user_model()


class ProfileSignalTest(TestCase):
    def test_profile_created_on_user_save(self):
        user = User.objects.create_user(email='carol@example.com', password='pass123')
        self.assertTrue(Profile.objects.filter(user=user).exists())

    def test_profile_linked_via_reverse_accessor(self):
        user = User.objects.create_user(email='dave@example.com', password='pass123')
        profile = user.profile
        self.assertIsInstance(profile, Profile)
        self.assertEqual(profile.user, user)

    def test_only_one_profile_created_per_user(self):
        user = User.objects.create_user(email='eve@example.com', password='pass123')
        # Updating the user must not create an extra profile
        user.save()
        self.assertEqual(Profile.objects.filter(user=user).count(), 1)

    def test_profile_str(self):
        user = User.objects.create_user(email='frank@example.com', password='pass123')
        self.assertEqual(str(user.profile), f'Perfil de {user.email}')
