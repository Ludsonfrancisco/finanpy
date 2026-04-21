from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model
from ai.services.analysis_service import AnalysisService

User = get_user_model()

class Command(BaseCommand):
    help = 'Gera análise de IA financeira para os usuários'

    def add_arguments(self, parser):
        parser.add_argument(
            '--user-id',
            type=int,
            help='ID do usuário específico para rodar a análise',
        )

    def handle(self, *args, **options):
        user_id = options.get('user_id')
        
        if user_id:
            users = User.objects.filter(id=user_id, is_active=True)
            if not users.exists():
                self.stdout.write(self.style.ERROR(f'Usuário com ID {user_id} não encontrado ou inativo.'))
                return
        else:
            users = User.objects.filter(is_active=True)

        total_users = users.count()
        success_count = 0
        error_count = 0

        self.stdout.write(f'Iniciando análise para {total_users} usuários...')

        for user in users:
            try:
                AnalysisService.run_for_user(user)
                success_count += 1
                self.stdout.write(self.style.SUCCESS(f'Análise concluída para: {user.email}'))
            except Exception as e:
                error_count += 1
                self.stdout.write(self.style.ERROR(f'Erro ao processar usuário {user.email}: {str(e)}'))

        self.stdout.write(self.style.SUCCESS(
            f'Processamento finalizado. Sucesso: {success_count}, Erros: {error_count}'
        ))
