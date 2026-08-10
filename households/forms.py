from django.core.exceptions import NON_FIELD_ERRORS, ValidationError


class HouseholdModelFormMixin:
    def _update_errors(self, errors):
        error_dict = getattr(errors, 'error_dict', None)
        if error_dict:
            for field in tuple(error_dict):
                if field != NON_FIELD_ERRORS and field not in self.fields:
                    error_dict.setdefault(NON_FIELD_ERRORS, []).extend(
                        error_dict.pop(field)
                    )
        return super()._update_errors(errors)


def validate_instance_or_add_form_errors(form):
    try:
        form.instance.full_clean()
    except ValidationError as exc:
        if hasattr(exc, 'error_dict'):
            for field, errors in exc.error_dict.items():
                target = field if field in form.fields else None
                for error in errors:
                    form.add_error(target, error)
        else:
            for error in exc.error_list:
                form.add_error(None, error)
        return False
    return True
