from django.conf import settings
from django.db import models


class AIAnalysis(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='ai_analyses',
    )
    analysis_text = models.TextField()
    insights = models.JSONField(default=list)
    period_start = models.DateField()
    period_end = models.DateField()
    model_used = models.CharField(max_length=100, default='gpt-5-mini')
    tokens_used = models.IntegerField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'AIAnalysis({self.user_id}, {self.period_end})'
