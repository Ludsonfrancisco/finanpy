from django.contrib import admin

from .models import ImportAccountLink, ImportBatch, ImportRecord, SourceReference

admin.site.register(ImportAccountLink)
admin.site.register(ImportBatch)
admin.site.register(ImportRecord)
admin.site.register(SourceReference)
