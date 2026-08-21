from django.test import SimpleTestCase

from core.release import ReleaseVersionError, validate_app_version


class ReleaseVersionTest(SimpleTestCase):
    def test_production_accepts_only_full_lowercase_sha(self):
        sha = 'a' * 40
        self.assertEqual(validate_app_version(sha, debug=False), sha)
        for invalid in ('', 'development', 'unknown', 'A' * 40, 'a' * 39):
            with self.subTest(invalid=invalid):
                with self.assertRaises(ReleaseVersionError):
                    validate_app_version(invalid, debug=False)

    def test_development_allows_development_or_full_sha(self):
        self.assertEqual(
            validate_app_version('development', debug=True),
            'development',
        )
        self.assertEqual(validate_app_version('b' * 40, debug=True), 'b' * 40)
