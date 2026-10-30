-- =====================================================================
-- Hora Extra — banco de dados (Supabase / PostgreSQL)
-- Login próprio por CPF + PIN (Edge Functions). O app recebe um JWT assinado
-- com o segredo do projeto; as políticas RLS usam auth.uid() = conta.
-- =====================================================================
create extension if not exists pgcrypto;
create extension if not exists pg_cron;

-- Perfis de convenção (regras de cálculo — nada fixo no código do app)
create table if not exists perfis_convencao (
  id text primary key,                         -- 'clt', 'feaac'
  nome text not null,
  sindicato text,
  registro_mte text,
  versao text not null,                        -- 'CCT 2025/2026'
  vigencia_inicio date,
  vigencia_fim date,
  regras jsonb not null,                       -- faixasDiaUtil, adicionalDomingoFeriado, adicionalDiaCompensado, noturno, bancoHoras, reflexoDSR, baseIncluiAdicionais
  ativo boolean not null default true,
  atualizado_em timestamptz not null default now()
);

create table if not exists contas (
  id uuid primary key default gen_random_uuid(),
  cpf char(11) not null unique,                -- chave de login (não editável)
  email text not null,
  apelido text not null,
  convencao_id text not null default 'clt' references perfis_convencao(id),
  pin_hash text not null,                      -- bcrypt(PIN + pepper); nunca o PIN em texto
  consentimento_lgpd_em timestamptz not null,
  criado_em timestamptz not null default now()
);

-- Tentativas e bloqueios ficam no servidor (por CPF e por IP)
create table if not exists tentativas_login (
  id bigserial primary key,
  cpf char(11),
  ip inet,
  sucesso boolean not null,
  criado_em timestamptz not null default now()
);
create index if not exists tentativas_cpf_idx on tentativas_login (cpf, criado_em desc);
create index if not exists tentativas_ip_idx on tentativas_login (ip, criado_em desc);

create table if not exists bloqueios (
  cpf char(11) primary key,
  erros int not null default 0,                -- erros desde o último sucesso
  nivel int not null default 0,                -- 1 = 15 min, 2 = 1 h, 3 = 24 h
  ate timestamptz
);

create table if not exists codigos_recuperacao (
  cpf char(11) primary key,
  codigo_hash text not null,
  expira_em timestamptz not null,
  tentativas int not null default 0
);

-- Dados de cálculo (só os extraídos; nenhum documento original é guardado)
create table if not exists configuracoes (
  conta_id uuid primary key references contas(id) on delete cascade,
  dados jsonb not null,                        -- salário, adicionais, divisor, jornada por dia, data de corte, banco de horas…
  versao_perfil text,
  atualizado_em timestamptz not null default now()
);
create table if not exists espelhos (
  conta_id uuid not null references contas(id) on delete cascade,
  competencia char(7) not null,                -- '2026-10'
  dias jsonb not null,
  aviso_retencao_em timestamptz,
  atualizado_em timestamptz not null default now(),
  primary key (conta_id, competencia)
);
create table if not exists holerites (
  conta_id uuid not null references contas(id) on delete cascade,
  competencia char(7) not null,
  dados jsonb not null,                        -- rubricas extraídas, CNPJ, empresa
  aviso_retencao_em timestamptz,
  importado_em timestamptz not null default now(),
  primary key (conta_id, competencia)
);

-- RLS: cada conta só enxerga os próprios dados
alter table contas enable row level security;
alter table configuracoes enable row level security;
alter table espelhos enable row level security;
alter table holerites enable row level security;
alter table tentativas_login enable row level security;   -- sem políticas: só as Edge Functions (service role)
alter table bloqueios enable row level security;
alter table codigos_recuperacao enable row level security;
alter table perfis_convencao enable row level security;

create policy perfis_leitura on perfis_convencao for select using (ativo);
create policy conta_propria on contas for select using (id = auth.uid());
create policy conta_edita on contas for update using (id = auth.uid()) with check (id = auth.uid());
create policy cfg_propria on configuracoes for all using (conta_id = auth.uid()) with check (conta_id = auth.uid());
create policy esp_proprio on espelhos for all using (conta_id = auth.uid()) with check (conta_id = auth.uid());
create policy hol_proprio on holerites for all using (conta_id = auth.uid()) with check (conta_id = auth.uid());
-- CPF e PIN não podem ser alterados pelo app
revoke update (cpf, pin_hash) on contas from authenticated;

-- Retenção de 3 meses: marca o aviso e apaga 15 dias depois (o app avisa e oferece exportação)
create or replace function aplicar_retencao() returns void language plpgsql as $$
declare limite char(7) := to_char(date_trunc('month', now()) - interval '2 months', 'YYYY-MM');
begin
  update espelhos set aviso_retencao_em = now() where competencia < limite and aviso_retencao_em is null;
  update holerites set aviso_retencao_em = now() where competencia < limite and aviso_retencao_em is null;
  delete from espelhos where competencia < limite and aviso_retencao_em < now() - interval '15 days';
  delete from holerites where competencia < limite and aviso_retencao_em < now() - interval '15 days';
  delete from tentativas_login where criado_em < now() - interval '30 days';
end $$;
select cron.schedule('retencao-diaria', '0 6 * * *', 'select aplicar_retencao()');

-- Perfis iniciais
insert into perfis_convencao (id, nome, sindicato, versao, vigencia_inicio, vigencia_fim, regras) values
('clt', 'CLT mínimo (padrão)', 'Legislação (CLT)', 'CLT 2026', null, null,
 '{"faixasDiaUtil":[{"ateHorasNoDia":null,"adicional":0.50}],"adicionalDomingoFeriado":1.00,"adicionalDiaCompensado":null,
   "noturno":{"inicio":"22:00","fim":"05:00","adicional":0.20,"horaReduzida":true,"prorrogacao":true},
   "bancoHoras":{"prazoDias":180,"prazoMaxColetivo":365,"exigeProtocolo":false,"pagaSaldoComAdicional":true},
   "reflexoDSR":true,"baseIncluiAdicionais":["triênio","anuênio"]}'),
('feaac', 'FEAAC / SEAAC × SESCON-SP', 'FEAAC/SEAAC × SESCON-SP', 'CCT 2025/2026', '2025-08-01', '2026-07-31',
 '{"faixasDiaUtil":[{"ateHorasNoDia":2,"adicional":0.60},{"ateHorasNoDia":null,"adicional":0.80}],"adicionalDomingoFeriado":1.00,"adicionalDiaCompensado":1.00,
   "noturno":{"inicio":"22:00","fim":"05:00","adicional":0.30,"horaReduzida":true,"prorrogacao":true},
   "bancoHoras":{"prazoDias":60,"prazoMaxColetivo":210,"exigeProtocolo":true,"baseQuinzena":true,"pagaSaldoComAdicional":true},
   "reflexoDSR":true,"baseIncluiAdicionais":["triênio"]}')
on conflict (id) do update set regras = excluded.regras, versao = excluded.versao, atualizado_em = now();
