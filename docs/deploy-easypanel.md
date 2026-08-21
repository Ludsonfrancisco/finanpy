# Runbook de deploy no EasyPanel

Este documento descreve o procedimento operacional para publicar o Lar Finance com
SQLite persistente. Runtime, Supervisor, proxy, smoke público e backup R2 foram
validados no EasyPanel `v2.33.1` em 2026-08-13. O aceite integral do runbook ainda
tem gates abertos. A evidência sanitizada está em
[automatic-r2-backup-production.md](audits/automatic-r2-backup-production.md).
O ensaio do candidato R1.4 está em
[2026-08-21-fail-fast-deploy-rehearsal.md](audits/2026-08-21-fail-fast-deploy-rehearsal.md).

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
- [x] O marco `0d85999f4e66290fa06484d802d08fbb310ad164` teve schema,
  persistência, proxy e smoke validados em 2026-08-13.
- [x] O proprietário confirmou em 20/08/2026 que o EasyPanel acompanha o GitHub
  `main`; health público respondeu 200.
- [x] O código removeu migration de `core/wsgi.py`; o entrypoint agora executa
  `prepare_deploy` de forma fail-fast antes do Supervisor.
- [x] A CI `32529705321`, no SHA
  `2584fa7db5e9ee9fa158cdfce54d3b2b24ef4a9d`, construiu a imagem e confirmou
  health com o SHA e os três processos esperados.
- [ ] A publicação GHCR foi pulada no push de branch. A Task 7 deve publicar a
  tag versionada/controlada `sha-<40-char-sha>`, resolver seu digest OCI,
  selecionar o candidato no EasyPanel e provar o health externo com o mesmo SHA.
- [ ] A Task 7 deve ensaiar rollback para a imagem anterior e confirmar rate
  limit persistente para `POST /login/`.

Interrompa o deploy se qualquer pré-requisito, backup, auditoria ou ensaio falhar.

## Topologia obrigatória

O SQLite exige que esta aplicação opere com uma única instância gravadora:

- exatamente **1 réplica** do serviço web no EasyPanel;
- Gunicorn com exatamente **1 worker**;
- Supervisor inicia Gunicorn e exatamente dois schedulers: um único
  `run_backup_scheduler` e um único `run_import_preview_purge_scheduler`; não
  crie cron/job duplicado;
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
rollback por digest OCI. Tags do registry não são tratadas como imutáveis.

Não habilite autoscaling, rolling deploy com duas réplicas simultâneas ou mais de um
worker enquanto o banco for SQLite. Se esse requisito deixar de ser aceitável, a
mudança correta é planejar a migração para um banco servidor, não compartilhar o
arquivo SQLite entre gravadores concorrentes.

Os fluxos de importação e o scheduler de purge gravam pelo mesmo file lock,
criado automaticamente ao lado de `db.sqlite3` no volume `/app/data`. Não altere
`SQLITE_PATH` para um local cujo diretório não seja compartilhado e gravável por
todos os processos do mesmo container. Contenção esgotada retorna o código seguro
`503 import_temporarily_unavailable`; o cliente pode tentar novamente, e o
scheduler de purge repete em 60 segundos.

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

Para o backup automático, cadastre também estas sete variáveis, sem copiar seus
valores para terminal, Git, logs, tickets ou relatórios:

```text
R2_BACKUP_ENDPOINT_URL
R2_BACKUP_ACCESS_KEY_ID
R2_BACKUP_SECRET_ACCESS_KEY
R2_BACKUP_BUCKET
R2_BACKUP_PREFIX
R2_BACKUP_TIME
R2_BACKUP_TIME_ZONE
```

Cadastre `R2_BACKUP_ACCESS_KEY_ID` e `R2_BACKUP_SECRET_ACCESS_KEY` como campos
secretos, sem expor os valores na visualização ou nos logs do deploy.

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

1. Registre a versão atual e a tag versionada/controlada da nova imagem no
   formato `ghcr.io/ludsonfrancisco/finanpy:sha-<sha Git de 40 caracteres>`.
   A Task 7 deve resolver o digest OCI publicado. Se o EasyPanel aceitar
   referência por digest, use
   `ghcr.io/ludsonfrancisco/finanpy@sha256:<digest de 64 hex>`; se não aceitar,
   registre a associação tag→digest e aborte se ela mudar na verificação feita
   imediatamente antes ou depois do deploy.

   Consulte o digest publicado sem fazer pull ou alterar o registry:

   ```sh
   docker buildx imagetools inspect \
     'ghcr.io/ludsonfrancisco/finanpy:sha-<sha Git de 40 caracteres>'
   ```

   Registre o campo `Digest: sha256:<64 hex>` em local operacional seguro. A tag
   sozinha não é prova de identidade imutável.
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
Na Task 7, inicie também a imagem anterior somente contra essa restauração
descartável e registre o digest OCI, health e auditoria. O fallback local de
21/08/2026 com `backup_sqlite` e `runserver` não substitui esse ensaio.

## Sequência de deploy

1. Ative modo de manutenção e confirme que não há requisições de escrita.
2. Repita o preflight no alvo real e confirme que as credenciais R2 estão
   disponíveis sem imprimir valores.
3. Confirme um backup externo verificável e conclua o ensaio na restauração
   descartável. Preserve o objeto R2 selecionado.
4. Selecione a imagem candidata pelo digest OCI registrado. Se a versão do
   EasyPanel não aceitar referência por digest, use a tag versionada/controlada
   `sha-<40-char-sha>` somente após confirmar a associação tag→digest e repita a
   confirmação depois do startup; aborte se os digests diferirem.
