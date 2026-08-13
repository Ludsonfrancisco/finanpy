# Backup automático do SQLite no Cloudflare R2

## Estado da entrega

A automação está codificada e testada no branch
`codex/task-automatic-r2-backup`. A imagem inicia um Gunicorn e um scheduler pelo
Supervisor. O scheduler tenta um backup por dia, às `03:00` em
`America/Sao_Paulo`; depois de falha, tenta novamente em uma hora. Um restart
depois do horário agenda a tentativa do dia imediatamente. A cobertura diária usa
a data local calculada no início da tentativa, enquanto o retry conta uma hora a
partir da conclusão. Assim, uma tentativa iniciada antes da meia-noite não marca o
dia seguinte como concluído.

**Ainda não houve ativação no EasyPanel, execução desta automação contra o R2
real, restart operacional nem restauração de um objeto produzido por ela.** O
backup R2 manual restaurado em 2026-08-12 é uma evidência anterior e não substitui
essa prova. Ativação é uma tarefa separada, depois de review, merge em `main` e
autorização explícita.

## Fluxo e invariantes

1. Adquire uma trava não bloqueante ao lado do banco.
2. Ainda sob a trava, procura resíduos próprios com nome exato no diretório
   temporário. Remove somente arquivos regulares, não simbólicos e validados; se
   a limpeza falhar, retorna `cleanup_failed` antes de acessar o R2.
3. Calcula a chave do dia no timezone configurado e verifica se ela já existe.
4. Se o objeto válido já existir, pula cópia/upload, mas repete a retenção antes
   de concluir `already_exists`.
5. Quando o objeto não existe, cria uma cópia temporária pela API de backup do
   SQLite e executa
   `PRAGMA integrity_check`.
6. Calcula tamanho e SHA-256, envia com `If-None-Match: *` e confirma o objeto por
   `HeadObject`.
7. Lista e valida todo o catálogo gerenciado antes de calcular retenção.
8. Exclui somente objetos gerenciados expirados, do mais antigo para o mais novo.
9. Tenta remover a cópia temporária e libera a trava ao sair. Se uma falha
   primária e o `unlink` falharem juntos, expõe `cleanup_failed` e preserva a falha
   primária como causa sanitizada; a próxima tentativa tenta recuperar o resíduo
   antes de qualquer operação remota.

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
| `already_exists` | A chave gerenciada do dia já existe e seus metadados são válidos. Nenhuma cópia, upload ou sobrescrita ocorre; a retenção é repetida e precisa terminar antes do sucesso. |
| `lock_busy` | Outra execução detém a trava. Não force nem remova a trava com processo ativo; confirme a execução concorrente e aguarde o retry. |
| `remote_invalid` | O preflight não conseguiu provar que o objeto do dia está ausente ou válido, por metadados, autorização, rede ou erro remoto. Não houve upload nem retenção; corrija a causa antes de repetir. |
| `upload_failed` | O upload, a condição de não sobrescrita ou a confirmação remota falhou. A limpeza temporária é tentada e a retenção não inicia. Se essa limpeza também falhar, o resultado exposto será `cleanup_failed`, com `upload_failed` preservado como causa sanitizada; a tentativa seguinte tentará recuperar o resíduo antes de acessar o R2. |
| `retention_failed` | O objeto do dia já está confirmado, novo ou preexistente, mas listagem ou exclusão falhou. Ele permanece no R2; exclusões anteriores à primeira falha podem ter sido concluídas. Preserve evidência, corrija o acesso/R2 e repita: a retenção será tentada sem reupload. |

Erros `configuration_invalid`, `copy_failed` e `cleanup_failed` indicam,
respectivamente, configuração inválida, falha na cópia íntegra e falha ao limpar
o temporário. `cleanup_failed` bloqueia operações remotas quando detectado no
início; durante outra falha, preserva a causa técnica sanitizada. Nenhum deles
autoriza apagar objetos ou editar o banco manualmente.

### Resíduo temporário depois de falha

Uma nova tentativa limpa automaticamente um resíduo próprio validado, sob a mesma
trava, antes de acessar o R2. Use o procedimento manual abaixo somente se
`cleanup_failed` persistir.

Inspecione ou remova um resíduo somente depois de colocar o serviço em manutenção
e pará-lo pelo mecanismo suportado do EasyPanel. Confirme na UI, no status e nos
logs da plataforma que o container e seus processos `web` e `backup-scheduler`
estão realmente parados e que não existe execução manual de `backup_to_r2`. Não
presuma que maintenance mode, sozinho, interrompe processos.

Somente depois desse stop comprovado, use um one-off ou console suportado pelo
EasyPanel que monte o mesmo `/app/data` sem iniciar a aplicação. Informe um único
path absoluto observado, sem glob nem loop, valide-o e remova somente esse arquivo:

```sh
export R2_TEMP_CANDIDATE='/app/data/backups/.lar-finance-r2-<identificador>.sqlite3'
python - <<'PY'
import os
import re
from pathlib import Path

temporary_directory = Path('/app/data/backups').resolve()
production_database = Path('/app/data/db.sqlite3').resolve()
provided_path = Path(os.environ['R2_TEMP_CANDIDATE'])
if not provided_path.is_absolute() or provided_path.is_symlink():
    raise SystemExit('refusing non-absolute or symbolic temporary path')
candidate = provided_path.resolve(strict=True)
valid_name = re.fullmatch(
    r'\.lar-finance-r2-[A-Za-z0-9_-]+\.sqlite3',
    candidate.name,
)
if (
    candidate.parent != temporary_directory
    or candidate == production_database
    or valid_name is None
    or not candidate.is_file()
):
    raise SystemExit('refusing unvalidated temporary path')
candidate.unlink()
print('validated temporary file removed')
PY
```

Nunca substitua o path por `/app/data/db.sqlite3`, nunca remova o diretório
`/app/data/backups` inteiro e nunca execute essa limpeza com scheduler ou backup
manual ativo. Se não for possível provar que o container e os processos estão
parados, não apague nada: marque o procedimento como `[INVESTIGAR]` e escale ao
operador da plataforma. Se a validação recusar o path, investigue em vez de
contorná-la.

Depois da inspeção, reinicie ou faça redeploy normalmente pela UI do EasyPanel,
sem command override, para usar o `CMD` Supervisor da imagem. Confirme nos logs e
no status da plataforma que `web` e `backup-scheduler` voltaram saudáveis antes de
sair da manutenção.

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
| Testes focados com `-Wd` | 104 testes, sem falha nem `DeprecationWarning` | Aprovado localmente |
| Suíte completa com `-Wd` | 376 testes | Aprovado localmente após os fixes desta wave |
| Cobertura completa | 376 testes; 7.062 statements; 111 misses; 98% | Aprovado, mínimo 90% |
| Ruff oficial | `ruff check . --config pyproject.toml` | Aprovado |
| Django/check/deploy/migrations | checks sem issues; nenhuma migration nova | Aprovado |
| Docker e Supervisor | CI run `31663696379` no head `5d4e461`, build real e smoke com Supervisor 4.3.0 | Aprovado nesse head; CI pós-fix ainda pendente e não prova EasyPanel |
| Secret scan direcionado | nenhum valor atribuído a access key ou secret em arquivo versionado | Aprovado na matriz final e no conteúdo commitado |
| R2/EasyPanel reais | não executados nesta entrega | Aberto; exige autorização separada |

O comando Ruff sem `--config` usa hoje `ruff.toml` e encontra dívida legada fora
do escopo desta documentação. O gate oficial com `pyproject.toml` permanece verde;
as duas configurações devem ser consolidadas em tarefa própria.
