# Horas Extras CLT

Calculadora de horas extras de acordo com a CLT: adicional de 50%/100%, adicional noturno com hora reduzida,
prorrogação após as 5h (Súmula 60, II TST), reflexo no DSR, total líquido (INSS e IRRF 2026) e leitura de prints do espelho de ponto.

## Instalar no Android

1. Abra a página **Releases** deste repositório no celular (logado no GitHub).
2. Baixe o arquivo `HorasExtras-v1.0.N.apk` da versão mais recente.
3. Toque no arquivo baixado e confirme a instalação (permita "instalar apps desta fonte", se o Android pedir).

Versões novas instalam por cima da anterior e mantêm os lançamentos.

## Estrutura

| Pasta | O que é |
|---|---|
| `web/` | O app em si (HTML/CSS/JS, um arquivo). Funciona também como site/PWA. |
| `android/` | Projeto Android que empacota a pasta `web/` num APK (WebView). |
| `.github/workflows/android.yml` | Gera e publica o APK automaticamente a cada alteração em `web/` ou `android/`. |

## Atualizar o app

Altere `web/index.html` e envie para a branch `main`. Em ~3 minutos uma nova versão aparece em **Releases**.
Para gerar manualmente: aba **Actions** → *Gerar APK Android* → **Run workflow**.

## Assinatura

O APK é assinado com `android/keystore/horasextras.jks` (senha padrão `horasextras`, ou o segredo `KEYSTORE_PASSWORD`).
Mantenha este repositório **privado**: quem tiver essa chave consegue publicar atualizações do app.
Não apague a chave — sem ela, novas versões não instalam por cima da atual.