5. Configure exatamente uma réplica e não sobrescreva `ENTRYPOINT`, `CMD` ou
   command no EasyPanel. O entrypoint da imagem executa automaticamente:

   ```text
   preflight → backup R2 opcional → migrate → audit → collectstatic → Supervisor
   ```

   O backup de deploy ocorre somente quando já existe banco e há migration
   pendente. Nessa condição ele é obrigatório: falha de configuração ou R2
   encerra o container antes de `migrate`. Banco novo ou sem migration pendente
   pula essa etapa.
6. Se o container terminar com exit diferente de zero, mantenha manutenção
   ativa. Não execute `migrate` manualmente, não inicie Gunicorn/Supervisor à
   parte e não tente uma segunda migration concorrente; preserve a evidência e
   siga o rollback.
7. Após startup bem-sucedido, confirme o mount, `SQLITE_PATH`, uma réplica, um
   worker e os três processos `web`, `backup-scheduler` e
   `import-preview-purge`.
8. Execute a auditoria no container em execução, valide o health e faça os smoke
   checks. Libere o tráfego somente após todas as verificações passarem.

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
- `GET /api/v1/health/` responde HTTP 200 com exatamente `status`, `api_version`
  e `version`; `status=ok`, `api_version=v1` e `version` coincide com o SHA da
  tag versionada associada ao digest selecionado;
- a regra de rate limit devolve `429` após o limite em teste controlado;
- logs não contêm senha, corpo de login, cookies ou segredos;
- após um restart controlado, o mesmo arquivo em `/app/data/db.sqlite3` continua
  disponível e a auditoria permanece íntegra;
- a plataforma continua mostrando uma réplica e o processo Gunicorn, um worker.

Qualquer falha de persistência, isolamento por Lar, autenticação, auditoria ou TLS é
critério de rollback.

Depois da ativação desta imagem, os smoke checks também devem confirmar os três
processos do Supervisor. Para backup, confirme `created` ou `already_exists`, a
chave única do dia e restart idempotente. Para imports, confirme o evento
`purged_import_records` sem conteúdo financeiro e processo saudável após restart.

## Rollback

O caminho prioritário é **parar escritas, voltar para a imagem anterior compatível
e restaurar o backup verificado**. Não sobrescreva o banco enquanto algum processo
Django, Gunicorn ou scheduler estiver aberto. Os comandos abaixo são um roteiro
para a Task 7; não foram executados nesta Task 6.

