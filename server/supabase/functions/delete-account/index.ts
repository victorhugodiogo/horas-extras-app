// LGPD: "Excluir minha conta e meus dados" (apaga a conta e tudo em cascata)
import { verify } from "https://deno.land/x/djwt@v3.0.2/mod.ts";
import { db, cors, json } from "../_shared/util.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  try {
    const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(Deno.env.get("JWT_SECRET")!), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
    const payload = await verify(token, key);
    const { error } = await db.from("contas").delete().eq("id", payload.sub as string);
    if (error) throw error;
    return json({ ok: true });
  } catch {
    return json({ ok: false, msg: "Sessão inválida." }, 401);
  }
});
