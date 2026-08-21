# Ensaio do deploy fail-fast e versão observável

Data: 2026-08-21

Escopo: R1.4 Task 6

Resultado: **DONE_WITH_CONCERNS**

Esta auditoria separa prova local, prova da CI/GHCR e prova do EasyPanel. Nenhum
comando usou o banco de produção, nenhuma configuração externa foi alterada,
nenhuma tag foi criada e nenhum objeto R2 foi excluído ou substituído.

## Preflight

- worktree e branch: `codex/r1-4-fail-fast-deploy`;
- HEAD, base obrigatória e branch remota:
  `2584fa7db5e9ee9fa158cdfce54d3b2b24ef4a9d`;
- árvore limpa antes da matriz e `git fetch --prune origin` concluído;
- Python, Flutter 3.47.0, Dart 3.13.0, Git, GitHub CLI e rclone disponíveis;
- Docker e Podman ausentes no Windows e no WSL2 Ubuntu;
- as sete variáveis R2 verificadas somente por presença estavam ausentes:
  `R2_BACKUP_ENDPOINT_URL`, `R2_BACKUP_ACCESS_KEY_ID`,
  `R2_BACKUP_SECRET_ACCESS_KEY`, `R2_BACKUP_BUCKET`, `R2_BACKUP_PREFIX`,
  `R2_BACKUP_TIME` e `R2_BACKUP_TIME_ZONE`;
- o rclone tinha arquivo de configuração, mas zero remotes configurados.

Nenhum valor de segredo foi lido ou registrado.

## Matriz local

| Gate | Resultado observado |
|---|---|
| `python -m ruff check . --config pyproject.toml` | exit `0` |
| `python manage.py check` | exit `0`, zero issues |
| `python manage.py check --deploy --fail-level WARNING` | exit `0`, zero issues |
| `python manage.py makemigrations --check --dry-run` | exit `0`, nenhuma alteração |
| `python -Wd manage.py test` | exit `0`, 581 testes em 201,752 s; zero `DeprecationWarning` observado |
| `coverage erase` | exit `0` |
| `coverage run manage.py test` | exit `0`, 581 testes em 226,286 s |
| `coverage report --fail-under=90` | exit `0`, 12.395 statements, 592 misses, 95% |
| `dart format --output=none --set-exit-if-changed .` | primeira execução exit `1`: dependências ainda não resolvidas, 74 warnings e 22 mudanças aparentes; o comando não gravou arquivos |
| repetição do formato após `flutter pub get` efetuado pelo gate seguinte | exit `0`, 156 arquivos, zero mudanças |
| `flutter analyze` | exit `0`, zero issues |
| `flutter test` | exit `0`, 374 testes |
| `flutter build windows --release ...` | primeira execução exit `1`, `MSB3491` por caminho do worktree maior que 260 caracteres |
| build Windows pela unidade curta | primeira tentativa exit `1`, cache CMake misturava os dois paths; após `flutter clean`, nova resolução e rebuild pela unidade curta, exit `0` |
| `flutter build apk --release ...` | exit `0`, APK de 61,7 MB |
| `git diff --check` antes das edições | exit `0` |

Os dois gates com falha inicial foram investigados sem mudar código. O formato
passou com o mesmo SDK fixado depois da resolução de dependências. O build
Windows passou depois de limpar somente artefatos gerados e usar um path curto.
Os três registrantes tocados pelo Flutter apenas por normalização de fim de linha
foram restaurados; nenhuma alteração em `mobile/` integra esta task.

## Ensaio fail-fast em SQLite descartável

Como não havia runtime de container, o ensaio literal da imagem candidata não
foi executado. O `deploy/start.sh` executado no host pelo Git Bash foi somente
um **fallback local do fluxo de comandos**: ele não constitui prova da imagem,
do filesystem do container, do mount em `/app/data` nem de `container_exit`.
Esse fallback usou uma cópia SQLite criada somente até `households.0001`, em
diretório efêmero fora do repositório. As credenciais R2 foram
intencionalmente removidas do ambiente.

| Verificação | Resultado local |
|---|---|
| criação do SQLite antigo | exit `0` |
| `start.sh` no host | exit `1` antes do Supervisor |
| health local em `127.0.0.1:8000` | inalcançável |
| tamanho antes/depois | 147.456 bytes, idêntico |
| SHA-256 antes/depois | prefixo sanitizado `e1b9356fecb1`, idêntico |
| `django_migrations` antes/depois | 16/16 |
| fingerprint das migrations antes/depois | prefixo sanitizado `9a7f57cb7c27`, idêntico |
| código de erro | `configuration_invalid`, etapa `backup` |

Isso comprova apenas que, no host, o fluxo de comandos interrompeu antes de
backup, migration e Supervisor e preservou a cópia. Não comprova o
`container_exit`, o mount, o health inalcançável da imagem candidata nem o
comportamento com a imagem empacotada, porque Docker/Podman estavam ausentes.

## Fallback local de restauração e rollback

O caminho documentado de R2 exige `HeadObject`, `download_file`, comparação de
`ContentLength`/metadata SHA e `PRAGMA integrity_check`. Sem credenciais e sem
remote configurado, nenhum objeto foi listado ou baixado.

