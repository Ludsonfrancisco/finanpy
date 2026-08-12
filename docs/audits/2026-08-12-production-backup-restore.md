# Backup real off-host e ensaio de restauração

Data: 2026-08-12

Escopo: gerar uma cópia consistente do SQLite usado no EasyPanel, enviá-la para
armazenamento privado fora do servidor e provar a restauração com o código atual.
Nenhuma linha financeira, email, credencial ou outro dado pessoal foi consultado
ou registrado. O arquivo foi tratado como bytes opacos.

## Routing da tarefa

- Modelo recomendado: `gpt-5.6-sol`
- Intensidade recomendada: `high`
- Motivo: operação sobre backup financeiro real, credenciais temporárias,
  migrations e evidência de recuperação.
- Identidade do modelo realmente executado: não verificável no ambiente atual.

## Ambiente comprovado

- EasyPanel `v2.32.2`.
- Aplicação `financeiro/finanpy` com uma réplica ativa.
- SQLite em `/app/data/db.sqlite3`.
- Volume Docker legado `financeiro_sqlite_data` montado em `/app/data`.
- Cloudflare R2, bucket privado `lar-finance-backups`, classe `Standard` e acesso
  público desabilitado.
- Provedor `Lar Finance R2` cadastrado no EasyPanel com token de conta limitado a
  leitura/gravação de objetos somente nesse bucket.

## Backup e transferência

1. A API de backup do SQLite gerou uma cópia consistente dentro do volume.
2. `PRAGMA integrity_check` passou na origem e na cópia.
3. Artefato gerado: `lar-finance-20260812T201212Z.sqlite3`.
4. Tamanho: `180224` bytes.
5. SHA-256:
   `2897ad1e230119771966857727ff66236cf23f732145ab3f4ac08bc15d4a9c65`.
6. O objeto foi enviado por HTTPS para
   `production/2026-08-12/lar-finance-20260812T201212Z.sqlite3`.
7. O envio usou URL S3 pré-assinada com validade de 15 minutos. O token temporário
   foi revogado e o script que continha a URL foi excluído logo após HTTP `200`.
8. O painel R2 confirmou o objeto em `Standard`, com `180,22 kB`.

Segundo a [documentação de segurança do R2](https://developers.cloudflare.com/r2/reference/data-security/),
objetos e metadados são criptografados automaticamente em repouso com AES-256 e
o transporte usa TLS.

## Ensaio de restauração

O mesmo objeto foi baixado com token temporário somente leitura, também revogado
imediatamente. A restauração ocorreu em diretório descartável fora do repositório.

| Verificação | Resultado |
|---|---|
| Bytes baixados | `180224` |
| SHA-256 no destino | idêntico ao hash da origem |
| SQLite antes das migrations | `integrity_check=ok` |
| `check --deploy --fail-level WARNING` | 0 issues |
| `migrate --plan` | migrations novas identificadas corretamente |
| `migrate --noinput` | todas aplicadas sem erro |
| Migrations registradas após restauração | `40` |
| Auditoria do Lar | 12 famílias com contagem zero; `integrity_status=ok` |
| SQLite após migrations | `integrity_check=ok` |

A restauração migrada foi somente uma cópia. O banco em produção não foi
substituído, migrado ou reiniciado por esta tarefa.

## Limitação encontrada no EasyPanel

O job nativo de backup de volume falhou antes de ler dados. Ele calculou o caminho
`/etc/easypanel/projects/financeiro/finanpy/volumes/sqlite_data`, que não existe
nesta instalação. O volume legado está fisicamente sob o volume Docker
`financeiro_sqlite_data`. O job com falha foi removido e não existe agenda ativa.

Consequência: o bucket e o provedor R2 estão válidos, mas o agendamento automático
exige uma tarefa própria para escolher e testar uma destas alternativas:

- migrar o volume legado para o layout suportado pelo EasyPanel;
- executar `backup_sqlite` e upload S3 por um runner dedicado com segredo gerenciado;
- migrar para PostgreSQL e usar o mecanismo de backup do banco.

Não automatizar cópia direta do arquivo SQLite enquanto ele estiver aberto para
escrita. A automação deve continuar usando a API de backup do SQLite.

## Limpeza e estado final

- tokens temporários de upload e download revogados;
- scripts temporários do EasyPanel excluídos;
- cópia transitória dentro do volume removida depois da prova off-host;
- restauração local e sua cópia de trabalho destruídas;
- job nativo incompatível removido;
- objeto externo preservado no bucket privado;
- token persistente do provedor permanece ativo, limitado exclusivamente ao
  bucket `lar-finance-backups`.

## Resultado e gates restantes

**PASS:** existe backup real off-host, com hash comprovado e restauração isolada
bem-sucedida usando o código atual.

Isto fecha o gate específico de backup externo restaurável. Ainda não autoriza o
deploy da imagem atual nem encerra o runbook de produção. Permanecem:

- implantar a imagem atual no EasyPanel com migrations controladas;
- provar persistência após restart do serviço e do host;
- validar proxy, TLS, rate limit e smoke checks reais;
- definir retenção e automatização do backup R2 em tarefa separada.
