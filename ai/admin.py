from django.contrib import admin

from .models import AIAnalysis


@admin.register(AIAnalysis)
class AIAnalysisAdmin(admin.ModelAdmin):
    list_display = ('user', 'period_start', 'period_end', 'model_used', 'tokens_used', 'created_at')
    list_filter = ('user', 'model_used')
    search_fields = ('user__email', 'analysis_text')
