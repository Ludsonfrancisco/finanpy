from rest_framework.pagination import CursorPagination


class ApiCursorPagination(CursorPagination):
    page_size = 50
    max_page_size = 100
    page_size_query_param = 'limit'
