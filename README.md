# Hora Extra — horas extras pela CLT e pela convenção coletiva

Calcula e confere horas extras pela **convenção coletiva** de cada pessoa (perfis "CLT mínimo" e "FEAAC/SEAAC × SESCON-SP"):
faixas por dia (ex.: 60% nas 2 primeiras, 80% nas excedentes), 100% em domingos, feriados e dias compensados, adicional noturno com
hora reduzida e prorrogação após as 5h, reflexo no DSR, banco de horas com vencimento, data de corte da folha, total líquido (INSS e IRRF 2026),
leitura de prints/PDF do espelho de ponto e do holerite, e **conferência espelho × holerite** com alertas e perguntas para o RH.

Contas por CPF + PIN (até 3 por aparelho). Hoje em **modo local** (dados no aparelho); o servidor está preparado em `server/`.

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
| `server/` | Banco de dados e funções de login (Supabase), prontos para ligar. |
| `.github/workflows/android.yml` | Gera e publica o APK automaticamente a cada alteração em `web/` ou `android/`. |

## Atualizar o app

Altere `web/index.html` e envie para a branch `main`. Em ~3 minutos uma nova versão aparece em **Releases**.
Para gerar manualmente: aba **Actions** → *Gerar APK Android* → **Run workflow**.

## Assinatura

O APK é assinado com `android/keystore/horasextras.jks` (senha padrão `horasextras`, ou o segredo `KEYSTORE_PASSWORD`).
Mantenha este repositório **privado**: quem tiver essa chave consegue publicar atualizações do app.
Não apague a chave — sem ela, novas versões não instalam por cima da atual.
