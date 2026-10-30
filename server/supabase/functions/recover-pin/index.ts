// Recuperação de PIN por código enviado ao e-mail cadastrado
import * as bcrypt from "https://deno.land/x/bcrypt@v0.4.1/mod.ts";
import { db, PEPPER, cors, json, digits, ipOf, captchaOk, sendEmail } from "../_shared/util.ts";

const OK_MSG = "Se o CPF estiver cadastrado, enviamos um código para o e-mail da conta.";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const b = await req.json().catch(() => ({}));
  const cpf = digits(b.cpf);
  if (b.etapa === "pedir") {
    if (!(await captchaOk(b.captchaToken, ipOf(req)))) return json({ ok: false, msg: "Conclua a verificação de segurança." }, 400);
    const { data: conta } = await db.from("contas").select("email, apelido").eq("cpf", cpf).maybeSingle();
    if (conta) {
      const codigo = String(crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000).padStart(6, "0");
      await db.from("codigos_recuperacao").upsert({ cpf, codigo_hash: await bcrypt.hash(codigo), expira_em: new Date(Date.now() + 15 * 60_000).toISOString(), tentativas: 0 });
      await sendEmail(conta.email, "Seu código — Hora Extra", `<p>Olá, ${conta.apelido}. Seu código para criar um PIN novo é <b>${codigo}</b>. Ele vale por 15 minutos.</p>`);
    }
    return json({ ok: true, msg: OK_MSG });
  }
  if (b.etapa === "confirmar") {
    const { data: rec } = await db.from("codigos_recuperacao").select("*").eq("cpf", cpf).maybeSingle();
    if (!rec || new Date(rec.expira_em) < new Date() || rec.tentativas >= 5) return json({ ok: false, msg: "Código inválido ou expirado." }, 400);
    if (!(await bcrypt.compare(String(b.codigo ?? ""), rec.codigo_hash))) {
      await db.from("codigos_recuperacao").update({ tentativas: rec.tentativas + 1 }).eq("cpf", cpf);
      return json({ ok: false, msg: "Código inválido ou expirado." }, 400);
    }
    if (!/^\d{4}$/.test(String(b.pin ?? ""))) return json({ ok: false, msg: "O PIN deve ter 4 números." }, 400);
    await db.from("contas").update({ pin_hash: await bcrypt.hash(b.pin + PEPPER, await bcrypt.genSalt(12)) }).eq("cpf", cpf);
    await db.from("codigos_recuperacao").delete().eq("cpf", cpf);
    await db.from("bloqueios").upsert({ cpf, erros: 0, nivel: 0, ate: null });
    return json({ ok: true, msg: "PIN alterado. Entre com o PIN novo." });
  }
  return json({ ok: false }, 400);
});
