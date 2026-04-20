from django.urls import path

from . import views

app_name = 'categories'

urlpatterns = [
    path('', views.CategoryListView.as_view(), name='list'),
    path('novo/', views.CategoryCreateView.as_view(), name='create'),
    path('<int:pk>/editar/', views.CategoryUpdateView.as_view(), name='update'),
    path('<int:pk>/excluir/', views.CategoryDeleteView.as_view(), name='delete'),
]
