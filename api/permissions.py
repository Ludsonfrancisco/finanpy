from rest_framework.permissions import BasePermission

from .models import DeviceSession


class IsDeviceSession(BasePermission):
    message = 'Uma sessão ativa de aparelho é obrigatória.'

    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and isinstance(request.auth, DeviceSession)
            and request.auth.user_id == request.user.pk
        )
