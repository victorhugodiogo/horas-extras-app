// Criação de conta: CPF único e validado, PIN com hash, consentimento LGPD
import * as bcrypt from "https://deno.land/x/bcrypt@v0.4.1/mod.ts";
import { db, PEPPER, cors, json, digits, cpfValido, ipOf, captchaOk, sessionToken } from "../_shared/util.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const b = await req.json().catch(() => ({}));
  const cpf = digits(b.cpf), email = String(b.email ?? "").trim(), apelido = String(b.apelido ?? "").trim();
  if (!(await captchaOk(b.captchaToken, ipOf(req)))) return json({ ok: false, msg: "Conclua a verificação de segurança." }, 400);
  if (!cpfValido(cpf)) return json({ ok: false, msg: "Informe um CPF válido." }, 400);
  if (!/^\S+@\S+\.\S+$/.test(email)) return json({ ok: false, msg: "Informe um e-mail válido." }, 400);
  if (!apelido) return json({ ok: false, msg: "Informe um apelido." }, 400);
  if (!/^\d{4}$/.test(String(b.pin ?? ""))) return json({ ok: false, msg: "O PIN deve ter 4 números." }, 400);
  if (b.consentimento !== true) return json({ ok: false, msg: "Autorize o uso dos dados para continuar." }, 400);
  const pin_hash = await bcrypt.hash(b.pin + PEPPER, await bcrypt.genSalt(12));
  const { data, error } = await db.from("contas").insert({
    cpf, email, apelido, convencao_id: b.convencao ?? "clt", pin_hash, consentimento_lgpd_em: new Date().toISOString(),
  }).select("id, apelido").single();
  // CPF já cadastrado: mesma resposta genérica de "entre com seu PIN"
  if (error) return json({ ok: false, msg: "Não foi possível criar a conta. Se você já tem cadastro, use Entrar." }, 409);
  return json({ ok: true, token: await sessionToken(data.id), conta: data });
});