Como fallback estritamente local, uma base sintética com 50 migrations foi
criada em diretório descartável; `backup_sqlite` produziu um arquivo local
consistente e ele foi copiado para outro path. Esse procedimento não acessou nem
simulou um objeto R2. A fonte e a restauração tinham 589.824 bytes e SHA-256 com
o mesmo prefixo sanitizado `fbf429db3692`. A cópia retornou
`PRAGMA integrity_check=ok`, `migrate --plan` sem operações, 12 famílias da
auditoria com contagem zero e `integrity_status=ok`.

`prepare_deploy` terminou com exit `0` nessa cópia. Um `runserver` temporário,
usando somente a restauração, respondeu HTTP 200 com exatamente:

```json
{"status":"ok","api_version":"v1","version":"2584fa7db5e9ee9fa158cdfce54d3b2b24ef4a9d"}
```

O processo foi encerrado e a porta ficou sem listener. `backup_sqlite` mais
`runserver` valida somente comandos e invariantes locais: não comprova
`HeadObject`, download, metadata ou hash remoto do R2 e não iniciou a imagem
anterior. A Task 7 deve executar esse ciclo literal no ambiente autorizado:
`HeadObject`, download sem alterar o objeto, comparação de `ContentLength`,
metadata SHA e hash local, `PRAGMA integrity_check` e startup da imagem anterior
somente sobre a cópia restaurada.

## Evidência da CI e fronteira GHCR

A execução GitHub Actions `32529705321` terminou com `success` no SHA
`2584fa7db5e9ee9fa158cdfce54d3b2b24ef4a9d`. O job Django construiu a imagem,
verificou Supervisor 4.3.0 e passou o smoke de startup da imagem construída,
health com SHA e topologia de três processos: `web`, `backup-scheduler` e
`import-preview-purge`. Os jobs Flutter de formato/análise/testes, Windows/MSIX,
Android e iOS também passaram.

O job cujo nome no workflow é `Publish immutable GHCR image` foi **skipped**,
porque a execução foi um push de branch. Esse nome de job não comprova uma
política de imutabilidade no registry. O contrato de release começa pela tag
versionada/controlada
`ghcr.io/ludsonfrancisco/finanpy:sha-<sha Git de 40 caracteres>`, mas nenhuma tag
desse candidato foi publicada nesta task. A identidade imutável é o digest OCI,
que também não foi resolvido nem observado.

## Decisão de responsabilidade do ensaio

Em 21/08/2026, o usuário autorizou adaptar pragmaticamente a responsabilidade
entre as tasks sem alterar o brief original: a Task 6 encerra com prova
local, prova da CI e runbook honesto; o ensaio literal da imagem candidata com
SQLite antigo, a verificação/restauração R2, o startup da imagem anterior e a
resolução do digest OCI tornam-se gates obrigatórios da Task 7 no ambiente que
dispõe do runtime e das credenciais. Esta decisão não converte os fallbacks
locais em prova de container ou R2.

## Fonte operacional única

- startup: preflight → backup R2 opcional → `migrate` → auditoria →
  `collectstatic` → Supervisor;
- topologia: uma réplica, um worker Gunicorn e dois schedulers;
- health: exatamente `status`, `api_version`, `version`;
- release: tag `sha-<40-char-sha>` versionada/controlada; digest OCI é a
  identidade imutável que a Task 7 deve resolver e registrar;
- rollback: manter manutenção, parar todos os processos, preservar o banco que
  falhou, validar a restauração staged fora do path ativo, promover no mesmo
  filesystem e selecionar a imagem anterior por digest quando suportado;
- nunca executar migration manual em paralelo nem sobrescrever o command da
  imagem.

## Gates abertos para a Task 7

R1.4 permanece em andamento. Com autorização explícita, a Task 7 ainda precisa:

1. criar a tag versionada/controlada que aciona a publicação GHCR e confirmar a
   imagem `sha-<40-char-sha>`;
2. resolver e registrar o digest OCI `sha256:<64 hex>` da tag. Se o EasyPanel
   aceitar referência por digest, selecionar
   `ghcr.io/ludsonfrancisco/finanpy@sha256:<digest>`; se não aceitar, registrar
   a associação tag→digest e verificá-la imediatamente antes e depois do deploy;
3. executar a imagem candidata com SQLite antigo descartável e credenciais R2
   ausentes, comprovando todos os asserts literais do brief;
4. executar `HeadObject`, baixar o objeto R2 selecionado sem alterá-lo e verificar
   `ContentLength`, metadata SHA, hash local e `PRAGMA integrity_check`;
5. iniciar a imagem anterior somente contra a restauração descartável e provar
   health/auditoria;
6. selecionar a imagem candidata no EasyPanel sem sobrescrever o entrypoint;
7. confirmar uma réplica, um worker, dois schedulers, health com o SHA exato e
   executar o rollback manual seguro do runbook.

Até esses gates passarem, não há prova de publicação GHCR nem de deploy R1.4 no
EasyPanel.
