-- =====================================================================
-- HORA EXTRA — servidor completo em um único arquivo (Supabase)
-- Como usar: Supabase → SQL Editor → New query → cole TODO este arquivo → Run.
-- Pode rodar de novo quando houver versão nova: ele não apaga dados.
--
-- Como funciona:
--   • As tabelas ficam fechadas (RLS ligado, sem acesso direto pelo app).
--   • O app só conversa com o banco pelas funções "he_*" abaixo (RPC).
--   • Login por CPF + PIN com bcrypt, CAPTCHA a partir do 3º erro,
--     bloqueio progressivo (15 min → 1 h → 24 h) no 5º e proteção contra
--     varredura por IP — tudo controlado no servidor (seção 9.1).
--   • E-mail (alerta de bloqueio e código de recuperação de PIN) é opcional:
--     funciona quando a chave do Resend for cadastrada (passo 6 do guia).
-- =====================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
do $$ begin create extension if not exists pg_net; exception when others then raise notice 'pg_net indisponível: e-mails desativados'; end $$;

-- ---------------------------------------------------------------------
-- Tabelas
-- ---------------------------------------------------------------------
create table if not exists config_app (chave text primary key, valor text not null);
insert into config_app (chave, valor) values ('pin_pepper', encode(extensions.gen_random_bytes(24), 'hex')) on conflict (chave) do nothing;
insert into config_app (chave, valor) values ('email_from', 'Hora Extra <onboarding@resend.dev>') on conflict (chave) do nothing;

create table if not exists perfis_convencao (
  id text primary key, nome text not null, sindicato text, registro_mte text, versao text not null,
  vigencia_inicio date, vigencia_fim date, regras jsonb not null, ativo boolean not null default true,
  atualizado_em timestamptz not null default now()
);

create table if not exists contas (
  id uuid primary key default gen_random_uuid(),
  cpf char(11) not null unique,
  email text not null,
  apelido text not null,
  convencao_id text not null default 'clt' references perfis_convencao(id),
  pin_hash text not null,
  consentimento_lgpd_em timestamptz not null,
  criado_em timestamptz not null default now()
);
create table if not exists sessoes (
  token_hash text primary key,
  conta_id uuid not null references contas(id) on delete cascade,
  expira_em timestamptz not null,
  criado_em timestamptz not null default now()
);
create table if not exists tentativas_login (
  id bigserial primary key, cpf char(11), ip text, sucesso boolean not null, criado_em timestamptz not null default now()
);
create index if not exists tentativas_cpf_idx on tentativas_login (cpf, criado_em desc);
create index if not exists tentativas_ip_idx on tentativas_login (ip, criado_em desc);
create table if not exists bloqueios (cpf char(11) primary key, erros int not null default 0, nivel int not null default 0, ate timestamptz);
create table if not exists desafios (id uuid primary key default gen_random_uuid(), resposta int not null, expira_em timestamptz not null);
create table if not exists recuperacao (cpf char(11) primary key, codigo_hash text not null, expira_em timestamptz not null, tentativas int not null default 0);

create table if not exists configuracoes (
  conta_id uuid primary key references contas(id) on delete cascade, dados jsonb not null, atualizado_em timestamptz not null default now()
);
create table if not exists espelhos (
  conta_id uuid not null references contas(id) on delete cascade, competencia char(7) not null, dias jsonb not null,
  aviso_retencao_em timestamptz, atualizado_em timestamptz not null default now(), primary key (conta_id, competencia)
);
create table if not exists holerites (
  conta_id uuid not null references contas(id) on delete cascade, competencia char(7) not null, dados jsonb not null,
  aviso_retencao_em timestamptz, atualizado_em timestamptz not null default now(), primary key (conta_id, competencia)
);

