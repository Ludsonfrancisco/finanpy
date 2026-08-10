import logging

from django.core.exceptions import PermissionDenied

from .models import Household
from .services import get_household_for_user

logger = logging.getLogger(__name__)


class HouseholdContextMixin:
    household = None

    def dispatch(self, request, *args, **kwargs):
        try:
            self.household = get_household_for_user(request.user)
        except Household.DoesNotExist as exc:
            logger.warning('Household access denied: no active household membership.')
            raise PermissionDenied('Acesso ao Lar indisponível.') from exc
        return super().dispatch(request, *args, **kwargs)
