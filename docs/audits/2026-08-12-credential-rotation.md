# Rotação da credencial histórica — 2026-08-12

## Escopo

Rotacionar a credencial única do Lar Finance na instalação real do EasyPanel sem
copiar email, senha anterior ou senha nova para código, documentação, chat ou log
de auditoria.

## Evidências sanitizadas

- Serviço de produção acessado no EasyPanel pelo proprietário autenticado.
- Banco consultado somente por contagens: 1 usuário total e 1 usuário ativo.
- O proprietário digitou a nova senha diretamente no prompt interativo do Django.
- `changepassword` confirmou a alteração com sucesso.
- O usuário permaneceu com senha utilizável e hasher `pbkdf2_sha256`.
- Todas as sessões Django então existentes foram removidas.
- A imagem implantada não contém o pacote `api`; sessões móveis `DeviceSession`
  ainda não existem nesse deploy e não exigiram revogação.
- Nenhum valor de credencial foi persistido neste repositório.

## Fora do escopo

- Nenhum deploy, migration, restart ou alteração de configuração foi executado.
- Nenhum dado financeiro foi lido ou alterado.
- O histórico Git não foi reescrito. A credencial antiga não pode ser reutilizada;
  eventual limpeza do histórico exige autorização e plano próprios.
- Backup externo, restauração real e validação completa do runbook EasyPanel
  permanecem pendentes.

## Resultado

A exposição operacional da credencial histórica foi mitigada. Isso não libera
sozinho uma nova implantação: os bloqueios de backup/restauração e validação do
runbook continuam válidos.
