"""
URL configuration for core project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/5.2/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include, path
from django.views.generic import TemplateView
from core.views import DashboardView, HomeView, OfflineView

urlpatterns = [
    path('', HomeView.as_view(), name='home'),
    path('offline/', OfflineView.as_view(), name='offline'),
    path('', include('users.urls')),
    path('', include('profiles.urls')),
    path('admin/', admin.site.urls),
    path('dashboard/', DashboardView.as_view(), name='dashboard'),
    path('accounts/', include('accounts.urls')),
    path('categories/', include('categories.urls')),
    path('transacoes/', include('transactions.urls')),
    path(
        'serviceworker.js',
        TemplateView.as_view(
            template_name='serviceworker.js',
            content_type='application/javascript',
        ),
        name='serviceworker',
    ),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