1. Ative manutenção no EasyPanel, mas, antes de parar a réplica, abra o console do
   container da aplicação ainda em execução. Defina um identificador UTC novo e
   capture a identidade efetiva do processo e UID/GID/mode do banco ativo. O
   comando cria somente um diretório técnico exclusivo no mesmo volume e um
   manifesto `0600`; não lê conteúdo financeiro:

   ```sh
   set -eu
   export ACTIVE_DB='/app/data/db.sqlite3'
   export INCIDENT_ID='<timestamp UTC aprovado, somente dígitos e T/Z>'
   export STAGE_DIR="/app/data/rollback-staging-${INCIDENT_ID}"
   export METADATA_FILE="${STAGE_DIR}/active-db-metadata.json"

   test "$SQLITE_PATH" = "$ACTIVE_DB"

   python - <<'PY'
   import json
   import os
   import re
   import stat
   from pathlib import Path

   def require(condition, message):
       if not condition:
           raise SystemExit(message)

   def runtime_can_read_write(file_stat, runtime_uid, runtime_gid, groups):
       if runtime_uid == 0:
           return True
       mode = stat.S_IMODE(file_stat.st_mode)
       if runtime_uid == file_stat.st_uid:
           bits = (mode >> 6) & 0o7
       elif file_stat.st_gid == runtime_gid or file_stat.st_gid in groups:
           bits = (mode >> 3) & 0o7
       else:
           bits = mode & 0o7
       return bits & 0o6 == 0o6

   def runtime_can_use_directory(directory_stat, runtime_uid, runtime_gid, groups):
       if runtime_uid == 0:
           return True
       mode = stat.S_IMODE(directory_stat.st_mode)
       if runtime_uid == directory_stat.st_uid:
           bits = (mode >> 6) & 0o7
       elif directory_stat.st_gid == runtime_gid or directory_stat.st_gid in groups:
           bits = (mode >> 3) & 0o7
       else:
           bits = mode & 0o7
       return bits & 0o7 == 0o7

   data_dir = Path('/app/data')
   active = Path(os.environ['ACTIVE_DB'])
   incident_id = os.environ['INCIDENT_ID']
   stage_dir = Path(os.environ['STAGE_DIR'])
   metadata_file = Path(os.environ['METADATA_FILE'])
   expected_stage = data_dir / f'rollback-staging-{incident_id}'

   require(re.fullmatch(r'[0-9]{8}T[0-9]{6}Z', incident_id), 'invalid incident ID')
   require(active == data_dir / 'db.sqlite3', 'unexpected active DB path')
   require(stage_dir == expected_stage, 'unexpected stage path')
   require(metadata_file == stage_dir / 'active-db-metadata.json', 'bad manifest path')
   require(data_dir.is_dir() and not data_dir.is_symlink(), 'unsafe data path')
   require(data_dir.resolve(strict=True) == data_dir, 'data path changed')
   require(active.exists() and not active.is_symlink(), 'unsafe active DB')
   require(active.resolve(strict=True) == active, 'active path changed')
   data_stat = os.lstat(data_dir)
   require(stat.S_ISDIR(data_stat.st_mode), 'data path is not a directory')
   active_stat = os.lstat(active)
   require(stat.S_ISREG(active_stat.st_mode), 'active DB is not regular')
   require(active_stat.st_dev == data_stat.st_dev, 'active DB filesystem mismatch')
   active_mode = stat.S_IMODE(active_stat.st_mode)
   require(active_mode & 0o007 == 0, 'active DB has permissions for other users')
   supervisor_config = Path('/app/deploy/supervisord.conf')
   require(
       supervisor_config.is_file() and not supervisor_config.is_symlink(),
       'unsafe Supervisor config',
   )
   supervisor_text = supervisor_config.read_text(encoding='utf-8')
   require(
       not re.search(r'(?mi)^\s*user\s*=', supervisor_text),
       'Supervisor programs change identity; capture each program identity instead',
   )
   require(
       b'supervisord' in Path('/proc/1/cmdline').read_bytes().replace(b'\0', b' '),
       'PID 1 is not Supervisor',
   )
   process_status = Path('/proc/1/status').read_text(encoding='utf-8')
   uid_match = re.search(r'(?m)^Uid:\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)$', process_status)
   gid_match = re.search(r'(?m)^Gid:\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)$', process_status)
   groups_match = re.search(r'(?m)^Groups:\s*(.*?)\s*$', process_status)
   require(uid_match and gid_match and groups_match, 'cannot read Supervisor identity')
   runtime_uid = int(uid_match.group(2))
   runtime_gid = int(gid_match.group(2))
   runtime_groups = [int(value) for value in groups_match.group(1).split()]
   require(
       os.geteuid() == runtime_uid and os.getegid() == runtime_gid,
       'console identity differs from Supervisor; use an approved matching session',
   )
   require(
       runtime_can_read_write(active_stat, runtime_uid, runtime_gid, runtime_groups),
       'application identity cannot read and write active DB',
   )
   require(
       runtime_can_use_directory(data_stat, runtime_uid, runtime_gid, runtime_groups),
       'application identity cannot create SQLite sidecars in data directory',
   )
   require(not stage_dir.exists() and not stage_dir.is_symlink(), 'stage dir exists')
   stage_dir.mkdir(mode=0o700)
   stage_stat = os.lstat(stage_dir)
   require(stat.S_ISDIR(stage_stat.st_mode), 'stage path is not a directory')
   require(stat.S_IMODE(stage_stat.st_mode) == 0o700, 'unsafe stage mode')
   require(stage_stat.st_uid == runtime_uid, 'stage owner mismatch')
   require(stage_stat.st_dev == active_stat.st_dev, 'stage filesystem mismatch')

   payload = {
       'incident_id': incident_id,
       'filesystem_dev': active_stat.st_dev,
       'data_uid': data_stat.st_uid,
       'data_gid': data_stat.st_gid,
       'data_mode': stat.S_IMODE(data_stat.st_mode),
       'db_uid': active_stat.st_uid,
       'db_gid': active_stat.st_gid,
       'db_mode': active_mode,
       'runtime_uid': runtime_uid,
       'runtime_gid': runtime_gid,
       'runtime_groups': runtime_groups,
       'runtime_source': 'supervisor-pid-1-inherited-by-programs',
   }
   flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
   descriptor = os.open(metadata_file, flags, 0o600)
   with os.fdopen(descriptor, 'w', encoding='utf-8') as target:
       json.dump(payload, target, sort_keys=True)
       target.write('\n')
       target.flush()
       os.fsync(target.fileno())
   manifest_stat = os.lstat(metadata_file)
   require(stat.S_ISREG(manifest_stat.st_mode), 'manifest is not regular')
   require(stat.S_IMODE(manifest_stat.st_mode) == 0o600, 'unsafe manifest mode')
   require(manifest_stat.st_uid == runtime_uid, 'manifest owner mismatch')
   print(
       'active_db_metadata_captured '
       f'uid={active_stat.st_uid} gid={active_stat.st_gid} mode={active_mode:04o} '
       f'runtime_uid={runtime_uid} runtime_gid={runtime_gid}'
   )
   PY
   ```

   Registre a linha sanitizada. Se o banco tiver qualquer permissão para
   “others” ou se a identidade herdada por Supervisor/Gunicorn/schedulers não
   puder ler, gravar e criar sidecars, o comando aborta. Ele também aborta se os
   programas tiverem `user=` próprio ou se o console usar outra identidade; nesse
   caso, capture cada identidade efetiva por procedimento aprovado antes de
   continuar.
2. Agora pare a única réplica candidata no EasyPanel, registre horário e estado
   `Stopped` e confirme que não existe container gravador em execução. Abra um
   console one-off de manutenção com o mesmo volume; ele não deve iniciar
   Supervisor, Gunicorn ou schedulers.
