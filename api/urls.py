from django.urls import path

from api.auth_views import (
    CurrentDeviceView,
    DeviceListView,
    LoginView,
    LogoutView,
    RefreshView,
    RevokeDeviceView,
)
from api.bills_views import (
    BillDetailResourceView,
    BillsMetricsResourceView,
    BillsResourceView,
    PayBillResourceView,
    ReopenBillResourceView,
)
from api.cards_views import (
    CardDetailResourceView,
    CardExpenseDetailResourceView,
    CardExpenseResourceView,
    CardsResourceView,
    PayCardInvoiceResourceView,
    ReopenCardInvoiceResourceView,
)
from api.import_views import (
    BindImportAccountView,
    CancelImportView,
    ConfirmImportView,
    ImportBatchDetailView,
    OfxPreviewView,
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
    path('bills/', BillsResourceView.as_view(), name='bills-list'),
    path('bills/<int:pk>/', BillDetailResourceView.as_view(), name='bills-detail'),
    path('bills/instances/<int:pk>/pay/', PayBillResourceView.as_view(), name='bills-pay'),
    path('bills/instances/<int:pk>/reopen/', ReopenBillResourceView.as_view(), name='bills-reopen'),
    path('bills/metrics/', BillsMetricsResourceView.as_view(), name='bills-metrics'),
    path('cards/', CardsResourceView.as_view(), name='cards-list'),
    path('cards/<int:pk>/', CardDetailResourceView.as_view(), name='cards-detail'),
    path('cards/expenses/', CardExpenseResourceView.as_view(), name='cards-expenses'),
    path('cards/expenses/<int:pk>/', CardExpenseDetailResourceView.as_view(), name='cards-expense-detail'),
    path('cards/invoices/<int:pk>/pay/', PayCardInvoiceResourceView.as_view(), name='cards-invoice-pay'),
    path('cards/invoices/<int:pk>/reopen/', ReopenCardInvoiceResourceView.as_view(), name='cards-invoice-reopen'),
    path('imports/ofx/preview/', OfxPreviewView.as_view(), name='ofx-preview'),
    path(
        'imports/<uuid:batch_uuid>/',
        ImportBatchDetailView.as_view(),
        name='import-detail',
    ),
    path(
        'imports/<uuid:batch_uuid>/bind-account/',
        BindImportAccountView.as_view(),
        name='import-bind-account',
    ),
    path(
        'imports/<uuid:batch_uuid>/confirm/',
        ConfirmImportView.as_view(),
        name='import-confirm',
    ),
    path(
        'imports/<uuid:batch_uuid>/cancel/',
        CancelImportView.as_view(),
        name='import-cancel',
    ),
    path(
        'devices/<uuid:device_uuid>/revoke/',
        RevokeDeviceView.as_view(),
        name='device-revoke',
    ),
]
