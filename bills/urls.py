from django.urls import path

from . import views

app_name = 'bills'

urlpatterns = [
    path('', views.BillListView.as_view(), name='list'),
    path('nova/', views.BillCreateView.as_view(), name='create'),
    path('<int:pk>/editar/', views.BillUpdateView.as_view(), name='update'),
    path('<int:pk>/excluir/', views.BillDeleteView.as_view(), name='delete'),
    path('instancia/<int:pk>/pagar/', views.PayBillView.as_view(), name='pay'),
    path('instancia/<int:pk>/reabrir/', views.ReopenBillView.as_view(), name='reopen'),
]
