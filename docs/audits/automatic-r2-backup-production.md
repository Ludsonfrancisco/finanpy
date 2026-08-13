# Auditoria da ativação do backup automático no R2

Data da execução: `2026-08-13`, fuso `America/Sao_Paulo`.

Escopo: ativar no EasyPanel o backup diário do SQLite para um bucket privado do
Cloudflare R2, provar idempotência após reinício e restaurar o objeto criado em uma
cópia descartável. Nenhuma credencial, identificador de conta, PII ou conteúdo
financeiro foi registrado.

## Resultado

`PASS` para a ativação do backup automático e para a restauração isolada.
`DONE_WITH_CONCERNS` para a Task 7 completa: rate limit, rollback imutável e duas
evidências de preflight/deploy permanecem abertos; o download off-host usou uma
sessão administrativa, não credencial temporária read-only. Nenhuma dessas
divergências foi tratada como aprovada.

- EasyPanel `v2.33.1`.
- Fonte implantada: `Ludsonfrancisco/finanpy`, branch `main`, commit
  `0d85999f4e66290fa06484d802d08fbb310ad164`.
- Uma réplica, Supervisor como PID 1, Gunicorn com um worker e um único
  `run_backup_scheduler`.
- SQLite persistente em `/app/data/db.sqlite3`.
- Proxy publicado na porta `8020` e encaminhado ao Gunicorn na porta `8000`.
- Aplicação pública: `https://financeiro.palmbook.online`.
- Bucket R2 privado `lar-finance-backups`, classe `Standard`, com token operacional
  Object Read & Write restrito ao bucket e armazenado somente no EasyPanel.
- Agenda: `03:00`, `America/Sao_Paulo`; prefixo gerenciado `production`.

## Preflight e deploy

O estado inicial não era reproduzível: apontava para outro repositório, uma branch
inexistente, migrations acopladas ao start, dois workers, porta interna `8020` e
command override que ignorava o Supervisor. Antes da mudança:

1. foi criada uma cópia SQLite consistente no volume, com modo `0600` e
   `PRAGMA integrity_check=ok`;
2. o objeto R2 anterior, fora do namespace gerenciado pela nova retenção, foi
   confirmado como backup restaurável histórico;
3. o repositório foi corrigido para a origem oficial e `main`;
4. as sete variáveis `R2_BACKUP_*` foram cadastradas, sem registrar valores
   secretos;
5. `TRUST_PROXY_HEADERS=True` foi habilitado para o proxy controlado pelo
   EasyPanel/Cloudflare;
6. o command override foi removido, a sobreposição de réplicas foi desativada e o
   mapeamento foi alinhado para `8020 -> 8000`;
7. o container passou a usar o `CMD` versionado do Dockerfile, que inicia o
   Supervisor.

O espaço livre do volume não foi registrado antes do deploy. A cópia pré-deploy
foi criada e verificada, mas essa ausência de evidência continua sendo uma
divergência do preflight, não um gate retroativamente aprovado.

Após o deploy:

- `PRAGMA integrity_check=ok` no banco real;
- 40 migrations registradas;
- `audit_household_integrity`: 12 famílias de inconsistência com contagem zero e
  `integrity_status=ok`;
- `check --deploy --fail-level WARNING`: zero issues;
- um Supervisor, um scheduler e um Gunicorn com exatamente um worker;
- health interno pelo proxy confiável: HTTP `200`;
- dez verificações públicas consecutivas, em intervalos de quatro segundos, com
  HTTP `200` em `/api/v1/health/` e `/login/`.

O estado final comprova schema atual e ausência de migrations pendentes nas cópias
restauradas. Não foi preservado um log sanitizado que demonstre a ordem do comando
`migrate` durante o deploy; essa evidência operacional permanece aberta.

Durante a operação, o serviço ficou no estado `Stopped` depois de um acionamento
pela UI. O botão de deploy apenas construiu a imagem e não iniciou um serviço já
parado. O serviço foi iniciado explicitamente pelo EasyPanel; isso foi recuperação
de um estado parado, não o restart de idempotência. Depois da estabilização e dos
smokes, houve um único restart intencional para a prova descrita abaixo.

## Objeto e idempotência

Objeto produzido:

```text
production/backups/2026/08/lar-finance-2026-08-13.sqlite3
```

