// Marsella Conecta — new business notification
//
// Fires whenever a row is inserted into `businesses` (wired up via
// a Database Webhook — see the deployment guide). Sends a short
// email to the admin so nothing sits unnoticed in "Pendiente
// Validacion". Uses Resend (https://resend.com) — free tier covers
// this comfortably for a neighborhood directory's volume.
//
// Required secrets (set in Supabase Studio > Edge Functions > Secrets):
//   RESEND_API_KEY   — from resend.com dashboard
//   NOTIFY_EMAIL      — where you want to receive alerts (your email)
//   FROM_EMAIL        — sender address (see deployment guide for the
//                        sandbox-vs-verified-domain distinction)

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    const record = payload.record; // the newly inserted business row

    if (!record) {
      return new Response(JSON.stringify({ error: 'No record in payload' }), { status: 400 });
    }

    const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
    const NOTIFY_EMAIL = Deno.env.get('NOTIFY_EMAIL');
    const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'onboarding@resend.dev';

    if (!RESEND_API_KEY || !NOTIFY_EMAIL) {
      console.error('Missing RESEND_API_KEY or NOTIFY_EMAIL secret');
      return new Response(JSON.stringify({ error: 'Missing configuration' }), { status: 500 });
    }

    const subject = `🆕 Nuevo negocio pendiente: ${record.nombre || 'Sin nombre'}`;
    const html = `
      <div style="font-family:sans-serif;max-width:480px">
        <h2 style="margin:0 0 12px">Nuevo negocio registrado</h2>
        <p><strong>Nombre:</strong> ${record.nombre || '—'}</p>
        <p><strong>Categoría:</strong> ${record.categoria || '—'}</p>
        <p><strong>Barrio:</strong> ${record.barrio || '—'}</p>
        <p><strong>Teléfono:</strong> ${record.telefono || '—'}</p>
        <p><strong>Estado:</strong> ${record.estado || 'Pendiente Validacion'}</p>
        <p style="margin-top:20px">
          <a href="https://marsella.hl-techhub.com/admin.html"
             style="background:#0d67a7;color:#fff;padding:10px 18px;border-radius:8px;text-decoration:none;font-weight:bold">
            Revisar en el Panel Admin
          </a>
        </p>
      </div>`;

    const emailRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: NOTIFY_EMAIL,
        subject,
        html,
      }),
    });

    if (!emailRes.ok) {
      const errText = await emailRes.text();
      console.error('Resend error:', errText);
      return new Response(JSON.stringify({ error: errText }), { status: 500 });
    }

    return new Response(JSON.stringify({ success: true }), { status: 200 });
  } catch (err) {
    console.error('Function error:', err);
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 });
  }
});