3. Pelo caminho R2 documentado, execute `HeadObject`, registre `ContentLength` e a
   metadata SHA em local operacional seguro e baixe sem alterar o objeto. Grave o
   download em `restore.sqlite3` dentro do `STAGE_DIR` criado na etapa anterior:
   ele fica fora do path ativo, mas no mesmo filesystem para permitir promoção
   atômica. Não use `/app/data/db.sqlite3` como destino do download. Na sessão
   one-off, repita o mesmo `INCIDENT_ID`, use as sete variáveis R2 do secret store,
   defina apenas a chave lógica selecionada e execute:

   ```sh
   set -eu
   export INCIDENT_ID='<mesmo timestamp UTC registrado na etapa 1>'
   export R2_RESTORE_KEY='<chave lógica do objeto R2 selecionado>'
   export STAGE_DIR="/app/data/rollback-staging-${INCIDENT_ID}"
   export STAGED_DB="${STAGE_DIR}/restore.sqlite3"
   export METADATA_FILE="${STAGE_DIR}/active-db-metadata.json"

   python - <<'PY'
   import hashlib
   import json
   import os
   import re
   import sqlite3
   import stat
   from pathlib import Path

   import boto3

   def require(condition, message):
       if not condition:
           raise SystemExit(message)

   def runtime_can_read_write(file_stat, runtime_uid, runtime_gid, groups):
       if runtime_uid == 0:
           return True
       mode = stat.S_IMODE(file_stat.st_mode)
       if runtime_uid == file_stat.st_uid:
           bits = (mode >> 6) & 0o7
       elif file_stat.st_gid == runtime_gid or file_stat.st_gid in groups:
           bits = (mode >> 3) & 0o7
       else:
           bits = mode & 0o7
       return bits & 0o6 == 0o6

   data_dir = Path('/app/data')
   stage_dir = Path(os.environ['STAGE_DIR'])
   staged = Path(os.environ['STAGED_DB'])
   metadata_file = Path(os.environ['METADATA_FILE'])
   incident_id = os.environ['INCIDENT_ID']
   key = os.environ['R2_RESTORE_KEY']
   expected_stage = data_dir / f'rollback-staging-{incident_id}'
   require(re.fullmatch(r'[0-9]{8}T[0-9]{6}Z', incident_id), 'invalid incident ID')
   require(data_dir.is_dir() and not data_dir.is_symlink(), 'unsafe data path')
   require(data_dir.resolve(strict=True) == data_dir, 'data path changed')
   require(stage_dir == expected_stage, 'unexpected stage path')
   require(staged == stage_dir / 'restore.sqlite3', 'unexpected staged DB path')
   require(metadata_file == stage_dir / 'active-db-metadata.json', 'bad manifest path')
   require(key and '\n' not in key and '\r' not in key, 'invalid R2 key')
   require(stage_dir.is_dir() and not stage_dir.is_symlink(), 'unsafe stage dir')
   require(stage_dir.resolve(strict=True) == stage_dir, 'stage path changed')
   require(metadata_file.exists() and not metadata_file.is_symlink(), 'manifest missing')
   require(stat.S_ISREG(os.lstat(metadata_file).st_mode), 'manifest is not regular')
   require(stat.S_IMODE(os.lstat(metadata_file).st_mode) == 0o600, 'unsafe manifest mode')
   manifest_descriptor = os.open(metadata_file, os.O_RDONLY | os.O_NOFOLLOW)
   with os.fdopen(manifest_descriptor, encoding='utf-8') as source:
       captured = json.load(source)
   require(captured.get('incident_id') == incident_id, 'manifest incident mismatch')
   require(
       captured.get('runtime_source') == 'supervisor-pid-1-inherited-by-programs',
       'untrusted runtime identity source',
   )
   require(isinstance(captured.get('db_uid'), int), 'invalid captured UID')
   require(isinstance(captured.get('db_gid'), int), 'invalid captured GID')
   require(isinstance(captured.get('db_mode'), int), 'invalid captured mode')
   require(isinstance(captured.get('runtime_uid'), int), 'invalid runtime UID')
   require(isinstance(captured.get('runtime_gid'), int), 'invalid runtime GID')
   require(isinstance(captured.get('runtime_groups'), list), 'invalid runtime groups')
   require(
       all(isinstance(group, int) and group >= 0 for group in captured['runtime_groups']),
       'invalid runtime group',
   )
   require(captured['db_uid'] >= 0 and captured['db_gid'] >= 0, 'negative UID/GID')
   require(0 <= captured['db_mode'] <= 0o777, 'captured mode out of range')
   require(captured['db_mode'] & 0o007 == 0, 'captured mode is world-accessible')
   manifest_stat = os.lstat(metadata_file)
   require(manifest_stat.st_uid == captured['runtime_uid'], 'manifest owner changed')
   require(os.stat(stage_dir).st_uid == captured.get('runtime_uid'), 'stage owner changed')
   require(stat.S_IMODE(os.stat(stage_dir).st_mode) == 0o700, 'unsafe stage mode')
   require(os.stat(stage_dir).st_dev == captured.get('filesystem_dev'), 'stage device changed')
   require(not staged.exists() and not staged.is_symlink(), 'staged DB exists')

   client = boto3.client(
       's3',
       endpoint_url=os.environ['R2_BACKUP_ENDPOINT_URL'],
       aws_access_key_id=os.environ['R2_BACKUP_ACCESS_KEY_ID'],
       aws_secret_access_key=os.environ['R2_BACKUP_SECRET_ACCESS_KEY'],
       region_name='auto',
   )
   bucket = os.environ['R2_BACKUP_BUCKET']
   head = client.head_object(Bucket=bucket, Key=key)
   size = head.get('ContentLength')
   metadata = head.get('Metadata', {})
   expected_sha = metadata.get('sha256', '')
   require(isinstance(size, int) and not isinstance(size, bool), 'invalid size')
   require(metadata.get('size') == str(size), 'metadata size mismatch')
   require(re.fullmatch(r'[0-9a-f]{64}', expected_sha), 'invalid metadata SHA')

   flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
   staged_descriptor = os.open(staged, flags, 0o600)
   with os.fdopen(staged_descriptor, 'wb') as target:
       client.download_fileobj(bucket, key, target)
       target.flush()
       os.fsync(target.fileno())
   require(staged.stat().st_size == size, 'downloaded size mismatch')
   with staged.open('rb') as source:
       actual_sha = hashlib.file_digest(source, 'sha256').hexdigest()
   require(actual_sha == expected_sha, 'downloaded SHA-256 mismatch')
   connection = sqlite3.connect(f'file:{staged}?mode=ro', uri=True)
   integrity = connection.execute('PRAGMA integrity_check').fetchone()[0]
   connection.close()
   require(integrity == 'ok', 'SQLite integrity check failed')

   staged_descriptor = os.open(staged, os.O_RDWR | os.O_NOFOLLOW)
   staged_stat = os.fstat(staged_descriptor)
   if (staged_stat.st_uid, staged_stat.st_gid) != (
       captured['db_uid'],
       captured['db_gid'],
   ):
       require(os.geteuid() == 0, 'root required to restore captured UID/GID')
       os.fchown(staged_descriptor, captured['db_uid'], captured['db_gid'])
   staged_stat = os.fstat(staged_descriptor)
   if stat.S_IMODE(staged_stat.st_mode) != captured['db_mode']:
       require(
           os.geteuid() == 0 or staged_stat.st_uid == os.geteuid(),
           'root or captured owner required to restore mode',
       )
       os.fchmod(staged_descriptor, captured['db_mode'])
   os.fsync(staged_descriptor)
   staged_stat = os.fstat(staged_descriptor)
   os.close(staged_descriptor)
   require(staged_stat.st_uid == captured['db_uid'], 'staged UID mismatch')
   require(staged_stat.st_gid == captured['db_gid'], 'staged GID mismatch')
   require(stat.S_IMODE(staged_stat.st_mode) == captured['db_mode'], 'staged mode mismatch')
   require(staged_stat.st_dev == captured['filesystem_dev'], 'staged device mismatch')
   require(stat.S_ISREG(staged_stat.st_mode), 'staged DB is not regular')
   require(stat.S_IMODE(staged_stat.st_mode) & 0o007 == 0, 'staged DB is world-accessible')
   require(
       runtime_can_read_write(
           staged_stat,
           captured['runtime_uid'],
           captured['runtime_gid'],
           captured['runtime_groups'],
       ),
       'application identity cannot read and write staged DB',
   )
   print(
       f'r2_restore_verified size={size} sha256={actual_sha} '
       f'uid={staged_stat.st_uid} gid={staged_stat.st_gid} '
       f'mode={stat.S_IMODE(staged_stat.st_mode):04o}'
   )
   PY
   ```

   A criação exclusiva `0600` impede que o download fique world-readable mesmo
   antes do ajuste. O código só usa UID/GID/mode capturados do banco ativo. Se a
   sessão não tiver privilégio para restaurar owner/group, ela aborta e exige um
   one-off autorizado como root; nunca faça `chown` para valores diferentes do
   manifesto. Registre a linha sanitizada, sem chaves ou conteúdo financeiro.