Evidência remota:

| Campo | Resultado |
|---|---|
| Classe | `Standard` |
| Content-Type | `application/vnd.sqlite3` |
| Tamanho | `352256` bytes |
| SHA-256 | `87acbc388066ce51f02ae3ed340e051b7e735f3a64c191d912689a84334fdfaf` |
| `backup-date` | `2026-08-13` |
| `retention` | `daily` |
| Criação | `2026-08-13 09:42:17 BRT` |

Uma execução manual posterior retornou `already_exists`, com o mesmo tamanho e
hash e sem exclusão. Depois de um restart controlado, o scheduler também retornou
`already_exists` e entrou em espera para a próxima agenda. A listagem permaneceu
com uma única chave do dia; não houve sobrescrita nem duplicação.

## Restaurações descartáveis

Primeiro, foi gerada no servidor uma URL assinada de leitura com validade de 60
segundos. A URL não foi impressa nem persistida e expirou automaticamente. O objeto
foi baixado para `/app/data/backups/restore-rehearsal-20260813.sqlite3`, nunca para
o path do banco real. Essa prova validou o download, mas não era off-host porque a
cópia estava no mesmo servidor.

Após a revisão, o mesmo objeto foi baixado diretamente pelo painel autenticado do
Cloudflare R2 para o Windows, fora do servidor e fora do repositório. A sessão do
painel não era uma credencial temporária somente leitura; portanto, a identidade
off-host foi comprovada, mas o requisito de menor privilégio do brief não foi.
Resultados na cópia:

- tamanho `352256` bytes, igual ao metadata remoto;
- SHA-256 idêntico ao metadata remoto;
- `PRAGMA integrity_check=ok`;
- `migrate --plan`: nenhuma operação planejada;
- `migrate --noinput`: nenhuma migration a aplicar, exit `0`;
- `audit_household_integrity`: 12 famílias zeradas e exit `0`;
- `check --deploy --fail-level WARNING`: exit `0`.

O banco de produção não foi substituído ou alterado pelos ensaios. Ao final, as
cópias restauradas, o backup pré-deploy e os artefatos de diagnóstico foram
removidos por paths exatos. A cópia do Windows foi removida permanentemente também
da Lixeira. O objeto R2 foi preservado e o banco real continuou íntegro.

## Configuração sanitizada

O ambiente final possui as sete chaves oficiais `R2_BACKUP_*`, sem aliases antigos,
sem duplicatas e sem valores expostos. O token persistente necessário ao scheduler
permanece apenas no secret store do EasyPanel. Nenhum token temporário persistente
foi criado para o download. O download off-host usou a sessão administrativa já
autenticada do painel e essa divergência permanece registrada abaixo.

## Riscos residuais

- `[INVESTIGAR]` O EasyPanel acompanha a branch mutável `main` e não apresentou no
  fluxo usado um digest de imagem selecionável. O SHA do código está registrado,
  mas rollback imutável de imagem ainda precisa ser materializado e ensaiado.
- `[INVESTIGAR]` Confirmar e documentar rate limit persistente para `POST /login/`
  na topologia Cloudflare Tunnel + EasyPanel.
- `[INVESTIGAR]` O espaço livre não foi registrado no preflight e não existe log
  sanitizado da ordem de `migrate` durante o deploy. Repetir e registrar ambos
  antes de declarar o runbook integralmente aprovado.
- `[INVESTIGAR]` Repetir o download off-host com credencial temporária somente
  leitura e revogá-la; a prova atual usou a sessão administrativa do painel.
- `[INVESTIGAR]` Existe credencial R2 anterior à ativação. Confirmar todos os seus
  consumidores antes de revogá-la; nunca revogar por suposição.
- Alertas externos para falha ou ausência do backup ainda não existem. Os logs
  estruturados são a evidência disponível até a task de monitoramento.
- SQLite continua limitado a uma réplica e um worker; a evolução incremental para
  PostgreSQL permanece no roadmap.

## Decisão

A automação diária R2 está **ativa** e o objeto gerado foi restaurado com sucesso
no servidor e fora dele. A Task 7 permanece `DONE_WITH_CONCERNS`, sem aceite global
de produção, até decisão ou resolução explícita dos gates residuais acima. O
resultado não autoriza migração de banco ou nova sprint sem aprovação separada.
