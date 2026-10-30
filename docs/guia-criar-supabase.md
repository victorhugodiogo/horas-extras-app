# Passo a passo: criar o servidor do Hora Extra no Supabase

Versão 1.0 · 30/10/2026 · tempo estimado: **15 minutos** · custo: **R$ 0** (plano gratuito, sem cartão)

> **O que você vai ter no final:** a conta criada no computador funciona no celular, os lançamentos sincronizam entre os aparelhos, e as tentativas de PIN, a verificação de segurança e o bloqueio passam a ser controlados no servidor.
>
> **O que você NÃO precisa:** instalar programas, usar linha de comando ou publicar funções. Tudo é feito no navegador, colando **um único arquivo**.

---

## Antes de começar

- Tenha em mãos o login do GitHub (dá para entrar no Supabase com ele).
- Abra o arquivo do servidor em outra aba, para copiar no passo 4:
  **https://github.com/victorhugodiogo/horas-extras-app/blob/main/server/supabase/setup.sql**
- Você vai criar uma **senha do banco de dados**. Guarde-a num lugar seguro (gerenciador de senhas). Ela **não** deve ser enviada a ninguém, nem ao Claude.

---

## Passo 1 — Criar a conta no Supabase

1. Acesse **https://supabase.com** e clique em **Start your project**.
2. Escolha **Continue with GitHub** e autorize (ou cadastre-se com e-mail e senha).
3. Se pedir para confirmar o e-mail, abra o e-mail do Supabase e clique no link.

## Passo 2 — Criar a organização

Na primeira vez o Supabase pede uma organização (é só uma "pasta" dos seus projetos):

| Campo | O que preencher |
|---|---|
| Name | `Victor` (ou o nome que quiser) |
| Type | **Personal** |
| Plan | **Free – $0/month** |

Clique em **Create organization**.

## Passo 3 — Criar o projeto

Clique em **New project** e preencha:

| Campo | O que preencher |
|---|---|
| Organization | a que você acabou de criar |
| Project name | `hora-extra` |
| Database Password | clique em **Generate a password**, depois em **Copy**, e guarde |
| Region | **South America (São Paulo)** — deixa o app mais rápido no Brasil |
| Security options / Data API | deixe como vier (**Data API ligado**) |

Clique em **Create new project** e aguarde cerca de **2 minutos**, até sumir a mensagem "Setting up project".

## Passo 4 — Instalar o servidor (colar o arquivo)

1. No menu da esquerda, clique em **SQL Editor** (ícone `>_`).
2. Clique em **+ New query** (ou no **+** ao lado de "SQL Editor").
3. Na outra aba (arquivo `setup.sql` no GitHub), clique no botão **Copy raw file** (ícone de duas folhas, no canto direito acima do código).
4. Volte ao Supabase, clique na área de texto, apague o que houver e cole (**Ctrl+V**).
5. Clique em **Run** (canto inferior direito) ou aperte **Ctrl+Enter**.
6. Se aparecer o aviso *"Potential issue detected"* ou *"destructive operation"*, clique em **Run this query**. É esperado: o arquivo cria tabelas e ajusta permissões; ele **não apaga** dados existentes.
7. No resultado, embaixo, deve aparecer:

   ```
   Hora Extra: servidor instalado com sucesso
   ```

> Se aparecer a mensagem *"pg_cron indisponível"* na aba **Messages**: vá em **Database → Extensions**, procure **pg_cron** e **pg_net**, ligue as duas e rode o arquivo de novo (passos 2 a 5). Sem elas o app funciona, mas sem a limpeza automática de 3 meses no servidor e sem e-mails.

**Para conferir:** menu **Table Editor** — devem aparecer as tabelas `contas`, `espelhos`, `holerites`, `configuracoes`, `perfis_convencao` (entre outras). A tabela `perfis_convencao` deve ter 2 linhas: *CLT mínimo (padrão)* e *FEAAC / SEAAC × SESCON-SP*.

## Passo 5 — Copiar os dois dados que o Claude precisa

1. No menu da esquerda, clique em **Project Settings** (engrenagem, no fim do menu).
2. Clique em **API Keys**.
3. Copie a **Publishable key** (começa com `sb_publishable_...`).
   - Se a tela mostrar abas, a chave fica em **API Keys**. Se não existir "Publishable key", abra a aba **Legacy API Keys** e copie a chave **anon / public** (começa com `eyJ...`).
