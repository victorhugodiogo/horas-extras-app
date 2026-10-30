// Login por CPF + PIN com CAPTCHA e bloqueio progressivo (seção 9.1)
import * as bcrypt from "https://deno.land/x/bcrypt@v0.4.1/mod.ts";
import { db, PEPPER, LOCK_MIN, cors, json, digits, ipOf, captchaOk, sendEmail, sessionToken } from "../_shared/util.ts";

const GENERIC = "CPF ou PIN incorretos.";            // nunca revela se o CPF existe

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const { cpf: rawCpf, pin, captchaToken } = await req.json().catch(() => ({}));
  const cpf = digits(rawCpf), ip = ipOf(req);
  if (cpf.length !== 11 || !/^\d{4}$/.test(String(pin ?? ""))) return json({ ok: false, msg: GENERIC }, 401);

  // bloqueio vigente?
  const { data: blk } = await db.from("bloqueios").select("*").eq("cpf", cpf).maybeSingle();
  if (blk?.ate && new Date(blk.ate) > new Date()) return json({ ok: false, bloqueadoAte: blk.ate }, 423);

  // varredura: muitas falhas do mesmo IP em CPFs diferentes => CAPTCHA desde a 1ª tentativa
  const desde = new Date(Date.now() - 15 * 60_000).toISOString();
  const { data: ipFails } = ip ? await db.from("tentativas_login").select("cpf").eq("ip", ip).eq("sucesso", false).gte("criado_em", desde) : { data: [] };
  const cpfsDistintos = new Set((ipFails ?? []).map((r) => r.cpf)).size;
  const erros = blk?.erros ?? 0;
  const precisaCaptcha = erros >= 3 || cpfsDistintos >= 5;
  if (precisaCaptcha && !(await captchaOk(captchaToken, ip))) return json({ ok: false, captcha: true, msg: "Conclua a verificação de segurança." }, 401);

  const { data: conta } = await db.from("contas").select("id, pin_hash, email, apelido").eq("cpf", cpf).maybeSingle();
  // quando a conta não existe, gasta o mesmo tempo de um hash (não revela se o CPF existe)
  const ok = conta ? await bcrypt.compare(pin + PEPPER, conta.pin_hash) : (await bcrypt.hash(pin + PEPPER, await bcrypt.genSalt(10)), false);
  await db.from("tentativas_login").insert({ cpf, ip, sucesso: ok });

  if (ok) {
    await db.from("bloqueios").upsert({ cpf, erros: 0, nivel: blk?.nivel ?? 0, ate: null });
    return json({ ok: true, token: await sessionToken(conta!.id), conta: { id: conta!.id, apelido: conta!.apelido } });
  }
  const novos = erros + 1;
  if (novos >= 5) {
    const nivel = Math.min((blk?.nivel ?? 0) + 1, LOCK_MIN.length);
    const ate = new Date(Date.now() + LOCK_MIN[nivel - 1] * 60_000).toISOString();
    await db.from("bloqueios").upsert({ cpf, erros: 3, nivel, ate });
    if (conta) await sendEmail(conta.email, "Alerta de segurança — Hora Extra",
      `<p>Olá, ${conta.apelido}. Houve 5 tentativas de acesso com PIN errado na sua conta. Bloqueamos novas tentativas por ${LOCK_MIN[nivel - 1] >= 60 ? LOCK_MIN[nivel - 1] / 60 + " hora(s)" : LOCK_MIN[nivel - 1] + " minutos"}.</p><p>Se não foi você, troque o PIN em "Esqueci meu PIN".</p>`);
    return json({ ok: false, bloqueadoAte: ate }, 423);
  }
  await db.from("bloqueios").upsert({ cpf, erros: novos, nivel: blk?.nivel ?? 0, ate: null });
  return json({ ok: false, msg: GENERIC, restantes: 5 - novos, captcha: novos >= 3 }, 401);
});
