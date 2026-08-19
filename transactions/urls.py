from django.urls import path

from . import views

app_name = 'transactions'

urlpatterns = [
    path('', views.TransactionListView.as_view(), name='list'),
    path('quick-create/', views.TransactionQuickCreateView.as_view(), name='quick_create'),
    path('<int:pk>/quick-delete/', views.TransactionQuickDeleteView.as_view(), name='quick_delete'),
    path('importar/', views.TransactionImportOFXView.as_view(), name='import_ofx'),
    path('exportar-ofx/', views.TransactionExportOFXView.as_view(), name='export_ofx'),
    path('nova/', views.TransactionCreateView.as_view(), name='create'),
    path('<int:pk>/editar/', views.TransactionUpdateView.as_view(), name='update'),
    path('<int:pk>/excluir/', views.TransactionDeleteView.as_view(), name='delete'),
]
