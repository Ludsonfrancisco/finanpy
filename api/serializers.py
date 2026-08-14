from django.contrib.auth import authenticate
from rest_framework import serializers

from households.models import FinancialOwner, HouseholdMembership

from .authentication import InvalidCredentials
from .models import DeviceSession


class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(trim_whitespace=False, write_only=True)
    platform = serializers.ChoiceField(choices=DeviceSession.PLATFORM_CHOICES)
    name = serializers.CharField(max_length=80)
    default_owner_uuid = serializers.UUIDField(required=False)

    def validate(self, attrs):
        user = authenticate(
            request=self.context.get('request'),
            email=attrs['email'],
            password=attrs['password'],
        )
        if user is None:
            raise InvalidCredentials()

        membership = (
            HouseholdMembership.objects.select_related('household')
            .filter(user=user, is_active=True, household__is_active=True)
            .first()
        )
        if membership is None:
            raise InvalidCredentials()

        owner_uuid = attrs.get('default_owner_uuid')
        owner_query = FinancialOwner.objects.filter(
            household=membership.household,
            is_active=True,
            type__in=(FinancialOwner.SELF, FinancialOwner.SPOUSE),
        )
        if owner_uuid is None:
            owner = owner_query.filter(type=FinancialOwner.SELF).first()
            if owner is None:
                raise InvalidCredentials()
        else:
            owner = owner_query.filter(uuid=owner_uuid).first()
            if owner is None:
                raise serializers.ValidationError(
                    {
                        'default_owner_uuid': [
                            'Escolha o responsável próprio ou cônjuge deste Lar.'
                        ]
                    }
                )

        attrs['user'] = user
        attrs['household'] = membership.household
        attrs['default_owner'] = owner
        return attrs


class RefreshSerializer(serializers.Serializer):
    refresh_token = serializers.CharField(trim_whitespace=False)


class DeviceSerializer(serializers.ModelSerializer):
    default_owner_uuid = serializers.UUIDField(source='default_owner.uuid', read_only=True)

    class Meta:
        model = DeviceSession
        fields = ('uuid', 'name', 'platform', 'default_owner_uuid')


class DeviceListSerializer(DeviceSerializer):
    class Meta(DeviceSerializer.Meta):
        fields = DeviceSerializer.Meta.fields + ('last_seen_at', 'created_at', 'revoked_at')


class IssuedTokensSerializer(serializers.Serializer):
    access_token = serializers.CharField(read_only=True)
    access_expires_at = serializers.DateTimeField(source='session.access_expires_at')
    refresh_token = serializers.CharField(read_only=True)
    refresh_expires_at = serializers.DateTimeField(source='session.refresh_expires_at')
    device = DeviceSerializer(source='session')


class CurrentDeviceSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=80, required=False)
    default_owner_uuid = serializers.UUIDField(required=False)

    def validate_default_owner_uuid(self, owner_uuid):
        session = self.context['session']
        owner = FinancialOwner.objects.filter(
            uuid=owner_uuid,
            household_id=session.household_id,
            is_active=True,
            type__in=(FinancialOwner.SELF, FinancialOwner.SPOUSE),
        ).first()
        if owner is None:
            raise serializers.ValidationError(
                'Escolha o responsável próprio ou cônjuge deste Lar.'
            )
        return owner

    def update(self, instance, validated_data):
        update_fields = []
        if 'name' in validated_data:
            instance.name = validated_data['name']
            update_fields.append('name')
        if 'default_owner_uuid' in validated_data:
            instance.default_owner = validated_data['default_owner_uuid']
            update_fields.append('default_owner')
        if update_fields:
            update_fields.append('updated_at')
            instance.full_clean()
            instance.save(update_fields=update_fields)
        return instance
