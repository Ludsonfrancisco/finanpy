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
    ImportBusyError,
    ImportConflictError,
    ImportStateError,
    bind_preview_account,
    cancel_preview,
    confirm_preview,
    create_preview,
    get_batch_for_household,
    read_preview_page,
)

from .import_serializers import (
    BindImportAccountSerializer,
    EmptySerializer,
    ImportPageSerializer,
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


class InvalidImportPage(InvalidOfx):
    default_detail = 'Página de prévia inválida.'
    default_code = 'invalid_import_page'


class ImportTemporarilyUnavailable(APIException):
    status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    default_detail = 'A importação está temporariamente ocupada. Tente novamente.'
    default_code = 'import_temporarily_unavailable'


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
        except ImportBusyError as error:
            self.handle_domain_error(error)
        except ImportAccessError as exc:
            raise NotFound() from exc

    def batch_payload(self, batch, page_query=None):
        after, limit = self.page_parameters(page_query)
        return serialize_import_batch(
            batch,
            read_preview_page(batch=batch, after=after, limit=limit),
        )

    @staticmethod
    def page_parameters(page_query):
        if page_query is None:
            return None, None
        serializer = ImportPageSerializer(data=page_query)
        if not serializer.is_valid():
            raise InvalidImportPage()
        return (
            serializer.validated_data.get('after'),
            serializer.validated_data.get('limit'),
        )

    def handle_domain_error(self, error):
        if isinstance(error, ImportBusyError):
            raise ImportTemporarilyUnavailable() from error
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
        return Response(self.batch_payload(batch), status=status.HTTP_201_CREATED)


class ImportBatchDetailView(ImportView):
    def get(self, request, batch_uuid):
        return Response(
            self.batch_payload(self.get_batch(batch_uuid), request.query_params)
        )


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
        return Response(self.batch_payload(batch))


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
        return Response(self.batch_payload(batch))


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
        return Response(self.batch_payload(batch))
