# Sprint 4 / Task 9 — relatório de fechamento

Data: 14/08/2026 (America/Sao_Paulo).

## Escopo e estado

A Task 9 fecha a fundação Flutter somente leitura sobre a base
`06ea7234074fb2fbbabc70720e7b32c120726e65`. Não houve merge em `main`, deploy,
uso de credencial real ou início da Sprint 5.

## Jornada integrada

O teste `integration_test/auth_sync_home_test.dart` usa um servidor HTTP local e
dados sintéticos. Ele cobre banco vazio, login, escolha de `Eu`, bootstrap, Home,
reabertura offline pelo mesmo Drift, delta após retomada, exatamente um refresh
de access token e logout. O cache financeiro permanece, os tokens são removidos
e qualquer chamada a `/sync/push/` reprova o teste.

A CI executa essa jornada no runner Windows antes de gerar o MSIX. Os builds de
Windows, Android e iOS recebem apenas o endpoint público
`https://financeiro.palmbook.online/api/v1`; nenhuma senha ou token é embutido.

## Correções da revisão final

- o Android release declara `android.permission.INTERNET`, verificado também no
  manifesto mesclado do APK;
- `SessionExpired` durante pull invalida imediatamente o estado autenticado e
  preserva o cache financeiro;
- logout grava um marcador local antes de limpar o cofre; falha de limpeza
  bloqueia restauração e é tentada novamente na próxima abertura;
- a integração Windows passou a ser gate da CI;
- o relatório passou de uma pasta ignorada para documentação versionada;
- builds instaláveis apontam para o endpoint público real;
- rollback da Task 9 e rollback integral da Sprint 4 foram separados.

## Benchmark Windows

O script `mobile/tool/run_windows_home_benchmark.ps1` compila o target profile,
faz um aquecimento que cria o dataset sintético e executa dez processos novos.
Cada amostra usa um cronômetro externo desde `Start-Process` até um marcador
gravado após o primeiro frame da Home real populada. O seed de 20 contas, 50
categorias e 10.000 transações fica fora da janela.

- equipamento: Ryzen 5 7500F, 31,6 GiB RAM, Windows 11 Pro 10.0.26200;
- Flutter 3.47.0 stable / Dart 3.13.0;
- amostras em ms: `1374.356, 1348.586, 1423.838, 1424.416, 1387.771,
  1452.408, 1416.010, 1347.566, 1378.519, 1576.466`;
- mediana: `1401.891 ms`;
- p95: `1576.466 ms`;
- critério: mediana menor que `2000 ms`, aprovado.

O resultado vale para o equipamento e modo acima; não é extrapolado para
Android ou iOS.

## Builds e distribuição privada

`msix` permanece fixado em `3.18.0`, com identidade
`online.palmbook.larfinance`, `install_certificate: false` e manifesto-fonte
`publisher: CN=Lar Finance Private`. Sem certificado próprio, a ferramenta usa
o certificado de teste `CN=Msix Testing`, thumbprint
`028BC9922D198EE83D776AA19CB8E82897691E0C`. Ele serve somente para sideload
controlado em `CurrentUser\\TrustedPeople` e deve ser removido depois; não deve
ser instalado globalmente nem usado para distribuição pública.

O APK release local final tem 60.147.300 bytes e SHA-256
`40A903BB33B77231C361C094618D66F004896162C2EF1837C49B49F8973095C6`.
O MSIX local final tem 14.836.461 bytes e SHA-256
`C8D20F6109FB858F55E9ECFF27EAA36453DC7AF45EE76FB83E45ED3954AF0D32`.

Na CI final, o APK tem 60.147.284 bytes e SHA-256
`8ED6D700444DEE97201C156589BB60508742E817807EFC4ACC0901C5069B0DC8`;
o MSIX tem 14.904.294 bytes e SHA-256
`0B41DBB6CD14086EACA5768D90F3A142952A02773EE8CB28CA4808296C85F4EF`.

## Evidência de CI

- run inicial `31854915133`: falhou e revelou manifesto Windows ignorado e
  goldens dependentes do rasterizador;
- run corretivo `31856052144`: seis jobs verdes;
- run documental `31856531422`: seis jobs verdes;
- run `31857659911`: seis jobs verdes no commit `b1d3b6c`, incluindo a jornada
  integrada Windows, builds Windows/MSIX, Android/APK e iOS sem assinatura.

## Riscos residuais

- instalação em iPhone físico, codesign e distribuição iOS permanecem fora da
  Sprint 4; o build sem assinatura é validado no macOS da CI;
- o MSIX usa certificado de teste e não é pacote de distribuição pública;
- o arquivo `flutter-version.json` preserva a saída integral da ferramenta e,
  por isso, contém o caminho local capturado; os jobs usam apenas a versão;
- strings ainda não estão extraídas para arquivos de internacionalização; isso
  permanece no roadmap de evolução, sem bloquear o piloto privado em pt-BR.

## Rollback

Para reverter somente a Task 9, reverta
`06ea7234074fb2fbbabc70720e7b32c120726e65..HEAD`. Para toda a Sprint 4, reverta
`31552fa..HEAD`, incluindo o fallback compatível do login no backend. Não houve
migration, deploy ou alteração externa de dados nesta Task 9.
