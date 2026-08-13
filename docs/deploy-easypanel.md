# Runbook de deploy no EasyPanel

Este documento descreve o procedimento operacional para publicar o Lar Finance com
SQLite persistente. Runtime, Supervisor, proxy, smoke público e backup R2 foram
validados no EasyPanel `v2.33.1` em 2026-08-13. O aceite integral do runbook ainda
tem gates abertos. A evidência sanitizada está em
[automatic-r2-backup-production.md](audits/automatic-r2-backup-production.md).

## Estado e bloqueios de produção

Estado dos gates operacionais, sem registrar segredos:

- [x] Credencial histórica rotacionada no EasyPanel em 2026-08-12 e sessões Django
  anteriores revogadas. Nenhum valor foi registrado no repositório.
- [x] Backup do SQLite real copiado para bucket R2 privado e restaurado em ambiente
  descartável em 2026-08-12, com SHA-256, migrations, auditoria e integridade
  aprovados. Consulte
  `docs/audits/2026-08-12-production-backup-restore.md`.
- [x] Automação diária R2, idempotência, retenção `14/8/12`, scheduler e
  isolamento do processo web implementados e cobertos por testes locais.
- [x] Cadastrar as variáveis R2, ativar a imagem e provar execução, restart,
  objeto remoto e restauração descartável da nova automação no EasyPanel real.
- [x] Implantar o `main` em `0d85999f4e66290fa06484d802d08fbb310ad164`,
  validar schema final, persistência após restart, proxy e smoke público. A ordem
  do `migrate` durante o deploy não ficou evidenciada e permanece aberta abaixo.
- [ ] `[INVESTIGAR]` Materializar rollback por digest/tag imutável da imagem e
  confirmar rate limit persistente para `POST /login/`.

Interrompa o deploy se qualquer pré-requisito, backup, auditoria ou ensaio falhar.

## Topologia obrigatória

O SQLite exige que esta aplicação opere com uma única instância gravadora:

- exatamente **1 réplica** do serviço web no EasyPanel;
- Gunicorn com exatamente **1 worker**;
- Supervisor inicia Gunicorn e um único `run_backup_scheduler`; não crie um
  segundo cron/job para o mesmo comando;
- volume persistente montado em `/app/data`;
- `SQLITE_PATH=/app/data/db.sqlite3`;
- se houver uploads, volume persistente adicional montado em `/app/media`.

O `docker-compose.yml` demonstra esses mounts localmente, mas os volumes do Compose
não são criados automaticamente quando o EasyPanel publica diretamente pelo
`Dockerfile`. Configure-os manualmente na aplicação.

Na versão instalada `v2.33.1`, os mounts e jobs ficam em `Storage`, os scripts em
`Scripts`, o console no botão `Console` do serviço e os provedores externos em
`Settings > Storage Providers`. Uma réplica sem sobreposição foi comprovada. Ainda
é necessário registrar o espaço livre antes da mudança, a ordem de migrations e o
rollback por digest/tag imutável.

Não habilite autoscaling, rolling deploy com duas réplicas simultâneas ou mais de um
worker enquanto o banco for SQLite. Se esse requisito deixar de ser aceitável, a
mudança correta é planejar a migração para um banco servidor, não compartilhar o
arquivo SQLite entre gravadores concorrentes.

## Domínio, TLS, proxy e variáveis

Configure o domínio no proxy do EasyPanel e emita um certificado TLS válido antes
de liberar tráfego. A porta interna da aplicação é `8000`; não exponha essa porta
diretamente à internet.

Cadastre as variáveis abaixo no gerenciador de ambiente/segredos do EasyPanel. Use
valores reais somente na interface segura; não os copie para este arquivo ou para o
repositório.

```text
SECRET_KEY=<valor de produção longo, aleatório e exclusivo>
DEBUG=False
ALLOWED_HOSTS=<domínio público, sem esquema e sem espaços>
CSRF_TRUSTED_ORIGINS=https://<domínio público>
SQLITE_PATH=/app/data/db.sqlite3
SECURE_SSL_REDIRECT=True
SESSION_COOKIE_SECURE=True
CSRF_COOKIE_SECURE=True
TRUST_PROXY_HEADERS=True
SECURE_HSTS_SECONDS=<valor aprovado após validar TLS>
SECURE_HSTS_INCLUDE_SUBDOMAINS=<True somente se todos os subdomínios usarem HTTPS>
SECURE_HSTS_PRELOAD=<True somente após decisão explícita de preload>
```

