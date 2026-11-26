// Study assistant. Uses the Google Gemini free tier.
// Deploy: supabase functions deploy ai-assistant
// Secret: supabase secrets set GEMINI_API_KEY=<free key from aistudio.google.com>
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const key = Deno.env.get("GEMINI_API_KEY");
    if (!key) {
      return new Response(JSON.stringify({ error: "no_key" }), {
        status: 200, headers: { ...cors, "Content-Type": "application/json" },
      });
    }
    const { messages, lang } = await req.json();
    const contents = (messages ?? []).slice(-12).map((m: any) => ({
      role: m.role === "assistant" ? "model" : "user",
      parts: [{ text: String(m.text ?? "").slice(0, 2000) }],
    }));
    const system =
      `You are Deki, a friendly study assistant inside a learning app. Answer briefly and clearly in the user's language (${lang ?? "ar"}; Egyptian Arabic if Arabic). Help with studying, explaining concepts and exam tips.`;
    const r = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${key}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: system }] },
          contents,
        }),
      },
    );
    const j = await r.json();
    const text = j?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
    return new Response(JSON.stringify({ text }), {
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 200, headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});
