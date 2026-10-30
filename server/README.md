# Servidor (preparado, ainda não ligado)

Hoje o app funciona em **modo local**: contas, PIN e cálculos ficam no próprio aparelho.
Esta pasta tem tudo para passar ao **modo servidor** (seções 8, 9, 12 e 14 do documento de regras):
dados sincronizados entre celular e computador, tentativas e bloqueios controlados no servidor,
CAPTCHA invisível e recuperação de PIN por e-mail.

## O que tem aqui

| Arquivo | Função |
|---|---|
| `supabase/schema.sql` | Tabelas, políticas de acesso (cada conta só vê os próprios dados), perfis de convenção e retenção automática de 3 meses |
| `supabase/functions/auth-pin` | Login CPF + PIN: CAPTCHA a partir do 3º erro, bloqueio progressivo (15 min → 1 h → 24 h) no 5º, e-mail de alerta, proteção contra varredura por IP |
| `supabase/functions/signup` | Criar conta: CPF único e validado, PIN com bcrypt + pepper, consentimento LGPD |
| `supabase/functions/recover-pin` | "Esqueci meu PIN": código de 6 dígitos por e-mail, válido por 15 minutos |
| `supabase/functions/delete-account` | "Excluir minha conta e meus dados" |

## Para ligar (uma vez)

1. Crie um projeto gratuito em supabase.com e rode `supabase/schema.sql` no SQL Editor.
2. Crie um site no Cloudflare Turnstile (gratuito) e uma conta no Resend (e-mail, gratuito até 3.000/mês).
3. Configure os segredos das funções: `JWT_SECRET` (o JWT secret do projeto), `PIN_PEPPER` (texto aleatório longo),
   `TURNSTILE_SECRET`, `RESEND_API_KEY`, `EMAIL_FROM`, `APP_ORIGIN`.
4. Publique as funções: `supabase functions deploy auth-pin signup recover-pin delete-account --no-verify-jwt`.
5. Passe para o desenvolvimento: a URL do projeto, a chave pública (anon) e a chave do site do Turnstile.
   O app troca o armazenamento local por chamadas a essas funções e às tabelas.

> Estas funções foram escritas, mas ainda não foram executadas contra um projeto real. Elas precisam ser
> testadas no momento da ligação.