4. Copie a **Project URL**: clique no botão **Connect** no topo da página (ou em **Project Settings → Data API**). O endereço é parecido com `https://abcdefghijkl.supabase.co`.

**Envie ao Claude só estes dois:**

```
Project URL: https://xxxxxxxxxxxx.supabase.co
Publishable key: sb_publishable_xxxxxxxxxxxxxxxx
```

> ⚠️ **Nunca envie** a *Secret key* / *service_role*, nem a senha do banco. Elas dão acesso total aos dados. A publishable key pode ficar no app: ela só consegue chamar as funções do Hora Extra, nunca ler as tabelas direto.

---

## Passo 6 (opcional) — E-mails: alerta de bloqueio e "Esqueci meu PIN"

Sem este passo tudo funciona, exceto o envio de e-mails (o "Esqueci meu PIN" avisa que o e-mail ainda não está ativo).

1. Crie uma conta gratuita em **https://resend.com** (até 3.000 e-mails/mês).
2. Menu **API Keys → Create API Key** → nome `hora-extra`, permissão **Sending access** → **Add**. Copie a chave (começa com `re_`; ela só aparece uma vez).
3. No Supabase, **SQL Editor → + New query**, cole o comando abaixo trocando `re_SUA_CHAVE` pela sua chave, e clique em **Run**:

   ```sql
   insert into config_app (chave, valor) values ('resend_key', 're_SUA_CHAVE')
   on conflict (chave) do update set valor = excluded.valor;
   ```

4. **Limitação do plano grátis do Resend sem domínio próprio:** os e-mails só chegam ao **endereço com que você criou a conta no Resend**. Para mandar a qualquer pessoa, cadastre um domínio em **Resend → Domains** e depois rode:

   ```sql
   update config_app set valor = 'Hora Extra <nao-responda@seudominio.com.br>' where chave = 'email_from';
   ```

> Faça este passo você mesmo. Não é preciso enviar a chave do Resend ao Claude.

---

## Depois de enviar a URL e a chave ao Claude

O Claude vai:
1. Ligar o app ao servidor (site no GitHub Pages e APK).
2. Trocar o login local pelo do servidor, com a verificação de segurança e o bloqueio controlados lá.
3. Na primeira vez que você entrar, oferecer **enviar os lançamentos já salvos no aparelho** para a sua conta no servidor.
4. Testar com você: criar conta no computador e entrar no celular.

---

## Cuidados com o plano gratuito

| Situação | O que fazer |
|---|---|
| **Projeto pausado** (acontece após 1 semana sem nenhum uso) | Entre em supabase.com, abra o projeto e clique em **Restore project**. Os dados não se perdem. |
| Banco cheio (limite de 500 MB) | Improvável: cada mês de espelho ocupa poucos KB. O app guarda só 3 meses. |
| Quer backup diário e sem pausa | Plano Pro (US$ 25/mês). Não é necessário para começar. |

---

## Problemas comuns

| Sintoma | Causa | Solução |
|---|---|---|
| `syntax error at or near ...` ao rodar | O arquivo foi colado pela metade | Use **Copy raw file** no GitHub e cole de novo, apagando o que havia |
| `permission denied` | Rodou como outro usuário/role | No SQL Editor, deixe o seletor de role em **postgres** (padrão) |
| Mensagem "pg_cron indisponível" | Extensões desligadas | Database → Extensions → ligar **pg_cron** e **pg_net** → rodar de novo |
| Não acho a Publishable key | Tela antiga | Use **Legacy API Keys → anon public** |
| App diz "sem conexão com o servidor" | Projeto pausado | **Restore project** no painel |

---

## Checklist

- [ ] Conta no Supabase criada
- [ ] Projeto `hora-extra` em **São Paulo**, senha do banco guardada
- [ ] `setup.sql` rodado → "servidor instalado com sucesso"
- [ ] Tabela `perfis_convencao` com 2 linhas
- [ ] **Project URL** e **Publishable key** enviadas ao Claude (nada mais)
- [ ] (Opcional) Chave do Resend cadastrada pelo SQL Editor
