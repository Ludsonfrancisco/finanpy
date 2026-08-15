# Sprint 4 — Fundação Flutter e Home Casa de Valores

## Resultado

A Sprint 4 entrega o primeiro cliente Flutter do Lar Finance para Windows,
Android e iOS a partir de um único workspace. A fundação inclui login familiar,
sessão por dispositivo, storage seguro nativo, SQLite/Drift, bootstrap e delta
atômicos, cache offline, shell adaptativo, temas Casa de Valores e Home real
somente leitura para `Lar`, `Eu` e `Esposa`.

Nenhuma escrita financeira entrou no cliente e a jornada integrada comprova que
`/sync/push/` nunca é chamado. A Sprint 5 não foi iniciada.

## Evidência funcional

O teste de integração usa exclusivamente um servidor HTTP local e dados
sintéticos. Ele atravessa login, escolha de responsável, bootstrap, Home,
reabertura offline pelo mesmo arquivo Drift, retomada com delta, refresh único
de access token e logout com cache financeiro retido e credenciais removidas.

A suíte local aprovou 180 testes Flutter e um teste integrado Windows. O backend
permaneceu verde com 461 testes, Ruff, checks Django/deploy/migrations e 97% de
cobertura.

## Performance

O cache quente foi medido em Flutter profile no Windows, abrindo um banco Drift
de 20 contas, 50 categorias e 10.000 transações em cada uma das dez amostras. Em
um Ryzen 5 7500F com 31,6 GiB RAM, Flutter 3.47.0/Dart 3.13.0 e Windows 11 Pro
10.0.26200, a mediana bootstrap→primeiro frame populado foi 42,063 ms e o p95
67,737 ms. O critério de mediana abaixo de 2 s foi atendido. A medida não afirma
performance em Android/iOS.

## Builds privados

O build local Windows release e o Android APK release passaram com o endpoint
sintético `example.invalid`. O artefato MSIX da CI tem 14.902.744 bytes e
SHA-256
`6219ED0AFFD43D230097A0276E3062495C8A1F4BB504721682576062DD79F27D`.

O projeto fixa [`msix` 3.18.0](https://pub.dev/packages/msix/versions/3.18.0) e
mantém no manifesto-fonte `publisher: CN=Lar Finance Private`. Como não há
certificado privado próprio deliberadamente nesta fase, o pacote local é assinado
pelo certificado embarcado da ferramenta, `CN=Msix Testing` (thumbprint
`028BC9922D198EE83D776AA19CB8E82897691E0C`), cuja cadeia não é confiável por
padrão. Isso é adequado somente a um piloto controlado, não a distribuição.

### Sideload controlado

1. Confirme o SHA-256 acima no arquivo exato.
2. Confira que `Get-AuthenticodeSignature` retorna o subject e thumbprint acima.
3. Registre se o thumbprint já existe em `Cert:\CurrentUser\TrustedPeople`.
4. Exporte o certificado embutido e importe-o apenas em
   `Cert:\CurrentUser\TrustedPeople`.
5. Instale com `Add-AppxPackage`.
6. Se o certificado foi adicionado neste piloto, remova exatamente esse
   thumbprint do mesmo store depois da instalação.

Não altere a confiança global do Windows, não habilite Developer Mode e não
publique esse certificado. Um pacote de distribuição exige certificado próprio
compatível com `CN=Lar Finance Private`.

## CI e limites

A [CI 31856052144](https://github.com/Ludsonfrancisco/finanpy/actions/runs/31856052144)
aprovou as seis frentes: Django, secret scan, Ubuntu format/analyze/testes,
Windows release/MSIX/hash/goldens, Ubuntu Android APK e macOS com testes e build
iOS release sem assinatura. Todos leem a versão Flutter fixada e não recebem
credenciais reais. Goldens pixel a pixel rodam somente no rasterizador canônico
Windows; Linux e macOS executam os demais 172 testes.

Não houve deploy nem mudança no backend ou nos dados. Para rollback, reverta o
commit de fechamento da Sprint 4; não há migration ou operação externa a desfazer.

O relatório detalhado e a matriz de gates estão em
`.superpowers/sdd/flutter-task-9-report.md`.
