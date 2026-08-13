from django.contrib import admin

from .models import ImportAccountLink, ImportBatch, ImportRecord, SourceReference

admin.site.register(ImportAccountLink)


@admin.register(ImportBatch)
class ImportBatchAdmin(admin.ModelAdmin):
    list_display = (
        'uuid',
        'household',
        'provider',
        'product_type',
        'status',
        'is_repeated_file',
    )
    list_filter = ('provider', 'product_type', 'status', 'is_repeated_file')


@admin.register(ImportRecord)
class ImportRecordAdmin(admin.ModelAdmin):
    list_display = ('batch', 'line_number', 'outcome', 'external_id', 'posted_on')


admin.site.register(SourceReference)