4. No mesmo console one-off, substitua os
   valores entre `<...>` pelos dados já registrados. Então execute exatamente as
   guardas e validações abaixo; qualquer exit diferente de zero mantém a
   manutenção e interrompe o rollback:

   ```sh
   set -eu
   export ACTIVE_DB='/app/data/db.sqlite3'
   export INCIDENT_ID='<mesmo timestamp UTC registrado na etapa 1>'
   export STAGE_DIR="/app/data/rollback-staging-${INCIDENT_ID}"
   export STAGED_DB="${STAGE_DIR}/restore.sqlite3"
   export FAILED_DB="${STAGE_DIR}/failed.sqlite3"
   export METADATA_FILE="${STAGE_DIR}/active-db-metadata.json"
   export EXPECTED_SIZE='<ContentLength decimal retornado pelo HeadObject>'
   export EXPECTED_SHA256='<SHA-256 de 64 hex minúsculos da metadata R2>'

   test "$SQLITE_PATH" = "$ACTIVE_DB"
   test ! -e /tmp/supervisord.pid

   python - <<'PY'
   import hashlib
   import json
   import os
   import re
   import sqlite3
   import stat
   from pathlib import Path

   def require(condition, message):
       if not condition:
           raise SystemExit(message)

   def runtime_can_read_write(file_stat, runtime_uid, runtime_gid, groups):
       if runtime_uid == 0:
           return True
       mode = stat.S_IMODE(file_stat.st_mode)
       if runtime_uid == file_stat.st_uid:
           bits = (mode >> 6) & 0o7
       elif file_stat.st_gid == runtime_gid or file_stat.st_gid in groups:
           bits = (mode >> 3) & 0o7
       else:
           bits = mode & 0o7
       return bits & 0o6 == 0o6

   def runtime_can_use_directory(directory_stat, runtime_uid, runtime_gid, groups):
       if runtime_uid == 0:
           return True
       mode = stat.S_IMODE(directory_stat.st_mode)
       if runtime_uid == directory_stat.st_uid:
           bits = (mode >> 6) & 0o7
       elif directory_stat.st_gid == runtime_gid or directory_stat.st_gid in groups:
           bits = (mode >> 3) & 0o7
       else:
           bits = mode & 0o7
       return bits & 0o7 == 0o7

   active = Path(os.environ['ACTIVE_DB'])
   stage_dir = Path(os.environ['STAGE_DIR'])
   staged = Path(os.environ['STAGED_DB'])
   failed = Path(os.environ['FAILED_DB'])
   metadata_file = Path(os.environ['METADATA_FILE'])
   incident_id = os.environ['INCIDENT_ID']
   expected_size_text = os.environ['EXPECTED_SIZE']
   expected_sha = os.environ['EXPECTED_SHA256']

   require(active == Path('/app/data/db.sqlite3'), 'unexpected active DB path')
   require(
       stage_dir == Path('/app/data') / f'rollback-staging-{incident_id}',
       'unexpected stage path',
   )
   require(staged == stage_dir / 'restore.sqlite3', 'unexpected staged DB path')
   require(failed == stage_dir / 'failed.sqlite3', 'unexpected failed DB path')
   require(metadata_file == stage_dir / 'active-db-metadata.json', 'bad manifest path')
   require(
       re.fullmatch(r'[0-9]{8}T[0-9]{6}Z', incident_id),
       'invalid incident ID',
   )
   require(re.fullmatch(r'[0-9]+', expected_size_text), 'invalid expected size')
   require(re.fullmatch(r'[0-9a-f]{64}', expected_sha), 'invalid expected SHA')
   require(not Path('/app/data').is_symlink(), 'data path is a symlink')
   require(stage_dir.is_dir() and not stage_dir.is_symlink(), 'unsafe stage dir')
   require(active.exists() and not active.is_symlink(), 'unsafe active DB')
   require(staged.exists() and not staged.is_symlink(), 'unsafe staged DB')
   require(not failed.exists() and not failed.is_symlink(), 'failed DB exists')
   require(metadata_file.exists() and not metadata_file.is_symlink(), 'manifest missing')
   require(stat.S_ISREG(os.lstat(metadata_file).st_mode), 'manifest is not regular')
   require(stage_dir.resolve(strict=True) == stage_dir, 'stage path changed')
   require(active.resolve(strict=True) == active, 'active path changed')
   require(staged.resolve(strict=True) == staged, 'staged path changed')
   require(failed.parent.resolve(strict=True) == stage_dir, 'failed path changed')
   require(stat.S_ISREG(os.lstat(active).st_mode), 'active DB is not regular')
   require(stat.S_ISREG(os.lstat(staged).st_mode), 'staged DB is not regular')
   manifest_descriptor = os.open(metadata_file, os.O_RDONLY | os.O_NOFOLLOW)
   with os.fdopen(manifest_descriptor, encoding='utf-8') as source:
       captured = json.load(source)
   require(captured.get('incident_id') == incident_id, 'manifest incident mismatch')
   require(
       captured.get('runtime_source') == 'supervisor-pid-1-inherited-by-programs',
       'untrusted runtime identity source',
   )
   require(isinstance(captured.get('db_uid'), int), 'invalid captured UID')
   require(isinstance(captured.get('db_gid'), int), 'invalid captured GID')
   require(isinstance(captured.get('db_mode'), int), 'invalid captured mode')
   require(isinstance(captured.get('runtime_uid'), int), 'invalid runtime UID')
   require(isinstance(captured.get('runtime_gid'), int), 'invalid runtime GID')
   require(isinstance(captured.get('runtime_groups'), list), 'invalid runtime groups')
   require(isinstance(captured.get('data_uid'), int), 'invalid data UID')
   require(isinstance(captured.get('data_gid'), int), 'invalid data GID')
   require(isinstance(captured.get('data_mode'), int), 'invalid data mode')
   require(stat.S_IMODE(os.lstat(metadata_file).st_mode) == 0o600, 'unsafe manifest mode')
   require(os.lstat(metadata_file).st_uid == captured['runtime_uid'], 'manifest owner changed')
   require(os.lstat(stage_dir).st_uid == captured['runtime_uid'], 'stage owner changed')
   require(stat.S_IMODE(os.lstat(stage_dir).st_mode) == 0o700, 'unsafe stage mode')
   require(0 <= captured['db_mode'] <= 0o777, 'captured mode out of range')
   require(captured['db_mode'] & 0o007 == 0, 'captured mode is world-accessible')
   active_stat = os.lstat(active)
   staged_stat = os.lstat(staged)
   data_stat = os.lstat('/app/data')
   require(stat.S_ISDIR(data_stat.st_mode), 'data path is not a directory')
   require(data_stat.st_uid == captured.get('data_uid'), 'data directory UID changed')
   require(data_stat.st_gid == captured.get('data_gid'), 'data directory GID changed')
   require(stat.S_IMODE(data_stat.st_mode) == captured.get('data_mode'), 'data mode changed')
   require(active_stat.st_uid == captured.get('db_uid'), 'active UID changed')
   require(active_stat.st_gid == captured.get('db_gid'), 'active GID changed')
   require(stat.S_IMODE(active_stat.st_mode) == captured.get('db_mode'), 'active mode changed')
   require(staged_stat.st_uid == captured.get('db_uid'), 'staged UID mismatch')
   require(staged_stat.st_gid == captured.get('db_gid'), 'staged GID mismatch')
   require(stat.S_IMODE(staged_stat.st_mode) == captured.get('db_mode'), 'staged mode mismatch')
   require(stat.S_IMODE(staged_stat.st_mode) & 0o007 == 0, 'staged DB is world-accessible')
   require(
       runtime_can_read_write(
           staged_stat,
           captured['runtime_uid'],
           captured['runtime_gid'],
           captured['runtime_groups'],
       ),
       'application identity cannot read and write staged DB',
   )
   require(
       runtime_can_use_directory(
           data_stat,
           captured['runtime_uid'],
           captured['runtime_gid'],
           captured['runtime_groups'],
       ),
       'application identity cannot create SQLite sidecars in data directory',
   )
   require(not os.path.lexists('/app/data/db.sqlite3-wal'), 'WAL entry exists; preserve and investigate')
   require(not os.path.lexists('/app/data/db.sqlite3-shm'), 'SHM entry exists; preserve and investigate')
   require(
       not os.path.lexists('/app/data/db.sqlite3-journal'),
       'rollback journal entry exists; preserve and investigate',
   )
   require(os.stat(active).st_dev == os.stat(staged).st_dev, 'different filesystems')
   require(os.stat(staged).st_dev == captured.get('filesystem_dev'), 'device mismatch')
   require(os.stat(staged).st_size == int(expected_size_text), 'size mismatch')

   with staged.open('rb') as source:
       actual_sha = hashlib.file_digest(source, 'sha256').hexdigest()
   require(actual_sha == expected_sha, 'SHA-256 mismatch')

   connection = sqlite3.connect(f'file:{staged}?mode=ro', uri=True)
   integrity = connection.execute('PRAGMA integrity_check').fetchone()[0]
   connection.close()
   require(integrity == 'ok', 'SQLite integrity check failed')
   print(f'staged_restore_verified size={staged.stat().st_size} sha256={actual_sha}')
   PY
   ```

   Se qualquer `db.sqlite3-wal`, `db.sqlite3-shm` ou `db.sqlite3-journal` existir,
   preserve o sidecar e investigue o encerramento/estado transacional. Nunca o
   exclua automaticamente nem prossiga com a promoção.