Para o backup automático, cadastre também as sete variáveis abaixo. Preencha os
dois valores secretos somente no secret store; nunca os copie para terminal, Git,
logs, tickets ou relatórios.

```text
R2_BACKUP_ENDPOINT_URL=https://<account-id>.r2.cloudflarestorage.com
R2_BACKUP_BUCKET=lar-finance-backups
R2_BACKUP_PREFIX=production
R2_BACKUP_TIME=03:00
R2_BACKUP_TIME_ZONE=America/Sao_Paulo
```

Cadastre `R2_BACKUP_ACCESS_KEY_ID` e `R2_BACKUP_SECRET_ACCESS_KEY` como campos
secretos separados, sem expor os valores na visualização ou nos logs do deploy.

Use token Cloudflare R2 com permissão **Object Read & Write** limitada apenas ao
bucket privado `lar-finance-backups`. Ela é necessária para listar, ler, criar e
excluir objetos gerenciados. Não conceda acesso a outros buckets nem acesso
administrativo à conta.

`ALLOWED_HOSTS` e `CSRF_TRUSTED_ORIGINS` aceitam múltiplos valores separados por
vírgula; na implementação atual, não coloque espaços depois das vírgulas. Nunca
reutilize a chave de CI em produção.

`TRUST_PROXY_HEADERS=True` pressupõe que o tráfego chegue somente pelo proxy
confiável do EasyPanel e que ele controle `X-Forwarded-Proto`. Evite aceitar esse
header diretamente de clientes externos. Um erro nessa camada pode causar loop de
redirect ou fazer o Django interpretar HTTP como HTTPS incorretamente.

Depois que o TLS estiver estável, defina HSTS de forma progressiva. Só habilite
`SECURE_HSTS_INCLUDE_SUBDOMAINS` ou `SECURE_HSTS_PRELOAD` após verificar todos os
subdomínios; essas opções têm impacto que não é revertido imediatamente nos
navegadores.

## Rate limit do login

Crie no proxy uma regra para **`POST /login/`**. Ponto inicial recomendado:

- até 5 tentativas por minuto por IP, com burst curto e resposta HTTP `429` ao
  exceder o limite;
- não limitar `GET /login/` com a mesma regra;
- revisar o limite com métricas reais para não bloquear usuários legítimos atrás
  de NAT;
- registrar método, rota, status, horário, IP de origem normalizado e request ID;
- nunca registrar corpo da requisição, senha, cookies, tokens ou cabeçalhos de
  autenticação.

O proxy deve obter o IP real apenas de uma cadeia de proxies confiável. Teste a
regra com credenciais descartáveis e confirme que tentativas bloqueadas não chegam
ao Django.

`[INVESTIGAR]` Confirmar se a versão instalada do EasyPanel oferece rate limit por
método e caminho. Se a função estiver no proxy subjacente, documentar a configuração
suportada pelo EasyPanel em vez de editar manualmente arquivos que a plataforma
possa sobrescrever. Se não houver suporte, manter o deploy bloqueado até existir uma
proteção equivalente e persistente.

## Preflight

Execute em uma janela de manutenção, antes de alterar o banco:

1. Registre a versão atual e a nova versão imutável da imagem.
2. Confirme uma réplica, um worker, o mount `/app/data` e o caminho absoluto do
   banco. Não imprima variáveis secretas.
3. Confirme espaço livre suficiente para o banco ativo, o backup e a reconstrução
   temporária feita por migrations. Reserve, no mínimo, três vezes o tamanho atual
   do arquivo, além da margem operacional do volume.
4. Confirme que a aplicação atual consegue ler o volume e que o arquivo apontado
   por `SQLITE_PATH` existe.
5. Na imagem candidata, com as variáveis de produção, execute:

   ```sh
   python manage.py check --deploy --fail-level WARNING
   python manage.py showmigrations --plan
   python manage.py audit_household_integrity
   ```

O comando de auditoria é somente leitura e termina com código diferente de zero se
encontrar inconsistências. O resultado esperado é `integrity_status=ok`, com todas
as contagens iguais a zero. Não prossiga se o schema atual não for compatível com o
comando, se houver migration inesperada ou se qualquer contagem for positiva;
investigue e ensaie a correção em uma cópia.

## Backup verificado e cópia externa

Ative manutenção ou bloqueie escritas antes do backup. No terminal do container ou
em um job one-off que use o mesmo volume, gere um nome novo a cada execução:

