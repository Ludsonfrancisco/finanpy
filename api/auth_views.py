from rest_framework import status
from rest_framework.exceptions import NotFound
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from .authentication import InvalidRefreshToken
from .models import DeviceSession
from .permissions import IsDeviceSession
from .serializers import (
    CurrentDeviceSerializer,
    DeviceListSerializer,
    IssuedTokensSerializer,
    LoginSerializer,
    RefreshSerializer,
)
from .tokens import (
    InvalidRefreshTokenError,
    RefreshReuseError,
    issue_session,
    revoke_session,
    rotate_refresh_token,
)


class LoginView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'login'

    def post(self, request):
        serializer = LoginSerializer(data=request.data, context={'request': request})
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        issued = issue_session(
            user=data['user'],
            household=data['household'],
            default_owner=data['default_owner'],
            platform=data['platform'],
            name=data['name'],
        )
        return Response(IssuedTokensSerializer(issued).data)


class RefreshView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'refresh'

    def post(self, request):
        serializer = RefreshSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            issued = rotate_refresh_token(serializer.validated_data['refresh_token'])
        except (InvalidRefreshTokenError, RefreshReuseError) as exc:
            raise InvalidRefreshToken() from exc
        return Response(IssuedTokensSerializer(issued).data)


class LogoutView(APIView):
    permission_classes = [IsDeviceSession]

    def post(self, request):
        revoke_session(request.auth)
        return Response(status=status.HTTP_204_NO_CONTENT)


class DeviceListView(APIView):
    permission_classes = [IsDeviceSession]

    def get(self, request):
        sessions = DeviceSession.objects.select_related('default_owner').filter(
            user=request.user,
            household_id=request.auth.household_id,
        ).order_by('-last_seen_at', 'uuid')
        return Response(DeviceListSerializer(sessions, many=True).data)


class CurrentDeviceView(APIView):
    permission_classes = [IsDeviceSession]

    def patch(self, request):
        serializer = CurrentDeviceSerializer(
            request.auth,
            data=request.data,
            partial=True,
            context={'session': request.auth},
        )
        serializer.is_valid(raise_exception=True)
        session = serializer.save()
        return Response(DeviceListSerializer(session).data)


class RevokeDeviceView(APIView):
    permission_classes = [IsDeviceSession]

    def post(self, request, device_uuid):
        target = DeviceSession.objects.filter(
            uuid=device_uuid,
            user=request.user,
            household_id=request.auth.household_id,
        ).first()
        if target is None:
            raise NotFound()
        revoke_session(target)
        return Response(status=status.HTTP_204_NO_CONTENT)
