# Backup automático do SQLite no Cloudflare R2

## Estado da entrega

A automação está codificada e testada no branch
`codex/task-automatic-r2-backup`. A imagem inicia um Gunicorn e um scheduler pelo
Supervisor. O scheduler tenta um backup por dia, às `03:00` em
`America/Sao_Paulo`; depois de falha, tenta novamente em uma hora. Um restart
depois do horário agenda a tentativa do dia imediatamente.

**Ainda não houve ativação no EasyPanel, execução desta automação contra o R2
real, restart operacional nem restauração de um objeto produzido por ela.** O
backup R2 manual restaurado em 2026-08-12 é uma evidência anterior e não substitui
essa prova. Ativação é uma tarefa separada, depois de review, merge em `main` e
autorização explícita.

## Fluxo e invariantes

1. Adquire uma trava não bloqueante ao lado do banco.
2. Calcula a chave do dia no timezone configurado e verifica se ela já existe.
3. Cria uma cópia temporária pela API de backup do SQLite e executa
   `PRAGMA integrity_check`.
4. Calcula tamanho e SHA-256, envia com `If-None-Match: *` e confirma o objeto por
   `HeadObject`.
5. Lista e valida todo o catálogo gerenciado antes de calcular retenção.
6. Exclui somente objetos gerenciados expirados, do mais antigo para o mais novo.
7. Remove a cópia temporária e libera a trava, inclusive depois de falha.

O processo nunca sobrescreve um objeto confirmado, nunca restaura automaticamente
o banco de produção e não inicia retenção antes de confirmar o upload.

## Configuração no EasyPanel

Cadastre exatamente estas sete variáveis. Os valores de access key e secret devem
ser inseridos diretamente no secret store e nunca copiados para Git, argumentos de
processo, logs, chat, tickets ou relatórios.

| Variável | Valor/regra |
|---|---|
| `R2_BACKUP_ENDPOINT_URL` | endpoint HTTPS da conta, no formato `https://<account-id>.r2.cloudflarestorage.com` |
| `R2_BACKUP_ACCESS_KEY_ID` | segredo fornecido pelo token dedicado |
| `R2_BACKUP_SECRET_ACCESS_KEY` | segredo fornecido pelo token dedicado |
| `R2_BACKUP_BUCKET` | `lar-finance-backups` em produção |
| `R2_BACKUP_PREFIX` | `production` em produção |
| `R2_BACKUP_TIME` | `03:00` |
| `R2_BACKUP_TIME_ZONE` | `America/Sao_Paulo` |

O bucket deve permanecer privado. Crie um token R2 dedicado com permissão
**Object Read & Write** limitada somente a `lar-finance-backups`. A implementação
precisa listar, ler metadados, criar e excluir objetos; não precisa administrar a
conta nem acessar outros buckets.

Antes de ativar, confirme uma réplica, um worker Gunicorn, o mount `/app/data`,
`SQLITE_PATH=/app/data/db.sqlite3`, um backup externo anterior restaurável, espaço
livre e checks de produção. Não crie cron paralelo: o Supervisor já inicia um
`run_backup_scheduler`.

## Execução manual e logs

Com as sete variáveis presentes no ambiente do container:

```sh
python manage.py backup_to_r2
```

O comando retorna exit code diferente de zero em falha. A linha JSON sanitizada
em stdout registra `timestamp`, `service`, `event`, `status`, `stage`, `key`,
`size`, os 12 primeiros caracteres do `sha256`, `duration_ms`, `deleted_count` e
`error_code`. Ela não inclui credenciais nem conteúdo financeiro.

| Resultado | Interpretação e ação |
|---|---|
| `created` | Cópia local íntegra, upload e `HeadObject` confirmados; a retenção terminou. Registre a evidência sanitizada. |
| `already_exists` | A chave gerenciada do dia já existe e seus metadados são válidos. Nenhum upload, sobrescrita ou retenção ocorre nessa tentativa. |
| `lock_busy` | Outra execução detém a trava. Não force nem remova a trava com processo ativo; confirme a execução concorrente e aguarde o retry. |
| `remote_invalid` | O preflight não conseguiu provar que o objeto do dia está ausente ou válido, por metadados, autorização, rede ou erro remoto. Não houve upload nem retenção; corrija a causa antes de repetir. |
| `upload_failed` | O upload, a condição de não sobrescrita ou a confirmação remota falhou. A cópia temporária é removida e a retenção não inicia. Verifique R2 e repita sem renomear objetos. |
| `retention_failed` | O novo objeto já foi confirmado, mas listagem ou exclusão falhou. Ele permanece no R2; exclusões anteriores à primeira falha podem ter sido concluídas. Preserve evidência, corrija o acesso/R2 e repita. |

Erros `configuration_invalid`, `copy_failed` e `cleanup_failed` indicam,
respectivamente, configuração inválida, falha na cópia íntegra e falha ao limpar
o temporário. Nenhum deles autoriza apagar objetos ou editar o banco manualmente.

## Chave, metadados e retenção

A chave gerenciada tem formato exato:

```text
production/backups/YYYY/MM/lar-finance-YYYY-MM-DD.sqlite3
```

O objeto usa `Content-Type: application/vnd.sqlite3` e estes metadados S3:

| Metadado | Conteúdo |
|---|---|
| `sha256` | digest hexadecimal de 64 caracteres da cópia local |
| `size` | tamanho decimal em bytes, igual a `ContentLength` |
| `backup-date` | data ISO `YYYY-MM-DD`, coerente com chave e diretórios |
| `retention` | união ordenada de `daily`, `weekly` e `monthly` aplicável ao dia |