```sh
BACKUP_PATH="/app/data/backups/pre-deploy-$(date -u +%Y%m%dT%H%M%SZ).sqlite3"
python manage.py backup_sqlite --output "$BACKUP_PATH"
sha256sum "$BACKUP_PATH"
```

Só aceite o backup quando o comando retornar `Backup verified`. Ele usa a API de
backup do SQLite, não sobrescreve arquivos e executa `PRAGMA integrity_check` antes
de concluir. O hash serve para conferir a transferência; ele não substitui a
verificação de integridade.

O destino padrão do comando seria `/app/backups`, que pode estar no filesystem
efêmero do container. Por isso, sempre informe `--output` em um destino persistente.
O diretório `/app/data/backups` é apenas uma área de passagem no mesmo volume do
banco e **não é um backup externo**.

Transfira a cópia de forma criptografada para armazenamento fora do servidor do
EasyPanel. Restrinja acesso, defina retenção e compare o SHA-256 no destino. Não
apague o backup local até concluir o ensaio e a validação off-host.

O destino off-host escolhido é um bucket privado Cloudflare R2. A prova real de
2026-08-12 confirmou upload/download por TLS, hash idêntico e restauração. O R2
criptografa objetos e metadados em repouso automaticamente. Mantenha o token do
EasyPanel limitado ao bucket `lar-finance-backups` e nunca registre suas chaves.

Na instalação `v2.33.1`, o job nativo de `Volume Backups` não lê o volume Docker
legado `financeiro_sqlite_data`: ele procura um diretório do layout novo sob
`/etc/easypanel/projects/.../volumes/sqlite_data`. Não recrie esse job até migrar
o volume. A imagem candidata contorna essa limitação com um scheduler no próprio
container: ele usa a API de backup do SQLite antes do upload, confirma o objeto com
`HeadObject` e só então aplica retenção. Operação manual:

```sh
python manage.py backup_to_r2
```

Não execute esse comando antes de confirmar o preflight e evitar uma execução
concorrente. Configuração, resultados, download descartável e rollback estão no
[runbook do backup automático](sprints/automatic-r2-backup.md). O estado atual é:
**automação ativa em produção, idempotência após restart e restauração descartável
comprovadas em 2026-08-13**. Consulte a
[auditoria](audits/automatic-r2-backup-production.md).

## Ensaio obrigatório em restauração descartável

Antes do banco de produção, faça o ciclo completo em uma restauração isolada do
backup recém-gerado:

1. Copie o backup off-host para um volume temporário e criptografado, sem acesso
   público e com permissões equivalentes às de produção.
2. Restaure-o com outro caminho absoluto, por exemplo
   `/app/rehearsal/db.sqlite3`. Nunca aponte o ensaio para `/app/data/db.sqlite3`.
3. Use a mesma imagem candidata e as mesmas opções Django, mas um domínio isolado e
   sem jobs ou integrações capazes de enviar dados.
4. Execute:

   ```sh
   python manage.py check --deploy --fail-level WARNING
   python manage.py migrate --plan
   python manage.py migrate
   python manage.py audit_household_integrity
   ```

5. Confirme `integrity_status=ok`, as migrations esperadas e os smoke checks
   aplicáveis ao ambiente isolado.
6. Destrua a restauração segundo a política de dados após registrar somente
   resultados técnicos; não copie registros financeiros ou dados pessoais para
   logs ou documentação.

Um ensaio antigo ou feito com outro backup/hash não autoriza o deploy atual.

## Sequência de deploy

1. Ative modo de manutenção e confirme que não há requisições de escrita.
2. Repita o preflight no alvo real.
3. Gere o backup verificado, copie-o para fora do host e valide o hash no destino.
4. Selecione a imagem candidata pelo identificador imutável ensaiado.
5. Execute a migration como etapa única e controlada, conectada ao volume
   `/app/data`:

   ```sh
   python manage.py migrate
   python manage.py audit_household_integrity
   python manage.py collectstatic --noinput
   ```

6. Se qualquer comando falhar, mantenha manutenção ativa e inicie o rollback. Não
   inicie uma segunda migration concorrente.
7. Inicie exatamente uma réplica sem sobrescrever o command da imagem, para que
   seu `CMD` inicie o Supervisor. Se o EasyPanel exigir command explícito, use:

   ```sh
   supervisord -c /app/deploy/supervisord.conf
   ```

   Não inicie Gunicorn diretamente: isso ignora o scheduler. A configuração
   versionada mantém o web com um worker e um único `backup-scheduler`.
8. Confirme novamente o mount, `SQLITE_PATH`, uma réplica, um worker e os dois
   processos `web` e `backup-scheduler`; execute a auditoria no container em
   execução e faça os smoke checks.
