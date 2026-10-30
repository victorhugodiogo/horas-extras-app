// Funções comuns às Edge Functions (Deno)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

export const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
export const PEPPER = Deno.env.get("PIN_PEPPER") ?? "";
export const LOCK_MIN = [15, 60, 1440];

export const cors = {
  "Access-Control-Allow-Origin": Deno.env.get("APP_ORIGIN") ?? "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

export const digits = (v: unknown) => String(v ?? "").replace(/\D/g, "");
export function cpfValido(c: string): boolean {
  if (c.length !== 11 || /^(\d)\1{10}$/.test(c)) return false;
  let s = 0; for (let i = 0; i < 9; i++) s += +c[i] * (10 - i);
  let d = (s * 10) % 11 % 10; if (d !== +c[9]) return false;
  s = 0; for (let i = 0; i < 10; i++) s += +c[i] * (11 - i);
  d = (s * 10) % 11 % 10; return d === +c[10];
}
export const ipOf = (req: Request) =>
  (req.headers.get("cf-connecting-ip") ?? req.headers.get("x-forwarded-for")?.split(",")[0] ?? "").trim() || null;

/** CAPTCHA invisível (Cloudflare Turnstile) */
export async function captchaOk(token: string | undefined, ip: string | null): Promise<boolean> {
  if (!token) return false;
  const form = new FormData();
  form.append("secret", Deno.env.get("TURNSTILE_SECRET")!);
  form.append("response", token);
  if (ip) form.append("remoteip", ip);
  const r = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", { method: "POST", body: form });
  const out = await r.json();
  return !!out.success;
}

/** E-mail transacional (Resend) */
export async function sendEmail(to: string, subject: string, html: string) {
  const key = Deno.env.get("RESEND_API_KEY"); if (!key) return;
  await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: Deno.env.get("EMAIL_FROM") ?? "Hora Extra <no-reply@example.com>", to, subject, html }),
  });
}

/** JWT da sessão (aceito pelo Supabase: RLS usa auth.uid()) */
export async function sessionToken(contaId: string): Promise<string> {
  const secret = new TextEncoder().encode(Deno.env.get("JWT_SECRET")!);
  const key = await crypto.subtle.importKey("raw", secret, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return await create({ alg: "HS256", typ: "JWT" },
    { sub: contaId, role: "authenticated", aud: "authenticated", exp: getNumericDate(60 * 60 * 12) }, key);
}
