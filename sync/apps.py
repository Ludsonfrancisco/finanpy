from django.apps import AppConfig


class SyncConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'sync'

    def ready(self):
        from accounts.models import Account
        from categories.models import Category
        from sync.signals import connect_sync_signals
        from transactions.models import Transaction

        for model in (Account, Category, Transaction):
            connect_sync_signals(model)
