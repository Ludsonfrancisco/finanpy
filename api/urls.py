from django.urls import path

from api.auth_views import (
    CurrentDeviceView,
    DeviceListView,
    LoginView,
    LogoutView,
    RefreshView,
    RevokeDeviceView,
)
from api.resources import (
    AccountListView,
    BootstrapView,
    CategoryListView,
    HouseholdView,
    OwnerListView,
    SummaryView,
    TransactionListView,
)
from api.sync_views import SyncPullView, SyncPushView
from api.views import HealthView

urlpatterns = [
    path('health/', HealthView.as_view(), name='health'),
    path('auth/login/', LoginView.as_view(), name='auth-login'),
    path('auth/refresh/', RefreshView.as_view(), name='auth-refresh'),
    path('auth/logout/', LogoutView.as_view(), name='auth-logout'),
    path('devices/', DeviceListView.as_view(), name='device-list'),
    path('devices/current/', CurrentDeviceView.as_view(), name='device-current'),
    path('household/', HouseholdView.as_view(), name='household'),
    path('owners/', OwnerListView.as_view(), name='owner-list'),
    path('accounts/', AccountListView.as_view(), name='account-list'),
    path('categories/', CategoryListView.as_view(), name='category-list'),
    path('transactions/', TransactionListView.as_view(), name='transaction-list'),
    path('summary/', SummaryView.as_view(), name='summary'),
    path('bootstrap/', BootstrapView.as_view(), name='bootstrap'),
    path('sync/push/', SyncPushView.as_view(), name='sync-push'),
    path('sync/changes/', SyncPullView.as_view(), name='sync-changes'),
    path(
        'devices/<uuid:device_uuid>/revoke/',
        RevokeDeviceView.as_view(),
        name='device-revoke',
    ),
]
