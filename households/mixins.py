from .services import ensure_household_for_user


class HouseholdContextMixin:
    household = None

    def dispatch(self, request, *args, **kwargs):
        self.household = ensure_household_for_user(request.user)
        return super().dispatch(request, *args, **kwargs)