5. Preserve o banco falho e promova a cópia validada com renames no mesmo
   filesystem. Estes comandos não usam glob, loop ou exclusão; não os execute se
   qualquer guarda anterior falhar:

   ```sh
   sync "$ACTIVE_DB" "$STAGED_DB"
   mv -- "$ACTIVE_DB" "$FAILED_DB"
   mv -- "$STAGED_DB" "$ACTIVE_DB"
   sync "$ACTIVE_DB" "$FAILED_DB"

   python - <<'PY'
   import hashlib
   import json
   import os
   import sqlite3
   import stat
   from pathlib import Path

   def require(condition, message):
       if not condition:
           raise SystemExit(message)

   def runtime_can_read_write(file_stat, runtime_uid, runtime_gid, groups):
       if runtime_uid == 0:
           return True
       mode = stat.S_IMODE(file_stat.st_mode)
       if runtime_uid == file_stat.st_uid:
           bits = (mode >> 6) & 0o7
       elif file_stat.st_gid == runtime_gid or file_stat.st_gid in groups:
           bits = (mode >> 3) & 0o7
       else:
           bits = mode & 0o7
       return bits & 0o6 == 0o6

   def runtime_can_use_directory(directory_stat, runtime_uid, runtime_gid, groups):
       if runtime_uid == 0:
           return True
       mode = stat.S_IMODE(directory_stat.st_mode)
       if runtime_uid == directory_stat.st_uid:
           bits = (mode >> 6) & 0o7
       elif directory_stat.st_gid == runtime_gid or directory_stat.st_gid in groups:
           bits = (mode >> 3) & 0o7
       else:
           bits = mode & 0o7
       return bits & 0o7 == 0o7

   active = Path(os.environ['ACTIVE_DB'])
   failed = Path(os.environ['FAILED_DB'])
   metadata_file = Path(os.environ['METADATA_FILE'])
   expected_sha = os.environ['EXPECTED_SHA256']
   require(active == Path('/app/data/db.sqlite3'), 'unexpected active DB path')
   require(metadata_file == failed.parent / 'active-db-metadata.json', 'bad manifest path')
   require(active.exists() and not active.is_symlink(), 'unsafe active DB')
   require(failed.exists() and not failed.is_symlink(), 'unsafe preserved DB')
   require(active.resolve(strict=True) == active, 'active path changed')
   require(failed.resolve(strict=True) == failed, 'preserved path changed')
   manifest_descriptor = os.open(metadata_file, os.O_RDONLY | os.O_NOFOLLOW)
   with os.fdopen(manifest_descriptor, encoding='utf-8') as source:
       captured = json.load(source)
   require(
       captured.get('runtime_source') == 'supervisor-pid-1-inherited-by-programs',
       'untrusted runtime identity source',
   )
   require(isinstance(captured.get('runtime_uid'), int), 'invalid runtime UID')
   require(isinstance(captured.get('runtime_gid'), int), 'invalid runtime GID')
   require(isinstance(captured.get('runtime_groups'), list), 'invalid runtime groups')
   require(stat.S_IMODE(os.lstat(metadata_file).st_mode) == 0o600, 'unsafe manifest mode')
   require(os.lstat(metadata_file).st_uid == captured['runtime_uid'], 'manifest owner changed')
   active_stat = os.lstat(active)
   failed_stat = os.lstat(failed)
   data_stat = os.lstat('/app/data')
   require(stat.S_ISREG(active_stat.st_mode), 'active DB is not regular')
   require(stat.S_ISREG(failed_stat.st_mode), 'preserved DB is not regular')
   require(active_stat.st_uid == captured.get('db_uid'), 'active UID mismatch')
   require(active_stat.st_gid == captured.get('db_gid'), 'active GID mismatch')
   require(stat.S_IMODE(active_stat.st_mode) == captured.get('db_mode'), 'active mode mismatch')
   require(failed_stat.st_uid == captured.get('db_uid'), 'preserved UID mismatch')
   require(failed_stat.st_gid == captured.get('db_gid'), 'preserved GID mismatch')
   require(stat.S_IMODE(failed_stat.st_mode) == captured.get('db_mode'), 'preserved mode mismatch')
   require(active_stat.st_dev == captured.get('filesystem_dev'), 'active device mismatch')
   require(failed_stat.st_dev == captured.get('filesystem_dev'), 'preserved device mismatch')
   require(data_stat.st_dev == captured.get('filesystem_dev'), 'data device mismatch')
   require(data_stat.st_uid == captured.get('data_uid'), 'data directory UID changed')
   require(data_stat.st_gid == captured.get('data_gid'), 'data directory GID changed')
   require(stat.S_IMODE(data_stat.st_mode) == captured.get('data_mode'), 'data mode changed')
   require(stat.S_IMODE(active_stat.st_mode) & 0o007 == 0, 'active DB is world-accessible')
   require(
       runtime_can_read_write(
           active_stat,
           captured.get('runtime_uid'),
           captured.get('runtime_gid'),
           captured.get('runtime_groups'),
       ),
       'application identity cannot read and write promoted DB',
   )
   require(
       runtime_can_use_directory(
           data_stat,
           captured.get('runtime_uid'),
           captured.get('runtime_gid'),
           captured.get('runtime_groups'),
       ),
       'application identity cannot create SQLite sidecars in data directory',
   )
   require(not os.path.lexists('/app/data/db.sqlite3-wal'), 'WAL entry appeared after promotion')
   require(not os.path.lexists('/app/data/db.sqlite3-shm'), 'SHM entry appeared after promotion')
   require(not os.path.lexists('/app/data/db.sqlite3-journal'), 'journal entry appeared after promotion')
   with active.open('rb') as source:
       actual_sha = hashlib.file_digest(source, 'sha256').hexdigest()
   require(actual_sha == expected_sha, 'SHA-256 mismatch after promotion')
   connection = sqlite3.connect(f'file:{active}?mode=ro', uri=True)
   integrity = connection.execute('PRAGMA integrity_check').fetchone()[0]
   connection.close()
   require(integrity == 'ok', 'SQLite integrity check failed after promotion')
   print(f'active_restore_verified size={active.stat().st_size} sha256={actual_sha}')
   PY
   ```

   A promoção de `STAGED_DB` para `ACTIVE_DB` é atômica por ocorrer no mesmo
   filesystem. Se o segundo `mv` falhar, não reinicie processos: confirme que
   `ACTIVE_DB` está ausente e que `FAILED_DB` é o arquivo regular preservado antes
   de executar uma única reversão:

   ```sh
   test "$ACTIVE_DB" = '/app/data/db.sqlite3'
   test ! -e "$ACTIVE_DB"
   test ! -L "$FAILED_DB"
   test -f "$FAILED_DB"

   python - <<'PY'
   import json
   import os
   import stat
   from pathlib import Path

   def require(condition, message):
       if not condition:
           raise SystemExit(message)

   active = Path(os.environ['ACTIVE_DB'])
   failed = Path(os.environ['FAILED_DB'])
   metadata_file = Path(os.environ['METADATA_FILE'])
   require(active == Path('/app/data/db.sqlite3'), 'unexpected active DB path')
   require(not active.exists() and not active.is_symlink(), 'active path reappeared')
   require(failed.exists() and not failed.is_symlink(), 'unsafe preserved DB')
   require(failed.resolve(strict=True) == failed, 'preserved path changed')
   require(metadata_file == failed.parent / 'active-db-metadata.json', 'bad manifest path')
   require(metadata_file.exists() and not metadata_file.is_symlink(), 'manifest missing')
   descriptor = os.open(metadata_file, os.O_RDONLY | os.O_NOFOLLOW)
   with os.fdopen(descriptor, encoding='utf-8') as source:
       captured = json.load(source)
   failed_stat = os.lstat(failed)
   require(stat.S_ISREG(failed_stat.st_mode), 'preserved DB is not regular')
   require(failed_stat.st_uid == captured.get('db_uid'), 'preserved UID mismatch')
   require(failed_stat.st_gid == captured.get('db_gid'), 'preserved GID mismatch')
   require(stat.S_IMODE(failed_stat.st_mode) == captured.get('db_mode'), 'preserved mode mismatch')
   require(failed_stat.st_dev == captured.get('filesystem_dev'), 'preserved device mismatch')
   require(stat.S_IMODE(failed_stat.st_mode) & 0o007 == 0, 'preserved DB is world-accessible')
   PY

   mv -- "$FAILED_DB" "$ACTIVE_DB"
   sync "$ACTIVE_DB"
   ```
