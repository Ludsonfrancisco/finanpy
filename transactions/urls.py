from django.urls import path

from . import views

app_name = 'transactions'

urlpatterns = [
    path('', views.TransactionListView.as_view(), name='list'),
    path('exportar-ofx/', views.TransactionExportOFXView.as_view(), name='export_ofx'),
    path('nova/', views.TransactionCreateView.as_view(), name='create'),
    path('<int:pk>/editar/', views.TransactionUpdateView.as_view(), name='update'),
    path('<int:pk>/excluir/', views.TransactionDeleteView.as_view(), name='delete'),
]
