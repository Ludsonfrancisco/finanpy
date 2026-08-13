from rest_framework import status
from rest_framework.exceptions import APIException, NotFound
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import Account
from imports.ofx import (
    MAX_OFX_BYTES,
    OfxParseError,
    OversizedOfxError,
    UnsupportedOfxError,
)
from imports.services import (
    ExpiredPreviewError,
    ImportAccessError,
    ImportConflictError,
    ImportStateError,
    bind_preview_account,
    cancel_preview,
    confirm_preview,
    create_preview,
    get_batch_for_household,
)

from .import_serializers import (
    BindImportAccountSerializer,
    EmptySerializer,
    OfxPreviewSerializer,
    serialize_import_batch,
)
from .permissions import IsDeviceSession


class InvalidOfx(APIException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Não foi possível processar a importação.'
    default_code = 'invalid_ofx'


class UnsupportedOfx(InvalidOfx):
    default_code = 'unsupported_ofx'


class FileTooLarge(InvalidOfx):
    default_code = 'file_too_large'


class InvalidImportState(InvalidOfx):
    default_code = 'invalid_import_state'


class ExpiredImportPreview(InvalidOfx):
    default_code = 'expired_import_preview'


def _read_ofx_upload(uploaded_file):
    """Read an uploaded OFX without retaining bytes above the accepted limit."""
    size = getattr(uploaded_file, 'size', None)
    if isinstance(size, int) and size > MAX_OFX_BYTES:
        raise OversizedOfxError('OFX content exceeds the maximum accepted size.')

    content = bytearray()
    for chunk in uploaded_file.chunks():
        if len(content) + len(chunk) > MAX_OFX_BYTES:
            raise OversizedOfxError('OFX content exceeds the maximum accepted size.')
        content.extend(chunk)
    return bytes(content)


class ImportView(APIView):
    permission_classes = [IsDeviceSession]

    def get_batch(self, batch_uuid):
        try:
            return get_batch_for_household(
                household=self.request.auth.household,
                batch_uuid=batch_uuid,
            )
        except ImportAccessError as exc:
            raise NotFound() from exc

    def handle_domain_error(self, error):
        if isinstance(error, ExpiredPreviewError):
            raise ExpiredImportPreview() from error
        if isinstance(error, (ImportStateError, ImportConflictError)):
            raise InvalidImportState() from error
        raise error


class OfxPreviewView(ImportView):
    def post(self, request):
        serializer = OfxPreviewSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            batch = create_preview(
                household=request.auth.household,
                device_session=request.auth,
                content=_read_ofx_upload(serializer.validated_data['file']),
            )
        except OversizedOfxError as error:
            raise FileTooLarge() from error
        except UnsupportedOfxError as error:
            raise UnsupportedOfx() from error
        except OfxParseError as error:
            raise InvalidOfx() from error
        except (ImportStateError, ImportConflictError, ExpiredPreviewError) as error:
            self.handle_domain_error(error)
        return Response(serialize_import_batch(batch), status=status.HTTP_201_CREATED)


class ImportBatchDetailView(ImportView):
    def get(self, request, batch_uuid):
        return Response(serialize_import_batch(self.get_batch(batch_uuid)))


class BindImportAccountView(ImportView):
    def post(self, request, batch_uuid):
        serializer = BindImportAccountSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        account = Account.objects.filter(
            uuid=serializer.validated_data['account_uuid'],
            household=request.auth.household,
        ).first()
        if account is None:
            raise NotFound()
        try:
            batch = bind_preview_account(
                batch=self.get_batch(batch_uuid),
                account=account,
            )
        except (ImportStateError, ImportConflictError, ExpiredPreviewError) as error:
            self.handle_domain_error(error)
        except ImportAccessError as error:
            raise NotFound() from error
        return Response(serialize_import_batch(batch))


class ConfirmImportView(ImportView):
    def post(self, request, batch_uuid):
        serializer = EmptySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            batch = confirm_preview(
                batch=self.get_batch(batch_uuid),
                device_session=request.auth,
            )
        except (ImportStateError, ImportConflictError, ExpiredPreviewError) as error:
            self.handle_domain_error(error)
        except ImportAccessError as error:
            raise NotFound() from error
        return Response(serialize_import_batch(batch))


class CancelImportView(ImportView):
    def post(self, request, batch_uuid):
        serializer = EmptySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            batch = cancel_preview(batch=self.get_batch(batch_uuid))
        except (ImportStateError, ImportConflictError, ExpiredPreviewError) as error:
            self.handle_domain_error(error)
        except ImportAccessError as error:
            raise NotFound() from error
        return Response(serialize_import_batch(batch))
