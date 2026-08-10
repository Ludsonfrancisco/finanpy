# Padrões de código

Estas regras valem para o backend atual e para a evolução do Lar Finance.
Convenções Flutter específicas serão fixadas quando o workspace for aprovado.

## Regras transversais

- Escrever primeiro o teste que demonstra o comportamento esperado.
- Dinheiro usa `Decimal` e código de moeda; nunca `float`.
- Ausência de dado é nulo/desconhecido, nunca zero presumido.
- Toda entidade financeira é isolada pelo Lar e, quando aplicável, responsável.
- APIs futuras usam UUID externo, idempotência e erros estruturados.
- Logs nunca contêm token, arquivo, CPF, email completo, saldo, valor ou descrição.
- Importadores preservam origem, são idempotentes e só alteram o ledger após
  confirmação explícita.
- Mudanças arquiteturais exigem ADR em `docs/adr/`.
- Código, documentação e fixtures usam UTF-8.

## Python e Django

- PEP 8, aspas simples, nomes e código em inglês.
- Textos da interface em pt-BR.
- Preferência por Class-Based Views e recursos nativos do Django.
- Cada domínio permanece em seu app.
- Mudanças de comportamento exigem teste de regressão.
- Migrations aplicadas são imutáveis; correções usam uma nova migration.
- Ruff usa a configuração versionada em `pyproject.toml`.

## Segurança por Lar

`Household` é a fronteira de autorização. Toda view financeira deve usar
`HouseholdContextMixin` e filtrar por `self.household`. A associação precisa
estar ativa; ausência ou revogação deve negar acesso sem reativar dados.

Models financeiros validam:

- associação ativa do usuário legado;
- coerência entre Lar, conta, categoria e responsável financeiro;
- compartilhamento apenas entre membros do mesmo Lar.

Erros de campos internos omitidos de um `ModelForm` devem aparecer como erros
não associados a campo, nunca como resposta HTTP 500. FKs legadas para usuário
permanecem protegidas enquanto forem necessárias para auditoria e migração.

## Migrations e integridade

- Toda data migration tem ensaio de banco novo, banco legado e rollback.
- Preflight falha antes de alterar dados quando encontra inconsistência.
- Não manipular a tabela `django_migrations` para esconder divergência física.
- Constraints críticas são verificadas no banco, não apenas no ORM.
- `audit_household_integrity` permanece somente leitura e sem PII.

## Testes e entrega

- Cada correção inclui teste que falha antes da implementação.
- Rodar testes focados durante a tarefa e a suíte completa antes do commit final.
- Gates: Ruff, Django check, migrations check, deploy check e cobertura mínima.
- Cada tarefa concluída recebe commit e push; cada sprint recebe revisão final e
  relato objetivo do concluído e do próximo passo.
