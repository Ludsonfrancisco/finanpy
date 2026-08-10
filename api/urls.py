from django.urls import path

from api.auth_views import (
    CurrentDeviceView,
    DeviceListView,
    LoginView,
    LogoutView,
    RefreshView,
    RevokeDeviceView,
)
from api.views import HealthView

urlpatterns = [
    path('health/', HealthView.as_view(), name='health'),
    path('auth/login/', LoginView.as_view(), name='auth-login'),
    path('auth/refresh/', RefreshView.as_view(), name='auth-refresh'),
    path('auth/logout/', LogoutView.as_view(), name='auth-logout'),
    path('devices/', DeviceListView.as_view(), name='device-list'),
    path('devices/current/', CurrentDeviceView.as_view(), name='device-current'),
    path(
        'devices/<uuid:device_uuid>/revoke/',
        RevokeDeviceView.as_view(),
        name='device-revoke',
    ),
]