9. Libere o tráfego somente após todas as verificações passarem.

Prefira um job one-off ou deploy hook para `migrate`; não o acople a todo restart do
serviço. `[INVESTIGAR]` Confirmar o mecanismo suportado pela versão instalada do
EasyPanel para executar essa etapa sem iniciar duas réplicas e sem liberar tráfego
antes da auditoria.

## Smoke checks

Registre apenas status e identificadores técnicos, nunca conteúdo financeiro:

- HTTP redireciona para HTTPS sem loop;
- `GET /login/` responde sem erro `5xx`;
- login válido de uma conta privada de verificação chega ao dashboard;
- login inválido não revela se o usuário existe;
- dashboard, contas, categorias e movimentações carregam para o Lar esperado;
- logout encerra a sessão;
- `python manage.py audit_household_integrity` termina com
  `integrity_status=ok`;
- a regra de rate limit devolve `429` após o limite em teste controlado;
- logs não contêm senha, corpo de login, cookies ou segredos;
- após um restart controlado, o mesmo arquivo em `/app/data/db.sqlite3` continua
  disponível e a auditoria permanece íntegra;
- a plataforma continua mostrando uma réplica e o processo Gunicorn, um worker.

Qualquer falha de persistência, isolamento por Lar, autenticação, auditoria ou TLS é
critério de rollback.

Depois da ativação específica do backup, os smoke checks também devem confirmar
os dois processos do Supervisor, um resultado `created` ou `already_exists`, a
chave única do dia e um restart idempotente sem indisponibilizar o web.

## Rollback

O caminho prioritário é **parar escritas, voltar para a imagem anterior compatível
e restaurar o backup verificado**. Não sobrescreva o banco enquanto algum processo
Django ou Gunicorn estiver aberto.

1. Ative ou mantenha manutenção e pare a réplica candidata.
2. Preserve o banco que falhou com nome separado para diagnóstico, sem substituir
   o backup pré-deploy.
3. Confirme o caminho absoluto e o hash do backup escolhido. Verifique a cópia
   novamente antes de restaurar.
4. Restaure o arquivo em `/app/data/db.sqlite3` com permissões do usuário do
   container.
5. Selecione a imagem anterior pelo identificador imutável e inicie uma única
   réplica com um worker.
6. Execute checks e auditoria compatíveis com o schema restaurado, depois repita os
   smoke checks antes de liberar tráfego.
7. Registre motivo, horários, imagens, hash do backup e resultados, sem dados
   pessoais ou segredos.

Se o rollback for motivado apenas pela automação de backup e o schema continuar
compatível, volte para a imagem anterior imutável que inicia somente o Gunicorn.
Não apague nenhum objeto R2 durante o rollback. As variáveis podem permanecer no
secret store sem consumidor ou ser removidas depois de preservar evidência; nunca
revogue uma credencial antes de confirmar que não há outro consumidor autorizado.

Downgrade com `python manage.py migrate <app> <migration>` só é aceitável se o grafo
exato, a imagem anterior e o mesmo estado de dados tiverem passado por ida e volta
em restauração descartável. Na ausência dessa prova específica, restaure o backup;
não improvise um downgrade em produção e nunca altere manualmente a tabela
`django_migrations`.

`[INVESTIGAR]` A versão instalada permitiu uma réplica sem sobreposição, start/stop
e restore isolado, mas não expôs no fluxo usado um digest de imagem selecionável.
Materializar e ensaiar rollback por digest/tag imutável antes da próxima mudança de
schema ou infraestrutura.

## Registro da validação real

Ao concluir uma execução real, registre em local operacional seguro:

- data, operador e ambiente;
- identificadores imutáveis das imagens anterior e nova;
- confirmação da rotação/revogação da credencial histórica, sem valores;
- mount paths, número de réplicas e workers;
- hash e localização lógica do backup externo, sem credenciais de acesso;
- resultados do preflight, ensaio, migrations, auditoria, persistência após restart,
  rate limit, smoke checks e eventual rollback;
- status do backup automático, chave lógica, tamanho, SHA-256, idempotência,
  restart e restauração da cópia descartável, sem credenciais.

O registro real de 2026-08-13 está em
[automatic-r2-backup-production.md](audits/automatic-r2-backup-production.md). Ele
comprova deploy, restart, topologia, proxy, smoke público, objeto idempotente e
restauração isolada. Não comprova ainda rollback por digest imutável, rate limit de
login ou alertas externos.