-- Tabelas fechadas: nenhum acesso direto pela chave pública do app
do $$ declare t text; begin
  foreach t in array array['config_app','perfis_convencao','contas','sessoes','tentativas_login','bloqueios','desafios','recuperacao','configuracoes','espelhos','holerites'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
  end loop;
exception when undefined_object then null; end $$;

-- Perfis de convenção
insert into perfis_convencao (id, nome, sindicato, versao, vigencia_inicio, vigencia_fim, regras) values
('clt', 'CLT mínimo (padrão)', 'Legislação (CLT)', 'CLT 2026', null, null,
 '{"faixasDiaUtil":[{"ateHorasNoDia":null,"adicional":0.50}],"adicionalDomingoFeriado":1.00,"adicionalDiaCompensado":null,"noturno":{"inicio":"22:00","fim":"05:00","adicional":0.20,"horaReduzida":true,"prorrogacao":true},"bancoHoras":{"prazoDias":180,"prazoMaxColetivo":365,"exigeProtocolo":false},"reflexoDSR":true,"baseIncluiAdicionais":["triênio","anuênio"]}'),
('feaac', 'FEAAC / SEAAC × SESCON-SP', 'FEAAC/SEAAC × SESCON-SP', 'CCT 2025/2026', '2025-08-01', '2026-07-31',
 '{"faixasDiaUtil":[{"ateHorasNoDia":2,"adicional":0.60},{"ateHorasNoDia":null,"adicional":0.80}],"adicionalDomingoFeriado":1.00,"adicionalDiaCompensado":1.00,"noturno":{"inicio":"22:00","fim":"05:00","adicional":0.30,"horaReduzida":true,"prorrogacao":true},"bancoHoras":{"prazoDias":60,"prazoMaxColetivo":210,"exigeProtocolo":true,"baseQuinzena":true},"reflexoDSR":true,"baseIncluiAdicionais":["triênio"]}')
on conflict (id) do update set nome = excluded.nome, versao = excluded.versao, vigencia_inicio = excluded.vigencia_inicio,
  vigencia_fim = excluded.vigencia_fim, regras = excluded.regras, atualizado_em = now();

-- ---------------------------------------------------------------------
-- Funções internas (não chamáveis pelo app)
-- ---------------------------------------------------------------------
create or replace function he__cpf_valido(c text) returns boolean language plpgsql immutable as $$
declare s int; d int; i int;
begin
  if c !~ '^\d{11}$' or c ~ '^(\d)\1{10}$' then return false; end if;
  s := 0; for i in 1..9 loop s := s + substr(c,i,1)::int * (11 - i); end loop;
  d := (s * 10) % 11 % 10; if d <> substr(c,10,1)::int then return false; end if;
  s := 0; for i in 1..10 loop s := s + substr(c,i,1)::int * (12 - i); end loop;
  d := (s * 10) % 11 % 10; return d = substr(c,11,1)::int;
end $$;

create or replace function he__pepper() returns text language sql stable security definer set search_path = public as
$$ select valor from config_app where chave = 'pin_pepper' $$;

create or replace function he__ip() returns text language plpgsql stable as $$
declare h json;
begin
  h := nullif(current_setting('request.headers', true), '')::json;
  return coalesce(h->>'cf-connecting-ip', split_part(h->>'x-forwarded-for', ',', 1), null);
exception when others then return null;
end $$;

create or replace function he__conta(p_token text) returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare cid uuid;
begin
  select conta_id into cid from sessoes where token_hash = encode(digest(coalesce(p_token,''), 'sha256'), 'hex') and expira_em > now();
  if cid is null then raise exception 'sessao_invalida' using errcode = '28000'; end if;
  return cid;
end $$;

create or replace function he__desafio_ok(p_id uuid, p_resp int) returns boolean language plpgsql security definer set search_path = public as $$
declare ok boolean;
begin
  if p_id is null then return false; end if;
  select (resposta = p_resp and expira_em > now()) into ok from desafios where id = p_id;
  delete from desafios where id = p_id or expira_em < now();
  return coalesce(ok, false);
end $$;

create or replace function he__email(p_para text, p_assunto text, p_html text) returns void language plpgsql security definer set search_path = public as $$
declare k text; de text;
begin
  select valor into k from config_app where chave = 'resend_key';
  select valor into de from config_app where chave = 'email_from';
  if k is null then return; end if;
  perform net.http_post(url := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Authorization', 'Bearer ' || k, 'Content-Type', 'application/json'),
    body := jsonb_build_object('from', de, 'to', p_para, 'subject', p_assunto, 'html', p_html));
exception when others then raise notice 'e-mail não enviado: %', sqlerrm;
end $$;

create or replace function he__nova_sessao(p_conta uuid) returns text language plpgsql security definer set search_path = public, extensions as $$
declare tk text := encode(gen_random_bytes(32), 'hex');
begin
  delete from sessoes where expira_em < now();
  insert into sessoes (token_hash, conta_id, expira_em) values (encode(digest(tk, 'sha256'), 'hex'), p_conta, now() + interval '7 days');
  return tk;
end $$;

create or replace function he__conta_json(p_conta uuid) returns json language sql stable security definer set search_path = public as $$
  select json_build_object('id', id, 'cpf', cpf, 'email', email, 'apelido', apelido, 'conv', convencao_id,
    'criadoEm', criado_em, 'consentimentoEm', consentimento_lgpd_em) from contas where id = p_conta
$$;

-- ---------------------------------------------------------------------
-- Funções públicas (chamadas pelo app)
-- ---------------------------------------------------------------------

-- Desafio de segurança (CAPTCHA simples gerado e conferido no servidor)
create or replace function he_desafio() returns json language plpgsql security definer set search_path = public as $$
declare a int := 2 + floor(random() * 8)::int; b int := 2 + floor(random() * 8)::int; i uuid;
begin
  insert into desafios (resposta, expira_em) values (a + b, now() + interval '10 minutes') returning id into i;
  return json_build_object('id', i, 'pergunta', format('Quanto é %s + %s?', a, b));
end $$;

-- Criar conta
create or replace function he_criar_conta(p_cpf text, p_email text, p_apelido text, p_conv text, p_pin text,
  p_consentimento boolean, p_desafio uuid, p_resposta int) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare c text := regexp_replace(coalesce(p_cpf,''), '\D', '', 'g'); cid uuid;
begin
  if not he__desafio_ok(p_desafio, p_resposta) then return json_build_object('ok', false, 'captcha', true, 'msg', 'Resposta da verificação incorreta.'); end if;
  if not he__cpf_valido(c) then return json_build_object('ok', false, 'msg', 'Informe um CPF válido.'); end if;
  if coalesce(p_email,'') !~ '^\S+@\S+\.\S+$' then return json_build_object('ok', false, 'msg', 'Informe um e-mail válido.'); end if;
  if coalesce(trim(p_apelido),'') = '' then return json_build_object('ok', false, 'msg', 'Informe um apelido.'); end if;
  if coalesce(p_pin,'') !~ '^\d{4}$' then return json_build_object('ok', false, 'msg', 'O PIN deve ter 4 números.'); end if;
  if p_consentimento is not true then return json_build_object('ok', false, 'msg', 'Autorize o uso dos dados para continuar.'); end if;
  if exists (select 1 from contas where cpf = c) then
    return json_build_object('ok', false, 'existe', true, 'msg', 'Já existe uma conta com este CPF. Use "Entrar" ou "Esqueci meu PIN".');
  end if;
  insert into contas (cpf, email, apelido, convencao_id, pin_hash, consentimento_lgpd_em)
  values (c, trim(p_email), trim(p_apelido), coalesce((select id from perfis_convencao where id = p_conv), 'clt'),
          crypt(p_pin || he__pepper(), gen_salt('bf', 10)), now())
  returning id into cid;
  return json_build_object('ok', true, 'token', he__nova_sessao(cid), 'conta', he__conta_json(cid));
end $$;

-- Entrar (seção 9.1)
create or replace function he_entrar(p_cpf text, p_pin text, p_desafio uuid default null, p_resposta int default null) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare
  c text := regexp_replace(coalesce(p_cpf,''), '\D', '', 'g');
  v_ip text := he__ip();
  b bloqueios%rowtype; ct contas%rowtype;
  v_varredura int; ok boolean; v_erros int; v_nivel int; v_min int; v_ate timestamptz;
  bloqueios_min int[] := array[15, 60, 1440];
begin
  if length(c) <> 11 then return json_build_object('ok', false, 'msg', 'Informe um CPF com 11 dígitos.'); end if;
  select * into b from bloqueios where cpf = c;
  if b.ate is not null and b.ate > now() then return json_build_object('ok', false, 'bloqueadoAte', b.ate); end if;
  v_erros := coalesce(b.erros, 0);
  select count(distinct t.cpf) into v_varredura from tentativas_login t
    where v_ip is not null and t.ip = v_ip and not t.sucesso and t.criado_em > now() - interval '15 minutes';
  if (v_erros >= 3 or v_varredura >= 5) and not he__desafio_ok(p_desafio, p_resposta) then
    return json_build_object('ok', false, 'captcha', true, 'msg', 'Conclua a verificação de segurança para continuar.');
  end if;
  select * into ct from contas where cpf = c;
  if ct.id is not null then ok := coalesce(p_pin,'') ~ '^\d{4}$' and crypt(p_pin || he__pepper(), ct.pin_hash) = ct.pin_hash;
  else perform crypt(coalesce(p_pin,'') || 'x', gen_salt('bf', 10)); ok := false;     -- mesmo tempo de resposta
  end if;
  insert into tentativas_login (cpf, ip, sucesso) values (c, v_ip, ok);
  if ok then
    insert into bloqueios (cpf, erros, nivel, ate) values (c, 0, 0, null)
      on conflict (cpf) do update set erros = 0, nivel = 0, ate = null;
    return json_build_object('ok', true, 'token', he__nova_sessao(ct.id), 'conta', he__conta_json(ct.id));
  end if;
  v_erros := v_erros + 1;
  if v_erros >= 5 then
    v_nivel := least(coalesce(b.nivel, 0) + 1, 3); v_min := bloqueios_min[v_nivel]; v_ate := now() + make_interval(mins => v_min);
    insert into bloqueios (cpf, erros, nivel, ate) values (c, 3, v_nivel, v_ate)
      on conflict (cpf) do update set erros = 3, nivel = excluded.nivel, ate = excluded.ate;
    if ct.id is not null then
      perform he__email(ct.email, 'Alerta de segurança — Hora Extra',
        format('<p>Olá, %s. Houve 5 tentativas de acesso com PIN errado na sua conta. Bloqueamos novas tentativas por %s.</p><p>Se não foi você, use "Esqueci meu PIN" para trocar o PIN.</p>',
               ct.apelido, case when v_min >= 1440 then '24 horas' when v_min >= 60 then '1 hora' else v_min || ' minutos' end));
    end if;
    return json_build_object('ok', false, 'bloqueadoAte', v_ate, 'minutos', v_min);
  end if;
  insert into bloqueios (cpf, erros, nivel, ate) values (c, v_erros, coalesce(b.nivel, 0), null)
    on conflict (cpf) do update set erros = excluded.erros, ate = null;
  return json_build_object('ok', false, 'msg', 'CPF ou PIN incorretos.', 'restantes', 5 - v_erros, 'captcha', v_erros >= 3);
end $$;

-- Sair
create or replace function he_sair(p_token text) returns json language plpgsql security definer set search_path = public, extensions as $$
begin delete from sessoes where token_hash = encode(digest(coalesce(p_token,''), 'sha256'), 'hex'); return json_build_object('ok', true); end $$;

-- Carregar todos os dados da conta
create or replace function he_carregar(p_token text) returns json language plpgsql security definer set search_path = public, extensions as $$
declare cid uuid := he__conta(p_token);
begin
  return json_build_object(
    'conta', he__conta_json(cid),
    'cfg', (select dados from configuracoes where conta_id = cid),
    'meses', coalesce((select json_object_agg(competencia, dias) from espelhos where conta_id = cid), '{}'::json),
    'holerites', coalesce((select json_object_agg(competencia, dados) from holerites where conta_id = cid), '{}'::json),
    'perfis', (select json_agg(json_build_object('id', id, 'nome', nome, 'versao', versao, 'regras', regras)) from perfis_convencao where ativo));
end $$;

-- Salvar (só o que mudou): configuração, meses e holerites; p_apagar = competências a remover
create or replace function he_salvar(p_token text, p_cfg jsonb default null, p_meses jsonb default null,
  p_holerites jsonb default null, p_apagar text[] default null) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare cid uuid := he__conta(p_token); k text; v jsonb;
begin
  if p_cfg is not null then
    insert into configuracoes (conta_id, dados) values (cid, p_cfg)
      on conflict (conta_id) do update set dados = excluded.dados, atualizado_em = now();
  end if;
  for k, v in select * from jsonb_each(coalesce(p_meses, '{}'::jsonb)) loop
    if k ~ '^\d{4}-\d{2}$' then
      insert into espelhos (conta_id, competencia, dias) values (cid, k, v)
        on conflict (conta_id, competencia) do update set dias = excluded.dias, atualizado_em = now(), aviso_retencao_em = null;
    end if;
  end loop;
  for k, v in select * from jsonb_each(coalesce(p_holerites, '{}'::jsonb)) loop
    if k ~ '^\d{4}-\d{2}$' then
      insert into holerites (conta_id, competencia, dados) values (cid, k, v)
        on conflict (conta_id, competencia) do update set dados = excluded.dados, atualizado_em = now();
    end if;
  end loop;
  if p_apagar is not null then
    delete from espelhos where conta_id = cid and competencia = any(p_apagar);
    delete from holerites where conta_id = cid and competencia = any(p_apagar);
  end if;
  return json_build_object('ok', true, 'salvoEm', now());
end $$;

-- Alterar e-mail, apelido e convenção (CPF não muda)
create or replace function he_atualizar_conta(p_token text, p_email text, p_apelido text, p_conv text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare cid uuid := he__conta(p_token);
begin
  if coalesce(p_email,'') !~ '^\S+@\S+\.\S+$' then return json_build_object('ok', false, 'msg', 'Informe um e-mail válido.'); end if;
  if coalesce(trim(p_apelido),'') = '' then return json_build_object('ok', false, 'msg', 'Informe um apelido.'); end if;
  update contas set email = trim(p_email), apelido = trim(p_apelido),
    convencao_id = coalesce((select id from perfis_convencao where id = p_conv), convencao_id) where id = cid;
  return json_build_object('ok', true, 'conta', he__conta_json(cid));
end $$;

-- LGPD: excluir conta e todos os dados
create or replace function he_excluir_conta(p_token text) returns json language plpgsql security definer set search_path = public, extensions as $$
declare cid uuid := he__conta(p_token); c text;
begin
  select cpf into c from contas where id = cid;
  delete from contas where id = cid;
  delete from bloqueios where cpf = c; delete from recuperacao where cpf = c; delete from tentativas_login where cpf = c;
  return json_build_object('ok', true);
end $$;

-- Esqueci meu PIN: 1) pedir código por e-mail
create or replace function he_recuperar_pedir(p_cpf text, p_desafio uuid, p_resposta int) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare c text := regexp_replace(coalesce(p_cpf,''), '\D', '', 'g'); ct contas%rowtype; cod text;
begin
  if not he__desafio_ok(p_desafio, p_resposta) then return json_build_object('ok', false, 'captcha', true, 'msg', 'Resposta da verificação incorreta.'); end if;
  if not exists (select 1 from config_app where chave = 'resend_key') then
    return json_build_object('ok', false, 'semEmail', true, 'msg', 'O envio de e-mail ainda não está ativo. Fale com o administrador.');
  end if;
  select * into ct from contas where cpf = c;
  if ct.id is not null then
    cod := lpad((floor(random() * 1000000))::int::text, 6, '0');
    insert into recuperacao (cpf, codigo_hash, expira_em, tentativas) values (c, crypt(cod, gen_salt('bf', 8)), now() + interval '15 minutes', 0)
      on conflict (cpf) do update set codigo_hash = excluded.codigo_hash, expira_em = excluded.expira_em, tentativas = 0;
    perform he__email(ct.email, 'Seu código — Hora Extra',
      format('<p>Olá, %s. Seu código para criar um PIN novo é <b>%s</b>. Ele vale por 15 minutos.</p><p>Se não foi você que pediu, ignore este e-mail.</p>', ct.apelido, cod));
  end if;
  return json_build_object('ok', true, 'msg', 'Se o CPF estiver cadastrado, enviamos um código para o e-mail da conta.');
end $$;

-- Esqueci meu PIN: 2) confirmar código e gravar PIN novo
create or replace function he_recuperar_confirmar(p_cpf text, p_codigo text, p_pin text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare c text := regexp_replace(coalesce(p_cpf,''), '\D', '', 'g'); r recuperacao%rowtype;
begin
  select * into r from recuperacao where cpf = c;
  if r.cpf is null or r.expira_em < now() or r.tentativas >= 5 then return json_build_object('ok', false, 'msg', 'Código inválido ou expirado.'); end if;
  if crypt(coalesce(p_codigo,''), r.codigo_hash) <> r.codigo_hash then
    update recuperacao set tentativas = tentativas + 1 where cpf = c;
    return json_build_object('ok', false, 'msg', 'Código inválido ou expirado.');
  end if;
  if coalesce(p_pin,'') !~ '^\d{4}$' then return json_build_object('ok', false, 'msg', 'O PIN deve ter 4 números.'); end if;
  update contas set pin_hash = crypt(p_pin || he__pepper(), gen_salt('bf', 10)) where cpf = c;
  delete from recuperacao where cpf = c;
  delete from sessoes where conta_id = (select id from contas where cpf = c);
  insert into bloqueios (cpf, erros, nivel, ate) values (c, 0, 0, null) on conflict (cpf) do update set erros = 0, nivel = 0, ate = null;
  return json_build_object('ok', true, 'msg', 'PIN alterado. Entre com o PIN novo.');
end $$;

-- Retenção de 3 meses: marca o aviso e apaga 15 dias depois (o app avisa e oferece exportação)
create or replace function he__retencao() returns void language plpgsql security definer set search_path = public as $$
declare limite text := to_char(date_trunc('month', now()) - interval '2 months', 'YYYY-MM');
begin
  update espelhos set aviso_retencao_em = now() where competencia < limite and aviso_retencao_em is null;
  update holerites set aviso_retencao_em = now() where competencia < limite and aviso_retencao_em is null;
  delete from espelhos where competencia < limite and aviso_retencao_em < now() - interval '15 days';
  delete from holerites where competencia < limite and aviso_retencao_em < now() - interval '15 days';
  delete from tentativas_login where criado_em < now() - interval '30 days';
  delete from sessoes where expira_em < now();
  delete from desafios where expira_em < now();
end $$;
do $$ begin
  create extension if not exists pg_cron;
  perform cron.unschedule('he-retencao') where exists (select 1 from cron.job where jobname = 'he-retencao');
  perform cron.schedule('he-retencao', '0 6 * * *', 'select public.he__retencao()');
exception when others then raise notice 'pg_cron indisponível: retenção automática no servidor desativada (%).', sqlerrm;
end $$;

-- Permissões: o app (chave pública) só executa as funções he_* públicas
revoke all on all functions in schema public from public, anon, authenticated;
grant execute on function he_desafio(), he_criar_conta(text,text,text,text,text,boolean,uuid,int),
  he_entrar(text,text,uuid,int), he_sair(text), he_carregar(text), he_salvar(text,jsonb,jsonb,jsonb,text[]),
  he_atualizar_conta(text,text,text,text), he_excluir_conta(text), he_recuperar_pedir(text,uuid,int),
  he_recuperar_confirmar(text,text,text) to anon, authenticated;

select 'Hora Extra: servidor instalado com sucesso' as resultado;
