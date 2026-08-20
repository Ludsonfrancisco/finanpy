from django.urls import path

from . import views

app_name = 'cards'

urlpatterns = [
    path('', views.CreditCardListView.as_view(), name='list'),
    path('importar/', views.CreditCardImportOFXView.as_view(), name='import_ofx'),
    path('create/', views.CreditCardCreateView.as_view(), name='create'),
    path('<int:pk>/', views.CreditCardDetailView.as_view(), name='detail'),
    path('<int:pk>/edit/', views.CreditCardUpdateView.as_view(), name='edit'),
    path('<int:pk>/delete/', views.CreditCardDeleteView.as_view(), name='delete'),
    path(
        'expenses/create/',
        views.CreditCardExpenseCreateView.as_view(),
        name='expense_create',
    ),
    path(
        'expenses/<int:pk>/delete/',
        views.CreditCardExpenseDeleteView.as_view(),
        name='expense_delete',
    ),
    path('invoices/<int:pk>/pay/', views.PayInvoiceView.as_view(), name='pay_invoice'),
    path(
        'invoices/<int:pk>/reopen/',
        views.ReopenInvoiceView.as_view(),
        name='reopen_invoice',
    ),
]
