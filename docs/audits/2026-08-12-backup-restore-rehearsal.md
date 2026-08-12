# Ensaio isolado de backup e restauração

Data: 2026-08-12

Escopo: validar o mecanismo atual de backup SQLite e o ciclo de restauração em
uma base sintética, isolada e descartável fora do repositório.

Servidor EasyPanel, banco real, volume de produção e dados financeiros reais não
foram acessados.

## Routing da tarefa

**Modelo recomendado:** `gpt-5.6-sol`

**Intensidade recomendada:** `high`

**Motivo:** restauração envolve integridade financeira, migrations e risco de uma
evidência incompleta autorizar indevidamente mudanças no banco real.

**Consumo esperado:** Alto

**Ferramentas necessárias:** Django, SQLite, SHA-256 e filesystem temporário

## Limite da evidência

O `db.sqlite3` local do workspace tinha `0 bytes`; portanto, não foi usado como
prova. O ensaio criou um banco sintético no schema atual e não afirma ter validado
o backup do EasyPanel.

Esta evidência comprova:

- criação consistente do backup pela API SQLite;
- verificação de integridade do arquivo gerado;
- transferência byte a byte entre diretórios isolados;
- abertura da restauração pela aplicação atual;
- compatibilidade de migrations;
- preservação de relações e resultados sintéticos conhecidos;
- aprovação da auditoria de integridade do Lar.

Esta evidência **não** comprova:

- cópia para outro computador, disco ou serviço de armazenamento;
- criptografia em trânsito ou em repouso;
- permissões equivalentes às do servidor;
- backup do banco real do EasyPanel;
- persistência após restart do container/host;
- Recovery Time Objective ou Recovery Point Objective reais.

## Procedimento executado

1. Criado diretório temporário isolado fora do repositório.
2. Criado banco SQLite sintético pelas migrations atuais.
3. Inserido fixture sem PII real: um usuário `.invalid`, um Lar, três
   responsáveis, uma conta, uma categoria e uma transação.
4. Executado `audit_household_integrity` na origem.
5. Gerado backup novo com `manage.py backup_sqlite`.
6. Copiado backup para diretório `offhost-simulated` e depois para outro caminho
   absoluto de restauração.
7. Comparado SHA-256 das três cópias.
8. Executados na restauração:
   - `check --deploy --fail-level WARNING`;
   - `migrate --plan`;
   - `migrate --noinput`;
   - `audit_household_integrity`;
   - asserts de contagem, saldo, relações do Lar e ledger de sync.
9. Executados os testes focados de backup e os gates estáticos.
10. Destruída a árvore temporária depois da coleta desta evidência técnica.

## Evidências técnicas

| Verificação | Resultado |
|---|---|
| Backup command | `Backup verified` |
| Tamanho das três cópias | 352.256 bytes cada |
| SHA-256 das três cópias | idêntico |
| Hash do fixture sintético | `E08B54D8ECF7100FFF44C693EC9118021E8CA66F435A896DB2C46380D7D9FA44` |
| `check --deploy` | 0 issues |
| Plano de migration | nenhuma operação planejada |
| Aplicação de migrations | nenhuma migration pendente |
| Auditoria do Lar | 12 checks com contagem zero; `integrity_status=ok` |
| Registros sintéticos | 1 usuário, 1 Lar, 1 membership, 3 owners, 1 conta, 1 categoria, 1 transação |
| Saldo restaurado | resultado esperado de `75.00` confirmado |
| Relações financeiras | conta, categoria, owner e transação no mesmo Lar |
| Sync ledger | mudança sintética presente após restauração |
| Testes focados | 4/4 passaram |
| Ruff `core` | passou |
| Django check | passou |
| Migration check | nenhuma mudança detectada |

O hash identifica somente o artefato sintético descartado. Não deve ser usado
como referência para qualquer backup futuro ou real.

## Resultado

O mecanismo local de backup/restauração funciona para o fixture sintético e o
schema atual. Isso reduz risco técnico, mas não libera migration nem deploy no
EasyPanel.

## Próximo gate obrigatório

Com autorização e acesso operacional:

1. colocar aplicação real em manutenção;
2. gerar backup verificado do volume real;
3. transferir de forma criptografada para armazenamento off-host real;
4. comparar SHA-256 no destino;
5. restaurar em ambiente isolado usando a mesma imagem candidata;
6. repetir checks, migrations, auditoria e smoke tests sem registrar PII;
7. destruir a restauração conforme política aprovada.

Até esse ciclo real terminar, os bloqueios de produção permanecem.

## Auditoria do roteamento

**Usado:** identidade exata do modelo principal não verificável no ambiente
atual; routing recomendado `gpt-5.6-sol/high`.

**Por que:** exigiu distinguir prova sintética de prova operacional e validar
integridade em várias camadas.

**Resultado:** Suficiente

**Poderia usar nível menor:** Não

**Recomendação para tarefas semelhantes:** `gpt-5.6-sol/high`

**Escalonamentos:** Nenhum.

**Tokens reais:** não disponíveis.