6. Antes do restart, use o ensaio descartável da imagem anterior para confirmar
   que sua identidade efetiva consegue ler e gravar um arquivo com o UID/GID/mode
   capturado. Se não conseguir, mantenha manutenção e corrija a incompatibilidade
   por procedimento aprovado; não abra o banco para “others”. Selecione a imagem
   anterior por
   `ghcr.io/ludsonfrancisco/finanpy@sha256:<digest anterior de 64 hex>` quando o
   EasyPanel aceitar digest. Caso contrário, selecione a tag versionada anterior,
   registre sua associação tag→digest imediatamente antes do restart e valide a
   mesma associação logo depois; divergência mantém a manutenção.
7. Inicie exatamente uma réplica, preservando o entrypoint, e confirme um worker
   Gunicorn e os dois schedulers. Execute checks e auditoria compatíveis com o
   schema restaurado, depois repita health e smoke checks antes de liberar tráfego.
8. Registre motivo, horários, tag e digest das imagens, tamanho/hash do backup,
   resultado do `HeadObject`, download, integridade, promoção e restart, sem dados
   pessoais ou segredos. Preserve o banco falho até uma decisão posterior de
   retenção; preserve também o manifesto e qualquer sidecar encontrado. Não
   exclua nem substitua objetos R2 durante o rollback.

