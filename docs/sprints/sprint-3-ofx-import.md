# Sprint 3 — Importação OFX Nubank

## Resultado

O piloto privado de importação manual está disponível no backend. Ele aceita
OFX BRL estruturalmente compatível com os arquivos Nubank cobertos pelos testes,
nos produtos `bank_account` e
`credit_card`. O arquivo é enviado, analisado em prévia e só altera o ledger
depois da confirmação explícita.

## Entregue

- modelos `ImportBatch`, `ImportRecord`, `ImportAccountLink` e
  `SourceReference`, com limites de Lar também protegidos por triggers SQLite;
- parser do perfil OFX que aceita os formatos OFX 1.x SGML e XML esperados pelo
  piloto, exige `CURDEF=BRL` e rejeita texto, valor, precisão ou campos
  estruturais que não cabem no modelo persistido;
- arquivo limitado a 10 MiB, hash SHA-256 por Lar, prévia válida por até 24h e
  descarte do conteúdo OFX bruto após o parse;
- associação automática por identificador OFX já vinculado ou parada para
  vínculo explícito a uma conta do mesmo Lar; o responsável é o da conta;
- deduplicação por arquivo repetido, FITID por conta/provedor e aviso por
  fingerprint semelhante; avisos exigem confirmação humana;
- confirmação atômica que cria transações, referências de origem e mudanças de
  sincronização; receita e despesa usam categorias `Não categorizado` separadas
  por Lar;
- API privada com cinco rotas: criar prévia, consultar, vincular conta,
  confirmar e cancelar. As respostas resumidas não expõem linhas, valores ou
  descrições do arquivo;
- ensaio de migration SQLite que instala o schema `imports`, verifica
  constraints/triggers e faz rollback completo do app sem remover `Account` ou
  `Transaction` existentes.
- cancelamento remove imediatamente as linhas normalizadas e conserva o recibo
  técnico do lote. Expirados são limpos de modo idempotente ao criar/consultar
  importações, pelo comando `python manage.py purge_import_previews` e pelo
  processo independente do Supervisor, que acorda na próxima expiração com
  intervalo limitado a uma hora.

## Limites conscientes

Não há suporte a CSV, outros bancos, Open Finance, limite de cartão, fatura
futura, parcelas, empréstimos, categorização inteligente ou Flutter. O
importador não infere campos ausentes no OFX e não faz conciliação de
transferências, estornos ou faturas.

## Operação e rollback

O deploy deve executar `python manage.py migrate` antes de expor a versão que
usa as rotas. Para remover a funcionalidade em ambiente de ensaio, faça backup
validado, interrompa novas importações e reverta as migrations `imports`;
`imports.0001` para baixo remove apenas as tabelas e triggers `imports`, mas os
dados de lotes confirmados e seus registros associados são removidos. Não usar
rollback de migration em produção como forma de desfazer lançamentos já
confirmados: use o procedimento financeiro de correção/auditoria a definir.

## Riscos restantes

- Os OFX cobertos não trazem identificador de instituição confiável. Portanto,
  `provider=nubank` identifica o perfil selecionado, não prova a origem do
  arquivo. O parser valida BRL e compatibilidade estrutural; outro banco com a
  mesma estrutura pode ser aceito. Origem verificável exige marcador futuro.
- A garantia operacional de retenção depende do processo Supervisor
  `import-preview-purge`, que executa imediatamente no start, acorda para a
  expiração mais próxima e limita qualquer espera a uma hora. O deploy mantém
  uma réplica, um worker web e os schedulers independentes.
- SQLite continua limitado a uma réplica e um worker; concorrência além dessa
  topologia não foi homologada.
- O OFX não fornece de modo confiável limite, faturas futuras ou parcelas; esses
  dados seguem para a Sprint 4, sem valores presumidos.

## Evidências de implementação

- `223fdaf`, `0ec910b`: domínio e fronteiras por Lar.
- `9b6bbd2`, `dc03c91`, `eb16073`: parser e validações OFX.
- `40acfe8`, `a5a21ca`: prévia e concorrência de vínculo.
- `058ebe5`, `4319e20`, `eca712e`: confirmação atômica e recuperação de corrida.
- `9bd6a59`, `447135f`: API privada e privacidade de upload.
- Task 6: teste de migration, documentos e matriz final registrados no commit
  desta entrega.

## Correções da revisão final

- contagens do recibo são recalculadas após avisos virarem lançamentos criados;
- cancelamento relê e bloqueia o lote em transação atômica, sem sobrescrever
  preview já vinculado ou confirmado;
- conta OFX nunca é vinculada a `Account.CREDIT`, enquanto cartão exige esse tipo;
- `ACCTID`, `FITID`, `MEMO`, moeda, escala e precisão do valor são validados antes
  de qualquer persistência e retornam erros OFX sanitizados;
- linhas normalizadas canceladas são removidas imediatamente. Expiradas são
  removidas até o prazo pelo scheduler Supervisor, que acorda para a expiração
  mais próxima e limita a espera a uma hora; o recibo técnico do batch permanece;
- OpenAPI registra 10 MiB, códigos estáveis, `expires_at` e a limitação de que o
  perfil estrutural não autentica a instituição de origem.

## Matriz final da Task 6

- `python -Wd manage.py test` focado nas alterações: 84 testes aprovados sem
  `DeprecationWarning`.
- `coverage run manage.py test` + `coverage report --fail-under=90`: 447 testes,
  98% (8.620 statements, 163 não cobertos), gate aprovado.
- Ruff, `manage.py check`, migration drift e `git diff --check`: aprovados.
- `check --deploy --fail-level WARNING` foi aprovado com variáveis de produção
  sintéticas. Com as variáveis efêmeras obrigatórias de teste (`DEBUG=True` e
  SSL desligado), Django emite cinco warnings de deploy esperados; não foram
  ocultados nem usados para alterar configurações de produção.