A seleção preserva a união dos 14 objetos diários mais recentes, dos 8
domingos mais recentes e dos 12 primeiros dias de mês mais recentes. O objeto
gerenciado mais recente é sempre preservado. Objetos fora de
`production/backups/`, com chave desconhecida ou metadados que não atendam ao
contrato não são elegíveis para exclusão. Uma falha de catálogo interrompe o
preflight antes de qualquer exclusão.

## Validação por download descartável

Faça esta prova somente na tarefa de ativação autorizada. Use credencial
temporária de leitura ou o token operacional no ambiente seguro, sem imprimir os
valores. Defina a chave lógica confirmada no R2 e baixe para diretório efêmero fora
do repositório:

```sh
RESTORE_DIR="$(mktemp -d)"
export RESTORE_DB="$RESTORE_DIR/restore.sqlite3"
export R2_RESTORE_KEY='production/backups/YYYY/MM/lar-finance-YYYY-MM-DD.sqlite3'
test "$RESTORE_DB" != '/app/data/db.sqlite3'
python - <<'PY'
import hashlib
import os
from pathlib import Path

import boto3

target = Path(os.environ['RESTORE_DB']).resolve()
production = Path('/app/data/db.sqlite3').resolve()
if target == production:
    raise SystemExit('refusing production restore path')

client = boto3.client(
    's3',
    endpoint_url=os.environ['R2_BACKUP_ENDPOINT_URL'],
    aws_access_key_id=os.environ['R2_BACKUP_ACCESS_KEY_ID'],
    aws_secret_access_key=os.environ['R2_BACKUP_SECRET_ACCESS_KEY'],
    region_name='auto',
)
bucket = os.environ['R2_BACKUP_BUCKET']
key = os.environ['R2_RESTORE_KEY']
head = client.head_object(Bucket=bucket, Key=key)
client.download_file(bucket, key, str(target))
hasher = hashlib.sha256()
with target.open('rb') as downloaded:
    for chunk in iter(lambda: downloaded.read(1024 * 1024), b''):
        hasher.update(chunk)
digest = hasher.hexdigest()
if target.stat().st_size != head['ContentLength']:
    raise SystemExit('downloaded size mismatch')
if digest != head['Metadata']['sha256']:
    raise SystemExit('downloaded SHA-256 mismatch')
print('download identity verified')
PY
python - "$RESTORE_DB" <<'PY'
import sqlite3
import sys

with sqlite3.connect(sys.argv[1]) as connection:
    result = connection.execute('PRAGMA integrity_check').fetchone()[0]
if result != 'ok':
    raise SystemExit('SQLite integrity check failed')
print('SQLite integrity verified')
PY
SQLITE_PATH="$RESTORE_DB" python manage.py check --deploy --fail-level WARNING
SQLITE_PATH="$RESTORE_DB" python manage.py migrate --plan
SQLITE_PATH="$RESTORE_DB" python manage.py migrate --noinput
SQLITE_PATH="$RESTORE_DB" python manage.py audit_household_integrity
```

**Nunca aponte o restore ou qualquer comando do ensaio para
`/app/data/db.sqlite3`.** Confirme novamente o path antes de cada comando. Depois
de registrar apenas resultado, tamanho, hash e chave lógica, revogue a credencial
temporária e destrua o diretório descartável de acordo com a política de dados. O
objeto R2 deve permanecer intacto.

## Rollback da automação

1. Mantenha ou ative manutenção e pare a imagem candidata.
2. Preserve banco, logs sanitizados e objetos R2; não execute retenção manual.
3. Selecione pelo digest a imagem anterior compatível, que inicia apenas o
   Gunicorn, com uma réplica e um worker.
4. Se não houve mudança ou corrupção do banco, não restaure dados apenas para
   desligar o scheduler. Se houve, siga o rollback completo do EasyPanel com o
   backup verificado.
5. Execute checks, auditoria e smoke checks antes de liberar tráfego.
6. Deixe as variáveis R2 sem consumidor ou remova-as depois da investigação. Não
   apague objetos R2 durante o rollback.

Nenhuma migration foi criada por esta entrega. A imagem anterior e os objetos já
enviados permanecem independentes.

## Matriz de evidência da entrega de código

| Gate | Evidência em 2026-08-13 | Estado/limite |
|---|---|---|
| Testes focados com `-Wd` | 98 testes, sem falha nem `DeprecationWarning` | Aprovado localmente |
| Suíte completa com `-Wd` | 370 testes | Aprovado localmente |
| Cobertura completa | 370 testes; 6.929 statements; 108 misses; 98% | Aprovado, mínimo 90% |
| Ruff oficial | `ruff check . --config pyproject.toml` | Aprovado |
| Django/check/deploy/migrations | checks sem issues; nenhuma migration nova | Aprovado |
| Docker e Supervisor | CI run `31661559845`, build real e smoke com Supervisor 4.3.0 | Aprovado no CI; não prova EasyPanel |
| Secret scan direcionado | nenhum valor atribuído a access key ou secret em arquivo versionado | Aprovado; repetir antes do commit |
| R2/EasyPanel reais | não executados nesta entrega | Aberto; exige autorização separada |

O comando Ruff sem `--config` usa hoje `ruff.toml` e encontra dívida legada fora
do escopo desta documentação. O gate oficial com `pyproject.toml` permanece verde;
as duas configurações devem ser consolidadas em tarefa própria.