Se o rollback for motivado apenas pela automação de backup e o schema continuar
compatível, ainda assim selecione a imagem anterior pelo digest observado. As
variáveis podem permanecer no secret store sem consumidor ou ser removidas depois
de preservar evidência; nunca revogue uma credencial antes de confirmar que não há
outro consumidor autorizado.

Downgrade com `python manage.py migrate <app> <migration>` só é aceitável se o grafo
exato, a imagem anterior e o mesmo estado de dados tiverem passado por ida e volta
em restauração descartável. Na ausência dessa prova específica, restaure o backup;
não improvise um downgrade em produção e nunca altere manualmente a tabela
`django_migrations`.

A versão instalada permitiu uma réplica sem sobreposição, start/stop e restore
isolado em 2026-08-13, mas a imagem anterior por digest OCI ainda não foi
ensaiada. Essa é uma ação explícita da Task 7 antes de aceitar R1.4.

## Registro da validação real

Ao concluir uma execução real, registre em local operacional seguro:

- data, operador e ambiente;
- tags versionadas, digests OCI e associações tag→digest das imagens anterior e
  nova;
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
restauração isolada. Não comprova ainda rollback por digest OCI, rate limit de
login ou alertas externos. A prova local/CI de 21/08/2026 comprova o código e a
imagem candidata na CI, mas não comprova publicação GHCR nem alteração no
EasyPanel; essas ações aguardam a Task 7.
