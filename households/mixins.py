import logging

from django.core.exceptions import PermissionDenied

from .models import Household
from .services import get_household_for_user

logger = logging.getLogger(__name__)


class HouseholdContextMixin:
    household = None

    def dispatch(self, request, *args, **kwargs):
        if request.user.is_authenticated:
            try:
                self.household = get_household_for_user(request.user)
            except Household.DoesNotExist:
                from .models import HouseholdMembership
                if (
                    HouseholdMembership.objects.filter(user=request.user, is_active=False).exists()
                    or Household.objects.filter(memberships__user=request.user, is_active=False).exists()
                ):
                    logger.warning('Acesso negado: Associação ou Lar desativado para o usuário.')
                    raise PermissionDenied('Acesso ao Lar indisponível.')

                from .services import ensure_household_for_user
                try:
                    self.household = ensure_household_for_user(request.user)
                except Exception as exc:
                    logger.warning('Household auto-bootstrap failed: %s', exc)
                    raise PermissionDenied('Acesso ao Lar indisponível.') from exc
        return super().dispatch(request, *args, **kwargs)
